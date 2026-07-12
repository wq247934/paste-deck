//
//  TranslationCoordinator.swift
//  PasteDeck
//
//  Coordinates selected-text translation, screenshot OCR, global shortcuts, and translation windows.
//

import AppKit
import SwiftData
import SwiftUI

extension Notification.Name {
    /// 翻译设置保存后通知协调器重新注册快捷键与划词监听。
    static let translationSettingsDidChange = Notification.Name("PasteDeck.translationSettingsDidChange")
}

/// 翻译窗口的打开方式，决定原文区域是否进入编辑状态。
enum TranslationWindowMode {
    /// 从划词或截图获得原文，打开后立即翻译。
    case immediate
    /// 打开空白输入框，用户按回车后开始翻译。
    case input
}

/// 鼠标事件来源用于确保一次划词的按下和抬起坐标来自同一坐标系。
private enum AutomaticSelectionEventSource: Equatable {
    case eventTap
    case globalMonitor
}

@MainActor
final class TranslationCoordinator {
    static let shared = TranslationCoordinator()

    private var automaticSelectionMonitor: Any?
    private var automaticSelectionEventTap: CFMachPort?
    private var automaticSelectionEventTapRunLoopSource: CFRunLoopSource?
    private var settingsObserver: NSObjectProtocol?
    private var lastObservedAutomaticSelectionText: String?
    private var automaticSelectionStartPoint: NSPoint?
    private var automaticSelectionEventSource: AutomaticSelectionEventSource?
    private var lastAutomaticMouseInteractionDate = Date.distantPast
    private var isReadingAutomaticSelection = false
    private var automaticSelectionReadGeneration: UInt64 = 0
    private var automaticSelectionSuppressedUntil = Date.distantPast
    private var isCapturingScreenshot = false
    private var hasRequestedInputMonitoringPermission = false
    private let windowController = TranslationWindowController()

    private init() {}

    func start() {
        reloadConfiguration()
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .translationSettingsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TranslationCoordinator.shared.reloadConfiguration()
            }
        }
    }

    func stop() {
        removeAutomaticSelectionMonitor()
        for identifier in [
            HotKeyIdentifier.selectionTranslation,
            .screenshotTranslation,
            .inputTranslation
        ] {
            HotKeyManager.shared.unregister(identifier: identifier)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }

    func translateSelectedText() {
        automaticSelectionReadGeneration &+= 1
        automaticSelectionSuppressedUntil = Date().addingTimeInterval(1)
        isReadingAutomaticSelection = false
        guard AXIsProcessTrusted() else {
            Self.requestAccessibilityPermission()
            windowController.showError("读取选中文字需要“辅助功能”权限。请授权 PasteDeck 后重新触发快捷键。")
            return
        }
        SelectedTextReader.readSelectedText(allowsClipboardFallback: true) { [weak self] text in
            Task { @MainActor in
                guard let text else {
                    self?.windowController.showError("没有读取到选中文字。请确认文本仍处于选中状态；部分受保护页面不允许应用读取或复制内容。")
                    return
                }
                self?.windowController.show(text: text, mode: .immediate)
            }
        }
    }

    func captureAndTranslate() {
        guard !isCapturingScreenshot else {
            NSSound.beep()
            return
        }
        isCapturingScreenshot = true
        ScreenshotTranslationService.capture { [weak self] result in
            Task { @MainActor in
                self?.isCapturingScreenshot = false
                switch result {
                case .success(let text):
                    self?.windowController.show(text: text, mode: .immediate)
                case .failure(let error):
                    if case TranslationInteractionError.captureCancelled = error {
                        return
                    }
                    self?.windowController.showError(error.localizedDescription)
                }
            }
        }
    }

    func openInputTranslation() {
        windowController.show(text: "", mode: .input)
    }

    private func reloadConfiguration() {
        let settings = Self.fetchSettings()
        configureHotKey(
            identifier: .selectionTranslation,
            enabled: settings.selectionTranslationShortcutEnabled ?? true,
            keyCode: settings.selectionTranslationKeyCode ?? 2,
            modifiers: settings.selectionTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
        ) { [weak self] in
            self?.translateSelectedText()
        }
        configureHotKey(
            identifier: .screenshotTranslation,
            enabled: settings.screenshotTranslationShortcutEnabled ?? true,
            keyCode: settings.screenshotTranslationKeyCode ?? 1,
            modifiers: settings.screenshotTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
        ) { [weak self] in
            self?.captureAndTranslate()
        }
        configureHotKey(
            identifier: .inputTranslation,
            enabled: settings.inputTranslationShortcutEnabled ?? true,
            keyCode: settings.inputTranslationKeyCode ?? 0,
            modifiers: settings.inputTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
        ) { [weak self] in
            self?.openInputTranslation()
        }

        if settings.automaticSelectionTranslationEnabled ?? false {
            if !AXIsProcessTrusted() {
                Self.requestAccessibilityPermission()
            }
            // Rebuild the monitor whenever settings or privacy permissions change.
            // In particular, this swaps the temporary NSEvent fallback for the
            // reliable event tap as soon as Input Monitoring is granted.
            removeAutomaticSelectionMonitor()
            installAutomaticSelectionMonitor()
        } else {
            removeAutomaticSelectionMonitor()
        }
    }

    private func configureHotKey(
        identifier: HotKeyIdentifier,
        enabled: Bool,
        keyCode: Int,
        modifiers: Int,
        callback: @escaping () -> Void
    ) {
        guard enabled else {
            HotKeyManager.shared.unregister(identifier: identifier)
            return
        }
        HotKeyManager.shared.register(
            identifier: identifier,
            keyCode: UInt32(keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)),
            callback: callback
        )
    }

    private func installAutomaticSelectionMonitor() {
        // Keep both event sources. In practice, different macOS releases and
        // applications can suppress one of them even after permission is granted.
        // The read-in-progress guard coalesces duplicate mouse-up notifications.
        installNSEventGlobalMonitor()
        if CGPreflightListenEventAccess() {
            installAutomaticSelectionEventTap()
        } else {
            requestInputMonitoringPermissionIfNeeded()
        }
    }

    private func installAutomaticSelectionEventTap() {
        guard automaticSelectionEventTap == nil else { return }
        let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { eventTap, eventType, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let coordinator = Unmanaged<TranslationCoordinator>.fromOpaque(userInfo).takeUnretainedValue()
                if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                    DispatchQueue.main.async {
                        coordinator.reenableAutomaticSelectionEventTap()
                    }
                    return Unmanaged.passUnretained(event)
                }
                let eventLocation = event.location
                let clickCount = event.getIntegerValueField(.mouseEventClickState)
                DispatchQueue.main.async {
                    switch eventType {
                    case .leftMouseDown:
                        coordinator.recordAutomaticMouseDown(
                            at: eventLocation,
                            source: .eventTap
                        )
                    case .leftMouseUp:
                        coordinator.recordAutomaticMouseUp(
                            at: eventLocation,
                            clickCount: clickCount,
                            source: .eventTap
                        )
                    default:
                        break
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            // The preflight check can pass before macOS finishes applying a
            // permission change, so retain the NSEvent fallback in this case.
            installNSEventGlobalMonitor()
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        automaticSelectionEventTap = eventTap
        automaticSelectionEventTapRunLoopSource = runLoopSource
    }

    private func reenableAutomaticSelectionEventTap() {
        guard let automaticSelectionEventTap else { return }
        CGEvent.tapEnable(tap: automaticSelectionEventTap, enable: true)
    }

    private func requestInputMonitoringPermissionIfNeeded() {
        guard !hasRequestedInputMonitoringPermission else { return }
        hasRequestedInputMonitoringPermission = true
        _ = CGRequestListenEventAccess()
    }

    private func installNSEventGlobalMonitor() {
        if automaticSelectionMonitor == nil {
            automaticSelectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                let eventLocation = event.locationInWindow
                let clickCount = Int64(event.clickCount)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if event.type == .leftMouseDown {
                        self.recordAutomaticMouseDown(
                            at: eventLocation,
                            source: .globalMonitor
                        )
                    } else if event.type == .leftMouseUp {
                        self.recordAutomaticMouseUp(
                            at: eventLocation,
                            clickCount: clickCount,
                            source: .globalMonitor
                        )
                    }
                }
            }
        }
    }

    private func recordAutomaticMouseDown(
        at point: NSPoint,
        source: AutomaticSelectionEventSource
    ) {
        // Event taps also receive clicks inside PasteDeck. Closing the
        // translation window must not be treated as a new external selection,
        // otherwise the still-selected source text would reopen it in a loop.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            automaticSelectionStartPoint = nil
            automaticSelectionEventSource = nil
            return
        }
        automaticSelectionStartPoint = point
        automaticSelectionEventSource = source
        lastAutomaticMouseInteractionDate = Date()
    }

    private func recordAutomaticMouseUp(
        at point: NSPoint,
        clickCount: Int64,
        source: AutomaticSelectionEventSource
    ) {
        guard automaticSelectionEventSource == source else { return }
        lastAutomaticMouseInteractionDate = Date()
        let startPoint = automaticSelectionStartPoint ?? point
        automaticSelectionStartPoint = nil
        automaticSelectionEventSource = nil
        let draggedDistance = hypot(point.x - startPoint.x, point.y - startPoint.y)
        guard draggedDistance >= 2 || clickCount >= 2 else { return }
        // A completed external drag is deliberate user intent, even when its
        // text is the same as the previous selection. Plain clicks must retain
        // the last value so returning focus cannot reopen a closed window.
        lastObservedAutomaticSelectionText = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self,
                  Date() >= self.automaticSelectionSuppressedUntil else {
                return
            }
            self.handleAutomaticSelection(allowsClipboardFallback: true)
        }
    }

    private func removeAutomaticSelectionMonitor() {
        if let automaticSelectionEventTap {
            CGEvent.tapEnable(tap: automaticSelectionEventTap, enable: false)
        }
        if let automaticSelectionEventTapRunLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                automaticSelectionEventTapRunLoopSource,
                .commonModes
            )
        }
        self.automaticSelectionEventTapRunLoopSource = nil
        self.automaticSelectionEventTap = nil
        if let automaticSelectionMonitor {
            NSEvent.removeMonitor(automaticSelectionMonitor)
            self.automaticSelectionMonitor = nil
        }
        lastObservedAutomaticSelectionText = nil
        automaticSelectionEventSource = nil
    }

    private func handleAutomaticSelection(
        allowsClipboardFallback: Bool
    ) {
        guard AXIsProcessTrusted(),
              !isReadingAutomaticSelection,
              Date() >= automaticSelectionSuppressedUntil else { return }
        automaticSelectionReadGeneration &+= 1
        let readGeneration = automaticSelectionReadGeneration
        isReadingAutomaticSelection = true
        SelectedTextReader.readSelectedText(
            allowsClipboardFallback: allowsClipboardFallback,
            fallbackMaximumWait: allowsClipboardFallback ? 0.25 : 0.4
        ) { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.isReadingAutomaticSelection = false
                guard readGeneration == self.automaticSelectionReadGeneration,
                      Date() >= self.automaticSelectionSuppressedUntil else { return }
                guard let text, text.count <= 12_000 else {
                    return
                }
                guard text != self.lastObservedAutomaticSelectionText else { return }
                self.lastObservedAutomaticSelectionText = text
                // Reuse the same AppKit window as the manual shortcut so both
                // entry points share one reliable presentation path.
                self.windowController.show(text: text, mode: .immediate)
            }
        }
    }

    private static func fetchSettings() -> AppSettings {
        let context = ModelContext(AppModelContainer.container)
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return settings
        }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    private static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

// MARK: - Selected Text

private enum SelectedTextReader {
    static func readSelectedText(
        allowsClipboardFallback: Bool,
        fallbackMaximumWait: TimeInterval = 0.4,
        completion: @escaping (String?) -> Void
    ) {
        if let text = selectedTextUsingAccessibility() {
            completion(text)
            return
        }
        guard allowsClipboardFallback else {
            completion(nil)
            return
        }
        PasteService.shared.readSelectedTextBySimulatingCopy(
            maximumWait: fallbackMaximumWait,
            completion: completion
        )
    }

    private static func selectedTextUsingAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApplicationValue: CFTypeRef?
        let focusedApplication: AXUIElement? = {
            guard AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedApplicationAttribute as CFString,
                &focusedApplicationValue
            ) == .success,
            let focusedApplicationValue else {
                return nil
            }
            return unsafeBitCast(focusedApplicationValue, to: AXUIElement.self)
        }()

        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) != .success {
            if let focusedApplication {
                _ = AXUIElementCopyAttributeValue(
                    focusedApplication,
                    kAXFocusedUIElementAttribute as CFString,
                    &focusedValue
                )
            }
        }

        if let focusedValue {
            let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
            if let text = selectedTextInParentChain(startingAt: focusedElement) {
                return text
            }
        }

        // 浏览器和 Electron 的页面选区通常挂在 WebArea 的 text-marker range 上，
        // 而不是当前 focused element。仅在前台窗口内做有上限的只读遍历。
        if let focusedApplication {
            var focusedWindowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                focusedApplication,
                kAXFocusedWindowAttribute as CFString,
                &focusedWindowValue
            ) == .success,
            let focusedWindowValue {
                let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
                if let text = selectedTextInTree(root: focusedWindow, maximumNodes: 500) {
                    return text
                }
            }
        }
        return nil
    }

    private static func selectedTextInParentChain(startingAt element: AXUIElement) -> String? {
        var currentElement: AXUIElement? = element
        for _ in 0..<10 {
            guard let current = currentElement else { break }
            if let text = selectedText(from: current) {
                return text
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue else {
                break
            }
            currentElement = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return nil
    }

    private static func selectedTextInTree(root: AXUIElement, maximumNodes: Int) -> String? {
        var pendingElements: [AXUIElement] = [root]
        var visitedElementHashes: Set<CFHashCode> = []
        var inspectedNodeCount = 0
        var pendingElementIndex = 0

        while pendingElementIndex < pendingElements.count, inspectedNodeCount < maximumNodes {
            let element = pendingElements[pendingElementIndex]
            pendingElementIndex += 1
            let elementHash = CFHash(element)
            guard visitedElementHashes.insert(elementHash).inserted else { continue }
            inspectedNodeCount += 1

            if let text = selectedText(from: element) {
                return text
            }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                pendingElements.append(contentsOf: children)
            }
        }
        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
        let text = sanitizedSelectedText(selectedValue as? String) {
            return text
        }

        var markerRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRangeValue
        ) == .success,
        let markerRangeValue else {
            return nil
        }
        var markerTextValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRangeValue,
            &markerTextValue
        ) == .success else {
            return nil
        }
        return sanitizedSelectedText(markerTextValue as? String)
    }

    private static func sanitizedSelectedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed,
              !trimmed.isEmpty,
              !trimmed.hasPrefix("PasteDeck.SelectionProbe.") else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Screenshot OCR

private enum ScreenshotTranslationService {
    static func capture(completion: @escaping (Result<String, Error>) -> Void) {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            completion(.failure(TranslationInteractionError.screenRecordingPermissionRequired))
            return
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeck-Translation-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", fileURL.path]
        process.terminationHandler = { process in
            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: fileURL.path) else {
                completion(.failure(TranslationInteractionError.captureCancelled))
                return
            }
            ImageOCRService.shared.recognizeText(inImageAt: fileURL.path) { text in
                try? FileManager.default.removeItem(at: fileURL)
                guard let text, !text.isEmpty else {
                    completion(.failure(TranslationInteractionError.noTextRecognized))
                    return
                }
                completion(.success(text))
            }
        }
        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }
}

private enum TranslationInteractionError: LocalizedError {
    case captureCancelled
    case noTextRecognized
    case screenRecordingPermissionRequired

    var errorDescription: String? {
        switch self {
        case .captureCancelled: return "已取消截图"
        case .noTextRecognized: return "截图中未识别到文字"
        case .screenRecordingPermissionRequired: return "截图翻译需要“屏幕录制”权限。授权后请完全退出并重新打开 PasteDeck。"
        }
    }
}

// MARK: - View Model

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText: String
    @Published var translatedText = ""
    @Published var errorMessage: String?
    @Published var isTranslating = false
    @Published var providerName = "翻译"
    @Published var llmConfigurations: [LLMTranslationConfiguration] = []
    @Published var mode: TranslationWindowMode

    init(sourceText: String, mode: TranslationWindowMode) {
        self.sourceText = sourceText
        self.mode = mode
        refreshConfigurations()
    }

    func reset(sourceText: String, mode: TranslationWindowMode) {
        self.sourceText = sourceText
        self.mode = mode
        translatedText = ""
        errorMessage = nil
        refreshConfigurations()
        if mode == .immediate {
            translateUsingAPI()
        }
    }

    func translateUsingAPI() {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let settings = Self.fetchSettings()
        let configuration = settings.translationProviderConfiguration
        guard configuration.isConfigured else {
            errorMessage = "请先在“设置 -> 翻译”中启用并配置常规翻译 API"
            return
        }

        providerName = configuration.name.isEmpty ? configuration.kind.displayName : configuration.name
        isTranslating = true
        errorMessage = nil
        let service = TranslateService(configuration: configuration)
        let targetLanguage = TranslateService.detectTargetLanguage(for: source)
        service.translateSegment(source, to: targetLanguage) { [weak self] result in
            DispatchQueue.main.async {
                self?.isTranslating = false
                switch result {
                case .success(let text):
                    self?.translatedText = text
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func translateUsingLLM(_ configuration: LLMTranslationConfiguration) {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        providerName = configuration.name
        isTranslating = true
        errorMessage = nil
        let targetLanguage = TranslateService.detectTargetLanguage(for: source)
        LLMTranslationService(configuration: configuration).translate(source, targetLanguage: targetLanguage) { [weak self] result in
            DispatchQueue.main.async {
                self?.isTranslating = false
                switch result {
                case .success(let text):
                    self?.translatedText = text
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshConfigurations() {
        let settings = Self.fetchSettings()
        let provider = settings.translationProviderConfiguration
        providerName = provider.name.isEmpty ? provider.kind.displayName : provider.name
        llmConfigurations = settings.llmTranslationConfigurations.filter(\.isConfigured)
    }

    private static func fetchSettings() -> AppSettings {
        let context = ModelContext(AppModelContainer.container)
        return (try? context.fetch(FetchDescriptor<AppSettings>()).first) ?? AppSettings()
    }
}

// MARK: - Translation Window

@MainActor
private final class TranslationWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var viewModel: TranslationViewModel?

    func show(text: String, mode: TranslationWindowMode) {
        if let window, let viewModel {
            viewModel.reset(sourceText: text, mode: mode)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = TranslationViewModel(sourceText: text, mode: mode)
        let rootView = TranslationWorkspaceView(model: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PasteDeck 翻译"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 520, height: 420)
        window.setContentSize(NSSize(width: 640, height: 560))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.appearance = AppearanceResolver.currentAppearance
        window.center()
        self.viewModel = viewModel
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if mode == .immediate {
            viewModel.translateUsingAPI()
        }
    }

    func showError(_ message: String) {
        show(text: "", mode: .input)
        viewModel?.errorMessage = message
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window?.contentViewController = nil
        window = nil
        viewModel = nil
    }
}

private struct TranslationWorkspaceView: View {
    @ObservedObject var model: TranslationViewModel
    @FocusState private var sourceFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("翻译", systemImage: "character.book.closed")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(model.providerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("原文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField("输入要翻译的内容，按回车翻译", text: $model.sourceText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...9)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                    .focused($sourceFocused)
                    .onSubmit { model.translateUsingAPI() }
            }

            HStack {
                Picker("", selection: .constant("auto")) {
                    Text("自动检测").tag("auto")
                }
                .labelsHidden()
                .frame(width: 120)
                Spacer()
                Image(systemName: "arrow.down")
                    .foregroundColor(.secondary)
                Spacer()
                Text("自动选择目标语言")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("译文")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if model.isTranslating {
                        ProgressView().controlSize(.small)
                    }
                    if !model.translatedText.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.translatedText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("复制译文")
                    }
                }
                ScrollView {
                    Text(model.translatedText.isEmpty && model.errorMessage == nil ? "等待翻译" : model.translatedText)
                        .font(.system(size: 16))
                        .foregroundColor(model.translatedText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            HStack {
                Button("翻译") { model.translateUsingAPI() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTranslating)
                Spacer()
                if !model.llmConfigurations.isEmpty {
                    Menu {
                        ForEach(model.llmConfigurations) { configuration in
                            Button(configuration.name) {
                                model.translateUsingLLM(configuration)
                            }
                        }
                    } label: {
                        Label("使用大模型重译", systemImage: "sparkles")
                    }
                    .disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTranslating)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            sourceFocused = model.mode == .input
        }
        .onChange(of: model.mode) { _, mode in
            sourceFocused = mode == .input
        }
    }
}

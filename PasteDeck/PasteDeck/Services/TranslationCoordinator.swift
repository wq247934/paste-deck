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

/// 翻译工作区窗口的稳定标识，供主面板在焦点交接期间识别为应用内辅助窗口，避免误触发整应用隐藏。
let translationWorkspaceWindowIdentifier = NSUserInterfaceItemIdentifier("PasteDeckTranslationWorkspace")

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

    /// 将应用内已有文本直接送入统一翻译工作区；预览窗口等入口不再维护独立译文状态。
    func translate(text: String) {
        windowController.show(text: text, mode: .immediate)
    }

    /// 从主面板的“翻译”系统分类恢复一条历史记录，并以原翻译工作区形式展示。
    func openTranslationHistory(itemID: UUID) {
        windowController.showHistory(itemID: itemID)
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

/// 译文面板的来源种类；每个候选值决定译文卡片的调用方式和界面标签。
enum TranslationOutputKind: String, Codable {
    /// 已启用的常规机器翻译 API 自动创建的译文卡片。
    case api
    /// 用户从菜单主动选择的大模型新增译文卡片。
    case llm
}

/// 翻译工作区中的一张独立译文卡片。
struct TranslationOutput: Identifiable, Codable {
    /// 卡片唯一标识；常规 API 使用配置 id，大模型每次调用都会生成新 id 以保留对比结果。
    let id: UUID
    /// 产生该译文的调用种类；候选值为 api、llm。
    let kind: TranslationOutputKind
    /// 产生译文的配置稳定标识；用于恢复历史翻译窗口后按当前配置重试。
    let configurationID: UUID
    /// 卡片标题，显示服务或用户定义的密钥名称。
    let providerName: String
    /// 卡片副标题，显示 API 类型或具体模型名称。
    let detail: String
    /// 已成功返回的译文内容，空字符串表示尚未完成。
    var translatedText: String
    /// 请求失败时显示的可恢复错误信息。
    var errorMessage: String?
    /// 当前卡片是否正在等待对应服务返回。
    var isTranslating: Bool
}

/// 大模型超长原文的风险提示策略。阈值用于提醒成本和服务商上下文限制风险，不会阻止用户确认后继续。
enum LLMTranslationTokenSafety {
    /// 超过该估算输入 token 数时，在发送大模型请求前征求用户确认。
    static let warningTokenLimit = 8_000
    /// 翻译系统提示及消息结构的保守预留 token 数。
    private static let promptOverheadTokens = 160

    /// 估算输入 token：中文等 CJK 字符近似一个 token，其他 Unicode 字符每四个近似一个 token。
    static func estimatedInputTokens(for text: String) -> Int {
        let cjkCount = text.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }.count
        let remainingCount = max(0, text.unicodeScalars.count - cjkCount)
        return cjkCount + Int(ceil(Double(remainingCount) / 4)) + promptOverheadTokens
    }
}

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText: String
    @Published var errorMessage: String?
    @Published private(set) var outputs: [TranslationOutput] = []
    @Published private(set) var providerConfigurations: [TranslationProviderConfiguration] = []
    @Published var llmConfigurations: [LLMTranslationConfiguration] = []
    @Published var mode: TranslationWindowMode
    /// 当前持久化翻译工作区的 ClipboardItem 标识；nil 表示用户尚未实际发起翻译。
    @Published private(set) var historyItemID: UUID?

    /// 正在运行的网络请求，按译文卡片标识保存以支持单卡取消。
    private var activeRequests: [UUID: URLSessionDataTask] = [:]
    /// 用户取消后忽略服务端迟到回调，避免“已取消”又被覆盖为请求错误。
    private var cancelledOutputIDs: Set<UUID> = []

    init(sourceText: String, mode: TranslationWindowMode) {
        self.sourceText = sourceText
        self.mode = mode
        self.historyItemID = nil
        refreshConfigurations()
    }

    func reset(sourceText: String, mode: TranslationWindowMode) {
        cancelAll()
        self.sourceText = sourceText
        self.mode = mode
        historyItemID = nil
        outputs = []
        errorMessage = nil
        refreshConfigurations()
        if mode == .immediate {
            translateUsingAPI()
        }
    }

    /// 从翻译分类中恢复一次历史翻译，使主面板预览回到用户当时的完整翻译窗口。
    func restoreHistory(itemID: UUID) -> Bool {
        guard let workspace = TranslationWorkspaceCache.load(itemID: itemID) else {
            return false
        }
        cancelAll()
        sourceText = workspace.sourceText
        outputs = workspace.outputs.map { output in
            var output = output
            output.isTranslating = false
            return output
        }
        self.historyItemID = itemID
        errorMessage = nil
        mode = .input
        refreshConfigurations()
        return true
    }

    func translateUsingAPI() {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        refreshConfigurations()
        let enabledConfigurations = providerConfigurations.filter(\.isConfigured)
        guard !enabledConfigurations.isEmpty else {
            errorMessage = "请先在“设置 -> 翻译”中启用并配置至少一种常规翻译 API"
            return
        }

        ensureWorkspace(source: source)
        errorMessage = nil
        let targetLanguage = TranslateService.detectTargetLanguage(for: source)
        cancelOutputs(of: .api)
        outputs.removeAll { $0.kind == .api }

        for configuration in enabledConfigurations {
            let outputID = configuration.id
            outputs.append(TranslationOutput(
                id: outputID,
                kind: .api,
                configurationID: configuration.id,
                providerName: configuration.name.isEmpty ? configuration.kind.displayName : configuration.name,
                detail: configuration.kind.displayName,
                translatedText: "",
                errorMessage: nil,
                isTranslating: true
            ))
            startAPITranslation(
                outputID: outputID,
                configuration: configuration,
                source: source,
                targetLanguage: targetLanguage
            )
        }
        saveWorkspace()
    }

    /// 新增一张大模型译文卡片，而不是覆盖现有的常规 API 或其他模型结果，方便逐项比较。
    func translateUsingLLM(_ configuration: LLMTranslationConfiguration) {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        guard configuration.isConfigured else {
            errorMessage = "所选大模型尚未完成配置"
            return
        }

        ensureWorkspace(source: source)
        let outputID = UUID()
        let targetLanguage = TranslateService.detectTargetLanguage(for: source)
        errorMessage = nil
        outputs.append(TranslationOutput(
            id: outputID,
            kind: .llm,
            configurationID: configuration.id,
            providerName: configuration.name,
            detail: configuration.model,
            translatedText: "",
            errorMessage: nil,
            isTranslating: true
        ))
        startLLMTranslation(
            outputID: outputID,
            configuration: configuration,
            source: source,
            targetLanguage: targetLanguage
        )
        saveWorkspace()
    }

    /// 当前原文是否超过大模型翻译的风险提示阈值；调用方确认后仍可继续发送请求。
    func requiresLLMTokenConfirmation() -> Bool {
        LLMTranslationTokenSafety.estimatedInputTokens(for: sourceText)
            > LLMTranslationTokenSafety.warningTokenLimit
    }

    /// 当前原文的估算输入 token，用于给确认弹窗展示透明的风险依据。
    var estimatedLLMInputTokens: Int {
        LLMTranslationTokenSafety.estimatedInputTokens(for: sourceText)
    }

    /// 取消仍在请求中的单张译文卡片。
    func cancelOutput(id: UUID) {
        guard let index = outputs.firstIndex(where: { $0.id == id }), outputs[index].isTranslating else {
            return
        }
        cancelledOutputIDs.insert(id)
        activeRequests[id]?.cancel()
        activeRequests[id] = nil
        outputs[index].isTranslating = false
        outputs[index].errorMessage = "已取消"
        saveWorkspace()
    }

    /// 用当前仍存在的同一配置重新发起失败或已取消的译文请求。
    func retryOutput(id: UUID) {
        guard let output = outputs.first(where: { $0.id == id }) else { return }
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let targetLanguage = TranslateService.detectTargetLanguage(for: source)
        guard let index = outputs.firstIndex(where: { $0.id == id }) else { return }
        outputs[index].translatedText = ""
        outputs[index].errorMessage = nil
        outputs[index].isTranslating = true
        cancelledOutputIDs.remove(id)

        switch output.kind {
        case .api:
            guard let configuration = providerConfigurations.first(where: { $0.id == output.configurationID && $0.isConfigured }) else {
                outputs[index].isTranslating = false
                outputs[index].errorMessage = "原翻译 API 已删除或未完成配置"
                saveWorkspace()
                return
            }
            startAPITranslation(outputID: id, configuration: configuration, source: source, targetLanguage: targetLanguage)
        case .llm:
            guard let configuration = llmConfigurations.first(where: { $0.id == output.configurationID && $0.isConfigured }) else {
                outputs[index].isTranslating = false
                outputs[index].errorMessage = "原大模型已删除或未完成配置"
                saveWorkspace()
                return
            }
            startLLMTranslation(outputID: id, configuration: configuration, source: source, targetLanguage: targetLanguage)
        }
        saveWorkspace()
    }

    /// 关闭或切换翻译窗口时取消全部未完成请求，避免后台请求继续消耗额度。
    func cancelAll() {
        let activeOutputIDs = Array(activeRequests.keys)
        for outputID in activeOutputIDs {
            cancelOutput(id: outputID)
        }
    }

    private func completeOutput(id: UUID, result: Result<String, Error>) {
        activeRequests[id] = nil
        guard !cancelledOutputIDs.contains(id) else { return }
        guard let index = outputs.firstIndex(where: { $0.id == id }) else { return }
        outputs[index].isTranslating = false
        switch result {
        case .success(let translatedText):
            outputs[index].translatedText = translatedText
            outputs[index].errorMessage = nil
        case .failure(let error):
            if let urlError = error as? URLError, urlError.code == .timedOut {
                outputs[index].errorMessage = "请求超时，请重试"
            } else if let urlError = error as? URLError, urlError.code == .cancelled {
                outputs[index].errorMessage = "已取消"
            } else {
                outputs[index].errorMessage = error.localizedDescription
            }
        }
        saveWorkspace()
    }

    private func startAPITranslation(
        outputID: UUID,
        configuration: TranslationProviderConfiguration,
        source: String,
        targetLanguage: String
    ) {
        let task = TranslateService(configuration: configuration).translateSegment(source, to: targetLanguage) { [weak self] result in
            DispatchQueue.main.async {
                self?.completeOutput(id: outputID, result: result)
            }
        }
        if let task {
            activeRequests[outputID] = task
        }
    }

    private func startLLMTranslation(
        outputID: UUID,
        configuration: LLMTranslationConfiguration,
        source: String,
        targetLanguage: String
    ) {
        let task = LLMTranslationService(configuration: configuration).translate(source, targetLanguage: targetLanguage) { [weak self] result in
            DispatchQueue.main.async {
                self?.completeOutput(id: outputID, result: result)
            }
        }
        if let task {
            activeRequests[outputID] = task
        }
    }

    private func cancelOutputs(of kind: TranslationOutputKind) {
        let outputIDs = outputs.filter { $0.kind == kind && $0.isTranslating }.map(\.id)
        for outputID in outputIDs {
            cancelOutput(id: outputID)
        }
    }

    private func ensureWorkspace(source: String) {
        guard historyItemID == nil else { return }
        historyItemID = TranslationWorkspaceCache.create(sourceText: source)
    }

    private func saveWorkspace() {
        guard let historyItemID else { return }
        TranslationWorkspaceCache.save(itemID: historyItemID, outputs: outputs)
    }

    private func refreshConfigurations() {
        let settings = Self.fetchSettings()
        providerConfigurations = settings.translationProviderConfigurations
        llmConfigurations = settings.llmTranslationConfigurations.filter(\.isConfigured)
    }

    private static func fetchSettings() -> AppSettings {
        let context = ModelContext(AppModelContainer.container)
        return (try? context.fetch(FetchDescriptor<AppSettings>()).first) ?? AppSettings()
    }
}

// MARK: - Translation Window

/// 翻译工作区窗口统一响应 responder chain 的取消操作，让 Esc 与 Command + W 走同一关闭流程。
private final class TranslationWorkspaceWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        // TextEditor 会成为 first responder，因此在窗口分发层截获无修饰键 Esc，确保编辑状态下也能可靠关闭。
        let blockingModifiers = event.modifierFlags.intersection([.command, .control, .option])
        if event.type == .keyDown, event.keyCode == 53, blockingModifiers.isEmpty {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

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
        let window = TranslationWorkspaceWindow(contentViewController: hostingController)
        window.identifier = translationWorkspaceWindowIdentifier
        window.title = "PasteDeck 翻译"
        // 与剪贴板主面板和普通预览保持相同层级，使最近一次用户触发的窗口可确定地位于最前。
        window.level = .popUpMenu
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 460, height: 360)
        window.setContentSize(NSSize(width: 760, height: 680))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.onCancel = { [weak window] in
            window?.performClose(nil)
        }
        window.appearance = AppearanceResolver.currentAppearance
        window.center()
        self.viewModel = viewModel
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        if mode == .immediate {
            viewModel.translateUsingAPI()
        }
    }

    /// 打开已缓存的翻译工作区；缓存不存在或损坏时不创建空白窗口，避免误导用户。
    func showHistory(itemID: UUID) {
        if let window, let viewModel {
            guard viewModel.restoreHistory(itemID: itemID) else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let workspace = TranslationWorkspaceCache.load(itemID: itemID) else { return }
        let viewModel = TranslationViewModel(sourceText: workspace.sourceText, mode: .input)
        guard viewModel.restoreHistory(itemID: itemID) else { return }
        let rootView = TranslationWorkspaceView(model: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = TranslationWorkspaceWindow(contentViewController: hostingController)
        window.identifier = translationWorkspaceWindowIdentifier
        window.title = "PasteDeck 翻译"
        // 历史翻译工作区也必须覆盖仍可见的剪贴板主面板。
        window.level = .popUpMenu
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 460, height: 360)
        window.setContentSize(NSSize(width: 760, height: 680))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.onCancel = { [weak window] in
            window?.performClose(nil)
        }
        window.appearance = AppearanceResolver.currentAppearance
        window.center()
        self.viewModel = viewModel
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showError(_ message: String) {
        show(text: "", mode: .input)
        viewModel?.errorMessage = message
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        viewModel?.cancelAll()
        window?.contentViewController = nil
        window = nil
        viewModel = nil
        restoreMainPanelFocus()
    }

    /// 翻译工作区关闭后恢复仍可见的剪贴板主面板焦点，与普通预览窗口保持一致。
    private func restoreMainPanelFocus() {
        let panelController = NSApp.windows
            .compactMap { $0.delegate as? MainPanelController }
            .first
        panelController?.restorePanelFocus()
    }
}

private struct TranslationWorkspaceView: View {
    @ObservedObject var model: TranslationViewModel
    @FocusState private var sourceFocused: Bool
    @State private var pendingLLMConfiguration: LLMTranslationConfiguration?

    private var hasSource: Bool {
        !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var configuredProviderCount: Int {
        model.providerConfigurations.filter(\.isConfigured).count
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceCard

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !model.llmConfigurations.isEmpty {
                        llmModelStrip
                    }

                    resultSection
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 460, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            sourceFocused = model.mode == .input
        }
        .onChange(of: model.mode) { _, mode in
            sourceFocused = mode == .input
        }
        .alert(
            "长文本翻译风险提示",
            isPresented: Binding(
                get: { pendingLLMConfiguration != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingLLMConfiguration = nil
                    }
                }
            ),
            presenting: pendingLLMConfiguration
        ) { configuration in
            Button("取消", role: .cancel) {
                pendingLLMConfiguration = nil
            }
            Button("仍要翻译") {
                model.translateUsingLLM(configuration)
                pendingLLMConfiguration = nil
            }
        } message: { _ in
            Text("原文预计约 \(model.estimatedLLMInputTokens.formatted()) token，超过 \(LLMTranslationTokenSafety.warningTokenLimit.formatted()) token 提示阈值。长文本可能产生较高费用，或超出所选模型的上下文限制。是否继续？")
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.68)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("翻译工作区")
                    .font(.system(size: 17, weight: .semibold))
                Text("自动识别中英文 · 多结果并排对比")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Label("\(configuredProviderCount) 个服务", systemImage: "bolt.horizontal.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.055), in: Capsule())

            Text("Esc 关闭")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("原文", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.sourceText.count.formatted()) 字符")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $model.sourceText)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .focused($sourceFocused)
                .padding(10)
                .frame(height: 148)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(sourceFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Label(
                    configuredProviderCount == 0 ? "请先配置翻译服务" : "将由已启用服务并行生成结果",
                    systemImage: configuredProviderCount == 0 ? "gearshape" : "bolt.fill"
                )
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                Spacer()

                Button {
                    model.translateUsingAPI()
                } label: {
                    Label(model.outputs.isEmpty ? "翻译" : "重新翻译", systemImage: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasSource || configuredProviderCount == 0)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var llmModelStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("大模型对比", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("点击模型追加一张译文卡片")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.llmConfigurations) { configuration in
                        Button {
                            requestLLMTranslation(configuration)
                        } label: {
                            HStack(spacing: 8) {
                                TranslationBrandLogoView(brand: configuration.translationBrand, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(configuration.name)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(configuration.model)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasSource)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if model.outputs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.secondary)
                Text("译文会显示在这里")
                    .font(.system(size: 14, weight: .semibold))
                Text("点击原文卡片中的“翻译”，或选择一个大模型开始对比。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("翻译结果", systemImage: "rectangle.3.group")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(model.outputs.count) 张卡片")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(model.outputs) { output in
                        translationCard(output)
                    }
                }
            }
        }
    }

    private func translationCard(_ output: TranslationOutput) -> some View {
        let outputBrand = translationBrand(for: output)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                TranslationBrandLogoView(brand: outputBrand, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(output.providerName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(output.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if output.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                    Button {
                        model.cancelOutput(id: output.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("取消翻译")
                }
                if !output.translatedText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output.translatedText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("复制译文")
                }
            }

            ScrollView(.vertical) {
                Text(output.translatedText.isEmpty ? (output.errorMessage == nil ? "正在等待译文…" : "") : output.translatedText)
                    .font(.system(size: 15))
                    .foregroundColor(output.translatedText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150, maxHeight: 210)

            if let errorMessage = output.errorMessage {
                HStack(spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Button("重试") {
                        model.retryOutput(id: output.id)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// 历史工作区可能引用已删除的配置，因此优先按稳定配置 ID 查找，再用卡片文本兜底识别品牌。
    private func translationBrand(for output: TranslationOutput) -> TranslationBrand? {
        switch output.kind {
        case .api:
            return model.providerConfigurations
                .first(where: { $0.id == output.configurationID })?
                .kind.translationBrand
                ?? TranslationBrand.infer(providerName: output.providerName, detail: output.detail)
        case .llm:
            return model.llmConfigurations
                .first(where: { $0.id == output.configurationID })?
                .translationBrand
                ?? TranslationBrand.infer(providerName: output.providerName, detail: output.detail)
        }
    }

    private func requestLLMTranslation(_ configuration: LLMTranslationConfiguration) {
        if model.requiresLLMTokenConfirmation() {
            pendingLLMConfiguration = configuration
            return
        }
        model.translateUsingLLM(configuration)
    }
}

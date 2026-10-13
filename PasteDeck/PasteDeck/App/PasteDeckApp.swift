//
//  PasteDeckApp.swift
//  PasteDeck
//
//  A macOS clipboard manager that records all copied content
//  and provides quick access via keyboard shortcut.
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

extension Notification.Name {
    static let openWorkbench = Notification.Name("openWorkbench")
}

@main
struct PasteDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// SwiftData container for clipboard items and app settings
    let modelContainer: ModelContainer

    init() {
        modelContainer = AppModelContainer.container

        // 确保“收藏”和“翻译”两个系统分类存在，并保持翻译紧随收藏之后。
        Self.seedSystemCollections(context: modelContainer.mainContext)
    }

    /// 如果数据库中缺少系统分类则创建，并将普通收藏夹顺延，保证翻译分类始终紧随收藏。
    private static func seedSystemCollections(context: ModelContext) {
        let collections = (try? context.fetch(FetchDescriptor<FavoriteCollection>())) ?? []
        let defaultCollection = collections.first(where: \.isDefault)
        let translationCollection = collections.first(where: \.isTranslation)

        if defaultCollection == nil {
            context.insert(FavoriteCollection(name: "收藏", sortOrder: 0, isDefault: true))
        }

        if translationCollection == nil {
            for collection in collections where !collection.isDefault {
                collection.sortOrder += 1
            }
            context.insert(FavoriteCollection(name: "翻译", sortOrder: 1, isTranslation: true))
        }

        let systemCollections = ((try? context.fetch(FetchDescriptor<FavoriteCollection>())) ?? [])
        systemCollections.first(where: \.isDefault)?.sortOrder = 0
        systemCollections.first(where: \.isTranslation)?.sortOrder = 1
        try? context.save()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - App Delegate

/// Main application delegate handling lifecycle, status bar, and services
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenuDelegate: MenuRefreshDelegate?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyManager: HotKeyManager?
    private var mainPanelController: MainPanelController?
    private var settingsWindow: NSWindow?
    private var settingsWindowFrame: NSRect?
    private var settingsKeyMonitor: Any?
    private var isMenuBarQuotaDisplayEnabled = false
    private var quotaStatusObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup UI first (status bar is always available)
        setupStatusBar()

        WorkbenchWindowController.shared.onOpenSettings = { [weak self] in
            self?.openSettings(pane: .general)
        }

        // Start services (HotKeyManager handles accessibility permission gracefully)
        setupServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainPanelController?.savePanelFrame()
        TranslationCoordinator.shared.stop()
        hotKeyManager?.unregister()
        removeSettingsAppearanceObserver()
        if let settingsKeyMonitor {
            NSEvent.removeMonitor(settingsKeyMonitor)
        }
        if let quotaStatusObserver {
            NotificationCenter.default.removeObserver(quotaStatusObserver)
        }
    }

    // MARK: - Status Bar Setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // 使用更明确的剪贴板图标
            let image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "PasteDeck")
            image?.isTemplate = true
            button.image = image
            button.imageScaling = .scaleProportionallyDown
        }

        let (menu, delegate) = StatusMenuBuilder.buildMenu(
            openWorkbench: { [weak self] in
                self?.openWorkbench()
            },
            openMainPanel: { [weak self] in
                self?.openMainPanel()
            },
            openStats: { [weak self] in
                self?.openSettings(pane: .stats)
            },
            translateSelection: {
                Task { @MainActor in
                    TranslationCoordinator.shared.translateSelectedText()
                }
            },
            translateScreenshot: {
                Task { @MainActor in
                    TranslationCoordinator.shared.captureAndTranslate()
                }
            },
            translateInput: {
                Task { @MainActor in
                    TranslationCoordinator.shared.openInputTranslation()
                }
            },
            openTranslationSettings: { [weak self] in
                self?.openSettings(pane: .translation)
            },
            openQuotaSettings: { [weak self] in
                self?.openSettings(pane: .quota)
            },
            openSettings: { [weak self] in
                self?.openSettings(pane: .general)
            },
            openHelp: { [weak self] in
                self?.openSettings(pane: .help)
            },
            quit: { [weak self] in
                self?.quitApp()
            }
        )
        statusMenuDelegate = delegate
        statusItem?.menu = menu
    }

    // MARK: - Services Setup

    /// Start all background services. Requires accessibility permission.
    private func setupServices() {
        // Guard: don't start twice
        guard clipboardMonitor == nil else { return }

        // Start clipboard monitoring
        let modelContext = ModelContext(AppModelContainer.container)
        clipboardMonitor = ClipboardMonitor(modelContext: modelContext)
        clipboardMonitor?.startMonitoring()

        // Connect clipboard monitor to paste service
        PasteService.shared.setClipboardMonitor(clipboardMonitor!)

        // Register global hotkey from AppSettings
        let settingsContext = ModelContext(AppModelContainer.container)
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let appSettings = (try? settingsContext.fetch(settingsDescriptor).first) ?? AppSettings()

        hotKeyManager = HotKeyManager.shared
        hotKeyManager?.registerHotKey(
            keyCode: UInt32(appSettings.hotkeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(appSettings.hotkeyModifiers))
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleMainPanel()
            }
        }

        // 翻译协调器独立注册 Option+D / Option+S / Option+A，并按设置启停划词监听。
        TranslationCoordinator.shared.start()

        // 额度查询：按设置应用菜单栏余额显示，并延迟做首次后台刷新，避免抢占启动。
        let quotaMenuBarEnabled = appSettings.showQuotaInMenuBar ?? false
        QuotaStatusManager.shared.setMenuBarDisplayEnabled(quotaMenuBarEnabled)
        applyMenuBarQuotaDisplay(enabled: quotaMenuBarEnabled)
        quotaStatusObserver = NotificationCenter.default.addObserver(
            forName: QuotaStatusManager.statusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshMenuBarQuotaTitle()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quotaMenuBarDisplaySettingDidChange(_:)),
            name: QuotaStatusManager.menuBarDisplayDidChange,
            object: nil
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            QuotaStatusManager.shared.refreshIfStale(maxAge: 0)
        }

        // 监听快捷键变更通知（设置页修改快捷键后发送）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleMainPanel),
            name: .toggleMainPanel,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openWorkbench),
            name: .openWorkbench,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings as () -> Void),
            name: .openSettingsWindow,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideMainPanelForScreenshotTranslation),
            name: .mainPanelShouldCloseForScreenshotTranslation,
            object: nil
        )

        // Main panel is created lazily on first use so app launch does not
        // pay the SwiftUI/SwiftData history-loading cost.
    }

    // MARK: - Menu Bar Quota Display

    /// 应用“菜单栏显示余额”开关：调整状态项长度并刷新文本。
    private func applyMenuBarQuotaDisplay(enabled: Bool) {
        isMenuBarQuotaDisplayEnabled = enabled
        guard let statusItem else { return }

        if enabled {
            statusItem.length = NSStatusItem.variableLength
            refreshMenuBarQuotaTitle()
        } else {
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.toolTip = nil
            statusItem.length = NSStatusItem.squareLength
        }
    }

    /// 余额快照变化后重写菜单栏文本；未开启显示或暂无数据时仅保留图标。
    private func refreshMenuBarQuotaTitle() {
        guard isMenuBarQuotaDisplayEnabled, let button = statusItem?.button else { return }
        button.attributedTitle = QuotaStatusManager.shared.menuBarAttributedTitle ?? NSAttributedString()
        button.toolTip = QuotaStatusManager.shared.menuBarToolTip
    }

    @objc private func quotaMenuBarDisplaySettingDidChange(_ notification: Notification) {
        let enabled = (notification.userInfo?[QuotaStatusManager.menuBarDisplayEnabledKey] as? Bool) ?? false
        QuotaStatusManager.shared.setMenuBarDisplayEnabled(enabled)
        applyMenuBarQuotaDisplay(enabled: enabled)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 登录启动时不创建主面板，保持剪贴板监听和菜单栏服务静默运行；用户重新打开已运行的应用时再展示主面板。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        self.openMainPanel()
        return false
    }

    // MARK: - Menu Actions

    @objc private func openWorkbench() {
        WorkbenchWindowController.shared.showWorkbench()
    }

    @objc private func openMainPanel() {
        mainPanelControllerForUse().showPanel()
    }

    @objc private func openSettings() {
        openSettings(pane: .general)
    }

    /// 打开设置窗口并定位到指定设置页。
    /// - Parameter pane: 初次打开时选中的设置页；若窗口已存在则忽略并直接前置。
    private func openSettings(pane: SettingsPane) {
        // 如果已有设置窗口且可见，直接前置
        if let existing = settingsWindow, existing.isVisible {
            NotificationCenter.default.post(name: .selectSettingsPane, object: pane)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow(initialPane: pane)
            .modelContainer(AppModelContainer.container)
            .themeStyled()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PasteDeck 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentMinSize = SettingsWindowLayout.minimumContentSize
        window.setContentSize(SettingsWindowLayout.defaultContentSize)
        // 按当前外观模式渲染设置页（浅色/深色/跟随系统）。
        window.appearance = AppearanceResolver.currentAppearance
        installSettingsAppearanceObserver()
        if let settingsWindowFrame {
            window.setFrame(settingsWindowFrame, display: false)
        } else {
            window.center()
        }
        settingsWindow = window
        installSettingsKeyMonitorIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 确保有"窗口"菜单包含"关闭"项，使 ⌘+W 可用
        ensureWindowMenuExists()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleMainPanel() {
        mainPanelControllerForUse().togglePanel()
    }

    /// 截图翻译不把剪贴板面板当作截图目标。若面板已打开，先主动关闭它但保持应用不隐藏，
    /// 再由协调器在下一轮主线程事件循环展示截图选择层，确保窗口焦点交接只有一个确定顺序。
    @objc private func hideMainPanelForScreenshotTranslation() {
        mainPanelController?.hidePanel(shouldHideApp: false)
    }

    private func mainPanelControllerForUse() -> MainPanelController {
        if let mainPanelController {
            return mainPanelController
        }
        let controller = MainPanelController()
        controller.settingsWindowProvider = { [weak self] in
            self?.settingsWindow
        }
        mainPanelController = controller
        return controller
    }

    // MARK: - Window Menu

    /// 确保应用菜单栏包含"窗口"菜单（含"关闭"项），使 ⌘+W 可用
    private func ensureWindowMenuExists() {
        // 如果已经有窗口菜单则跳过
        if NSApp.mainMenu?.items.contains(where: { $0.title == "窗口" }) == true {
            return
        }

        let windowMenu = NSMenu(title: "窗口")

        let closeItem = NSMenuItem(title: "关闭", action: #selector(handleCloseWindowMenuItem(_:)), keyEquivalent: "w")
        closeItem.target = self
        windowMenu.addItem(closeItem)

        windowMenu.addItem(NSMenuItem.separator())

        let minimizeItem = NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomItem)

        let menuItem = NSMenuItem()
        menuItem.title = "窗口"
        menuItem.submenu = windowMenu

        // 插入到帮助菜单之前，如果没有帮助菜单则追加到末尾
        if let helpIndex = NSApp.mainMenu?.items.firstIndex(where: { $0.title == "帮助" }) {
            NSApp.mainMenu?.insertItem(menuItem, at: helpIndex)
        } else {
            NSApp.mainMenu?.addItem(menuItem)
        }
    }

    /// 统一响应系统菜单的 ⌘W 快捷键：严格只关闭最前方的单个活跃窗口，绝不连带穿透
    @objc private func handleCloseWindowMenuItem(_ sender: Any?) {
        CloseWindowDispatcher.closeFrontmostWindowOnly()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === settingsWindow else { return }
        removeSettingsAppearanceObserver()
        releaseSettingsWindow(closingWindow)
    }

    private func releaseSettingsWindow(_ window: NSWindow) {
        settingsWindowFrame = window.frame
        window.delegate = nil
        window.contentViewController = nil
        if window === settingsWindow {
            settingsWindow = nil
        }
    }

    private var settingsAppearanceObserver: NSObjectProtocol?

    /// 设置页打开期间监听外观模式变更，实时更新设置窗口外观。
    private func installSettingsAppearanceObserver() {
        guard settingsAppearanceObserver == nil else { return }
        settingsAppearanceObserver = NotificationCenter.default.addObserver(
            forName: .appearanceModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.settingsWindow?.appearance = AppearanceResolver.currentAppearance
            }
        }
    }

    private func removeSettingsAppearanceObserver() {
        if let observer = settingsAppearanceObserver {
            NotificationCenter.default.removeObserver(observer)
            settingsAppearanceObserver = nil
        }
    }

    private func installSettingsKeyMonitorIfNeeded() {
        guard settingsKeyMonitor == nil else { return }

        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleSettingsKey(event)
        }
    }

    private func handleSettingsKey(_ event: NSEvent) -> NSEvent? {
        guard let settingsWindow, settingsWindow.isVisible else { return event }
        guard NSApp.keyWindow === settingsWindow else { return event }
        guard settingsWindow.attachedSheet == nil else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 || (event.keyCode == 13 && modifiers == .command) {
            settingsWindow.performClose(nil)
            return nil
        }

        return event
    }
}

// MARK: - Model Container Singleton

enum AppModelContainer {
    static var storeURL: URL {
        let appSupportURL: URL
        if let overridePath = ProcessInfo.processInfo.environment["PASTEDECK_STORE_URL"] {
            // 测试支撑：允许 QA 运行使用隔离的存储目录，避免触碰真实历史数据。
            appSupportURL = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            appSupportURL = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        }

        let pasteDeckURL = appSupportURL.appendingPathComponent("com.pastedeck.app")
        try? FileManager.default.createDirectory(at: pasteDeckURL, withIntermediateDirectories: true)
        return pasteDeckURL.appendingPathComponent("PasteDeck.sqlite")
    }

    static let container: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
            AppSettings.self,
            FavoriteCollection.self,
            DailyStatsSnapshot.self,
            TranslationUsageSnapshot.self
        ])

        let url = storeURL
        let modelConfiguration = ModelConfiguration(url: url, allowsSave: true)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }()
}

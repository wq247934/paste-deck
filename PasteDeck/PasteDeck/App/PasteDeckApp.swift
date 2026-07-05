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

@main
struct PasteDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// SwiftData container for clipboard items and app settings
    let modelContainer: ModelContainer

    init() {
        modelContainer = AppModelContainer.container

        // 确保默认收藏夹存在
        Self.seedDefaultCollection(context: modelContainer.mainContext)
    }

    /// 如果数据库中没有默认收藏夹，创建一个
    private static func seedDefaultCollection(context: ModelContext) {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.isDefault == true }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        if count == 0 {
            let defaultCollection = FavoriteCollection(name: "收藏", sortOrder: 0, isDefault: true)
            context.insert(defaultCollection)
            try? context.save()
        }
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
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyManager: HotKeyManager?
    private var mainPanelController: MainPanelController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup UI first (status bar is always available)
        setupStatusBar()

        // Start services (HotKeyManager handles accessibility permission gracefully)
        setupServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
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

        // Create menu
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开 PasteDeck", action: #selector(openMainPanel), keyEquivalent: "v")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 PasteDeck", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

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

        // 监听快捷键变更通知（设置页修改快捷键后发送）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleMainPanel),
            name: .toggleMainPanel,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettingsWindow,
            object: nil
        )

        // Main panel is created lazily on first use so app launch does not
        // pay the SwiftUI/SwiftData history-loading cost.
    }

    // MARK: - Menu Actions

    @objc private func openMainPanel() {
        mainPanelControllerForUse().showPanel()
    }

    @objc private func openSettings() {
        // 如果已有设置窗口且可见，直接前置
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindow()
            .modelContainer(AppModelContainer.container)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PasteDeck 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window

        // 确保有"窗口"菜单包含"关闭"项，使 ⌘+W 可用
        ensureWindowMenuExists()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleMainPanel() {
        mainPanelControllerForUse().togglePanel()
    }

    private func mainPanelControllerForUse() -> MainPanelController {
        if let mainPanelController {
            return mainPanelController
        }
        let controller = MainPanelController()
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

        let closeItem = NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
}

// MARK: - Model Container Singleton

enum AppModelContainer {
    static let container: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
            AppSettings.self,
            FavoriteCollection.self
        ])

        let appSupportURL = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let pasteDeckURL = appSupportURL.appendingPathComponent("com.pastedeck.app")
        try? FileManager.default.createDirectory(at: pasteDeckURL, withIntermediateDirectories: true)

        let storeURL = pasteDeckURL.appendingPathComponent("PasteDeck.sqlite")

        let modelConfiguration = ModelConfiguration(url: storeURL, allowsSave: true)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }()
}

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

        // 注入测试数据（仅当数据库为空时执行一次）
        injectTestDataIfNeeded()

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

        // Initialize main panel controller
        mainPanelController = MainPanelController()
    }

    // MARK: - Menu Actions

    @objc private func openMainPanel() {
        mainPanelController?.showPanel()
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

    // MARK: - Test Data Injection

    /// 仅当数据库为空时注入测试数据（一次性，方便验证历史记录清理功能）
    private func injectTestDataIfNeeded() {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<ClipboardItem>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let now = Date()
        let calendar = Calendar.current

        let sampleTexts = [
            "今天复制的内容", "会议记录：讨论Q3产品路线图", "代码片段：func hello() { print(\"hi\") }",
            "记得买牛奶", "https://developer.apple.com", "提交季度报告",
            "SwiftUI 学习笔记", "项目启动会", "// TODO: fix this later",
            "尊敬的客户，感谢您的来信", "健身房会员到期", "周末约了朋友吃饭",
            "航班信息：CA1234 北京-上海", "密码：Abc@123456", "生日提醒：妈妈 3月15日",
            "git commit -m 'fix: resolve merge conflict'", "外卖地址：朝阳区xxx路xx号",
            "银行卡尾号 8888", "快递单号：SF1234567890", "WiFi密码：MyWiFi2024",
            "docker run -d -p 8080:80 nginx", "npm install -g typescript",
            "pip install requests", "curl -X GET https://api.example.com",
            "SELECT * FROM users WHERE active = true", "ssh user@192.168.1.100",
            "TODO: 完成PPT", "明天下午3点客户电话会议", "采购清单：键盘、鼠标、显示器",
            "汇率：1 USD = 7.24 CNY", "python3 -m venv .venv", "kubectl get pods -n default",
        ]

        let totalCount = 2000
        for i in 0..<totalCount {
            let text = sampleTexts[i % sampleTexts.count] + " #\(i + 1)"
            // 时间分布：50%在最近7天，30%在8-30天，15%在1-3个月，5%在4-6个月
            let random = Int.random(in: 0..<100)
            let daysAgo: Int
            if random < 50 {
                daysAgo = -Int.random(in: 0...7)
            } else if random < 80 {
                daysAgo = -Int.random(in: 8...30)
            } else if random < 95 {
                daysAgo = -Int.random(in: 31...90)
            } else {
                daysAgo = -Int.random(in: 91...180)
            }

            let date = calendar.date(byAdding: .day, value: daysAgo, to: now)!
            let item = ClipboardItem(
                contentType: .text,
                textContent: text,
                sourceApp: "测试数据"
            )
            item.createdAt = date
            context.insert(item)
        }

        try? context.save()
        NSLog("[PasteDeck] Injected \(totalCount) test data items")
    }

    @objc private func toggleMainPanel() {
        mainPanelController?.togglePanel()
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

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
        do {
            let schema = Schema([
                ClipboardItem.self,
                AppSettings.self
            ])

            // 创建专属的存储路径
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            // 使用 Bundle ID 作为子目录，确保数据隔离
            let pasteDeckURL = appSupportURL.appendingPathComponent("com.pastedeck.app")

            // 创建目录（如果不存在）
            try FileManager.default.createDirectory(at: pasteDeckURL, withIntermediateDirectories: true)

            // 指定数据库文件路径
            let storeURL = pasteDeckURL.appendingPathComponent("PasteDeck.sqlite")

            // 创建 ModelConfiguration
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true
            )

            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
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

        // Register global hotkey: ⌘+Shift+V (keyCode 9 = V)
        // HotKeyManager internally handles missing permission (graceful degradation)
        hotKeyManager = HotKeyManager()
        hotKeyManager?.registerHotKey(keyCode: 9, modifiers: [.command, .shift]) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleMainPanel()
            }
        }

        // Initialize main panel controller
        mainPanelController = MainPanelController()
    }

    // MARK: - Menu Actions

    @objc private func openMainPanel() {
        mainPanelController?.showPanel()
    }

    @objc private func openSettings() {
        let settingsView = SettingsWindow()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func toggleMainPanel() {
        mainPanelController?.togglePanel()
    }
}

// MARK: - Model Container Singleton

/// Shared SwiftData container for the entire app
enum AppModelContainer {
    static let container: ModelContainer = {
        do {
            let schema = Schema([
                ClipboardItem.self,
                AppSettings.self
            ])

            // 创建专属的存储路径
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            // 使用 Bundle ID 作为子目录，确保数据隔离
            let pasteDeckURL = appSupportURL.appendingPathComponent("com.pastedeck.app")

            // 创建目录（如果不存在）
            try FileManager.default.createDirectory(at: pasteDeckURL, withIntermediateDirectories: true)

            // 指定数据库文件路径
            let storeURL = pasteDeckURL.appendingPathComponent("PasteDeck.sqlite")

            // 创建 ModelConfiguration
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true
            )

            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }()
}

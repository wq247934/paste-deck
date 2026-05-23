//
//  PasteDeckApp.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

@main
struct PasteDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                ClipboardItem.self,
                AppSettings.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyManager: HotKeyManager?
    private var mainPanelController: MainPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: 应用启动")
        print("AppDelegate: 应用路径 = \(Bundle.main.bundlePath)")

        // 先检查辅助功能权限，如果没有则请求
        checkAndRequestAccessibilityPermission()

        // Setup status bar icon
        setupStatusBar()

        // Initialize services
        setupServices()
    }

    private func checkAndRequestAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        print("AppDelegate: 辅助功能权限 = \(trusted)")

        if !trusted {
            // 弹出系统权限请求对话框
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

            // 显示提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = """
                PasteDeck 需要辅助功能权限才能：
                • 监听全局快捷键 (⌘+Shift+V)
                • 监控剪切板变化

                请在系统设置中授权：
                系统设置 → 隐私与安全性 → 辅助功能

                点击"打开系统设置"按钮，然后添加 PasteDeck
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后设置")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        hotKeyManager?.unregister()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clipboard.on.clipboard", accessibilityDescription: "PasteDeck")
            button.image?.isTemplate = true
            print("AppDelegate: 菜单栏图标已创建")
        } else {
            print("AppDelegate: 无法创建菜单栏图标")
        }

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

    private func setupServices() {
        let modelContext = ModelContext(AppModelContainer.container)
        clipboardMonitor = ClipboardMonitor(modelContext: modelContext)
        clipboardMonitor?.startMonitoring()
        print("AppDelegate: 剪切板监听已启动")

        // 注册全局快捷键: ⌘+Shift+V
        // V 键的 keyCode 是 9
        hotKeyManager = HotKeyManager()
        hotKeyManager?.registerHotKey(keyCode: 9, modifiers: [.command, .shift]) { [weak self] in
            DispatchQueue.main.async {
                print("AppDelegate: 快捷键回调执行")
                self?.toggleMainPanel()
            }
        }
        print("AppDelegate: 快捷键注册状态 = \(hotKeyManager?.isHotKeyRegistered() ?? false)")

        mainPanelController = MainPanelController()
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if trusted {
            print("Accessibility permission granted")
        } else {
            print("Accessibility permission required for clipboard monitoring and hotkeys")
        }
    }

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
        print("AppDelegate: toggleMainPanel, isVisible=\(mainPanelController != nil)")
        mainPanelController?.togglePanel()
    }
}

// MARK: - Model Container Singleton
enum AppModelContainer {
    static let container: ModelContainer = {
        do {
            let schema = Schema([
                ClipboardItem.self,
                AppSettings.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }()
}

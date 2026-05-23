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
        // Setup status bar icon
        setupStatusBar()

        // Initialize services
        setupServices()

        // Request Accessibility permissions
        requestAccessibilityPermission()
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

        hotKeyManager = HotKeyManager()
        hotKeyManager?.registerHotKey(keyCode: 9, modifiers: [.command, .shift]) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleMainPanel()
            }
        }

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

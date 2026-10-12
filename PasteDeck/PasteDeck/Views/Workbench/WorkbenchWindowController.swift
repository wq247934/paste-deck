//
//  WorkbenchWindowController.swift
//  PasteDeck
//
//  Window controller for the PasteDeck 2.0 productivity workbench.
//  Manages window lifecycle, positioning, minimum sizes, and window restoration.
//

import AppKit
import SwiftUI
import SwiftData

final class WorkbenchWindowController: NSObject, NSWindowDelegate {
    static let shared = WorkbenchWindowController()

    static let windowIdentifier = NSUserInterfaceItemIdentifier("PasteDeckWorkbenchWindow")

    private enum Layout {
        static let defaultSize = NSSize(width: 1080, height: 720)
        static let minimumSize = NSSize(width: 820, height: 520)
        static let frameAutosaveName = "PasteDeck.Workbench.Frame"
    }

    private var window: NSWindow?
    var onOpenSettings: (() -> Void)?

    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    func showWorkbench() {
        if let window = window {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        setupWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWorkbench() {
        window?.orderOut(nil)
    }

    func toggleWorkbench() {
        if isWindowVisible {
            hideWorkbench()
        } else {
            showWorkbench()
        }
    }

    private func setupWindow() {
        let workbenchView = WorkbenchView(
            onClose: { [weak self] in
                self?.hideWorkbench()
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            }
        )
        .modelContainer(AppModelContainer.container)

        let hostingController = NSHostingController(rootView: workbenchView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.identifier = Self.windowIdentifier
        window.title = "PasteDeck 2.0"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = Layout.minimumSize
        window.setContentSize(Layout.defaultSize)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(Layout.frameAutosaveName)

        if !window.setFrameUsingName(Layout.frameAutosaveName) {
            window.center()
        }

        self.window = window
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 关键防护：若处于子窗口关闭冷却期内（刚刚按 ⌘W/Esc 关闭了预览窗口或工具弹窗），
        // 绝对不允许系统顺着 Responder Chain 连带关闭工作台！
        if WindowCloseCooldown.isInCooldown {
            return false
        }
        hideWorkbench()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: Layout.frameAutosaveName)
    }
}

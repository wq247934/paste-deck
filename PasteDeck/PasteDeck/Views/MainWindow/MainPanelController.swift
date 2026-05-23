//
//  MainPanelController.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import SwiftUI
import SwiftData

class MainPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var isVisible = false
    private var canCloseOnResignKey = false

    override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level.floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.delegate = self

        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16

        let hostingView = NSHostingView(rootView: MainPanelView(closeHandler: { [weak self] in
            self?.hidePanel()
        })
        .modelContainer(AppModelContainer.container))

        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = NSView.AutoresizingMask([.width, .height])
        visualEffectView.addSubview(hostingView)

        panel.contentView = visualEffectView

        self.panel = panel
    }

    func showPanel() {
        guard let panel = panel else {
            print("MainPanelController: showPanel - panel is nil")
            return
        }

        print("MainPanelController: showPanel")
        centerPanel(panel)

        // 先设置 canCloseOnResignKey = false，防止刚打开就关闭
        canCloseOnResignKey = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true

        // 延迟 0.3 秒后才允许失去焦点关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.canCloseOnResignKey = true
        }
    }

    func hidePanel() {
        print("MainPanelController: hidePanel")
        canCloseOnResignKey = false
        panel?.orderOut(nil)
        isVisible = false
    }

    func togglePanel() {
        print("MainPanelController: togglePanel, isVisible=\(isVisible)")
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        let x = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - panelSize.height) / 2 + 100

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    func windowDidResignKey(_ notification: Notification) {
        // 只有在允许的情况下才关闭
        if canCloseOnResignKey {
            print("MainPanelController: windowDidResignKey - 关闭窗口")
            hidePanel()
        } else {
            print("MainPanelController: windowDidResignKey - 忽略（刚打开）")
        }
    }
}

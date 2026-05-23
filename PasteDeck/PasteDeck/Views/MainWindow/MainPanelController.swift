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
    private var lastToggleTime: Date = Date.distantPast

    override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level.popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false

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

        canCloseOnResignKey = false
        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true

        // 延迟后才允许失去焦点关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.canCloseOnResignKey = true
            print("MainPanelController: canCloseOnResignKey = true")
        }
    }

    func hidePanel() {
        print("MainPanelController: hidePanel")
        canCloseOnResignKey = false
        panel?.orderOut(nil)
        isVisible = false
    }

    func togglePanel() {
        // 防抖动：300ms 内只响应一次
        let now = Date()
        let elapsed = now.timeIntervalSince(lastToggleTime)
        if elapsed < 0.3 {
            print("MainPanelController: togglePanel 忽略（防抖动）elapsed=\(elapsed)")
            return
        }
        lastToggleTime = now

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
        print("MainPanelController: windowWillClose")
        isVisible = false
    }

    func windowDidResignKey(_ notification: Notification) {
        print("MainPanelController: windowDidResignKey, canCloseOnResignKey=\(canCloseOnResignKey)")
        if canCloseOnResignKey {
            hidePanel()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        print("MainPanelController: windowDidBecomeKey")
    }
}

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

class MainPanelController: NSObject {
    private var panel: NSPanel?
    private var isVisible = false

    override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level.floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16

        let hostingView = NSHostingView(rootView: MainPanelView()
            .modelContainer(AppModelContainer.container))

        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = NSView.AutoresizingMask([.width, .height])
        visualEffectView.addSubview(hostingView)

        panel.contentView = visualEffectView

        self.panel = panel
    }

    func showPanel() {
        guard let panel = panel else { return }

        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hidePanel() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func togglePanel() {
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
}

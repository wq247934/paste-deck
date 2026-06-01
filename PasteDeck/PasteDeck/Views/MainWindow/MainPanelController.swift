//
//  MainPanelController.swift
//  PasteDeck
//
//  Controls the main floating panel that displays clipboard history.
//  Handles panel visibility, positioning, and window lifecycle.
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import SwiftUI
import SwiftData

/// Manages the main floating panel for clipboard history display
class MainPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var isVisible = false

    /// Prevents auto-close when opening preview window
    private var canCloseOnResignKey = false

    /// Debounce timer to prevent rapid toggle from key repeat
    private var lastToggleTime: Date = Date.distantPast

    /// Esc 键监听已移至 KeyboardEventMonitorView 统一处理

    override init() {
        super.init()
        setupPanel()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        // Create floating panel with transparent title bar
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window appearance and behavior
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

        // Add blur background effect
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16

        // Embed SwiftUI view
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

    // MARK: - Public Methods

    /// 临时禁用 resignKey 自动关闭（预览窗口关闭恢复焦点时调用）
    func suspendAutoClose() {
        canCloseOnResignKey = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.canCloseOnResignKey = true
        }
    }

    func showPanel() {
        guard let panel = panel else { return }

        canCloseOnResignKey = false
        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true

        // 通知 MainPanelView 重置焦点和选中状态
        NotificationCenter.default.post(name: .panelDidShow, object: nil)

        // Delay enabling auto-close to prevent immediate dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.canCloseOnResignKey = true
        }
    }

    func hidePanel() {
        canCloseOnResignKey = false
        panel?.orderOut(nil)
        isVisible = false

        // 隐藏面板时清空搜索框、多选和筛选状态
        NotificationCenter.default.post(name: .clearSearchText, object: nil)

        // 清空翻译缓存
        TranslateCache.shared.clear()

        // 隐藏 app 自身，让之前的 app 重新获得焦点
        // 这对后续 simulatePaste(Cmd+V) 至关重要
        NSApp.hide(nil)
    }

    func togglePanel() {
        // Debounce: ignore toggles within 300ms (prevents key repeat issues)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastToggleTime)
        if elapsed < 0.3 { return }
        lastToggleTime = now

        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Private Methods

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        // Center horizontally, slightly above center vertically
        let x = screenFrame.origin.x + (screenFrame.width - panelSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - panelSize.height) / 2 + 100

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }

    func windowDidResignKey(_ notification: Notification) {
        // Check if preview window is open - don't close main panel if so
        let hasPreviewWindow = NSApp.windows.contains { window in
            window.contentViewController?.view is NSHostingView<PreviewWindow>
        }

        // Check if a sheet is attached to the panel (e.g. new collection sheet)
        let hasSheet = panel?.attachedSheet != nil

        // Only auto-close if no preview window or sheet is open
        if canCloseOnResignKey && !hasPreviewWindow && !hasSheet {
            hidePanel()
        }
    }
}

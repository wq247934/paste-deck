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
    private var panel: KeyboardFocusPanel?
    private var isVisible = false

    /// Prevents auto-close when opening preview window
    private var canCloseOnResignKey = false

    /// Identifies the latest focus request so queued work from an older show/hide cycle cannot steal focus.
    private var focusRequestGeneration: UInt = 0

    /// Keeps transient menu or window changes from closing the panel while its key status is being established.
    private var isEstablishingFocus = false

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
        let panel = KeyboardFocusPanel(
            keyboardContentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
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

        // Add blur background effect
        // 使用能跟随 window.appearance 的材质；.hudWindow 会强制暗色，
        // 导致用户选择浅色/跟随系统时主面板仍显示为暗色。
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16

        // Embed SwiftUI view
        let hostingView = NSHostingView(rootView: MainPanelView(closeHandler: { [weak self] in
            self?.hidePanel()
        }, openSettingsHandler: { [weak self] in
            self?.openSettingsFromPanel()
        })
        .modelContainer(AppModelContainer.container))

        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = NSView.AutoresizingMask([.width, .height])
        visualEffectView.addSubview(hostingView)

        panel.contentView = visualEffectView
        self.panel = panel

        // 按当前外观模式渲染（浅色/深色/跟随系统）。
        // 必须在主面板内容装配完成后设置，确保子视图继承该 appearance。
        applyAppearance()

        // 监听设置中的外观模式变更，实时更新已打开的主面板。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceModeChange),
            name: .appearanceModeDidChange,
            object: nil
        )
    }

    /// 将当前外观模式应用到主面板窗口。
    @objc func applyAppearance() {
        panel?.appearance = AppearanceResolver.currentAppearance
    }

    @objc private func handleAppearanceModeChange() {
        applyAppearance()
    }

    // MARK: - Public Methods

    /// 预览窗口关闭后，通过与快捷键呼出相同的路径恢复主面板键盘焦点。
    func restorePanelFocus() {
        guard isVisible, panel?.isVisible == true else { return }
        establishPanelFocus()
    }

    func showPanel() {
        guard let panel = panel else { return }

        // A previous settings/paste flow may have hidden PasteDeck. Unhide the
        // windows without activating the app that owns this non-activating panel.
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }

        canCloseOnResignKey = false
        isVisible = true
        centerPanel(panel)

        // 通知 MainPanelView 重置焦点和选中状态
        NotificationCenter.default.post(name: .panelDidShow, object: nil)

        establishPanelFocus()
    }

    func hidePanel(shouldHideApp: Bool = true) {
        let shouldHideActiveApplication = shouldHideApp && NSApp.isActive

        focusRequestGeneration &+= 1
        isEstablishingFocus = false
        canCloseOnResignKey = false
        isVisible = false
        panel?.orderOut(nil)

        // 隐藏面板时清空搜索框、多选和筛选状态
        NotificationCenter.default.post(name: .clearSearchText, object: nil)

        // 清空翻译缓存
        TranslateCache.shared.clear()

        // 隐藏 app 自身，让之前的 app 重新获得焦点
        // 这对后续 simulatePaste(Cmd+V) 至关重要
        // A non-activating panel leaves the source app active, so hiding
        // PasteDeck is only needed when one of its regular windows was active.
        if shouldHideActiveApplication {
            NSApp.hide(nil)
        }
    }

    func togglePanel() {
        // Debounce: ignore toggles within 300ms (prevents key repeat issues)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastToggleTime)
        if elapsed < 0.3 { return }
        lastToggleTime = now

        // If the panel is visible but failed to become key (for example after a
        // menu, AutoFill popover, or stale show cycle), the shortcut repairs
        // focus instead of treating the panel as successfully open and hiding it.
        if isVisible, panel?.isVisible == true, panel?.isKeyWindow == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func openSettingsFromPanel() {
        hidePanel(shouldHideApp: false)
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }

    // MARK: - Private Methods

    /// Establishes key-window focus immediately and confirms it once after the
    /// current AppKit event (such as status-menu tracking) has completed.
    private func establishPanelFocus() {
        guard let panel, isVisible else { return }

        focusRequestGeneration &+= 1
        let requestGeneration = focusRequestGeneration
        isEstablishingFocus = true
        canCloseOnResignKey = false

        panel.makeKeyAndOrderFront(nil)
        if panel.isKeyWindow {
            requestCardFocus()
        }

        DispatchQueue.main.async { [weak self] in
            self?.confirmPanelFocus(requestGeneration: requestGeneration)
        }
    }

    /// Completes one bounded focus attempt. A protected system surface may
    /// legitimately refuse key status; in that case do not leave a misleading,
    /// visible panel that cannot receive the user's arrow keys.
    private func confirmPanelFocus(requestGeneration: UInt) {
        guard requestGeneration == focusRequestGeneration,
              isVisible,
              let panel,
              panel.isVisible else { return }

        if hasPresentedAuxiliaryWindow {
            isEstablishingFocus = false
            canCloseOnResignKey = true
            return
        }

        panel.makeKeyAndOrderFront(nil)
        guard panel.isKeyWindow else {
            hidePanel(shouldHideApp: false)
            return
        }

        isEstablishingFocus = false
        canCloseOnResignKey = true
        requestCardFocus()
    }

    private func requestCardFocus() {
        NotificationCenter.default.post(name: .panelDidRequestCardFocus, object: panel)
    }

    private var hasPresentedAuxiliaryWindow: Bool {
        let hasPreviewWindow = NSApp.windows.contains { window in
            window.isVisible && window.contentViewController?.view is NSHostingView<PreviewWindow>
        }
        let hasSheet = panel?.attachedSheet != nil
        return hasPreviewWindow || hasSheet
    }

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
        focusRequestGeneration &+= 1
        isEstablishingFocus = false
        canCloseOnResignKey = false
        isVisible = false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let focusedPanel = notification.object as? NSWindow,
              focusedPanel === panel,
              isVisible else { return }

        requestCardFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let resignedPanel = notification.object as? NSWindow,
              resignedPanel === panel,
              isVisible else { return }

        // A transient resign during the bounded focus handoff is repaired by
        // confirmPanelFocus on the next main-loop turn.
        guard !isEstablishingFocus else { return }

        // Only auto-close if no preview window or sheet is open.
        if canCloseOnResignKey && !hasPresentedAuxiliaryWindow {
            hidePanel()
        }
    }
}

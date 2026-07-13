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

extension Notification.Name {
    /// 设置页持久化主面板方向或竖向样式后发送，使已创建的 AppKit 面板同步窗口约束与 frame。
    static let panelLayoutDidChange = Notification.Name("panelLayoutDidChange")
}

/// 主面板窗口在横竖布局间切换时使用的稳定尺寸和 frame 存储键。
enum MainPanelWindowLayout {
    static let horizontalDefaultContentSize = NSSize(width: 800, height: 400)
    static let verticalDefaultContentSize = NSSize(width: 480, height: 680)
    static let horizontalMinimumContentSize = NSSize(width: 520, height: 260)
    static let verticalMinimumContentSize = NSSize(width: 360, height: 420)

    private static let horizontalFrameAutosaveName = "PasteDeck.MainPanel.Horizontal.Frame"
    private static let verticalFrameAutosaveName = "PasteDeck.MainPanel.Vertical.Frame"

    static func defaultContentSize(for orientation: PanelOrientation) -> NSSize {
        switch orientation {
        case .horizontal:
            return horizontalDefaultContentSize
        case .vertical:
            return verticalDefaultContentSize
        }
    }

    static func minimumContentSize(for orientation: PanelOrientation) -> NSSize {
        switch orientation {
        case .horizontal:
            return horizontalMinimumContentSize
        case .vertical:
            return verticalMinimumContentSize
        }
    }

    static func frameAutosaveName(for orientation: PanelOrientation) -> String {
        switch orientation {
        case .horizontal:
            return horizontalFrameAutosaveName
        case .vertical:
            return verticalFrameAutosaveName
        }
    }
}

/// Pure geometry used to recover a saved frame after displays are removed or resized.
enum MainPanelFrameGeometry {
    static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func constrainedFrame(
        _ requestedFrame: NSRect,
        visibleFrames: [NSRect],
        minimumSize: NSSize = .zero,
        fallbackVisibleFrame: NSRect? = nil
    ) -> NSRect {
        guard !visibleFrames.isEmpty else { return requestedFrame }

        // Preserve the exact persisted frame whenever the original display is
        // still present. This avoids tiny position drift across repeated opens.
        if requestedFrame.width >= minimumSize.width,
           requestedFrame.height >= minimumSize.height,
           isFullyCovered(requestedFrame, by: visibleFrames) {
            return requestedFrame
        }

        let intersectionAreas = visibleFrames.map { visibleFrame in
            let intersection = visibleFrame.intersection(requestedFrame)
            return intersection.isNull ? CGFloat.zero : intersection.width * intersection.height
        }
        let largestIntersectionArea = intersectionAreas.max() ?? .zero

        let targetVisibleFrame: NSRect
        if largestIntersectionArea > 0,
           let targetIndex = intersectionAreas.firstIndex(of: largestIntersectionArea) {
            targetVisibleFrame = visibleFrames[targetIndex]
        } else {
            targetVisibleFrame = fallbackVisibleFrame ?? visibleFrames[0]
        }

        var constrainedFrame = requestedFrame
        constrainedFrame.size.width = min(
            max(requestedFrame.width, max(minimumSize.width, 1)),
            targetVisibleFrame.width
        )
        constrainedFrame.size.height = min(
            max(requestedFrame.height, max(minimumSize.height, 1)),
            targetVisibleFrame.height
        )
        constrainedFrame.origin.x = min(
            max(requestedFrame.minX, targetVisibleFrame.minX),
            targetVisibleFrame.maxX - constrainedFrame.width
        )
        constrainedFrame.origin.y = min(
            max(requestedFrame.minY, targetVisibleFrame.minY),
            targetVisibleFrame.maxY - constrainedFrame.height
        )
        return constrainedFrame
    }

    /// Returns true when the union of all connected visible screen rectangles
    /// covers the requested frame, including a window intentionally spanning
    /// adjacent displays. A sweep across screen x-boundaries avoids treating
    /// the empty gap between offset displays as usable space.
    private static func isFullyCovered(_ requestedFrame: NSRect, by visibleFrames: [NSRect]) -> Bool {
        guard requestedFrame.width > 0, requestedFrame.height > 0 else { return false }

        let intersections = visibleFrames.compactMap { visibleFrame -> NSRect? in
            let intersection = visibleFrame.intersection(requestedFrame)
            return intersection.isNull || intersection.isEmpty ? nil : intersection
        }
        guard !intersections.isEmpty else { return false }

        let horizontalBoundaries = Set(
            [requestedFrame.minX, requestedFrame.maxX]
                + intersections.flatMap { [$0.minX, $0.maxX] }
        ).sorted()
        let coverageTolerance: CGFloat = 0.5

        for boundaryIndex in 0..<(horizontalBoundaries.count - 1) {
            let leftBoundary = horizontalBoundaries[boundaryIndex]
            let rightBoundary = horizontalBoundaries[boundaryIndex + 1]
            guard rightBoundary - leftBoundary > coverageTolerance else { continue }

            let horizontalMidpoint = (leftBoundary + rightBoundary) / 2
            let verticalRanges = intersections
                .filter { $0.minX <= horizontalMidpoint && $0.maxX >= horizontalMidpoint }
                .map { max($0.minY, requestedFrame.minY)...min($0.maxY, requestedFrame.maxY) }
                .sorted { $0.lowerBound < $1.lowerBound }
            guard var mergedRange = verticalRanges.first else { return false }

            var coveredHeight: CGFloat = 0
            for verticalRange in verticalRanges.dropFirst() {
                if verticalRange.lowerBound <= mergedRange.upperBound + coverageTolerance {
                    mergedRange = mergedRange.lowerBound...max(mergedRange.upperBound, verticalRange.upperBound)
                } else {
                    coveredHeight += mergedRange.upperBound - mergedRange.lowerBound
                    mergedRange = verticalRange
                }
            }
            coveredHeight += mergedRange.upperBound - mergedRange.lowerBound

            if coveredHeight + coverageTolerance < requestedFrame.height {
                return false
            }
        }

        return true
    }
}

/// Manages the main floating panel for clipboard history display
class MainPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyboardFocusPanel?
    private var isVisible = false

    /// Resolves the current settings window without retaining AppDelegate or the window controller graph.
    var settingsWindowProvider: (() -> NSWindow?)?

    /// Tracks which layout owns the panel's current frame so switches never overwrite the other layout's geometry.
    private var activeOrientation: PanelOrientation = .horizontal

    /// Delegate move/resize notifications caused by restore and clamp must not overwrite persisted user geometry.
    private var isApplyingProgrammaticFrame = false

    /// Prevents auto-close when opening preview window
    private var canCloseOnResignKey = false

    /// Identifies the latest focus request so queued work from an older show/hide cycle cannot steal focus.
    private var focusRequestGeneration: UInt = 0

    /// Suspends focus confirmation while AppKit finishes deciding which window receives a resign-key handoff.
    private var pendingResignGeneration: UInt?

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
        let initialOrientation = loadPanelOrientation()
        activeOrientation = initialOrientation
        let defaultContentSize = MainPanelWindowLayout.defaultContentSize(for: initialOrientation)

        // Create floating panel with transparent title bar
        let panel = KeyboardFocusPanel(
            keyboardContentRect: NSRect(origin: .zero, size: defaultContentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        panel.contentMinSize = MainPanelWindowLayout.minimumContentSize(for: initialOrientation)

        // Add blur background effect
        // 使用能跟随 window.appearance 的材质；.hudWindow 会强制暗色，
        // 导致用户选择浅色/跟随系统时主面板仍显示为暗色。
        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: defaultContentSize))
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
        restorePanelFrame(for: initialOrientation)

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

        // MainPanelView observes SwiftData for its content layout; the controller
        // separately owns AppKit frame persistence and minimum-size constraints.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelLayoutChange),
            name: .panelLayoutDidChange,
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

    @objc private func handlePanelLayoutChange() {
        synchronizePanelOrientation()
    }

    // MARK: - Public Methods

    /// 预览窗口关闭后，通过与快捷键呼出相同的路径恢复主面板键盘焦点。
    func restorePanelFocus() {
        guard isVisible, panel?.isVisible == true else { return }
        establishPanelFocus()
    }

    func showPanel() {
        guard panel != nil else { return }

        // Settings may have changed while the panel was hidden. Switching here
        // is a fallback for any caller that persisted settings without posting
        // panelLayoutDidChange.
        synchronizePanelOrientation()

        // A previous settings/paste flow may have hidden PasteDeck. Unhide the
        // windows without activating the app that owns this non-activating panel.
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }

        canCloseOnResignKey = false
        isVisible = true

        // 通知 MainPanelView 重置焦点和选中状态
        NotificationCenter.default.post(name: .panelDidShow, object: nil)

        establishPanelFocus()
    }

    func hidePanel(shouldHideApp: Bool = true) {
        let shouldHideActiveApplication = shouldHideApp && NSApp.isActive

        persistCurrentPanelFrame()
        focusRequestGeneration &+= 1
        pendingResignGeneration = nil
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

    /// Persists the active layout's frame during app termination even when the panel is already hidden.
    func savePanelFrame() {
        persistCurrentPanelFrame()
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

    private func loadPanelOrientation() -> PanelOrientation {
        let modelContext = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else {
            return .horizontal
        }
        return settings.panelOrientation
    }

    /// Saves the outgoing layout before restoring the incoming layout's
    /// independent frame. Vertical presentation styles intentionally share one
    /// frame because only the orientation changes the window's overall shape.
    private func synchronizePanelOrientation() {
        let newOrientation = loadPanelOrientation()
        guard newOrientation != activeOrientation else { return }

        persistCurrentPanelFrame(for: activeOrientation)
        activeOrientation = newOrientation
        restorePanelFrame(for: newOrientation)
    }

    private func persistCurrentPanelFrame(for orientation: PanelOrientation? = nil) {
        guard let panel, !isApplyingProgrammaticFrame else { return }
        let frameOrientation = orientation ?? activeOrientation
        panel.saveFrame(usingName: MainPanelWindowLayout.frameAutosaveName(for: frameOrientation))
    }

    /// Restores the exact stored frame when possible, then constrains it to a
    /// current visible screen so disconnected displays cannot strand the panel.
    private func restorePanelFrame(for orientation: PanelOrientation) {
        guard let panel else { return }

        let defaultContentSize = MainPanelWindowLayout.defaultContentSize(for: orientation)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        isApplyingProgrammaticFrame = true

        panel.contentMinSize = MainPanelWindowLayout.minimumContentSize(for: orientation)
        let didRestoreStoredFrame = panel.setFrameUsingName(
            MainPanelWindowLayout.frameAutosaveName(for: orientation),
            force: true
        )

        if !didRestoreStoredFrame {
            panel.setContentSize(defaultContentSize)
            if let defaultVisibleFrame = NSScreen.main?.visibleFrame ?? visibleFrames.first {
                let centeredFrame = MainPanelFrameGeometry.centeredFrame(
                    size: panel.frame.size,
                    in: defaultVisibleFrame
                )
                panel.setFrame(centeredFrame, display: false)
            }
        }

        let minimumContentSize = MainPanelWindowLayout.minimumContentSize(for: orientation)
        let minimumFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size
        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            panel.frame,
            visibleFrames: visibleFrames,
            minimumSize: minimumFrameSize,
            fallbackVisibleFrame: NSScreen.main?.visibleFrame
        )
        if constrainedFrame != panel.frame {
            panel.setFrame(constrainedFrame, display: false)
        }

        isApplyingProgrammaticFrame = false
        persistCurrentPanelFrame(for: orientation)
    }

    /// Establishes key-window focus immediately and confirms it once after the
    /// current AppKit event (such as status-menu tracking) has completed.
    private func establishPanelFocus() {
        guard let panel, isVisible else { return }

        focusRequestGeneration &+= 1
        let requestGeneration = focusRequestGeneration
        pendingResignGeneration = nil
        isEstablishingFocus = true
        canCloseOnResignKey = false

        panel.makeKeyAndOrderFront(nil)
        // 预览或翻译工作区仍可见时，主面板通过全局快捷键再次被唤起。
        // 三者处于同一窗口层级，显式重排可保证这次用户操作的主面板位于最前。
        panel.orderFrontRegardless()
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

        // A resign callback may be queued before this confirmation. Let its
        // next-turn resolver inspect the actual destination first so we never
        // steal focus back from the settings window.
        guard pendingResignGeneration != requestGeneration else { return }

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
        // 翻译工作区从主面板打开后会接管 key window。它和普通预览一样属于应用内辅助窗口，
        // 必须在失焦判断中保留主面板，避免 hidePanel() 进一步执行 NSApp.hide(nil) 把新窗口立即隐藏。
        let hasTranslationWorkspace = NSApp.windows.contains { window in
            window.isVisible && window.identifier == translationWorkspaceWindowIdentifier
        }
        let hasSheet = panel?.attachedSheet != nil
        return hasPreviewWindow || hasTranslationWorkspace || hasSheet
    }

    /// AppKit posts resign-key before the destination window is always final.
    /// Waiting one main-loop turn lets us distinguish a settings-window handoff
    /// from an external-app click without hiding every PasteDeck window.
    private func resolvePanelResignKey(requestGeneration: UInt) {
        guard requestGeneration == focusRequestGeneration,
              isVisible,
              let panel,
              panel.isVisible else { return }

        if panel.isKeyWindow {
            pendingResignGeneration = nil
            if isEstablishingFocus {
                confirmPanelFocus(requestGeneration: requestGeneration)
            }
            return
        }

        if hasPresentedAuxiliaryWindow {
            pendingResignGeneration = nil
            isEstablishingFocus = false
            canCloseOnResignKey = true
            return
        }

        let settingsWindow = settingsWindowProvider?()
        let settingsWindowOwnsFocus = settingsWindow?.isVisible == true
            && (NSApp.keyWindow === settingsWindow || NSApp.isActive)
        if settingsWindowOwnsFocus {
            pendingResignGeneration = nil
            hidePanel(shouldHideApp: false)
            return
        }

        // During the bounded initial handoff, a status-menu or protected-system
        // surface can cause a transient resign before the panel is established.
        // Only retry after the destination check above has ruled out settings.
        if isEstablishingFocus {
            pendingResignGeneration = nil
            confirmPanelFocus(requestGeneration: requestGeneration)
            return
        }

        pendingResignGeneration = nil
        if canCloseOnResignKey {
            hidePanel()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? NSWindow,
              closingPanel === panel else { return }

        persistCurrentPanelFrame()
        focusRequestGeneration &+= 1
        pendingResignGeneration = nil
        isEstablishingFocus = false
        canCloseOnResignKey = false
        isVisible = false
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedPanel = notification.object as? NSWindow,
              movedPanel === panel else { return }
        persistCurrentPanelFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let resizedPanel = notification.object as? NSWindow,
              resizedPanel === panel else { return }
        persistCurrentPanelFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let focusedPanel = notification.object as? NSWindow,
              focusedPanel === panel,
              isVisible else { return }

        if pendingResignGeneration == focusRequestGeneration {
            pendingResignGeneration = nil
        }
        requestCardFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let resignedPanel = notification.object as? NSWindow,
              resignedPanel === panel,
              isVisible else { return }

        let requestGeneration = focusRequestGeneration
        pendingResignGeneration = requestGeneration
        DispatchQueue.main.async { [weak self] in
            self?.resolvePanelResignKey(requestGeneration: requestGeneration)
        }
    }
}

//
//  CloseWindowDispatcher.swift
//  PasteDeck
//
//  统一负责 ⌘W 和 Esc 的多窗口分层独立关闭，确保一次操作严格只关闭当前最前层单个窗口，
//  彻底杜绝菜单项 Responder Chain 冒泡、按键抖动以及窗口交接导致的连带多窗口关闭。
//

import AppKit

final class CloseWindowDispatcher {
    private static var lastCloseTime: Date = Date.distantPast
    private static let lock = NSLock()

    /// 当前是否处于关闭冷却期（350ms 内不重复执行任何关闭操作，物理阻断按键抖动）
    static var isInCooldown: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastCloseTime) < 0.35
    }

    /// 标记一次关闭操作已发生
    static func recordClose() {
        lock.lock()
        defer { lock.unlock() }
        lastCloseTime = Date()
        WindowCloseCooldown.recordChildWindowClosed()
    }

    /// 严格只关闭当前最前方的单个活跃窗口，并立即返回
    @discardableResult
    static func closeFrontmostWindowOnly() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                performCloseFrontmost()
            }
        } else {
            DispatchQueue.main.async {
                _ = MainActor.assumeIsolated {
                    performCloseFrontmost()
                }
            }
            return true
        }
    }

    @MainActor
    private static func performCloseFrontmost() -> Bool {
        guard !isInCooldown else { return false }

        // 1. 优先检查当前是否有处于可见状态的「预览窗口」
        if let previewWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.identifier == previewWindowIdentifier
        }) {
            recordClose()
            NotificationCenter.default.post(
                name: PreviewWindowController.previewWindowShouldClose,
                object: previewWindow
            )
            return true
        }

        // 2. 检查当前是否有处于可见状态的「独立工具弹窗」
        if let toolWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.identifier == ToolWindowController.windowIdentifier
        }) {
            recordClose()
            NotificationCenter.default.post(
                name: ToolWindowController.toolWindowShouldClose,
                object: toolWindow
            )
            return true
        }

        // 3. 检查当前活跃的 keyWindow
        guard let keyWindow = NSApp.keyWindow, keyWindow.isVisible else {
            return false
        }

        // 3.1 设置窗口
        if keyWindow.title.contains("设置") {
            recordClose()
            keyWindow.performClose(nil)
            return true
        }

        // 3.2 翻译工作区
        if keyWindow.title.contains("翻译") {
            recordClose()
            keyWindow.performClose(nil)
            return true
        }

        // 3.3 工作台窗口
        if keyWindow.identifier == WorkbenchWindowController.windowIdentifier || keyWindow.title.contains("PasteDeck 2.0") {
            recordClose()
            WorkbenchWindowController.shared.hideWorkbench()
            return true
        }

        // 3.4 速贴面板
        if let panelController = NSApp.windows.compactMap({ $0.delegate as? MainPanelController }).first,
           panelController.manages(window: keyWindow) {
            recordClose()
            panelController.hidePanel()
            return true
        }

        recordClose()
        keyWindow.performClose(nil)
        return true
    }
}

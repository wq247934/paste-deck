//
//  ToolWindowController.swift
//  PasteDeck
//
//  独立工具弹窗控制器。参考 PreviewWindowController 的 NSWindow 管理方式，
//  但与预览窗口完全独立：从统一搜索结果打开，关闭后把主面板焦点交还给
//  搜索框（通过 MainPanelController.restorePanelFocus 的统一生命周期机制）。
//

import AppKit
import SwiftUI

final class ToolWindowController: NSObject, NSWindowDelegate {

    /// 稳定的窗口标识：主面板失焦保护与 Esc 分发都用它识别工具窗口。
    static let windowIdentifier = NSUserInterfaceItemIdentifier("PasteDeckToolWindow")

    /// 主面板键盘监视器发现工具窗口按 Esc 时转发该通知。
    static let toolWindowShouldClose = Notification.Name("PasteDeck.toolWindowShouldClose")

    private enum Layout {
        static let minimumWindowSize = CGSize(width: 460, height: 380)
    }

    private var window: NSWindow?
    private var onCloseCallback: (() -> Void)?
    /// 标记是否已执行过关闭+恢复焦点，防止 windowWillClose 与 performClose 重复执行。
    private var didCloseAndRestore = false
    private var closeObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    // MARK: - 打开

    func show(tool: BuiltinTool, context: ToolContext, onClose: @escaping () -> Void) {
        // 先清理可能残留的旧窗口与监听器。
        cleanup()

        MainWindowReference.window = NSApp.keyWindow
        onCloseCallback = onClose
        didCloseAndRestore = false

        let preferredSize = tool.descriptor.preferredWindowSize
        let screen = MainWindowReference.window?.screen

        let hostingController = NSHostingController(
            rootView: tool.makeContentView(context: context).themeStyled()
        )

        let window = KeyboardFocusPanel(
            keyboardContentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.identifier = Self.windowIdentifier
        window.title = tool.descriptor.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 与主面板同层级，保证工具窗口显示在主面板前方。
        window.level = .popUpMenu
        window.minSize = NSSize(width: Layout.minimumWindowSize.width, height: Layout.minimumWindowSize.height)
        window.setContentSize(preferredSize)
        window.setFrame(Self.centeredFrame(size: preferredSize, on: screen), display: false)
        window.isReleasedWhenClosed = false
        window.appearance = AppearanceResolver.currentAppearance
        window.delegate = self

        self.window = window

        closeObserver = NotificationCenter.default.addObserver(
            forName: Self.toolWindowShouldClose,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.performClose()
        }

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appearanceModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.appearance = AppearanceResolver.currentAppearance
        }

        // 统一按键监听：当工具弹窗为 keyWindow 时，按 Esc 或 ⌘W 严格只关闭当前工具窗口本身
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let currentWindow = self.window,
                  let eventWindow = event.window,
                  eventWindow === currentWindow,
                  eventWindow.isKeyWindow else {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 || (event.keyCode == 13 && modifiers == .command) {
                self.performClose()
                return nil
            }
            return event
        }

        window.makeKeyAndOrderFront(nil)
        // 与主面板保持相同层级并显式置前；用户再次唤起主面板时
        // MainPanelController 会反向把主面板置于最前。
        window.orderFrontRegardless()
    }

    // MARK: - 关闭

    /// 统一关闭入口：关窗口 → 恢复主面板焦点（优先搜索框）→ 回调。
    func performClose() {
        guard !didCloseAndRestore else { return }
        didCloseAndRestore = true

        WindowCloseCooldown.recordChildWindowClosed()

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        window?.close()
        window = nil

        restoreMainPanelFocus()

        onCloseCallback?()
        onCloseCallback = nil
    }

    /// 清理残留窗口与监听器，不触发恢复焦点和回调。
    private func cleanup() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.close()
        window = nil
        onCloseCallback = nil
        didCloseAndRestore = false
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        appearanceObserver = nil
    }

    private func restoreMainPanelFocus() {
        guard let previousWindow = MainWindowReference.window, previousWindow.isVisible else { return }

        // 仅当父窗口确实为主面板时，才走主面板非激活聚焦流程
        if let panelController = NSApp.windows
            .compactMap({ $0.delegate as? MainPanelController })
            .first,
            panelController.manages(window: previousWindow) {
            panelController.restorePanelFocus(preferringSearchFocus: true)
            return
        }

        previousWindow.makeKeyAndOrderFront(nil)
        previousWindow.orderFrontRegardless()
        NotificationCenter.default.post(name: .workbenchDidRequestListFocus, object: nil)
    }

    private static func centeredFrame(size: CGSize, on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 窗口关闭的兜底：performClose 已执行则跳过，否则补执行。
        guard !didCloseAndRestore else { return }
        performClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 点击关闭按钮时走统一关闭流程，阻止系统直接关闭。
        performClose()
        return false
    }
}

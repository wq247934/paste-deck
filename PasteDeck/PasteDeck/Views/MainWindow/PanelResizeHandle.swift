//
//  PanelResizeHandle.swift
//  PasteDeck
//
//  上下文工具面板宽度的原生拖拽手柄。
//
//  主面板开启 isMovableByWindowBackground，而 NSHostingView 的命中测试
//  不会把 mouseDownCanMoveWindow 协商下传到内嵌的原生子视图，SwiftUI
//  手势无法从"窗口背景拖动"手里抢到事件。因此手柄由 MainPanelController
//  以原生 NSView 直接挂在 contentView 最上层，铺满整窗；hitTest 只在
//  侧边栏左缘条带区域返回自己，其余位置返回 nil 完全放行。
//
//  状态通过 PanelResizeHandleState 共享：MainPanelView 在渲染时写入
//  侧边栏可见性与当前宽度，覆盖层据此判定条带位置；拖拽写回
//  UserDefaults（与 MainPanelView 的 @AppStorage 同 key）实时生效。
//

import AppKit
import Combine

/// 拖拽手柄的共享状态（SwiftUI 渲染写入，覆盖层读取）。
@MainActor
final class PanelResizeHandleState: ObservableObject {
    static let shared = PanelResizeHandleState()

    static let widthDefaultsKey = "PasteDeck.ContextPanel.Width"
    static let widthRange: ClosedRange<Double> = 260...420

    /// 侧边栏当前是否可见（可见时条带才拦截事件）。
    @Published var isEnabled = false
    /// 侧边栏当前宽度（含手柄）。
    @Published var width: Double = 312
    /// 是否正在拖拽（用于握把高亮）。
    @Published var isDragging = false
    /// 鼠标是否悬停在条带上（用于握把高亮）。
    @Published var isHovering = false

    private init() {}
}

/// 铺满整窗的事件覆盖层：只有侧边栏左缘条带会命中。
final class PanelResizeHandleOverlayView: NSView {

    private let trailingPadding: CGFloat = 10
    /// 条带以侧边栏左缘为中心向两侧各延伸一半，保证容易命中。
    private let stripWidth: CGFloat = 18
    private var startWidth: CGFloat = 0
    private var startX: CGFloat = 0

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let contentView = superview {
            frame = NSRect(origin: .zero, size: contentView.bounds.size)
            autoresizingMask = [.width, .height]
        }
    }

    /// 手柄条带在窗口坐标中的矩形：以侧边栏左缘为中心向两侧延伸。
    private var stripRect: NSRect? {
        guard MainActor.assumeIsolated({ PanelResizeHandleState.shared.isEnabled }) else { return nil }
        let width = UserDefaults.standard.double(forKey: PanelResizeHandleState.widthDefaultsKey)
        guard width >= PanelResizeHandleState.widthRange.lowerBound else { return nil }
        let sidebarLeftEdge = bounds.width - trailingPadding - CGFloat(width)
        return NSRect(
            x: sidebarLeftEdge - stripWidth / 2,
            y: 0,
            width: stripWidth,
            height: bounds.height
        )
    }

    /// 只有条带区域才接管事件；其余位置完全放行。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let strip = stripRect, strip.contains(point) else { return nil }
        return self
    }

    /// 关键：不参与"背景拖动窗口"，条带上的拖拽事件由本视图接管。
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.userInfo?["strip"] != nil {
            removeTrackingArea(area)
        }
        guard let strip = stripRect else { return }
        let area = NSTrackingArea(
            rect: strip,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["strip": true]
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.isHovering = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.isHovering = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.isDragging = true
        }
        startWidth = UserDefaults.standard.double(forKey: PanelResizeHandleState.widthDefaultsKey)
        startX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        // 向左拖动（窗口坐标 x 变小）应加宽面板。
        let widened = startX - event.locationInWindow.x
        let proposed = min(
            PanelResizeHandleState.widthRange.upperBound,
            max(PanelResizeHandleState.widthRange.lowerBound, startWidth + widened)
        )
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.width = proposed
            UserDefaults.standard.set(proposed, forKey: PanelResizeHandleState.widthDefaultsKey)
        }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.isDragging = false
        }
        startWidth = 0
    }
}
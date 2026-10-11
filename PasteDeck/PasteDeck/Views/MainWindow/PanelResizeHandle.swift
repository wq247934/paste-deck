//
//  PanelResizeHandle.swift
//  PasteDeck
//
//  上下文工具面板宽度的拖拽手柄。
//
//  为什么用原生覆盖层：主面板开启了 isMovableByWindowBackground，
//  SwiftUI 手势无法从"拖动窗口"里接管左键事件。命中测试也无法交给
//  NSHostingView 协商（它不会把 mouseDownCanMoveWindow 下传给内嵌视图）。
//  所以手柄由 MainPanelController 以原生 NSView 直接挂在 contentView 最上层。
//
//  关键约束：宽度只有一个真相来源 —— PanelResizeHandleState.width。
//  覆盖层的 hitTest 绝不能去读 UserDefaults：
//    1) @AppStorage 只有在被写入后才落盘。全新安装时 key 不存在，
//       UserDefaults.double(forKey:) 返回 0，hitTest 里"宽度是否合法"
//       的判断会失败，条带永远算不出来，手柄静默失效。
//    2) 拖拽期间每个 mouseDragged 都同步写盘，是不必要的磁盘 I/O。
//  改为：拖拽时只更新内存中的 width，mouseUp 时一次性落盘，
//  同时通过 onChange 通知 SwiftUI 侧刷新布局。
//

import AppKit
import Combine

/// 拖拽手柄与主面板之间共享的宽度状态。
///
/// 主面板渲染时写入当前宽度与可见性，覆盖层读取并写回，
/// 因此面板打开、关闭、切换选中卡片时手柄都能自动跟随。
@MainActor
final class PanelResizeHandleState: ObservableObject {
    static let shared = PanelResizeHandleState()

    static let widthDefaultsKey = "PasteDeck.ContextPanel.Width"
    static let defaultWidth: Double = 312
    static let widthRange: ClosedRange<Double> = 260...420

    /// 侧边栏当前是否可见（只有可见时条带才拦截事件）。
    @Published private(set) var isEnabled = false
    /// 侧边栏当前宽度（含手柄槽）。唯一真相来源。
    @Published private(set) var width: Double = PanelResizeHandleState.defaultWidth
    /// 是否正在拖拽（用于握把高亮）。
    @Published private(set) var isDragging = false
    /// 鼠标是否悬停在条带上（用于握把高亮）。
    @Published private(set) var isHovering = false

    private init() {
        width = Self.restoredWidth()
    }

    /// 主面板渲染时调用：只同步可见性。
    /// 宽度不由调用方回写，否则旧值会覆盖用户刚拖出的结果。
    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
    }

    /// 面板重新显示时从磁盘恢复宽度。
    /// 单例在进程内只初始化一次，拖拽后的宽度需在此重新载入，
    /// 否则重启应用后仍沿用内存中的旧值。
    func refreshPersistedWidth() {
        width = Self.restoredWidth()
    }

    /// 拖拽过程中只更新内存，不落盘。
    func updateWidthDuringDrag(_ proposed: Double) {
        let clamped = clamp(proposed)
        guard width != clamped else { return }
        width = clamped
    }

    /// 拖拽结束时一次性持久化。
    func persistWidth() {
        UserDefaults.standard.set(width, forKey: Self.widthDefaultsKey)
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    private func clamp(_ value: Double) -> Double {
        min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, value))
    }

    /// 从持久化值恢复宽度；越界或缺失时回落到默认值。
    /// 与 init 使用同一套规则，供恢复逻辑与测试复用。
    static func restoredWidth(from defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: widthDefaultsKey)
        guard stored >= widthRange.lowerBound, stored <= widthRange.upperBound else {
            return defaultWidth
        }
        return stored
    }
}

/// 铺满整窗的事件覆盖层：只有侧边栏左缘条带会命中，其余位置完全放行。
final class PanelResizeHandleOverlayView: NSView {

    /// 侧边栏与窗口右缘之间的间距，与 MainPanelView 的 .padding(.trailing, 10) 保持一致。
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

    /// 手柄条带在视图坐标中的矩形：以侧边栏左缘为中心向两侧延伸。
    /// 只依赖内存中的 width，不触碰 UserDefaults。
    private var stripRect: NSRect? {
        let state = MainActor.assumeIsolated { PanelResizeHandleState.shared }
        guard state.isEnabled else { return nil }
        let sidebarLeftEdge = bounds.width - trailingPadding - CGFloat(state.width)
        // 窗口过窄时条带整体左移，保证仍然可命中。
        return NSRect(
            x: sidebarLeftEdge - stripWidth / 2,
            y: 0,
            width: stripWidth,
            height: bounds.height
        )
    }

    /// 只有条带区域才接管事件；其余位置返回 nil，交给下层视图。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let strip = stripRect, strip.contains(point) else { return nil }
        return self
    }

    /// 关键：不参与"拖动窗口背景"，条带上的拖拽由本视图接管。
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

    /// 条带位置随宽度变化而移动，跟踪区需要同步刷新。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.setHovering(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.setHovering(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.setDragging(true)
            startWidth = CGFloat(PanelResizeHandleState.shared.width)
        }
        startX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        // 向左拖动（窗口坐标 x 变小）应加宽面板。
        let widened = startX - event.locationInWindow.x
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.updateWidthDuringDrag(startWidth + widened)
        }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            PanelResizeHandleState.shared.setDragging(false)
            // 拖拽结束才落盘，避免拖拽过程中高频写 UserDefaults。
            PanelResizeHandleState.shared.persistWidth()
        }
        startWidth = 0
    }
}

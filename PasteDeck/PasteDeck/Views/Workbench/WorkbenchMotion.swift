//
//  WorkbenchMotion.swift
//  PasteDeck
//
//  工作台玻璃动效的共享基建：动效 token、Reduce Motion 门控，
//  以及胶囊拉伸与数字滚动两段可单测的纯几何数学。
//
//  设计约束：部署目标为 macOS 14，因此不使用 macOS 26 的 Liquid Glass
//  API（glassEffect），磨砂质感一律走系统材质（.thinMaterial / .regularMaterial）。
//

import SwiftUI
import AppKit

// MARK: - Motion Tokens

/// 工作台动效的集中定义。四个玻璃交互（侧栏胶囊、卡片光斑、模块放大、
/// 筛选液态分裂）共用同一套 token，避免各处散落硬编码时长与弹簧参数。
enum WorkbenchMotion {

    // MARK: Spring Tokens

    /// 侧栏选中胶囊滑动：略带回弹，到位时有轻微过冲。
    static let pillSpring = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// 胶囊沿移动方向的拉长/回缩：阻尼更低，过冲更明显，像橡皮筋。
    static let stretchSpring = Animation.spring(response: 0.28, dampingFraction: 0.55)

    /// 筛选胶囊液态分裂/融合：阻尼更高，起手更软、收尾更稳。
    static let liquidSpring = Animation.spring(response: 0.42, dampingFraction: 0.70)

    /// 模块卡片原位放大：几乎不回弹，强调"原地长大"而非"弹出来"。
    static let expandSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    // MARK: Eased Tokens

    /// 悬停态过渡。沿用设置页 hoverAnimation 的 0.14s 手感。
    static let hoverEase = Animation.easeOut(duration: 0.14)

    /// 光标移出卡片后光斑与倾斜复原。
    static let hoverReleaseEase = Animation.easeOut(duration: 0.22)

    /// 筛选选项分裂时的错峰步进，制造液态依次展开的节奏。
    static let liquidStaggerStep: Double = 0.02

    // MARK: 幅度常量

    /// 胶囊移动途中相对静止长度的最大拉伸比例。
    static let pillMaxStretch: CGFloat = 0.22

    /// 卡片 3D 倾斜的最大角度（度）。克制微妙，不晃动。
    static let cardMaxTilt: Double = 2.2

    /// 卡片平面内旋转的最大角度（度）。
    static let cardMaxRoll: Double = 0.8

    /// 光斑半径相对卡片短边的倍数。
    static let spotRadiusScale: CGFloat = 0.62
}

// MARK: - Reduce Motion Gating

private struct WorkbenchReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

extension EnvironmentValues {
    /// 工作台动效统一的「减弱动态」开关。
    ///
    /// 默认值取自系统辅助功能设置；开启后所有位移/倾斜/缩放动效退化为
    /// 直接取值切换，保证前庭敏感用户可用。
    var workbenchReduceMotion: Bool {
        get { self[WorkbenchReduceMotionKey.self] }
        set { self[WorkbenchReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// 在视图树上安装工作台的 Reduce Motion 门控。
    ///
    /// 只需在工作台根视图调用一次，子视图即可通过环境读取。
    func installWorkbenchMotionGate() -> some View {
        modifier(WorkbenchMotionGateModifier())
    }
}

private struct WorkbenchMotionGateModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        content.environment(\.workbenchReduceMotion, systemReduceMotion)
    }
}

// MARK: - Pill Stretch Geometry

/// 胶囊沿移动方向拉伸的几何数学。
///
/// 效果模型：胶囊沿起点到终点的路径行进，行进途中沿运动轴短暂拉长，
/// 到位前松弛回静止长度，形成橡皮筋式的拉伸回弹。拉伸以行进位置为中心
/// 对称生效，不改变行进本身的单调性（详见 `resolvedFrame` 的说明）。
///
/// 全部为纯函数，不依赖 SwiftUI 状态，可直接单元测试。
enum PillStretchMetrics {

    /// 胶囊相对静止状态沿运动轴的额外长度比例。1.0 表示回到静止长度。
    typealias Stretch = CGFloat

    /// 沿运动轴的拉伸倍率，水平轴取宽度、垂直轴取高度。
    enum Axis {
        case horizontal
        case vertical

        /// 该轴在矩形中的当前长度。
        func length(in rect: CGRect) -> CGFloat {
            switch self {
            case .horizontal: return rect.width
            case .vertical: return rect.height
            }
        }

        /// 构造轴对应的矩形。`rect` 的沿轴端点被保持不变。
        func resized(rect: CGRect, to length: CGFloat, anchoredAt anchor: CGFloat) -> CGRect {
            switch self {
            case .horizontal:
                return CGRect(x: anchor, y: rect.minY, width: length, height: rect.height)
            case .vertical:
                return CGRect(x: rect.minX, y: anchor, width: rect.width, height: length)
            }
        }
    }

    /// 胶囊从起点滑向终点的方向。
    enum Direction: Equatable {
        /// 向下移动。
        case forward
        /// 向上移动。
        case backward
        /// 同一位置（或水平移动，垂直拉伸不适用）。
        case none
    }

    /// 计算移动方向。`axis` 为水平时返回 `.none`，因为拉伸只作用于垂直轴。
    static func direction(
        from start: CGRect,
        to end: CGRect,
        axis: Axis = .vertical
    ) -> Direction {
        guard axis == .vertical else { return .none }
        let delta = end.midY - start.midY
        if delta > .ulpOfOne { return .forward }
        if delta < -.ulpOfOne { return .backward }
        return .none
    }

    /// 计算滑动过程中的拉伸倍率。
    ///
    /// - Parameters:
    ///   - direction: 移动方向。
    ///   - progress: 0…1 的归一化行程。行程中段拉伸最大，两端回到静止长度。
    ///   - maxStretch: 中段相对静止长度的最大额外比例。
    /// - Returns: 倍率，静止位置为 1.0，中段最大为 `1 + maxStretch`。
    static func scale(
        along direction: Direction,
        progress: CGFloat,
        maxStretch: CGFloat = WorkbenchMotion.pillMaxStretch
    ) -> Stretch {
        guard direction != .none else { return 1 }
        let clamped = min(max(progress, 0), 1)
        // 单峰弧线：0→中点升到 1，中点→1 回到 0。
        let bell = sin(clamped * .pi)
        return 1 + maxStretch * bell
    }

/// 计算胶囊在某一时刻的实际绘制矩形。
    ///
    /// 胶囊沿 `start`→`end` 线性行进；拉伸是叠加在行进之上的**瞬态形变**：
    /// 中段沿运动轴略微拉长、到位前松弛回静止长度，而不是从起点做绝对延伸。
    ///
    /// 之所以不把尾端钉死在起点：那样拉伸回缩的速度会快于行进速度，
    /// 胶囊中点会先前进再微微倒退（mid-Y 非单调），看起来像抖动而不是橡皮筋。
    /// 以插值位置为中心做对称伸缩可保证行进始终单调，形变只在行程中段可见，
    /// 这正是「移动中沿方向拉长、到位弹性回弹」的观感。
    static func resolvedFrame(
        start: CGRect,
        end: CGRect,
        progress: CGFloat,
        direction: Direction,
        maxStretch: CGFloat = WorkbenchMotion.pillMaxStretch
    ) -> CGRect {
        let clamped = min(max(progress, 0), 1)
        let base = CGRect(
            x: start.minX + (end.minX - start.minX) * clamped,
            y: start.minY + (end.minY - start.minY) * clamped,
            width: start.width + (end.width - start.width) * clamped,
            height: start.height + (end.height - start.height) * clamped
        )

        let stretch = scale(along: direction, progress: clamped, maxStretch: maxStretch)
        guard stretch != 1 else { return base }

        let axis: Axis = .vertical
        // 以插值后的中心对称伸缩：中心不漂移，只在行进路径上做瞬态拉长。
        // 锚点 = 中心 - 拉伸后长度的一半，让形变关于中心对称。
        let currentLength = axis.length(in: base)
        let stretchedLength = currentLength * stretch
        let centre = axis == .vertical ? base.midY : base.midX
        return axis.resized(rect: base, to: stretchedLength, anchoredAt: centre - stretchedLength / 2)
    }
}


//
//  WorkbenchGlassCard.swift
//  PasteDeck
//
//  工作台通用磨砂玻璃卡片。工具中心的模块卡（需求②）与原位放大后的
//  详情容器（需求③）共用同一实现，保证两处玻璃质感完全一致。
//
//  交互效果：
//  - 磨砂底：系统材质（macOS 14 可用，非 macOS 26 Liquid Glass）
//  - 光标跟随的柔和光斑：裁剪在卡片内的径向加亮
//  - 靠近光标的边框局部提亮：以光标为焦点的渐隐描边
//  - 轻微 3D 倾斜，移出后平滑复原
//

import SwiftUI

/// 可选内容承载的磨砂玻璃卡片。
///
/// 直接把内容作为视图包裹在玻璃壳内。悬停光斑与 3D 倾斜由本组件
/// 统一处理，调用方无需关心坐标换算与裁剪。
struct WorkbenchGlassCard<Content: View>: View {
    /// 卡片内容。
    @ViewBuilder var content: () -> Content

    var cornerRadius: CGFloat = 12
    /// 是否启用光斑与 3D 倾斜。放大后的详情容器通常不需要。
    var interactive: Bool = true

    @Environment(\.workbenchReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// 光标在卡片局部坐标系中的位置；nil 表示光标不在卡片内。
    @State private var hoverLocation: CGPoint?
    /// 当前卡片的渲染尺寸，用于把光斑半径与倾斜量换算到局部坐标。
    @State private var cardSize: CGSize = .zero

    /// 配置优先的初始化顺序，读起来更贴近调用点：
    /// `WorkbenchGlassCard(cornerRadius: 12) { ... }`
    init(
        cornerRadius: CGFloat = 12,
        interactive: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
        self.content = content
    }

    var body: some View {
        content()
            .background(backgroundLayers)
            .overlay(borderLayers)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cardSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in cardSize = newSize }
                }
            )
            .modifier(CardTiltModifier(
                hoverLocation: hoverLocation,
                cardSize: cardSize,
                reduceMotion: reduceMotion || !interactive
            ))
            .onContinuousHover { phase in
                guard interactive else { return }
                switch phase {
                case .active(let point):
                    hoverLocation = point
                case .ended:
                    hoverLocation = nil
                }
            }
            .animation(
                hoverLocation == nil ? WorkbenchMotion.hoverReleaseEase : WorkbenchMotion.hoverEase,
                value: hoverLocation == nil
            )
    }

    // MARK: - Glass Layers

    /// 磨砂底 + 跟随光标的光斑。
    @ViewBuilder
    private var backgroundLayers: some View {
        ZStack {
            // Frosted base from the shared glass surface: material plus a
            // low-opacity milky tint, so it reads as glass rather than a slab.
            FrostedGlassSurface(cornerRadius: cornerRadius)

            // Cursor-following soft light spot, clipped to the card.
            if let hoverLocation, cardSize != .zero {
                lightSpot(at: hoverLocation)
            }
        }
    }

    /// 以光标为中心的柔和加亮光斑。
    private func lightSpot(at location: CGPoint) -> some View {
        let radius = max(cardSize.width, cardSize.height) * WorkbenchMotion.spotRadiusScale
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.55),
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(location)
            // Additive blending keeps the frosted texture visible under the spot.
            .blendMode(.plusLighter)
    }

    // MARK: - Border Layers

    /// 靠近光标的边框局部提亮。
    ///
    /// 基础描边由 `FrostedGlassSurface` 提供，这里只叠加跟随光标的那一段高亮。
    @ViewBuilder
    private var borderLayers: some View {
        if let hoverLocation, cardSize != .zero, !reduceMotion {
            let radius = max(cardSize.width, cardSize.height) * WorkbenchMotion.spotRadiusScale
            Circle()
                .stroke(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color.white.opacity(0.45),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    ),
                    lineWidth: 1.5
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(hoverLocation)
                // Masked to the card by the parent `.clipShape`.
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - 3D Tilt

/// 让整张卡片朝光标方向做轻微 3D 倾斜；光标移出后回正。
///
/// 独立 ViewModifier 以便在 `contentShape`/`clipShape` 之后统一施加，
/// 避免倾斜把卡片内容一起拉出裁剪区。
private struct CardTiltModifier: ViewModifier {
    let hoverLocation: CGPoint?
    let cardSize: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion || hoverLocation == nil || cardSize == .zero {
            content
        } else {
            let location = hoverLocation ?? .zero
            // Normalise pointer position to -0.5…0.5 around the card centre.
            let normalizedX = (location.x / max(cardSize.width, 1)) - 0.5
            let normalizedY = (location.y / max(cardSize.height, 1)) - 0.5

            content
                .rotation3DEffect(
                    .degrees(normalizedY * -WorkbenchMotion.cardMaxTilt),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(normalizedX * WorkbenchMotion.cardMaxTilt),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .rotationEffect(.degrees(normalizedX * WorkbenchMotion.cardMaxRoll))
        }
    }
}

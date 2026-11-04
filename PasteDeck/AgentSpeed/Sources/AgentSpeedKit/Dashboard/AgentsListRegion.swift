import SwiftUI

/// The agent rows, clipped to `height` so the list opens and closes like a drawer. Once the rows outgrow it the region
/// scrolls, with soft fades on the edges that have more rows behind them (DESIGN section 4.4).
///
/// The region is the same scroll view in every state, and its height comes from the row count alone. SwiftUI
/// interpolates that height on every frame, so the sections below and the popover itself follow the drawer as one
/// motion instead of jumping to the final layout.
struct AgentsListRegion<Content: View>: View {
    let height: CGFloat
    let scrolls: Bool
    /// Nil under Reduce Motion: the height then changes at once and the rows only fade.
    let motion: Animation?
    @ViewBuilder let content: Content

    @State private var contentFrame: CGRect = .zero

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(RegionMetrics.top)
                    content
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RegionMetrics.space)) } action: { contentFrame = $0 }
            }
            .coordinateSpace(.named(RegionMetrics.space))
            .scrollDisabled(!scrolls)
            // A system scroller would take width from the tok/s column in the legacy style; the overlay knob never does.
            .scrollIndicators(.never)
            .animation(motion) { $0.modifier(AnimatedHeight(height: height)) }
            .mask {
                EdgeFadeMask(fadesTop: fadesTop, fadesBottom: fadesBottom, fade: RegionMetrics.fade)
            }
            .overlay {
                OverlayScrollIndicator(
                    content: contentFrame,
                    trailingInset: Spacing.xxs - DashboardLayout.padding,
                    isActive: scrolls
                )
            }
            .onChange(of: scrolls) { _, scrolls in
                guard !scrolls else { return }
                withAnimation(motion) { proxy.scrollTo(RegionMetrics.top, anchor: .top) }
            }
        }
    }

    private var fadesTop: Bool { scrolls && contentFrame.minY < -0.5 }
    /// Before the first measurement the rows sit at the top, so a scrolling region has more below.
    private var fadesBottom: Bool { scrolls && (contentFrame.isEmpty || contentFrame.maxY > height + 0.5) }
}

/// A frame height that SwiftUI interpolates frame by frame, so the layout runs at every step of the animation.
private struct AnimatedHeight: ViewModifier, Animatable {
    var height: CGFloat

    nonisolated var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(height: height, alignment: .top)
    }
}

private enum RegionMetrics {
    static let space = "agentsListRegion"
    static let top = "agentsListTop"
    static let fade: CGFloat = 16
}

private struct EdgeFadeMask: View {
    let fadesTop: Bool
    let fadesBottom: Bool
    let fade: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(fadesTop ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(fadesBottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
        .animation(Motion.fade, value: fadesTop)
        .animation(Motion.fade, value: fadesBottom)
    }
}

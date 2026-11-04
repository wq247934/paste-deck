import SwiftUI

/// Vertical stack that never grows past `maxHeight`: when the content is taller than the screen allows,
/// only the child marked `.dashboardFlexible()` is compressed (it scrolls), the rest keeps its ideal height.
struct DashboardColumn: Layout {
    var maxHeight: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = idealHeights(subviews, width: proposal.width)
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let total = heights.reduce(0, +)
        return CGSize(width: width, height: maxHeight.map { min(total, $0) } ?? total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var heights = idealHeights(subviews, width: bounds.width)
        let overflow = heights.reduce(0, +) - bounds.height
        if overflow > 0.5, let flexible = subviews.firstIndex(where: { $0[FlexibleChild.self] }) {
            heights[flexible] = max(0, heights[flexible] - overflow)
        }
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: heights[index])
            )
            y += heights[index]
        }
    }

    private func idealHeights(_ subviews: Subviews, width: CGFloat?) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }
}

private struct FlexibleChild: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Marks the child of `DashboardColumn` that may shrink and scroll.
    func dashboardFlexible() -> some View {
        layoutValue(key: FlexibleChild.self, value: true)
    }
}

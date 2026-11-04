import SwiftUI

/// A slim scroll knob drawn over a scroll region in place of the system scroller, so it never takes layout width or
/// shifts the content, whatever scroller style the system uses. It shows when the region starts to overflow and while
/// the content scrolls, then fades out shortly after.
struct OverlayScrollIndicator: View {
    /// The content's frame in the scroll region's own coordinate space.
    let content: CGRect
    /// Distance from the region's trailing edge to the knob; negative values put it in the margin beside the region.
    var trailingInset: CGFloat = Spacing.xxs
    /// False hides the knob, for a region that does not scroll right now.
    var isActive = true

    @State private var isRevealed = false
    @State private var activity = 0
    @Environment(\.colorSchemeContrast) private var contrast

    private static let width: CGFloat = 5
    private static let inset: CGFloat = 3
    private static let minLength: CGFloat = 22
    private static let linger: Duration = .milliseconds(900)

    var body: some View {
        GeometryReader { proxy in
            let knob = Self.knob(viewport: proxy.size.height, content: content)
            ZStack(alignment: .topLeading) {
                if let knob {
                    Capsule(style: .continuous)
                        .fill(.primary.opacity(contrast == .increased ? 0.5 : 0.28))
                        .frame(width: Self.width, height: knob.height)
                        .offset(x: proxy.size.width - Self.width - trailingInset, y: knob.minY)
                }
            }
            .onChange(of: knob != nil, initial: true) { _, overflows in
                if overflows { reveal() }
            }
        }
        .opacity(isActive && isRevealed ? 1 : 0)
        .animation(Motion.fade, value: isActive && isRevealed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: content.minY) { reveal() }
        .task(id: activity) {
            guard isRevealed else { return }
            try? await Task.sleep(for: Self.linger)
            if !Task.isCancelled { isRevealed = false }
        }
    }

    private func reveal() {
        guard isActive else { return }
        isRevealed = true
        activity &+= 1
    }

    /// The knob's frame in a viewport of the given height, or nil when everything fits.
    static func knob(viewport: CGFloat, content: CGRect) -> CGRect? {
        let overflow = content.height - viewport
        guard overflow > 0.5, viewport > minLength + inset * 2 else { return nil }
        let track = viewport - inset * 2
        let length = max(minLength, track * viewport / content.height)
        let progress = min(max(-content.minY / overflow, 0), 1)
        return CGRect(x: 0, y: inset + (track - length) * progress, width: width, height: length)
    }
}

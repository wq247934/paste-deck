import SwiftUI

/// A muted gauge with its needle resting at zero, for empty states (reads as an instrument, not a spinner).
struct RestingGauge: View {
    var lineWidth: CGFloat = 2

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = DashboardPalette.secondary(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
        Canvas { context, size in
            let inset = lineWidth / 2 + 0.25
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            context.stroke(
                GaugeGlyph.arc(in: rect, fraction: 1),
                with: .color(color.opacity(0.4)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let angle = Angle.degrees(135).radians
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.62, y: center.y + sin(angle) * radius * 0.62))
            context.stroke(needle, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: lineWidth * 0.85, lineCap: .round))
            let hub = lineWidth * 0.95
            context.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)), with: .color(color.opacity(0.75)))
        }
        .accessibilityHidden(true)
    }
}

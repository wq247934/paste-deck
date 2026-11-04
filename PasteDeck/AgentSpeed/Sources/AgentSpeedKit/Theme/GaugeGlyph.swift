import SwiftUI

/// The compact 270° ring used by the menu bar item and small status glyphs (DESIGN section 3).
struct GaugeGlyph: View {
    var fraction: Double
    var fill: Color
    var track: Color
    var lineWidth: CGFloat = 2
    /// Soft glow radius around the fill (0 disables it).
    var glow: CGFloat = 0
    var fillOpacity: Double = 1

    var body: some View {
        Canvas { context, size in
            let inset = lineWidth / 2 + 0.25
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let track = GaugeGlyph.arc(in: rect, fraction: 1)
            context.stroke(track, with: .color(self.track), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            let value = fraction.clamped(to: 0...1)
            guard value > 0.004 else { return }
            let arc = GaugeGlyph.arc(in: rect, fraction: value)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            if glow > 0 {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: glow / 2))
                    layer.opacity = 0.9 * fillOpacity
                    layer.stroke(arc, with: .color(fill), style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .round))
                }
            }
            context.opacity = fillOpacity
            context.stroke(arc, with: .color(fill), style: style)
        }
        .accessibilityHidden(true)
    }

    /// Arc from 135° clockwise over `fraction` of 270° (screen coordinates, y down).
    static func arc(in rect: CGRect, fraction: Double) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle.degrees(135)
        let end = Angle.degrees(135 + 270 * fraction)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

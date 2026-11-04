import AgentSpeedCore
import SwiftUI

/// The last 60 s of this computer's traffic (DESIGN 10, Dashboard 2): mirrored around a hairline midline — download
/// as an area above it, upload below — on one linear scale whose top is the window's largest value rounded up to a
/// 1-2-5 step (at least 10 KB/s). A scale change eases over 0.3 s (Reduce Motion: jumps); hovering shows a crosshair
/// with the time and both rates.
struct TrafficSparkline: View {
    let points: [TrafficPoint]
    let text: TrafficText
    let reduceMotion: Bool
    let accessibilityLabel: String

    @State private var domain: Double?
    @State private var hoverX: CGFloat?

    static let height: CGFloat = 28
    nonisolated static let window: TimeInterval = 60

    var body: some View {
        let target = Self.scaleTop(points.map { max($0.rate.rx, $0.rate.tx) }.max() ?? 0)
        ZStack(alignment: .topLeading) {
            TrafficSparklinePlot(points: points, domain: domain ?? target)
            if let hoverX {
                crosshair(at: hoverX)
            }
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hoverX = location.x
            case .ended: hoverX = nil
            }
        }
        .onChange(of: target, initial: true) { _, next in
            guard next != domain else { return }
            if domain == nil || reduceMotion {
                domain = next
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { domain = next }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    /// The largest value rounded up to 1, 2 or 5 × 10ⁿ bytes per second, at least 10 KB/s.
    static func scaleTop(_ value: Double) -> Double {
        let floor = 10_000.0
        guard value > floor else { return floor }
        let magnitude = pow(10, (log10(value)).rounded(.down))
        for step in [1.0, 2, 5, 10] where step * magnitude >= value { return step * magnitude }
        return 10 * magnitude
    }

    @ViewBuilder
    private func crosshair(at x: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if let point = Self.point(at: x, width: width, points: points) {
                let px = Self.x(of: point.time, width: width, end: points.last?.time ?? point.time)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: Self.height)
                    .offset(x: px)
                HStack(spacing: 6) {
                    Text(point.time, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.dashboardSecondary)
                    TrafficRateLabel(down: true, rate: point.rate.rx, text: text, size: 10)
                    TrafficRateLabel(down: false, rate: point.rate.tx, text: text, size: 10)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .fixedSize()
                .offset(x: min(max(0, px - 90), max(0, width - 200)), y: -22)
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func x(of time: Date, width: CGFloat, end: Date) -> CGFloat {
        let fraction = 1 - end.timeIntervalSince(time) / window
        return CGFloat(fraction) * width
    }

    static func point(at x: CGFloat, width: CGFloat, points: [TrafficPoint]) -> TrafficPoint? {
        guard let end = points.last?.time, width > 0 else { return nil }
        let time = end.addingTimeInterval(-window * Double(1 - x / width))
        return points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }
}

/// The mirrored areas, animatable in their scale.
private struct TrafficSparklinePlot: View, Animatable {
    var points: [TrafficPoint]
    var domain: Double

    nonisolated var animatableData: Double {
        get { domain }
        set { domain = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let mid = (size.height / 2).rounded()
            let half = mid - 1
            var midline = Path()
            midline.move(to: CGPoint(x: 0, y: mid))
            midline.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(midline, with: .color(Color(nsColor: .separatorColor)), lineWidth: 0.5)
            guard let end = points.last?.time, points.count > 1 else { return }
            func xs(_ point: TrafficPoint) -> CGFloat { TrafficSparkline.x(of: point.time, width: size.width, end: end) }
            func area(_ value: (TrafficPoint) -> Double, up: Bool) -> (fill: Path, line: Path) {
                var line = Path()
                var fill = Path()
                for (index, point) in points.enumerated() {
                    let v = min(1, max(0, value(point) / max(domain, 1)))
                    let y = up ? mid - CGFloat(v) * half : mid + CGFloat(v) * half
                    let p = CGPoint(x: xs(point), y: y)
                    if index == 0 {
                        line.move(to: p)
                        fill.move(to: CGPoint(x: p.x, y: mid))
                    } else {
                        line.addLine(to: p)
                    }
                    fill.addLine(to: p)
                }
                fill.addLine(to: CGPoint(x: xs(points[points.count - 1]), y: mid))
                fill.closeSubpath()
                return (fill, line)
            }
            let down = area({ $0.rate.rx }, up: true)
            let upload = area({ $0.rate.tx }, up: false)
            context.fill(down.fill, with: .color(.primary.opacity(0.16)))
            context.stroke(down.line, with: .color(.primary.opacity(0.55)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            context.fill(upload.fill, with: .color(.primary.opacity(0.10)))
            context.stroke(upload.line, with: .color(.primary.opacity(0.40)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

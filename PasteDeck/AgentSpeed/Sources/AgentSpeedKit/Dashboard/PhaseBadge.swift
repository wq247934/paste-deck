import AgentSpeedCore
import SwiftUI

/// Phase indicator of an agent row: shimmering dots while generating, a wrench while tools run, a grey dot when idle.
struct PhaseBadge: View {
    let phase: AgentPhase
    let tint: Color
    let animated: Bool

    var body: some View {
        Group {
            switch phase {
            case .generating:
                GeneratingDots(tint: tint, animated: animated)
            case .tools:
                Image(systemName: "wrench.adjustable.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
            case .idle:
                Circle()
                    .fill(.dashboardSecondary)
                    .opacity(0.55)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: DashboardLayout.badgeWidth, height: 12)
        .accessibilityHidden(true)
    }
}

/// Three dots with a travelling glow. The only per-frame animation in the dashboard; static under Reduce Motion.
private struct GeneratingDots: View {
    let tint: Color
    let animated: Bool

    private static let period: TimeInterval = 1.15
    private static let dot: CGFloat = 3.5
    private static let gap: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { timeline in
            let phase = animated ? timeline.date.timeIntervalSinceReferenceDate / Self.period : 0
            Canvas { context, size in
                let width = Self.dot * 3 + Self.gap * 2
                let originX = (size.width - width) / 2
                let y = (size.height - Self.dot) / 2
                for index in 0..<3 {
                    let level = animated ? Self.glow(phase: phase, index: index) : [1, 0.7, 0.45][index]
                    let rect = CGRect(
                        x: originX + CGFloat(index) * (Self.dot + Self.gap),
                        y: y,
                        width: Self.dot,
                        height: Self.dot
                    )
                    context.opacity = 0.35 + 0.65 * level
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                }
            }
        }
    }

    private static func glow(phase: Double, index: Int) -> Double {
        let local = (phase - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let wrapped = local < 0 ? local + 1 : local
        let wave = 0.5 + 0.5 * cos(2 * Double.pi * wrapped)
        return wave * wave
    }
}

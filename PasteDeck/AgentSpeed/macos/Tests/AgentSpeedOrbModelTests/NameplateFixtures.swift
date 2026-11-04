import AgentSpeedCore
import CoreGraphics
import Foundation
@testable import AgentSpeedOrbModel

/// Shared fakes for the name plate suites.
enum Nameplates {
    static let namer = OrbNamer(
        sourceName: { kind in
            switch kind {
            case .claudeCode: "Claude Code"
            case .claudeDesktop: "Claude Desktop"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            default: kind.rawValue
            }
        },
        allSources: "All Sources",
        pair: { "\($0) + \($1)" },
        more: { "\($0) +\($1)" }
    )

    /// The prototyped S / M / L sizes.
    static let sizes: [CGFloat] = [112, 148, 196]

    /// A 1440 × 900 display below the menu bar, in AppKit global points (y up).
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// Edge margin and orb-to-orb gap of a snapped orb.
    static let snap: CGFloat = 12

    static func disc(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 148) -> OrbDisc {
        OrbDisc(center: CGPoint(x: x, y: y), radius: size / 2)
    }

    /// A width of `k` points per grapheme.
    static func perGrapheme(_ k: CGFloat = 1) -> (String) -> CGFloat {
        { CGFloat($0.count) * k }
    }

    static func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    /// Euclidean distance between two rects (0 when they touch or overlap).
    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, b.minX - a.maxX, a.minX - b.maxX)
        let dy = max(0, b.minY - a.maxY, a.minY - b.maxY)
        return hypot(dx, dy)
    }

    static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(0, rect.minX - point.x, point.x - rect.maxX)
        let dy = max(0, rect.minY - point.y, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

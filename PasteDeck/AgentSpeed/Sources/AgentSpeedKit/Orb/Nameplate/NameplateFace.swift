import AgentSpeedOrbModel
import CoreGraphics

/// Laid-out plate content in its own coordinates (x from the plate's left edge): dots and text runs.
struct NameplateFace: Equatable {
    enum Role: Equatable {
        case text, secondary, accent
    }

    struct Dot: Equatable {
        var dot: NameplateDot
        /// Center from the plate's left edge.
        var x: CGFloat
    }

    struct Run: Equatable {
        var text: String
        var x: CGFloat
        var role: Role
        var tracking: CGFloat
    }

    var dots: [Dot] = []
    var runs: [Run] = []
    /// The plate width this face needs.
    var width: CGFloat
    /// Whether the text centers on the ideographic center rather than the cap height.
    var ideographic: Bool

    /// The face at rest: overlapping dots, then the (shortened) name.
    static func collapsed(dots: [NameplateDot], text: String, metrics: NameplateMetrics, tracking: CGFloat, textWidth: CGFloat,
                          ideographic: Bool) -> NameplateFace {
        let placed = dots.enumerated().map { Dot(dot: $1, x: metrics.dotCenter($0)) }
        return NameplateFace(
            dots: placed,
            runs: [Run(text: text, x: metrics.textStart(dots: dots.count), role: .text, tracking: tracking)],
            width: metrics.plateWidth(dots: dots.count, textWidth: textWidth),
            ideographic: ideographic
        )
    }

    /// One item of the expanded (chip) content: an optional dot and its text.
    struct Item: Equatable {
        var dot: NameplateDot?
        var text: String
        var role: Role
    }

    /// The chip's content in the plate's metrics: each item a dot and its text, `itemGap` apart; `measure` takes a
    /// text and its tracking.
    static func expanded(_ items: [Item], metrics: NameplateMetrics, measure: (String, CGFloat) -> CGFloat) -> NameplateFace {
        var x = metrics.leading
        var dots: [Dot] = []
        var runs: [Run] = []
        for (index, item) in items.enumerated() {
            if index > 0 { x += metrics.itemGap }
            if let dot = item.dot {
                dots.append(Dot(dot: dot, x: x + metrics.dot / 2))
                x += metrics.dot + metrics.textGap
            }
            let tracking = NameplateText.tracking(for: item.text, fontSize: metrics.fontSize)
            runs.append(Run(text: item.text, x: x, role: item.role, tracking: tracking))
            x += measure(item.text, tracking)
        }
        let ideographic = items.contains { NameplateText.containsCJK($0.text) }
        return NameplateFace(dots: dots, runs: runs, width: x + metrics.trailing, ideographic: ideographic)
    }
}

import AgentSpeedCore
import Foundation

/// How a row's value changed on a tick (DESIGN 2c Rows): a rise of more than 5 % flashes warm, a fall of more than 5 %
/// dims briefly. A value that was idle never flashes.
public enum BoardValueChange: Equatable, Sendable {
    case rise, fall, steady

    public init(from old: Double?, to new: Double) {
        guard let old, old > BoardGrouping.idle else {
            self = .steady
            return
        }
        self = new > old * 1.05 ? .rise : new < old * 0.95 ? .fall : .steady
    }
}

/// Shared rules of the boards' content (DESIGN 2c Content and Motion; the prototypes' `render`).
public enum BoardContentRules {
    /// A rise of more than 8 % + 20 tok/s in one tick punches the hero number.
    public static func punches(from old: Double?, to new: Double) -> Bool {
        guard let old, old > 0 else { return false }
        return new > old * 1.08 + 20
    }

    /// The characters of `new` that differ from `old` and roll in; nil when the lengths differ (the number is
    /// replaced whole, as in the prototypes).
    public static func rollingDigits(from old: String, to new: String) -> [Int]? {
        let a = Array(old), b = Array(new)
        guard a.count == b.count else { return nil }
        return b.indices.filter { a[$0] != b[$0] }
    }

    /// Timing's interval to the group above: `−` when it is slower (or equal), `+` when faster inside the ranking's
    /// band, then the difference in METRICS 7 format.
    public static func interval(ahead: Double, live: Double) -> String {
        let difference = ahead - live
        return (difference >= 0 ? "−" : "+") + SpeedFormat.speed(abs(difference))
    }

    /// The prototypes' `.name` flex row: the bold name keeps its width (but at least `minimum`) and the detail takes
    /// what remains after the gap.
    public static func nameSplit(available: Double, name: Double, gap: Double = 6, minimum: Double = 22)
        -> (name: Double, detail: Double) {
        let shown = max(min(name, available - gap), min(minimum, max(0, available)))
        return (shown, max(0, available - shown - gap))
    }

    /// A group's share of `live_A`, 0…1.
    public static func share(_ live: Double, of total: Double) -> Double {
        total > 0 ? min(1, max(0, live) / total) : 0
    }
}

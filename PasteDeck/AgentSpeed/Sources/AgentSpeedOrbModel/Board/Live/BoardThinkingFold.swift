import Foundation

/// When a board's 思考 hides (DESIGN 2c Live metrics, *Thinking hidden at zero*): while 思考 and another hero readout
/// are on and the board has a value, a 思考 that reads zero (`0`, or `0.0`) for 3 s hides; a value above zero brings it
/// back at once. The quiet state (no value) keeps the current visibility and restarts the hold. The fade and glide
/// are the content's (Core Animation); this decides the state on each engine tick. Times are seconds.
public struct BoardThinkingFold: Equatable, Sendable {
    public static let hold: TimeInterval = 3

    public private(set) var hidden = false
    private var zeroSince: TimeInterval?

    public init() {}

    /// Applies one tick. `eligible`: 思考 may hide (on with another hero readout); `quiet`: Σ w = 0 over the board's
    /// sources; `shown`: 思考 as METRICS 7 writes it. Returns whether 思考 is hidden.
    @discardableResult
    public mutating func update(eligible: Bool, quiet: Bool, shown: String, at time: TimeInterval) -> Bool {
        guard eligible else {
            hidden = false
            zeroSince = nil
            return hidden
        }
        if quiet {
            zeroSince = nil
        } else if OrbThinkingLine.readsZero(shown) {
            let since = zeroSince ?? time
            zeroSince = since
            if time - since >= Self.hold - 1e-9 { hidden = true }
        } else {
            zeroSince = nil
            hidden = false
        }
        return hidden
    }

    /// When the hold ends, for a board whose ticks stop changing to look again; nil when nothing is due.
    public func holdEnd(after time: TimeInterval) -> TimeInterval? {
        guard !hidden, let zeroSince, zeroSince + Self.hold > time else { return nil }
        return zeroSince + Self.hold
    }
}

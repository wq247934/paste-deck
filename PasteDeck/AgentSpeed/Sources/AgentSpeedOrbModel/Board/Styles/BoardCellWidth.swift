import Foundation

/// A fixed cell that values never move (DESIGN 2c Live metrics, *Table cells*; section 3's rule for the value): as wide
/// as its base, a wider value widens it at once, and it narrows back 6 s after the last value that needed more.
public struct BoardCellWidth: Equatable, Sendable {
    public static let hold: TimeInterval = 6

    public private(set) var base: Double
    public private(set) var current: Double
    private var wideAt: TimeInterval?

    public init(base: Double = 0) {
        self.base = base
        current = base
    }

    /// A new base (language, currency, font or switches changed): the cell starts over at it.
    public mutating func reset(base: Double) {
        guard base != self.base || current != base else { return }
        self.base = base
        current = base
        wideAt = nil
    }

    /// The width for values that need `need` at `time`.
    @discardableResult
    public mutating func fit(_ need: Double, at time: TimeInterval) -> Double {
        if need > current {
            current = need
            wideAt = time
        } else if need > base {
            wideAt = time
        } else if current > base, let wideAt, time - wideAt >= Self.hold {
            current = base
            self.wideAt = nil
        }
        return current
    }

    /// When the cell narrows back if nothing wider comes; nil while it is at its base.
    public var narrowsAt: TimeInterval? {
        guard current > base, let wideAt else { return nil }
        return wideAt + Self.hold
    }
}

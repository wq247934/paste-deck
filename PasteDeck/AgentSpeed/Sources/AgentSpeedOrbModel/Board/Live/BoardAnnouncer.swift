import Foundation

/// `a11y.board.newLeader` is announced politely at most once per 10 s (DESIGN 2c Accessibility).
public struct BoardAnnouncer: Equatable, Sendable {
    public static let interval: TimeInterval = 10

    private var last: TimeInterval?

    public init() {}

    /// True when an announcement may be made now (and records it).
    public mutating func mayAnnounce(now: TimeInterval) -> Bool {
        if let last, now - last < Self.interval { return false }
        last = now
        return true
    }
}

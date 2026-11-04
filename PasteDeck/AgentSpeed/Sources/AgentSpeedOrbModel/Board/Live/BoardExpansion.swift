import Foundation

/// Clicking a group shows up to 8 of its sub-agents in that space; the others collapse, and the expansion ends after
/// 60 s without interaction (DESIGN 2c Layout per size). Times in seconds of any monotonic clock.
public struct BoardExpansion: Equatable, Sendable {
    public static let timeout: TimeInterval = 60

    public private(set) var group: String?
    private var lastInteraction: TimeInterval = 0

    public init() {}

    /// A click on a group row: expands it, or collapses it when it is the expanded one.
    public mutating func toggle(_ id: String, now: TimeInterval) {
        group = group == id ? nil : id
        lastInteraction = now
    }

    /// Any other interaction with the board keeps the expansion open.
    public mutating func touch(now: TimeInterval) {
        if group != nil { lastInteraction = now }
    }

    /// When the expansion ends unless something touches it again.
    public var deadline: TimeInterval? { group.map { _ in lastInteraction + Self.timeout } }

    /// Ends the expansion once it timed out or its group left the board; true when that changed it.
    @discardableResult
    public mutating func expire(now: TimeInterval, present: Set<String>? = nil) -> Bool {
        guard let group else { return false }
        if now >= lastInteraction + Self.timeout || present.map({ !$0.contains(group) }) == true {
            self.group = nil
            return true
        }
        return false
    }

    public mutating func collapse() {
        group = nil
    }
}

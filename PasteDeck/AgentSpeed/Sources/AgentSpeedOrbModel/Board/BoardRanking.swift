import Foundation

/// One group as the ranking sees it on an engine tick.
public struct BoardRankEntry: Equatable, Sendable {
    public var id: String
    /// The group's live value (tok/s).
    public var live: Double
    /// The latest activity of any member, in milliseconds.
    public var lastActiveMs: Double

    public init(id: String, live: Double, lastActiveMs: Double) {
        self.id = id
        self.live = live
        self.lastActiveMs = lastActiveMs
    }
}

/// A group passed one or more groups on a tick (DESIGN 2c): ranks before and after the passes of that tick.
public struct BoardRankEvent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case overtake, newLeader
    }

    public var kind: Kind
    public var id: String
    public var from: Int
    public var to: Int

    public init(kind: Kind, id: String, from: Int, to: Int) {
        self.kind = kind
        self.id = id
        self.from = from
        self.to = to
    }
}

/// The board's stable ranking (DESIGN 2c, Ranking stability; reference `spec/tools/board_ranking.py`). A group passes
/// the group above it only after leading it by more than 10 % + 1 tok/s on two consecutive ticks, or at once by more
/// than 2× + 20; groups both below 0.05 order by latest activity (a lead of more than 1 s). New groups enter at the
/// place of their value; groups that leave are dropped; only passing emits an event.
public struct BoardRanking: Sendable {
    private struct Pair: Hashable, Sendable {
        let challenger: String
        let defender: String
    }

    /// Group ids, first place first.
    public private(set) var order: [String] = []
    private var pressure: [Pair: Int] = [:]

    public init() {}

    static func leads(_ a: BoardRankEntry, _ b: BoardRankEntry) -> Bool {
        if a.live < BoardGrouping.idle, b.live < BoardGrouping.idle {
            return a.lastActiveMs > b.lastActiveMs + 1000
        }
        return a.live > b.live * 1.1 + 1
    }

    static func overwhelms(_ a: BoardRankEntry, _ b: BoardRankEntry) -> Bool {
        a.live > b.live * 2 + 20
    }

    /// Feeds one engine tick; returns the order and the events of that tick.
    @discardableResult
    public mutating func tick(_ groups: [BoardRankEntry]) -> (order: [String], events: [BoardRankEvent]) {
        var byID: [String: BoardRankEntry] = [:]
        for group in groups where byID[group.id] == nil { byID[group.id] = group }
        var next: [Pair: Int] = [:]
        for a in byID.values {
            for b in byID.values where a.id != b.id && Self.leads(a, b) {
                let pair = Pair(challenger: a.id, defender: b.id)
                next[pair] = (pressure[pair] ?? 0) + 1
            }
        }
        pressure = next

        var order = order.filter { byID[$0] != nil }
        let known = Set(order)
        let newcomers = byID.values.filter { !known.contains($0.id) }.sorted { a, b in
            if a.live != b.live { return a.live > b.live }
            if a.lastActiveMs != b.lastActiveMs { return a.lastActiveMs > b.lastActiveMs }
            return a.id < b.id
        }
        for group in newcomers {
            let at = order.firstIndex { (byID[$0]?.live ?? 0) < group.live } ?? order.count
            order.insert(group.id, at: at)
        }
        let baseline = order

        if order.count > 1 {
            for i in 1..<order.count {
                var j = i
                while j > 0, let a = byID[order[j]], let b = byID[order[j - 1]],
                      (pressure[Pair(challenger: a.id, defender: b.id)] ?? 0) >= 2 || Self.overwhelms(a, b) {
                    order.swapAt(j - 1, j)
                    j -= 1
                }
            }
        }

        var before: [String: Int] = [:]
        for (rank, id) in baseline.enumerated() { before[id] = rank + 1 }
        var events: [BoardRankEvent] = []
        for (index, id) in order.enumerated() {
            let rank = index + 1
            guard let from = before[id], rank < from else { continue }
            events.append(BoardRankEvent(kind: rank == 1 ? .newLeader : .overtake, id: id, from: from, to: rank))
        }
        self.order = order
        return (order, events)
    }

    /// Forgets every group and its pressure (a board whose sources changed starts over).
    public mutating func reset() {
        order.removeAll()
        pressure.removeAll()
    }
}

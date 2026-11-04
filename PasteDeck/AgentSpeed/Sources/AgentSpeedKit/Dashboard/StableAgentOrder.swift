import AgentSpeedCore

/// Keeps the agents list from reshuffling on noise without ever splitting a parent group. The engine order
/// (METRICS 6.7) decides who is shown and wins whenever the gap is real; near-ties between whole groups, or between
/// siblings, keep the order the user is already looking at.
@MainActor
final class StableAgentOrder {
    private var previous: [String: Int] = [:]

    /// The rows to show, in display order: at most `limit` of them, or every agent when `limit` is nil.
    func arrange(_ agents: [AgentStatus], limit: Int?, speed: (AgentStatus) -> Double) -> [AgentStatus] {
        let tree = AgentTree(agents)
        let ownRank = agents.map { Self.rank($0.phase) }
        let ownSpeed = agents.map(speed)
        var groupRank = ownRank
        var groupSpeed = ownSpeed
        for index in agents.indices.reversed() {
            guard let parent = tree.parents[index] else { continue }
            groupRank[parent] = min(groupRank[parent], groupRank[index])
            groupSpeed[parent] += groupSpeed[index]
        }
        // Roots compare as whole groups and siblings by themselves, as the engine orders them.
        let order = tree.depthFirst { siblings, areRoots in
            areRoots
                ? stabilized(siblings, agents) { (groupRank[$0], groupSpeed[$0]) }
                : stabilized(siblings, agents) { (ownRank[$0], ownSpeed[$0]) }
        }

        // A depth-first prefix always includes the parents of the rows it shows.
        let limit = limit ?? order.count
        var shown = Set(order.prefix(limit))
        // An agent that just slipped below the cut stays if it near-ties the newcomer that would replace it. Only a
        // newcomer without shown children gives way, and only to an agent whose parent is shown.
        for candidate in order.dropFirst(limit) where previous[agents[candidate].id] != nil {
            if let parent = tree.parents[candidate], !shown.contains(parent) { continue }
            guard let slot = order.last(where: { index in
                shown.contains(index) && previous[agents[index].id] == nil && !tree.children[index].contains(where: shown.contains)
            }), slot != tree.parents[candidate],
                ownRank[slot] == ownRank[candidate],
                Self.isNearTie(ownSpeed[slot], ownSpeed[candidate]) else { continue }
            shown.remove(slot)
            shown.insert(candidate)
        }
        let rows = order.filter(shown.contains).map { agents[$0] }
        previous = Dictionary(rows.enumerated().map { ($1.id, $0) }) { first, _ in first }
        return rows
    }

    /// Swaps adjacent units back while they near-tie and the lower one was shown above the upper one.
    private func stabilized(_ units: [Int], _ agents: [AgentStatus], key: (Int) -> (rank: Int, speed: Double)) -> [Int] {
        guard units.count > 1 else { return units }
        var units = units
        var swapped = true
        var passes = 0
        while swapped, passes < units.count {
            swapped = false
            passes += 1
            for index in units.indices.dropLast() {
                let upper = units[index], lower = units[index + 1]
                guard let was = previous[agents[upper].id], let other = previous[agents[lower].id], other < was else { continue }
                let upperKey = key(upper), lowerKey = key(lower)
                guard upperKey.rank == lowerKey.rank, Self.isNearTie(upperKey.speed, lowerKey.speed) else { continue }
                units.swapAt(index, index + 1)
                swapped = true
            }
        }
        return units
    }

    private static func rank(_ phase: AgentPhase) -> Int {
        switch phase {
        case .generating: 0
        case .tools: 1
        case .idle: 2
        }
    }

    private static func isNearTie(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(3, 0.15 * max(a, b))
    }
}

import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Board grouping")
struct BoardGroupingTests {
    static func agent(_ id: String, parent: String? = nil, output: Double = 0, total: Double? = nil, active: Double = 0,
                      phase: AgentPhase = .idle, source: SourceKind = .claudeCode) -> AgentStatus {
        AgentStatus(id: id, source: source, project: "p-\(id)", model: nil, phase: phase, isSubagent: parent != nil,
                    live: Rate(output: output, total: total ?? output * 10), recentSpeed: nil,
                    lastActivity: Date(timeIntervalSince1970: active), parentId: parent)
    }

    @Test func groupsAreRootsWithAllTheirDescendants() {
        let agents = [
            Self.agent("r1", output: 10, active: 5, phase: .generating),
            Self.agent("s1", parent: "r1", output: 30, active: 9, phase: .generating),
            Self.agent("n1", parent: "s1", output: 5, active: 2),
            Self.agent("r2", output: 7, active: 1),
            Self.agent("s2", parent: "r1", output: 30, active: 12, phase: .tools),
        ]
        let groups = BoardGrouping.groups(agents, metric: .output)
        #expect(groups.map(\.id) == ["r1", "r2"])
        let first = groups[0]
        // Equal live values: the later activity first.
        #expect(first.subs.map(\.id) == ["s2", "s1", "n1"])
        #expect(first.live == 75)
        #expect(first.subLive == 65)
        #expect(first.generating == 2)
        #expect(first.lastActive == Date(timeIntervalSince1970: 12))
        #expect(groups[1].subs.isEmpty && groups[1].live == 7)
    }

    @Test func aSubAgentWithoutItsParentIsItsOwnRoot() {
        let agents = [Self.agent("orphan", parent: "gone", output: 3), Self.agent("r", output: 1)]
        let groups = BoardGrouping.groups(agents, metric: .output)
        #expect(groups.map(\.id) == ["orphan", "r"])
    }

    @Test func cyclesNeverHang() {
        let agents = [Self.agent("a", parent: "b", output: 1), Self.agent("b", parent: "a", output: 2)]
        let groups = BoardGrouping.groups(agents, metric: .output)
        #expect(Set(groups.map(\.id)) == ["a", "b"])
    }

    @Test func theMetricPicksTheValue() {
        let agents = [Self.agent("r", output: 2, total: 50), Self.agent("s", parent: "r", output: 1, total: 20)]
        #expect(BoardGrouping.groups(agents, metric: .total)[0].live == 70)
        #expect(BoardGrouping.groups(agents, metric: .output)[0].live == 3)
    }

    @Test func theBoardsSourcesFilterTheAgents() {
        // METRICS 6.8: the subset reading drops other sources and clears a parent outside the set.
        let agents = [
            Self.agent("r", output: 5, source: .codex),
            Self.agent("s", parent: "r", output: 4, source: .claudeCode),
            Self.agent("c", output: 2, source: .claudeCode),
        ]
        var snapshot = SpeedSnapshot.empty
        snapshot.agents = agents
        let reading = OrbSubset.reading(snapshot, sources: SourceSet([.claudeCode]))
        let groups = BoardGrouping.groups(reading.agents, metric: .output)
        #expect(groups.map(\.id) == ["s", "c"])
    }

    @Test func rankEntriesCarryLiveAndActivity() {
        let groups = BoardGrouping.groups([Self.agent("r", output: 4, active: 3)], metric: .output)
        #expect(BoardGrouping.rankEntries(groups) == [BoardRankEntry(id: "r", live: 4, lastActiveMs: 3000)])
    }
}

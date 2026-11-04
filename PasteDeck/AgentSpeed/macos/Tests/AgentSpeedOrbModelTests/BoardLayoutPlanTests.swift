import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Board layout plan")
struct BoardLayoutPlanTests {
    static func group(_ id: String, live: Double = 100, subs: Int = 0, activeSubs: Int? = nil) -> BoardPlanGroup {
        let active = activeSubs ?? subs
        return BoardPlanGroup(id: id, live: live, subs: (0..<subs).map { BoardPlanSub(id: "\(id)s\($0)", live: $0 < active ? Double(100 - $0) : 0) })
    }

    static func describe(_ rows: [BoardPlannedRow]) -> [String] {
        rows.map { row in
            switch row.kind {
            case .group(let index): "g\(index)@\(Int(row.y))"
            case .sub(let group, let sub): "g\(group).s\(sub)@\(Int(row.y))"
            case .moreSubs(let group, let count, _): "g\(group)+\(count)@\(Int(row.y))"
            case .moreGroups(let count, _): "+\(count)groups@\(Int(row.y))"
            }
        }
    }

    /// The planner's own cases use the prototypes' one-line group rows (a board keeps them at S; M and L draw the
    /// second line, DESIGN 2c Live metrics).
    static func oneLine(_ style: BoardStyle, _ size: BoardSize) -> BoardLayoutMetrics {
        var metrics = BoardLayoutMetrics.of(style, size)
        metrics.groupHeight = (size == .large ? 32 : 30) + (style == .timing ? 0 : 2)
        return metrics
    }

    @Test func metricsFollowThePrototypes() {
        let glass = BoardLayoutMetrics.of(.glass, .medium)
        #expect(glass.groupHeight == 38 && glass.subHeight == 22 && glass.moreHeight == 20 && glass.room == 188 && glass.top == 6)
        #expect(BoardLayoutMetrics.of(.glass, .small).groupHeight == 32 && BoardLayoutMetrics.of(.glass, .large).groupHeight == 40)
        #expect(BoardLayoutMetrics.of(.neon, .large) == BoardLayoutMetrics.of(.glass, .large))
        #expect(BoardLayoutMetrics.of(.glass, .large).room == 258)
        #expect(BoardLayoutMetrics.of(.glass, .small).room == 138)
        let timing = BoardLayoutMetrics.of(.timing, .medium)
        #expect(timing.groupHeight == 38 && timing.subHeight == 21 && timing.moreHeight == 19 && timing.room == 202 && timing.top == 0)
        #expect(BoardLayoutMetrics.of(.timing, .small).groupHeight == 30)
        #expect(BoardLayoutMetrics.of(.timing, .small).room == 152)
        #expect(BoardLayoutMetrics.of(.timing, .large).room == 272)
        #expect(BoardLayoutMetrics.of(.glass, .small).subLimits.isEmpty)
        #expect(BoardLayoutMetrics.of(.glass, .medium).subLimits == [2, 1, 1])
        #expect(BoardLayoutMetrics.of(.glass, .large).subLimits == [3, 3, 3, 2, 2])
        #expect(BoardLayoutMetrics.of(.glass, .large).groupLimit == 8)
    }

    @Test func aSwarmLeavesRoomForEveryGroupFirst() {
        let groups = [Self.group("a", subs: 100, activeSubs: 60), Self.group("b", subs: 3), Self.group("c", subs: 2),
                      Self.group("d", subs: 1)]
        let rows = BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.glass, .medium))
        #expect(Self.describe(rows) == ["g0@6", "g0.s0@38", "g0+99@60", "g1@80", "g2@112", "g3@144"])
        guard case .moreSubs(_, _, let live) = rows[2].kind else { Issue.record("more row"); return }
        #expect(live == (1..<60).reduce(0) { $0 + Double(100 - $1) }, "the rest's summed live value")
    }

    @Test func groupsThatDoNotFitBecomeTheMoreGroupsRow() {
        let groups = (0..<8).map { Self.group("g\($0)", live: Double(100 - $0)) }
        let rows = BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.glass, .medium))
        #expect(Self.describe(rows) == ["g0@6", "g1@38", "g2@70", "g3@102", "g4@134", "+3groups@166"])
        guard case .moreGroups(let count, let live) = rows.last?.kind else { Issue.record("rest row"); return }
        #expect(count == 3 && live == 95 + 94 + 93)
    }

    @Test func smallShowsNoSubRows() {
        let groups = (0..<4).map { Self.group("g\($0)", subs: 3) }
        #expect(Self.describe(BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.glass, .small))) == ["g0@6", "g1@38", "g2@70", "g3@102"])
        let five = (0..<5).map { Self.group("g\($0)", subs: 3) }
        #expect(Self.describe(BoardLayoutPlanner.plan(five, metrics: Self.oneLine(.glass, .small))) == ["g0@6", "g1@38", "g2@70", "+2groups@102"])
    }

    @Test func timingFillsSubRowsWithoutAMoreRowWhenAllFit() {
        let groups = (0..<3).map { Self.group("g\($0)", subs: 1) }
        let rows = BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.timing, .medium))
        #expect(Self.describe(rows) == ["g0@0", "g0.s0@30", "g1@51", "g1.s0@81", "g2@102", "g2.s0@132"])
    }

    @Test func idleSubAgentsGetNoRowUnlessExpanded() {
        let groups = [Self.group("a", subs: 10, activeSubs: 0), Self.group("b")]
        #expect(Self.describe(BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.glass, .large))) == ["g0@6", "g1@40"])
        let rows = BoardLayoutPlanner.plan(groups, metrics: Self.oneLine(.glass, .large), expanded: "a")
        #expect(Self.describe(rows) == ["g0@6", "g0.s0@40", "g0.s1@63", "g0.s2@86", "g0.s3@109", "g0.s4@132", "g0.s5@155",
                                         "g0.s6@178", "g0+3@201", "g1@221"])
    }

    @Test func noRowIsEverCutAndGroupsNeverYieldToSubRows() {
        var random = LedRandom(seed: 42)
        for _ in 0..<400 {
            let style = BoardStyle.allCases[Int(random.next() * 3)]
            let size = BoardSize.allCases[Int(random.next() * 3)]
            let metrics = BoardLayoutMetrics.of(style, size)
            let count = Int(random.next() * 12)
            let groups = (0..<count).map { index in
                Self.group("g\(index)", live: Double(1000 - index), subs: Int(random.next() * 6) * Int(random.next() * 4),
                           activeSubs: Int(random.next() * 8))
            }
            let expanded = random.next() < 0.3 && count > 0 ? "g\(Int(random.next() * Double(count)))" : nil
            let rows = BoardLayoutPlanner.plan(groups, metrics: metrics, expanded: expanded)
            let bottom = rows.map { $0.y + $0.height }.max() ?? metrics.top
            #expect(bottom <= metrics.top + metrics.room + 0.001, "\(style) \(size): rows end at \(bottom)")
            let plain = BoardLayoutPlanner.plan(groups.map { BoardPlanGroup(id: $0.id, live: $0.live, subs: []) }, metrics: metrics)
            let groupRows = rows.filter { if case .group = $0.kind { true } else { false } }.count
            let plainGroups = plain.filter { if case .group = $0.kind { true } else { false } }.count
            #expect(groupRows == plainGroups, "sub rows never push a group out")
            var y = metrics.top
            for row in rows {
                #expect(abs(row.y - y) < 0.001, "rows are stacked without gaps")
                y = row.y + row.height
            }
        }
    }
}

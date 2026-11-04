import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Board ranking")
struct BoardRankingTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("spec/fixtures/board-ranking-cases.json")

    struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let ticks: [Tick]
        }

        struct Tick: Decodable {
            let groups: [Group]
            let order: [String]
            let events: [Event]
        }

        struct Group: Decodable {
            let id: String
            let live: Double
            let lastActiveMs: Double
        }

        struct Event: Decodable {
            let type: String
            let id: String
            let from: Int
            let to: Int
        }

        let cases: [Case]
    }

    @Test func matchesTheSharedCases() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixture))
        #expect(fixture.cases.count >= 10)
        for item in fixture.cases {
            var ranking = BoardRanking()
            for (index, tick) in item.ticks.enumerated() {
                let result = ranking.tick(tick.groups.map { BoardRankEntry(id: $0.id, live: $0.live, lastActiveMs: $0.lastActiveMs) })
                #expect(result.order == tick.order, "\(item.name), tick \(index): order")
                let events = result.events.map { "\($0.kind.rawValue) \($0.id) \($0.from)→\($0.to)" }
                let wanted = tick.events.map { "\($0.type) \($0.id) \($0.from)→\($0.to)" }
                #expect(events == wanted, "\(item.name), tick \(index): events")
            }
        }
    }

    @Test func passingThreeGroupsReportsOneEventWithBothRanks() {
        var ranking = BoardRanking()
        ranking.tick([.init(id: "a", live: 300, lastActiveMs: 0), .init(id: "b", live: 200, lastActiveMs: 0),
                      .init(id: "c", live: 100, lastActiveMs: 0), .init(id: "d", live: 50, lastActiveMs: 0)])
        let result = ranking.tick([.init(id: "a", live: 300, lastActiveMs: 0), .init(id: "b", live: 200, lastActiveMs: 0),
                                   .init(id: "c", live: 100, lastActiveMs: 0), .init(id: "d", live: 900, lastActiveMs: 0)])
        #expect(result.order == ["d", "a", "b", "c"])
        #expect(result.events == [BoardRankEvent(kind: .newLeader, id: "d", from: 4, to: 1)])
    }

    @Test func resetForgetsTheOrder() {
        var ranking = BoardRanking()
        ranking.tick([.init(id: "a", live: 300, lastActiveMs: 0), .init(id: "b", live: 200, lastActiveMs: 0)])
        ranking.reset()
        #expect(ranking.order.isEmpty)
        let result = ranking.tick([.init(id: "b", live: 200, lastActiveMs: 0), .init(id: "a", live: 300, lastActiveMs: 0)])
        #expect(result.order == ["a", "b"])
        #expect(result.events.isEmpty)
    }
}

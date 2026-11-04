import Foundation
import Testing
@testable import AgentSpeedCore

/// METRICS 6.9 *Live thinking*: an agent's own thinking sums, which add up to the set's.
@Suite("Agent thinking sums")
struct AgentIntelligenceTests {
    static func sums(output: Double, thinking: Double, base: Double) -> IntelligenceSums {
        var sums = IntelligenceSums()
        sums.output = output
        sums.thinking = thinking
        sums.thinkingBase = base
        return sums
    }

    @Test func theShareIsReasoningOverTheOutputOfSourcesThatRecordIt() {
        #expect(Self.sums(output: 40, thinking: 10, base: 40).thinkingShare == 0.25)
        // Output of a source that does not record reasoning apart (DeepSeek Harness) weighs nothing in the share.
        #expect(Self.sums(output: 60, thinking: 10, base: 20).thinkingShare == 0.5)
        #expect(Self.sums(output: 30, thinking: 0, base: 0).thinkingShare == 0)
        #expect(IntelligenceSums.zero.thinkingShare == 0)
    }

    /// Over every `agentWindows` query: the agents' own sums add up to the set's, and an agent without a contribution
    /// in the window has zero sums.
    @Test func agentSumsAddUpAndAreZeroWithoutAContribution() throws {
        var checked = 0
        for name in IntelligenceCaseTests.agentWindowNames {
            var (engine, queries) = try IntelligenceCaseTests.engine("agentWindows", name)
            for query in queries {
                let now = try #require(query.int64("nowMs"))
                let snapshot = IntelligenceCaseTests.snapshot(&engine, now)
                IntelligenceCaseTests.expectAddUp(snapshot.agents.map(\.intelligence), snapshot.intelligence,
                                                  "\(name) @ \(now)")
                for (id, expected) in try #require(query["agents"] as? [String: [String: Any]])
                where expected.double("weight") == 0 {
                    let agent = try #require(snapshot.agents.first { $0.id == id })
                    #expect(agent.intelligence.output == 0 && agent.intelligence.thinking == 0
                        && agent.intelligence.thinkingBase == 0 && agent.intelligence.thinkingShare == 0,
                        "\(name) @ \(now) \(id)")
                    checked += 1
                }
            }
        }
        #expect(checked > 0)
    }
}

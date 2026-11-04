import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Orb unit (DESIGN 2b, 9)")
struct OrbUnitTests {
    static let detected = OrbAvailability(detected: [.codex, .claudeCode])

    @Test func decodesTolerantlyAndRoundTrips() throws {
        let decoder = JSONDecoder()
        let missing = try decoder.decode(OrbConfig.self, from: Data(#"{"id":"a"}"#.utf8))
        #expect(missing.unit == .tokens)
        let unknown = try decoder.decode(OrbConfig.self, from: Data(#"{"id":"a","unit":"lightyears"}"#.utf8))
        #expect(unknown.unit == .tokens)
        let cost = try decoder.decode(OrbConfig.self, from: Data(#"{"id":"a","unit":"cost"}"#.utf8))
        #expect(cost.unit == .cost)
        let encoded = try JSONEncoder().encode(cost)
        #expect(try decoder.decode(OrbConfig.self, from: encoded) == cost)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""unit":"cost""#))
    }

    @Test func addDuplicateAndSplitCopyTheUnitAndMergeKeepsTheTargets() throws {
        let doc = OrbsDocument(orbs: [
            OrbConfig(id: "a", unit: .cost),
            OrbConfig(id: "b", sources: .explicit([.codex])),
        ])
        let added = try #require(OrbEditing.add(to: doc, copying: "a", availability: Self.detected, newId: "n"))
        #expect(added.orb("n")?.unit == .cost)
        let duplicated = try #require(OrbEditing.duplicate("a", in: doc, newId: "d"))
        #expect(duplicated.orb("d")?.unit == .cost)
        let split = try #require(OrbEditing.split("a", in: doc, availability: Self.detected, newIds: ["s1", "s2"]))
        #expect(split.document.orbs.filter { $0.id != "b" }.allSatisfy { $0.unit == .cost })
        let merged = try #require(OrbEditing.merge(doc, keeping: "b"))
        #expect(merged.orbs.map(\.unit) == [.tokens])
        let set = OrbEditing.setUnit(.tokens, of: "a", in: doc)
        #expect(set.orb("a")?.unit == .tokens)
        #expect(OrbUnit.tokens.toggled == .cost && OrbUnit.cost.toggled == .tokens)
    }

    @Test func theSingleOrbMigrationStartsWithTokens() {
        #expect(OrbConfig.makeDefault(id: "x").unit == .tokens)
    }
}

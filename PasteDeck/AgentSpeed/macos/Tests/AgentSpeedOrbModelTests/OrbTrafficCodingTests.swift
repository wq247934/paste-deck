import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Orb traffic and name plate fields")
struct OrbTrafficCodingTests {
    private func decode(_ json: String) throws -> OrbConfig {
        try JSONDecoder().decode(OrbConfig.self, from: Data(json.utf8))
    }

    @Test func absentFieldsTakeTheirDefaults() throws {
        let orb = try decode(#"{"id":"a"}"#)
        #expect(orb.traffic == .sources)
        #expect(orb.showName == nil)
    }

    @Test func nullTrafficIsAbsentAndUnknownIsOff() throws {
        #expect(try decode(#"{"id":"a","traffic":null}"#).traffic == .sources)
        #expect(try decode(#"{"id":"a","traffic":"satellite"}"#).traffic == .off)
        #expect(try decode(#"{"id":"a","traffic":"machine","showName":false}"#).traffic == .machine)
        #expect(try decode(#"{"id":"a","traffic":"intelligence"}"#).traffic == .intelligence)
        #expect(try decode(#"{"id":"a","showName":"yes"}"#).showName == nil)
    }

    @Test func roundTripKeepsBothFields() throws {
        let orb = OrbConfig(id: "a", traffic: .intelligence, showName: true)
        let copy = try JSONDecoder().decode(OrbConfig.self, from: JSONEncoder().encode(orb))
        #expect(copy == orb)
    }

    @Test func addCopiesTrafficAndShowName() throws {
        var doc = OrbsDocument.fresh(id: "a")
        doc = OrbEditing.setTraffic(.machine, of: "a", in: doc)
        doc = OrbEditing.setShowName(false, of: "a", in: doc)
        let added = try #require(OrbEditing.add(to: doc, copying: "a", availability: OrbAvailability(detected: [.codex]), newId: "b"))
        #expect(added.orb("b")?.traffic == .machine)
        #expect(added.orb("b")?.showName == false)
        let duplicated = try #require(OrbEditing.duplicate("a", in: doc, newId: "c"))
        #expect(duplicated.orb("c")?.traffic == .machine)
    }
}

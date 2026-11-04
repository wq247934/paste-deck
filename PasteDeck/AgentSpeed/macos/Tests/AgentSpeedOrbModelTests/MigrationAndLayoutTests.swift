import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Migration and layouts")
struct MigrationAndLayoutTests {
    static let recordA = OrbPositionRecord(x: .high(12), y: .high(12))
    static let recordB = OrbPositionRecord(x: .low(12), y: .fraction(0.4))
    static let recordC = OrbPositionRecord(x: .fraction(0.5), y: .low(3))

    static let legacy = LegacyOrbSettings(
        visible: false, size: 196, opacity: 0.65, alwaysOnTop: false, clickThrough: true, fadeWhenIdle: true,
        allSpaces: false, positions: ["A": recordA, "B": recordB, "C": recordC], lastDisplay: "B"
    )

    @Test func createsOneOrbWithTheOldSettings() {
        let (document, master) = OrbsMigration.migrate(Self.legacy, id: "new", connectedDisplays: ["A", "B"], mainDisplay: "A")
        #expect(!master)
        #expect(document.orbs.count == 1)
        let orb = document.orbs[0]
        #expect(orb == OrbConfig(id: "new", name: nil, sources: .all, style: .led, size: 196, opacity: 0.65,
                                 alwaysOnTop: false, clickThrough: true, fadeWhenIdle: true, allSpaces: false, visible: true))
    }

    @Test func usesTheLastDisplayWhenConnected() {
        let (document, _) = OrbsMigration.migrate(Self.legacy, id: "o", connectedDisplays: ["B", "A"], mainDisplay: "A")
        #expect(document.entry(orb: "o", arrangement: "A+B") == OrbLayoutEntry(display: "B", record: Self.recordB))
        #expect(document.displayRecords["o"] == ["A": Self.recordA, "B": Self.recordB, "C": Self.recordC])
    }

    @Test func fallsBackToTheMainDisplayRecord() {
        let (document, _) = OrbsMigration.migrate(Self.legacy, id: "o", connectedDisplays: ["A", "C"], mainDisplay: "C")
        #expect(document.entry(orb: "o", arrangement: "A+C") == OrbLayoutEntry(display: "C", record: Self.recordC))
    }

    @Test func leavesTheDefaultCornerWhenTheMainDisplayHasNoRecord() {
        let (document, master) = OrbsMigration.migrate(
            LegacyOrbSettings(positions: ["A": Self.recordA], lastDisplay: "A"), id: "o", connectedDisplays: ["D"], mainDisplay: "D"
        )
        #expect(master)
        #expect(document.entry(orb: "o", arrangement: "D") == OrbLayoutEntry(display: "D", record: .defaultCorner))
        #expect(document.displayRecords["o"] == ["A": Self.recordA, "D": .defaultCorner])
        #expect(document.orbs[0].size == 148)
    }

    @Test func freshInstallHasOneDefaultOrb() {
        let document = OrbsDocument.fresh(id: "x")
        #expect(document.orbs == [OrbConfig.makeDefault(id: "x")])
        #expect(document.layouts.isEmpty)
    }

    @Test func arrangementKeysAreSorted() {
        #expect(OrbsDocument.arrangementKey(["B", "A", "C"]) == "A+B+C")
        #expect(OrbsDocument.arrangementKey(["Z"]) == "Z")
    }

    @Test func keepsTheSixteenMostRecentArrangements() {
        var document = OrbsDocument.fresh(id: "o")
        for index in 0..<17 {
            document.setEntry(OrbLayoutEntry(display: "D\(index)", record: Self.recordA), orb: "o", arrangement: "K\(index)")
        }
        #expect(document.layouts.count == 16)
        #expect(document.layouts["K0"] == nil)
        #expect(document.layoutOrder.first == "K1")
        // Using K1 again makes K2 the least recent.
        document.setEntry(OrbLayoutEntry(display: "D1", record: Self.recordB), orb: "o", arrangement: "K1")
        document.setEntry(OrbLayoutEntry(display: "D17", record: Self.recordB), orb: "o", arrangement: "K17")
        #expect(document.layouts["K1"] != nil)
        #expect(document.layouts["K2"] == nil)
        // Display fallbacks survive the dropped arrangements.
        #expect(document.fallbackRecord(orb: "o", display: "D0") == Self.recordA)
    }

    @Test func removingAnOrbDropsItsPositions() {
        var document = OrbsDocument(orbs: [OrbConfig(id: "a"), OrbConfig(id: "b")])
        document.setEntry(OrbLayoutEntry(display: "D", record: Self.recordA), orb: "a", arrangement: "K")
        document.setEntry(OrbLayoutEntry(display: "D", record: Self.recordB), orb: "b", arrangement: "K")
        document.setEntry(OrbLayoutEntry(display: "E", record: Self.recordB), orb: "b", arrangement: "L")
        document.removeOrb("b")
        #expect(document.orbs.map(\.id) == ["a"])
        #expect(document.layouts["K"]?["b"] == nil)
        #expect(document.layouts["L"] == nil)
        #expect(document.layoutOrder == ["K"])
        #expect(document.displayRecords["b"] == nil)
    }

    // MARK: Resolver

    @Test func resolverPrefersTheArrangementsOwnLayout() {
        var document = OrbsDocument(orbs: [OrbConfig(id: "o")])
        document.setEntry(OrbLayoutEntry(display: "A", record: Self.recordA), orb: "o", arrangement: "A")
        document.setEntry(OrbLayoutEntry(display: "B", record: Self.recordB), orb: "o", arrangement: "A+B")
        let entries = OrbLayoutResolver.entries(document: document, arrangement: "A+B", previousArrangement: "A",
                                                connected: ["A", "B"], main: "A")
        #expect(entries["o"] == OrbLayoutEntry(display: "B", record: Self.recordB))
    }

    @Test func resolverKeepsThePreviousRecordWhenItsDisplayIsStillConnected() {
        var document = OrbsDocument(orbs: [OrbConfig(id: "o")])
        document.setEntry(OrbLayoutEntry(display: "A", record: Self.recordA), orb: "o", arrangement: "A")
        let entries = OrbLayoutResolver.entries(document: document, arrangement: "A+N", previousArrangement: "A",
                                                connected: ["A", "N"], main: "N")
        #expect(entries["o"] == OrbLayoutEntry(display: "A", record: Self.recordA))
    }

    @Test func resolverUsesADisplayFallbackThenTheMainDisplay() {
        var document = OrbsDocument(orbs: [OrbConfig(id: "o"), OrbConfig(id: "p"), OrbConfig(id: "q")])
        document.setEntry(OrbLayoutEntry(display: "B", record: Self.recordB), orb: "o", arrangement: "B")
        document.setEntry(OrbLayoutEntry(display: "A", record: Self.recordA), orb: "o", arrangement: "A+C")
        document.setEntry(OrbLayoutEntry(display: "A", record: Self.recordC), orb: "p", arrangement: "A+C")
        // Only C is connected now: o has no record on C, so its last record moves to C keeping its anchors.
        var entries = OrbLayoutResolver.entries(document: document, arrangement: "C", previousArrangement: "A+C",
                                                connected: ["C"], main: "C")
        #expect(entries["o"] == OrbLayoutEntry(display: "C", record: Self.recordA))
        #expect(entries["p"] == OrbLayoutEntry(display: "C", record: Self.recordC))
        #expect(entries["q"] == .some(nil))
        // B is back alone: o finds its fallback on B.
        entries = OrbLayoutResolver.entries(document: document, arrangement: "B+D", previousArrangement: "C",
                                            connected: ["B", "D"], main: "D")
        #expect(entries["o"] == OrbLayoutEntry(display: "B", record: Self.recordB))
    }
}

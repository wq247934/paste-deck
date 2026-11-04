import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

/// The upgrade path (DESIGN 2b, Migration): after migrating, the single orb sits exactly where the single-orb version
/// put it at launch. The reference below is that version's launch logic (`restoreAtLaunch` / `fallbackCenter`).
@Suite("Upgrade path")
struct UpgradePathTests {
    struct Display {
        var key: String
        var visible: CGRect
    }

    static let builtIn = Display(key: "BUILTIN", visible: CGRect(x: 0, y: 0, width: 1512, height: 944))
    static let external = Display(key: "EXTERNAL", visible: CGRect(x: 1512, y: -300, width: 2560, height: 1415))
    static let projector = Display(key: "PROJECTOR", visible: CGRect(x: -1920, y: 0, width: 1920, height: 1055))

    /// The single-orb version: the last display's record when it is connected, else the primary display's record,
    /// else the default corner of the primary display.
    static func oldLaunchCenter(_ legacy: LegacyOrbSettings, displays: [Display], primary: Display) -> CGPoint {
        let radius = CGFloat(min(max(legacy.size, 96), 240)) / 2
        if let last = legacy.lastDisplay, let display = displays.first(where: { $0.key == last }), let record = legacy.positions[last] {
            return record.center(radius: radius, visible: display.visible)
        }
        if let record = legacy.positions[primary.key] {
            return record.center(radius: radius, visible: primary.visible)
        }
        return OrbSnap.defaultCenter(radius: radius, in: primary.visible)
    }

    static func newLaunchCenter(_ legacy: LegacyOrbSettings, displays: [Display], primary: Display) throws -> CGPoint {
        let keys = displays.map(\.key)
        let (document, _) = OrbsMigration.migrate(legacy, id: "orb", connectedDisplays: keys, mainDisplay: primary.key)
        let restored = try #require(OrbsDocument(data: document.data()))
        let infos = displays.map { OrbDisplayInfo(key: $0.key, visible: $0.visible) }
        return try #require(OrbLaunchPlacement.center(
            of: restored.orbs[0], document: restored, arrangement: OrbsDocument.arrangementKey(keys), displays: infos,
            main: keys[0], primary: OrbDisplayInfo(key: primary.key, visible: primary.visible)
        ))
    }

    static func legacy(size: Double = 148, positions: [String: OrbPositionRecord], last: String?) -> LegacyOrbSettings {
        LegacyOrbSettings(visible: true, size: size, opacity: 0.8, alwaysOnTop: true, clickThrough: false, fadeWhenIdle: true,
                          allSpaces: true, positions: positions, lastDisplay: last)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        var name: String
        var size: Double
        var positions: [String: OrbPositionRecord]
        var last: String?
        var connected: [String]
        var primary: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "last display connected", size: 148,
             positions: ["EXTERNAL": OrbPositionRecord(x: .low(12), y: .fraction(0.37)), "BUILTIN": OrbPositionRecord(x: .high(12), y: .high(12))],
             last: "EXTERNAL", connected: ["BUILTIN", "EXTERNAL"], primary: "BUILTIN"),
        Case(name: "last display gone, primary has a record", size: 196,
             positions: ["EXTERNAL": OrbPositionRecord(x: .low(12), y: .low(12)), "BUILTIN": OrbPositionRecord(x: .fraction(0.25), y: .high(3))],
             last: "EXTERNAL", connected: ["BUILTIN"], primary: "BUILTIN"),
        Case(name: "last display gone, another display has a record", size: 112,
             positions: ["EXTERNAL": OrbPositionRecord(x: .low(12), y: .low(12)), "PROJECTOR": OrbPositionRecord(x: .low(20), y: .high(20))],
             last: "EXTERNAL", connected: ["BUILTIN", "PROJECTOR"], primary: "BUILTIN"),
        Case(name: "never moved", size: 148, positions: [:], last: nil, connected: ["BUILTIN"], primary: "BUILTIN"),
        Case(name: "external primary with fractions", size: 300,
             positions: ["EXTERNAL": OrbPositionRecord(x: .fraction(0.61), y: .fraction(0.08))],
             last: "BUILTIN", connected: ["EXTERNAL", "BUILTIN", "PROJECTOR"], primary: "EXTERNAL"),
        Case(name: "tiny size clamps", size: 40, positions: ["BUILTIN": OrbPositionRecord(x: .high(0), y: .low(0))],
             last: "BUILTIN", connected: ["BUILTIN"], primary: "BUILTIN"),
    ]

    static func display(_ key: String) -> Display {
        [builtIn, external, projector].first { $0.key == key }!
    }

    @Test(arguments: cases)
    func migratedOrbSitsExactlyWhereTheOldOneDid(_ test: Case) throws {
        let legacy = Self.legacy(size: test.size, positions: test.positions, last: test.last)
        let displays = test.connected.map(Self.display)
        let primary = Self.display(test.primary)
        let old = Self.oldLaunchCenter(legacy, displays: displays, primary: primary)
        let new = try Self.newLaunchCenter(legacy, displays: displays, primary: primary)
        #expect(abs(old.x - new.x) < 0.001 && abs(old.y - new.y) < 0.001, "\(test.name): \(old) vs \(new)")
    }

    @Test func migratedOrbKeepsTheOldLookAndToggles() {
        let legacy = Self.legacy(size: 196, positions: [:], last: nil)
        let (document, master) = OrbsMigration.migrate(legacy, id: "orb", connectedDisplays: ["BUILTIN"], mainDisplay: "BUILTIN")
        #expect(master)
        #expect(document.orbs.count == 1)
        #expect(document.orbs[0].style == .led)
        #expect(document.orbs[0].sources == .all)
        #expect(document.orbs[0].size == 196)
        #expect(document.orbs[0].opacity == 0.8)
        #expect(document.orbs[0].fadeWhenIdle)
    }

    @Test func defaultCornerRecordResolvesToTheDefaultCenter() {
        for display in [Self.builtIn, Self.external, Self.projector] {
            for radius: CGFloat in [32, 48, 74, 120] {
                let resolved = OrbPositionRecord.defaultCorner.center(radius: radius, visible: display.visible)
                #expect(resolved == OrbSnap.defaultCenter(radius: radius, in: display.visible))
            }
        }
    }

    @Test func documentWithLayoutsSurvivesARoundTrip() throws {
        var document = OrbsDocument(orbs: [
            OrbConfig(id: "a", sources: .all, style: .led, size: 148),
            OrbConfig(id: "b", name: "Work", sources: .explicit([.claudeCode, .claudeDesktop]), style: .needle, size: 112,
                      opacity: 0.7, alwaysOnTop: false, clickThrough: true, redlineOutput: 600),
            OrbConfig(id: "c", sources: .normalized(["codex", "futureSource"]), style: .minimal, size: 64),
        ])
        document.setEntry(OrbLayoutEntry(display: "BUILTIN", record: .defaultCorner), orb: "a", arrangement: "BUILTIN")
        document.setEntry(OrbLayoutEntry(display: "EXTERNAL", record: OrbPositionRecord(x: .low(12), y: .fraction(0.31))),
                          orb: "b", arrangement: "BUILTIN+EXTERNAL")
        let restored = try #require(OrbsDocument(data: document.data()))
        #expect(restored == document)
        #expect(restored.data() == document.data())
    }
}

@Suite("Chip placement")
struct ChipPlacementTests {
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let size = CGSize(width: 140, height: 34)

    @Test func sitsCenteredSixPointsBelowTheDisc() {
        let disc = OrbDisc(center: CGPoint(x: 700, y: 500), radius: 74)
        let frame = OrbChipPlacement.frame(size: Self.size, disc: disc, visible: Self.visible, others: [])
        #expect(abs(frame.midX - 700) < 0.001)
        #expect(abs((frame.maxY - 8) - (500 - 74 - 6)) < 0.001)
    }

    @Test func movesBesideTheDiscTowardTheCenterWhenAnotherOrbIsBelow() {
        let disc = OrbDisc(center: CGPoint(x: 1200, y: 500), radius: 74)
        let below = OrbDisc(center: CGPoint(x: 1200, y: 340), radius: 74)
        let frame = OrbChipPlacement.frame(size: Self.size, disc: disc, visible: Self.visible, others: [below])
        #expect(frame.maxX - 8 <= 1200 - 74 - 6 + 0.001)
        #expect(abs(frame.midY - 500) < 0.001)
    }

    @Test func movesBesideWhenTheScreenEdgeIsBelowAndStaysInside() {
        let disc = OrbDisc(center: CGPoint(x: 100, y: 86), radius: 74)
        let frame = OrbChipPlacement.frame(size: Self.size, disc: disc, visible: Self.visible, others: [])
        #expect(frame.minX - (-8) >= -0.001)
        let minXWithMargin = frame.minX + 8
        let required = 100 + 74 + 6 - 0.001
        #expect(minXWithMargin >= required)
        #expect(frame.minY >= -8 - 0.001)
    }

    @Test func undoChipStacksUnderTheSourceChip() {
        let disc = OrbDisc(center: CGPoint(x: 700, y: 500), radius: 74)
        let chip = OrbChipPlacement.frame(size: Self.size, disc: disc, visible: Self.visible, others: [])
        let undo = OrbChipPlacement.frame(size: Self.size, disc: disc, visible: Self.visible, others: [], stack: 22)
        #expect(abs((chip.minY - undo.minY) - 22) < 0.001)
    }
}

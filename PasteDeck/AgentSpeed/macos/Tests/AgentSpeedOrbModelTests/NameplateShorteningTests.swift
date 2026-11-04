import AgentSpeedCore
import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Name plate shortening")
struct NameplateShorteningTests {
    static let claudePair = NameplateName.pair("Claude Code", "Claude Desktop")

    static func fit(_ name: NameplateName, _ budget: CGFloat, measure: (String) -> CGFloat = Nameplates.perGrapheme()) -> NameplateShortening.Result {
        NameplateShortening.fit(name, namer: Nameplates.namer, budget: budget, measure: measure)
    }

    static func scalars(_ text: String) -> [UInt32] {
        text.unicodeScalars.map(\.value)
    }

    @Test func theFullNameWhenItFitsAndShortenedFlagsOtherwise() {
        let result = Self.fit(Self.claudePair, 28)
        #expect(result == .init(text: "Claude Code + Claude Desktop", width: 28, fits: true, isShortened: false))
        #expect(!Self.fit(Self.claudePair, 100).isShortened)
        #expect(Self.fit(Self.claudePair, 20).isShortened, "A +1 is shortened")
        #expect(Self.fit(Self.claudePair, 12).isShortened)
        #expect(!Self.fit(.custom("Work"), 4).isShortened)
        #expect(!Self.fit(.single("Codex"), 5).isShortened)
        #expect(Self.fit(.single("Codex"), 4).isShortened)
    }

    @Test("Pair ladder: A + B, A +1, A… +1", arguments: [
        (27, "Claude Code +1"), (14, "Claude Code +1"), (13, "Claude Co… +1"), (12, "Claude C… +1"),
        (11, "Claude… +1"), (10, "Claude… +1"), (9, "Claud… +1"), (5, "C… +1"),
    ] as [(CGFloat, String)])
    func pairLadder(_ budget: CGFloat, _ expected: String) {
        let result = Self.fit(Self.claudePair, budget)
        #expect(result.text == expected)
        #expect(result.fits && result.isShortened)
        #expect(result.width <= budget)
    }

    @Test("More ladder: A +n, A… +n", arguments: [
        (.more("Codex", 2), 8, "Codex +2"), (.more("Codex", 2), 7, "Cod… +2"), (.more("Codex", 2), 5, "C… +2"),
        (.more("Claude Code", 3), 13, "Claude Co… +3"), (.more("Claude Code", 3), 11, "Claude… +3"),
    ] as [(NameplateName, CGFloat, String)])
    func moreLadder(_ name: NameplateName, _ budget: CGFloat, _ expected: String) {
        let result = Self.fit(name, budget)
        #expect(result.text == expected)
        #expect(result.fits)
        #expect(result.isShortened == (expected != NameplateShortening.fullText(name, namer: Nameplates.namer)))
    }

    @Test("One source, a custom name or all sources: tail ellipsis", arguments: [
        (.single("Gemini CLI"), 9, "Gemini C…"), (.single("Gemini CLI"), 8, "Gemini…"), (.single("Gemini CLI"), 2, "G…"),
        (.custom("Work Room"), 6, "Work…"), (.custom("Big  Room"), 6, "Big…"),
        (.allSources("All Sources"), 8, "All Sou…"), (.allSources("All Sources"), 5, "All…"),
    ] as [(NameplateName, CGFloat, String)])
    func tailEllipsis(_ name: NameplateName, _ budget: CGFloat, _ expected: String) {
        let result = Self.fit(name, budget)
        #expect(result.text == expected)
        #expect(result.fits && result.isShortened)
        #expect(!result.text.contains(" …"), "a trailing space is trimmed before the ellipsis")
    }

    @Test func aPairWithAShortFirstNameStillCountsTheOther() {
        let name = NameplateName.pair("Codex", "Claude Desktop")
        #expect(Self.fit(name, 22).text == "Codex + Claude Desktop")
        #expect(Self.fit(name, 21).text == "Codex +1")
        #expect(Self.fit(name, 7).text == "Cod… +1")
    }

    @Test func onlyTheTextChangesNeverTheType() {
        var measured: [String] = []
        let measure: (String) -> CGFloat = { text in
            measured.append(text)
            return CGFloat(text.count) * 5.5
        }
        let heads = (1...10).map { String(Array("Claude Code").prefix($0)).trimmingCharacters(in: .whitespaces) }
        let allowed = Set(["Claude Code + Claude Desktop", "Claude Code +1"] + heads.map { $0 + "… +1" })
        var previous: CGFloat = 0
        for step in 0...170 {
            let budget = CGFloat(step)
            let result = NameplateShortening.fit(Self.claudePair, namer: Nameplates.namer, budget: budget, measure: measure)
            #expect(result.width == CGFloat(result.text.count) * 5.5, "the width is the text measured at the plate's own size")
            #expect(result.fits == (result.width <= budget))
            #expect(result.width >= previous, "a wider budget never gives a shorter text")
            previous = result.width
        }
        #expect(Set(measured).isSubset(of: allowed))
    }

    @Test func thePlateIsTheMeasuredTextPlusFixedChrome() {
        let label = NameplateLabel(name: Self.claudePair, dots: [.source(.claudeCode), .source(.claudeDesktop)])
        for size in Nameplates.sizes {
            let metrics = NameplateMetrics(diameter: size)
            let measure = Nameplates.perGrapheme(0.55 * metrics.fontSize)
            for budget in [size + 6, 1.5 * size, 40] {
                let plate = NameplateShortening.plate(label, metrics: metrics, namer: Nameplates.namer, budget: budget, measure: measure)
                #expect(plate.text.width == measure(plate.text.text))
                #expect(Nameplates.isClose(plate.width, metrics.plateWidth(dots: 2, textWidth: plate.text.width)))
                #expect(!plate.text.fits || plate.width <= budget + 1e-9)
            }
        }
    }

    @Test func flagsAreNeverSplit() {
        let result = Self.fit(.custom("🇹🇼🇯🇵🇰🇷"), 2)
        #expect(result.text == "🇹🇼…")
        #expect(Self.scalars(result.text) == [0x1F1F9, 0x1F1FC, 0x2026])
    }

    @Test func zwjSequencesAndSkinTonesAreNeverSplit() {
        let coder = "👩‍💻"
        #expect(Self.fit(.custom("\(coder)\(coder)\(coder) Dev"), 3).text == coder + coder + "…")
        #expect(Self.fit(.custom("\(coder)\(coder)\(coder) Dev"), 5).text == coder + coder + coder + "…")
        #expect(Self.fit(.custom("👍🏽👍🏽👍🏽"), 2).text == "👍🏽…")
        // Even a measure that counts scalars only ever sees whole graphemes.
        let family = "👨‍👩‍👧‍👦"
        let scalarMeasure: (String) -> CGFloat = { CGFloat($0.unicodeScalars.count) }
        let roomy = Self.fit(.custom(family + family), 13, measure: scalarMeasure)
        #expect(roomy.text == family + "…" && roomy.fits)
        let tight = Self.fit(.custom(family + family), 7, measure: scalarMeasure)
        #expect(Self.scalars(tight.text) == Self.scalars(family + "…"))
        #expect(!tight.fits)
    }

    @Test func combiningMarksStayWithTheirBase() {
        let result = Self.fit(.custom("e\u{301}e\u{301}e\u{301}e\u{301}"), 3)
        #expect(Self.scalars(result.text) == [0x65, 0x301, 0x65, 0x301, 0x2026])
        let hangul = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}\u{1112}\u{1161}"
        #expect(Self.scalars(Self.fit(.custom(hangul), 2).text) == [0x1112, 0x1161, 0x11AB, 0x2026])
    }

    @Test func cjkNamesCutBetweenCharacters() {
        let wide: (String) -> CGFloat = { text in
            text.reduce(0) { $0 + (($1.unicodeScalars.first?.value ?? 0) >= 0x2E80 ? 2 : 1) }
        }
        #expect(Self.fit(.custom("東京工作室"), 7, measure: wide).text == "東京工…")
        #expect(Self.fit(.custom("工作\u{3000}室"), 7, measure: wide).text == "工作…", "an ideographic space is trimmed too")
        #expect(Self.fit(.single("クロードコード"), 9, measure: wide).text == "クロード…")
    }

    @Test func atLeastOneGraphemeStaysEvenWhenNothingFits() {
        for budget: CGFloat in [1, 0, -10] {
            let result = Self.fit(.custom("Workshop"), budget)
            #expect(result == .init(text: "W…", width: 2, fits: false, isShortened: true))
        }
        #expect(Self.fit(Self.claudePair, 4) == .init(text: "C… +1", width: 5, fits: false, isShortened: true))
        #expect(Self.fit(.more("Codex", 2), 4) == .init(text: "C… +2", width: 5, fits: false, isShortened: true))
    }
}

@Suite("Name plate spec example: Claude Code + Claude Desktop")
struct NameplateSpecExampleTests {
    static let full = "Claude Code + Claude Desktop"
    static let label = NameplateLabel.make(
        config: OrbConfig(id: "cc", sources: .explicit([.claudeCode, .claudeDesktop])), namer: Nameplates.namer, unavailable: []
    )

    /// The spec's table (f, h, d) and the plate width it gives for the full name.
    static func spec(_ size: CGFloat) -> (f: CGFloat, h: CGFloat, d: CGFloat, plate: CGFloat) {
        switch size {
        case 112: (9, 16, 5.4, 171)
        case 148: (10, 18, 6, 189)
        default: (12, 21, 7.2, 222)
        }
    }

    /// Two dots: leading (h − d) / 2, d + 2/3 d, text gap 0.42 f, trailing 0.52 h.
    static func chrome(_ size: CGFloat) -> CGFloat {
        let s = spec(size)
        return (s.h - s.d) / 2 + s.d * 5 / 3 + 0.42 * s.f + 0.52 * s.h
    }

    /// Exactly the spec's width for the full name; the same advance per grapheme for every shorter form.
    static func measure(_ size: CGFloat) -> (String) -> CGFloat {
        let fullWidth = spec(size).plate - chrome(size)
        let advance = fullWidth / CGFloat(full.count)
        return { $0 == full ? fullWidth : CGFloat($0.count) * advance }
    }

    static func plate(_ size: CGFloat, budget: CGFloat) -> (text: NameplateShortening.Result, width: CGFloat) {
        NameplateShortening.plate(
            label, metrics: NameplateMetrics(diameter: size), namer: Nameplates.namer, budget: budget, measure: measure(size)
        )
    }

    @Test(arguments: Nameplates.sizes)
    func theFullNameNeedsTheSpecWidth(_ size: CGFloat) {
        #expect(Self.label.dots.count == 2)
        let plate = Self.plate(size, budget: 1000)
        #expect(plate.text.text == Self.full)
        #expect(Nameplates.isClose(plate.width, Self.spec(size).plate, tolerance: 1e-6))
    }

    @Test func aloneAt112ItReadsClaudeCodePlusOne() {
        let budget = NameplateMetrics(diameter: 112).aloneBudget
        #expect(budget == 168)
        let plate = Self.plate(112, budget: budget)
        #expect(plate.text.text == "Claude Code +1")
        #expect(plate.text.fits && plate.text.isShortened)
        #expect(plate.width <= budget)
    }

    @Test(arguments: [148, 196] as [CGFloat])
    func aloneAt148And196ItReadsTheFullName(_ size: CGFloat) {
        let plate = Self.plate(size, budget: NameplateMetrics(diameter: size).aloneBudget)
        #expect(plate.text.text == Self.full)
        #expect(!plate.text.isShortened)
        #expect(Nameplates.isClose(plate.width, Self.spec(size).plate, tolerance: 1e-6))
    }

    @Test(arguments: Nameplates.sizes)
    func inATightRowItReadsClaudeCodePlusOne(_ size: CGFloat) {
        let step = size + Nameplates.snap
        let discs = (0..<3).map { Nameplates.disc(400 + CGFloat($0) * step, 437.5, size: size) }
        let budget = NameplateLayout.budget(for: 1, side: .below, discs: discs, visible: Nameplates.visible)
        #expect(Nameplates.isClose(budget, size + 6))
        let plate = Self.plate(size, budget: budget)
        #expect(plate.text.text == "Claude Code +1")
        #expect(plate.text.fits)
        #expect(plate.width <= budget + 1e-9)
    }
}

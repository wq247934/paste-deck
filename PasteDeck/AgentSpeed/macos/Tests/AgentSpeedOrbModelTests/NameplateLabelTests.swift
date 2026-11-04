import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Name plate content")
struct NameplateLabelTests {
    static func label(_ sources: OrbSourceSelection, name: String? = nil, unavailable: Set<SourceKind> = []) -> NameplateLabel {
        NameplateLabel.make(config: OrbConfig(id: "o", name: name, sources: sources), namer: Nameplates.namer, unavailable: unavailable)
    }

    @Test func allSourcesShowOneSpectrumDotThatIsNeverUnavailable() {
        #expect(Self.label(.all) == NameplateLabel(name: .allSources("All Sources"), dots: [.spectrum]))
        #expect(Self.label(.all, unavailable: Set(SourceKind.allCases)).dots == [.spectrum])
    }

    @Test func oneSource() {
        #expect(Self.label(.explicit([.gemini])) == NameplateLabel(name: .single("Gemini CLI"), dots: [.source(.gemini)]))
    }

    @Test func twoSourcesInSourceOrder() {
        let label = Self.label(.explicit([.claudeDesktop, .claudeCode]))
        #expect(label.name == .pair("Claude Code", "Claude Desktop"))
        #expect(label.dots == [.source(.claudeCode), .source(.claudeDesktop)])
    }

    @Test func threeSourcesNameTheFirstAndCountTheOthers() {
        let label = Self.label(.explicit([.gemini, .codex, .claudeCode]))
        #expect(label.name == .more("Codex", 2))
        #expect(label.dots == [.source(.codex), .source(.claudeCode), .source(.gemini)])
    }

    @Test func atMostThreeDots() {
        let label = Self.label(.explicit([.antigravity, .gemini, .codex, .claudeDesktop, .claudeCode]))
        #expect(label.name == .more("Codex", 4))
        #expect(label.dots == [.source(.codex), .source(.claudeCode), .source(.claudeDesktop)])
        #expect(label.dots.count == NameplateLabel.maxDots)
    }

    @Test func unavailableSourcesAreHollow() {
        let label = Self.label(.explicit([.codex, .gemini]), unavailable: [.gemini, .omp])
        #expect(label.dots == [.source(.codex), .unavailable(.gemini)])
        let allGone = Self.label(.explicit([.codex, .gemini]), unavailable: [.codex, .gemini])
        #expect(allGone.dots == [.unavailable(.codex), .unavailable(.gemini)])
        #expect(allGone.name == .pair("Codex", "Gemini CLI"), "the name stays; statuses live in the chip")
    }

    @Test func aCustomNameKeepsTheDots() {
        let label = Self.label(.explicit([.gemini, .codex]), name: "  Work  ", unavailable: [.gemini])
        #expect(label == NameplateLabel(name: .custom("Work"), dots: [.source(.codex), .unavailable(.gemini)]))
        #expect(Self.label(.all, name: "Everything") == NameplateLabel(name: .custom("Everything"), dots: [.spectrum]))
    }

    @Test func unknownKeysAreIgnored() {
        #expect(Self.label(.explicit(["future"])) == NameplateLabel(name: .allSources("All Sources"), dots: [.spectrum]))
        #expect(Self.label(.explicit(["codex", "future"])) == NameplateLabel(name: .single("Codex"), dots: [.source(.codex)]))
    }

    @Test(arguments: [
        OrbSourceSelection.all, .explicit([.codex]), .explicit([.claudeCode, .claudeDesktop]),
        .explicit([.gemini, .codex, .claudeCode]), .explicit(["future"]),
    ])
    func fullTextIsTheOrbsDisplayName(_ sources: OrbSourceSelection) {
        for name in [nil, "工作室"] {
            let config = OrbConfig(id: "o", name: name, sources: sources)
            let label = NameplateLabel.make(config: config, namer: Nameplates.namer, unavailable: [])
            #expect(NameplateShortening.fullText(label.name, namer: Nameplates.namer) == Nameplates.namer.displayName(config))
        }
    }
}

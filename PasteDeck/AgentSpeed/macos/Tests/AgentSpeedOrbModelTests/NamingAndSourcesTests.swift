import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Orb names and source selection")
struct NamingAndSourcesTests {
    static let namer = OrbNamer(
        sourceName: { kind in
            switch kind {
            case .claudeCode: "Claude Code"
            case .claudeDesktop: "Claude Desktop"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            default: kind.rawValue
            }
        },
        allSources: "All Sources",
        pair: { "\($0) + \($1)" },
        more: { "\($0) +\($1)" }
    )

    @Test func automaticNamesFollowTheSourceCount() {
        #expect(Self.namer.automaticName(.all) == "All Sources")
        #expect(Self.namer.automaticName(.explicit([.gemini])) == "Gemini CLI")
        #expect(Self.namer.automaticName(.explicit([.claudeDesktop, .claudeCode])) == "Claude Code + Claude Desktop")
        #expect(Self.namer.automaticName(.explicit([.gemini, .codex, .claudeCode])) == "Codex +2")
        #expect(Self.namer.automaticName(.explicit(["future", "codex"])) == "Codex")
        #expect(Self.namer.automaticName(.explicit(["future"])) == "All Sources")
    }

    @Test func customNamesWin() {
        let orb = OrbConfig(id: "a", name: "  Work  ", sources: .explicit([.codex]))
        #expect(orb.name == "Work")
        #expect(Self.namer.displayName(orb) == "Work")
        #expect(Self.namer.displayName(OrbConfig(id: "b", name: "   ", sources: .explicit([.codex]))) == "Codex")
    }

    @Test func duplicateNamesGetASuffix() {
        #expect(OrbNamer.duplicateName(nil) == nil)
        #expect(OrbNamer.duplicateName("Work") == "Work 2")
        #expect(OrbNamer.duplicateName("Work 2") == "Work 2 2")
        let long = String(repeating: "x", count: 32)
        #expect(OrbNamer.duplicateName(long) == String(repeating: "x", count: 30) + " 2")
    }

    @Test func togglingFollowsTheContextMenuRules() {
        #expect(OrbSourceSelection.all.toggling(.gemini) == .explicit(["gemini"]))
        let pair = OrbSourceSelection.explicit([.codex, .gemini])
        #expect(pair.toggling(.claudeCode) == .explicit(["codex", "claudeCode", "gemini"]))
        #expect(pair.toggling(.codex) == .explicit(["gemini"]))
        #expect(OrbSourceSelection.explicit([.codex]).toggling(.codex) == nil)
        #expect(OrbSourceSelection.explicit(["codex", "future"]).toggling(.codex) == nil)
        #expect(OrbSourceSelection.explicit(["codex", "future"]).toggling(.gemini) == .explicit(["codex", "gemini", "future"]))
    }

    @Test func trackingAndSets() {
        #expect(OrbSourceSelection.all.tracks(.omp))
        #expect(OrbSourceSelection.all.sourceSet == nil)
        #expect(OrbSourceSelection.all.knownSources.isEmpty)
        let selection = OrbSourceSelection.explicit([.antigravity, .codex])
        #expect(selection.tracks(.codex) && !selection.tracks(.claudeCode))
        #expect(selection.knownSources == [.codex, .antigravity])
        #expect(selection.sourceSet == SourceSet([.codex, .antigravity]))
    }

    @Test func selectionJSON() throws {
        let decode = { (json: String) in try JSONDecoder().decode(OrbSourceSelection.self, from: Data(json.utf8)) }
        #expect(try decode(#""all""#) == .all)
        #expect(try decode(#"[]"#) == .all)
        #expect(try decode(#"["gemini", "codex"]"#) == .explicit(["codex", "gemini"]))
        #expect(try decode(#"42"#) == .all)
        let data = try JSONEncoder().encode(OrbSourceSelection.explicit([.codex]))
        #expect(String(decoding: data, as: UTF8.self) == #"["codex"]"#)
    }
}

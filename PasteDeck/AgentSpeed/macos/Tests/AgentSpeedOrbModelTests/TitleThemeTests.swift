import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Title themes")
struct TitleThemeTests {
    private func lookup(_ key: String) -> String { "<\(key)>" }

    // MARK: Presets and resolution

    @Test func presetKeysFollowTheSpec() {
        #expect(TitlePreset.vehicles.titleKey(level: 1) == "title.walk")
        #expect(TitlePreset.vehicles.titleKey(level: 13) == "title.rocket")
        #expect(TitlePreset.vehicles.idleKey == "tier.idle")
        #expect(TitlePreset.cultivation.titleKey(level: 5) == "titles.cultivation.5")
        #expect(TitlePreset.cultivation.idleKey == "titles.cultivation.idle")
        #expect(TitlePreset.gameRank.nameKey == "titles.gameRank.name")
        #expect(TitlePreset.allCases.map(\.rawValue) == [
            "vehicles", "animals", "wind", "space", "cultivation", "wuxia", "mage", "gameRank", "engineer",
        ])
        #expect(TitlePreset.allCases.filter(\.showsVehicleArt) == [.vehicles])
    }

    @Test func customFieldsOverrideTheBaseAndEmptyFieldsFollowIt() {
        var set = CustomTitleSet(id: "c1", name: "Mine", base: .cultivation)
        set.setField(level: 4, "結丹")
        set.setField(level: 0, "睡覺")
        let theme = TitleTheme.custom(set)
        #expect(theme.text(level: 4, localized: lookup) == "結丹")
        #expect(theme.text(level: 0, localized: lookup) == "睡覺")
        #expect(theme.text(level: 5, localized: lookup) == "<titles.cultivation.5>")
        #expect(theme.showsVehicleArt == false)
        #expect(TitleTheme.custom(CustomTitleSet(id: "c2", name: "V", base: .vehicles)).showsVehicleArt)
    }

    @Test func unknownIdsFallBack() {
        let set = CustomTitleSet(id: "c1", name: "Mine", base: .wuxia)
        let doc = TitleThemesDocument(selected: "fromTheFuture", custom: [set])
        #expect(doc.general == .preset(.vehicles))
        #expect(doc.orbTheme(nil) == .preset(.vehicles))
        #expect(doc.orbTheme("deleted") == .preset(.vehicles))
        #expect(doc.orbTheme("c1") == .custom(set))
        #expect(doc.orbTheme("space") == .preset(.space))
        let selected = TitleThemesDocument(selected: "c1", custom: [set])
        #expect(selected.general == .custom(set))
        #expect(selected.orbTheme("unknown") == .custom(set), "an unknown orb theme counts as General")
    }

    // MARK: Persistence

    @Test func documentRoundTripsInTheSpecShape() throws {
        let json = """
        {"version": 1, "selected": "cultivation", "custom": [
          {"id": "3E0B", "name": "我的修仙路", "base": "cultivation", "idle": "",
           "titles": ["", "", "", "結丹", "", "", "", "", "", "", "", "飛升", ""]}]}
        """
        let doc = try #require(TitleThemesDocument(data: Data(json.utf8)))
        #expect(doc.selected == "cultivation")
        #expect(doc.custom.count == 1)
        #expect(doc.custom[0].titles[3] == "結丹")
        #expect(doc.custom[0].titles[11] == "飛升")
        let again = try #require(TitleThemesDocument(data: doc.data()))
        #expect(again == doc)
        let object = try #require(JSONSerialization.jsonObject(with: doc.data()) as? [String: Any])
        #expect(Set(object.keys) == ["version", "selected", "custom"])
    }

    @Test func loadingIsTolerant() throws {
        let json = """
        {"selected": "  ", "custom": [
          {"id": "a", "name": " Long\\tname ", "base": "nope", "titles": ["x"]},
          {"id": "a", "name": "dup"},
          {"name": "no id"},
          42,
          {"id": "b", "name": "B", "base": "space", "idle": "Z\\u202E", "titles": ["1","2","3","4","5","6","7","8","9","10","11","12","13","14"]}
        ]}
        """
        let doc = try #require(TitleThemesDocument(data: Data(json.utf8)))
        #expect(doc.selected == "vehicles")
        #expect(doc.custom.map(\.id) == ["a", "b"])
        #expect(doc.custom[0].base == .vehicles, "an unknown base becomes vehicles")
        #expect(doc.custom[0].name == "Long name")
        #expect(doc.custom[0].titles.count == 13)
        #expect(doc.custom[0].titles[0] == "x")
        #expect(doc.custom[1].titles.count == 13, "extra titles are cut")
        #expect(doc.custom[1].idle == "Z", "stored text is re-normalized")
        #expect(TitleThemesDocument(data: Data("[]".utf8)) == nil)
        #expect(TitleThemesDocument(data: nil) == nil)
        let tooMany = (0..<10).map { #"{"id": "s\#($0)", "name": "n\#($0)"}"# }.joined(separator: ",")
        let capped = try #require(TitleThemesDocument(data: Data(#"{"custom": [\#(tooMany)]}"#.utf8)))
        #expect(capped.custom.count == TitleThemesDocument.maxCustom)
    }

    // MARK: Text rules

    @Test func sanitizeAppliesTheTextRules() {
        #expect(TitleText.sanitize("  a\t\tb\nc\u{3000}d  ").text == "a b c d")
        #expect(TitleText.sanitize("x\u{0007}y\u{2028}z").text == "xyz")
        #expect(TitleText.sanitize("\u{202A}ab\u{2066}c\u{2069}").text == "abc")
        #expect(TitleText.sanitize("e\u{0301}").text == "\u{00E9}", "NFC")
        let emoji = TitleText.sanitize("Fast 🚀 ship ❤️")
        #expect(emoji.text == "Fast ship")
        #expect(emoji.removedEmoji)
        let symbols = TitleText.sanitize("★ ✦ ∞ 1")
        #expect(symbols.text == "★ ✦ ∞ 1")
        #expect(symbols.removedEmoji == false)
        let family = TitleText.sanitize("👨‍👩‍👧 team")
        #expect(family.text == "team")
        #expect(TitleText.sanitize(String(repeating: "字", count: 30)).text.count == TitleText.graphemeLimit)
    }

    @Test func fittedCutsAtWholeGraphemes() {
        let measure: (String) -> Double = { Double($0.count) * 7 }
        #expect(TitleText.fitted("短", maxWidth: 51.5, measure: measure) == ("短", false))
        let cut = TitleText.fitted("一二三四五六七八九", maxWidth: 51.5, measure: measure)
        #expect(cut.text == "一二三四五六七")
        #expect(cut.cut)
        #expect(TitleText.displayCase("Hero", english: true) == "HERO")
        #expect(TitleText.displayCase("Hero", english: false) == "Hero")
    }

    // MARK: Editing

    @Test func copyMakesAUniquelyNamedSelectedSet() throws {
        var doc = TitleThemesDocument()
        let name: (String) -> String = { "\($0)（自訂）" }
        doc = try #require(TitleThemeEditing.copy("cultivation", in: doc, newID: "n1", sourceName: "修真境界", copyName: name))
        #expect(doc.selected == "n1")
        #expect(doc.custom[0].name == "修真境界（自訂）")
        #expect(doc.custom[0].base == .cultivation)
        doc = try #require(TitleThemeEditing.copy("cultivation", in: doc, newID: "n2", sourceName: "修真境界", copyName: name))
        #expect(doc.custom[1].name == "修真境界（自訂） 2")
        doc = TitleThemeEditing.setField(level: 3, of: "n2", to: " 結丹 ", in: doc)
        doc = try #require(TitleThemeEditing.copy("n2", in: doc, newID: "n3", sourceName: "Mine", copyName: name))
        #expect(doc.custom[2].base == .cultivation, "a copy of a custom set keeps its base")
        #expect(doc.custom[2].titles[2] == "結丹", "and its texts")
        for index in 4...8 {
            doc = try #require(TitleThemeEditing.copy("vehicles", in: doc, newID: "x\(index)", sourceName: "V", copyName: name))
        }
        #expect(doc.custom.count == 8)
        #expect(TitleThemeEditing.copy("vehicles", in: doc, newID: "x9", sourceName: "V", copyName: name) == nil)
        #expect(TitleThemeEditing.copy("unknown", in: TitleThemesDocument(), newID: "y", sourceName: "?", copyName: name) == nil)
    }

    @Test func deleteFallsBackToTheBase() throws {
        var doc = TitleThemesDocument(custom: [CustomTitleSet(id: "c1", name: "Mine", base: .mage)])
        doc = TitleThemeEditing.select("c1", in: doc)
        #expect(doc.selected == "c1")
        let result = try #require(TitleThemeEditing.delete("c1", in: doc))
        #expect(result.base == .mage)
        #expect(result.document.selected == "mage")
        #expect(result.document.custom.isEmpty)
        #expect(TitleThemeEditing.delete("nope", in: doc) == nil)
        #expect(TitleThemeEditing.select("ghost", in: doc).selected == "c1", "selecting an unknown id changes nothing")
    }

    @Test func renameBaseAndReset() {
        var doc = TitleThemesDocument(custom: [CustomTitleSet(id: "c1", name: "Mine", base: .mage)])
        doc = TitleThemeEditing.rename("c1", to: "   ", in: doc)
        #expect(doc.custom[0].name == "Mine", "an empty name keeps the previous one")
        doc = TitleThemeEditing.rename("c1", to: String(repeating: "n", count: 40), in: doc)
        #expect(doc.custom[0].name.count == 32)
        doc = TitleThemeEditing.setField(level: 1, of: "c1", to: "One", in: doc)
        doc = TitleThemeEditing.setBase(.space, of: "c1", in: doc)
        #expect(doc.custom[0].base == .space)
        #expect(doc.custom[0].titles[0] == "One", "filled fields stay when the base changes")
        doc = TitleThemeEditing.resetAll("c1", in: doc)
        #expect(doc.custom[0].titles.allSatisfy { $0.isEmpty })
        #expect(doc.custom[0].idle.isEmpty)
    }

    // MARK: Per-orb override

    @Test func orbsCarryTheirThemeThroughEditing() throws {
        var orb = OrbConfig(id: "a", titleTheme: " wuxia ")
        #expect(orb.titleTheme == "wuxia")
        orb.titleTheme = nil
        var doc = OrbsDocument(orbs: [OrbConfig(id: "a", titleTheme: "c1"), OrbConfig(id: "b")])
        let decoded = try #require(OrbsDocument(data: doc.data()))
        #expect(decoded.orbs[0].titleTheme == "c1")
        #expect(decoded.orbs[1].titleTheme == nil)
        let legacy = #"{"version": 1, "orbs": [{"id": "x"}]}"#
        let legacyDocument = try #require(OrbsDocument(data: Data(legacy.utf8)))
        #expect(legacyDocument.orbs[0].titleTheme == nil, "older documents load")
        let added = try #require(OrbEditing.add(to: doc, copying: "a", availability: OrbAvailability(detected: []), newId: "n"))
        #expect(added.orb("n")?.titleTheme == "c1", "Add copies the title theme")
        doc = OrbEditing.replacingTitleTheme("c1", with: "mage", in: doc)
        #expect(doc.orb("a")?.titleTheme == "mage")
        doc = OrbEditing.setTitleTheme(nil, of: "a", in: doc)
        #expect(doc.orb("a")?.titleTheme == nil)
    }

    // MARK: Badge layout

    private func measure(_ text: String, size: Double, tracking: Double) -> Double {
        let cjk = text.unicodeScalars.contains { $0.value >= 0x3000 }
        let advance = cjk ? 1.0 : 0.62
        return Double(text.count) * size * (advance + tracking)
    }

    @Test func badgeLayoutRules() {
        let seal = TitleBadgeLayout.layout("初學乍練", language: "zh-Hant", measure: measure)
        #expect(seal.kind == .seal)
        #expect(seal.lines == ["初學", "乍練"])
        #expect(seal.size == 21)
        #expect(TitleBadgeLayout.layout("初學乍練", language: "ja", measure: measure).kind != .seal, "Japanese never uses the seal")
        let two = TitleBadgeLayout.layout("初級工程師", language: "zh-Hant", measure: measure)
        #expect(two.kind == .twoLines)
        #expect(two.lines == ["初級", "工程師"])
        #expect(TitleBadgeLayout.layout("10x 工程師", language: "zh-Hant", measure: measure).lines == ["10x", "工程師"])
        let kana = TitleBadgeLayout.layout("ブラックホール", language: "ja", measure: measure)
        #expect(kana.kind == .oneLine, "runs of kana never break")
        let single = TitleBadgeLayout.layout("神", language: "zh-Hant", measure: measure)
        #expect(single.size == 34)
        let latin = TitleBadgeLayout.layout("TRIBULATION", language: "en", measure: measure)
        #expect(latin.kind == .oneLine)
        #expect(latin.size < 14)
        #expect(latin.tracking == 0, "no tracking below 14 units")
        #expect(measure("TRIBULATION", size: latin.size, tracking: latin.tracking) <= TitleBadgeLayout.maxWidth)
        let force = TitleBadgeLayout.layout("RED GIANT", language: "en", measure: measure)
        #expect(force.kind == .twoLines)
        #expect(force.lines == ["RED", "GIANT"])
    }
}

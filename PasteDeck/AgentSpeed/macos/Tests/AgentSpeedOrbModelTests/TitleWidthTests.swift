import AppKit
import CoreText
import Foundation
import Testing
@testable import AgentSpeedOrbModel

/// DESIGN 1, Title length: every preset title in every language fits the maximum budget (`w7` ≤ 51.5 pt: semibold
/// system font at 7 pt, tracking 0, uppercase for English), measured with this platform's fonts. Vehicles predates
/// the budget; its English MOTORCYCLE and BULLET TRAIN are the only exceptions.
@Suite("Title width budget")
struct TitleWidthTests {
    static let languages = ["zh-Hant", "zh-Hans", "en", "ja"]
    static let exceptions: Set<String> = ["title.motorcycle/en", "title.bulletTrain/en"]

    static var strings: [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/strings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var table: [String: [String: String]] = [:]
        for (key, value) in object {
            if let entry = value as? [String: String] { table[key] = entry }
        }
        return table
    }

    static func w7(_ text: String, language: String) -> Double {
        let display = TitleText.displayCase(text, english: language == "en")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
            .kern: 0,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: display, attributes: attributes))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    @Test func everyPresetTitleFitsTheMaximumBudget() throws {
        let table = Self.strings
        try #require(!table.isEmpty, "spec/strings.json not found")
        var measured = 0
        var over: [String] = []
        for preset in TitlePreset.allCases {
            let keys = (1...TitlePreset.levelCount).map(preset.titleKey(level:)) + [preset.idleKey]
            for key in keys {
                let entry = try #require(table[key], "missing \(key)")
                for language in Self.languages {
                    let text = try #require(entry[language], "\(key) has no \(language)")
                    #expect(!text.isEmpty)
                    let width = Self.w7(text, language: language)
                    measured += 1
                    if width > TitleText.maximumWidth, !Self.exceptions.contains("\(key)/\(language)") {
                        over.append(String(format: "%@/%@ %@ %.1f pt", key, language, text, width))
                    }
                }
            }
        }
        #expect(measured == 9 * 14 * 4)
        #expect(over.isEmpty, "over the maximum budget: \(over)")
    }

    @Test func presetLaddersAreUniqueAndIdleIsNotATitle() throws {
        let table = Self.strings
        for preset in TitlePreset.allCases {
            for language in Self.languages {
                let titles = try (1...TitlePreset.levelCount).map { level in
                    try #require(table[preset.titleKey(level: level)]?[language])
                }
                let idle = try #require(table[preset.idleKey]?[language])
                #expect(Set(titles).count == titles.count, "\(preset.rawValue)/\(language) repeats a title")
                #expect(!titles.contains(idle), "\(preset.rawValue)/\(language) idle label is one of its titles")
            }
            #expect(table[preset.nameKey] != nil)
        }
    }
}

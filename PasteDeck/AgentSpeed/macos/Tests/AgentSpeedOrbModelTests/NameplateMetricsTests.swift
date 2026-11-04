import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Name plate geometry and type")
struct NameplateMetricsTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var size: CGFloat
        var font: CGFloat
        var height: CGFloat
        var gap: CGFloat
        var dot: CGFloat
        var alone: CGFloat = 0
        var ring: CGFloat = 0
        var testDescription: String { "S \(size)" }
    }

    @Test("Geometry table at 112 / 148 / 196", arguments: [
        Row(size: 112, font: 9, height: 16, gap: 4, dot: 5.4, alone: 168, ring: 1),
        Row(size: 148, font: 10, height: 18, gap: 5, dot: 6, alone: 222, ring: 1.08),
        Row(size: 196, font: 12, height: 21, gap: 7, dot: 7.2, alone: 294, ring: 1.296),
    ])
    func specTable(_ row: Row) {
        let m = NameplateMetrics(diameter: row.size)
        #expect(m.fontSize == row.font)
        #expect(m.height == row.height)
        #expect(m.cornerRadius == row.height / 2)
        #expect(m.gap == row.gap)
        #expect(Nameplates.isClose(m.dot, row.dot))
        #expect(m.aloneBudget == row.alone)
        #expect(Nameplates.isClose(m.ringWidth, row.ring), "max(1 pt, 0.18 d)")
    }

    @Test("Clamps at the ends and 0.5 pt text steps in between", arguments: [
        Row(size: 64, font: 9, height: 16, gap: 4, dot: 5.4),
        Row(size: 80, font: 9, height: 16, gap: 4, dot: 5.4),
        Row(size: 96, font: 9, height: 16, gap: 4, dot: 5.4),
        Row(size: 160, font: 10.5, height: 19, gap: 5, dot: 6.3),
        Row(size: 176, font: 11.5, height: 20, gap: 6, dot: 6.9),
        Row(size: 240, font: 12, height: 21, gap: 7, dot: 7.2),
    ])
    func clampsAndRounding(_ row: Row) {
        let m = NameplateMetrics(diameter: row.size)
        #expect(m.fontSize == row.font)
        #expect(m.height == row.height)
        #expect(m.gap == row.gap)
        #expect(Nameplates.isClose(m.dot, row.dot))
        #expect(m.aloneBudget == 1.5 * row.size)
    }

    @Test("Dots, padding and ring follow the rules", arguments: Nameplates.sizes)
    func derivedMeasures(_ size: CGFloat) {
        let m = NameplateMetrics(diameter: size)
        let d = m.dot
        #expect(Nameplates.isClose(m.dotStep, d * 2 / 3))
        #expect(Nameplates.isClose(d - m.dotStep, d / 3), "each dot overlaps the previous by a third")
        #expect(Nameplates.isClose(m.leading, (m.height - d) / 2))
        #expect(Nameplates.isClose(m.dotCenter(0), m.height / 2), "first dot concentric with the left cap")
        #expect(Nameplates.isClose(m.dotCenter(2) - m.dotCenter(1), m.dotStep))
        #expect(Nameplates.isClose(m.textGap, 0.42 * m.fontSize))
        #expect(Nameplates.isClose(m.trailing, 0.52 * m.height))
        #expect(Nameplates.isClose(m.ringWidth, max(1, 0.18 * d)))
        #expect(m.dotsWidth(0) == 0)
        #expect(Nameplates.isClose(m.dotsWidth(1), d))
        #expect(Nameplates.isClose(m.dotsWidth(3), d * 7 / 3))
        for dots in 1...3 {
            let lastDotEdge = m.dotCenter(dots - 1) + d / 2
            #expect(Nameplates.isClose(m.textStart(dots: dots), lastDotEdge + m.textGap), "text starts 0.42 f after the last dot")
        }
    }

    @Test func plateWidthAddsUpThePartsOfTheSpecExample() {
        // leading + two dots + text gap + trailing; the spec's 171 / 189 / 222 less these is the text.
        let chrome: [CGFloat] = [26.4, 29.56, 34.86]
        for (size, expected) in zip(Nameplates.sizes, chrome) {
            let m = NameplateMetrics(diameter: size)
            #expect(Nameplates.isClose(m.chrome(dots: 2), expected), "S \(size)")
            #expect(Nameplates.isClose(m.plateWidth(dots: 2, textWidth: 100), expected + 100))
            #expect(Nameplates.isClose(m.plateWidth(dots: 3, textWidth: 100) - m.plateWidth(dots: 2, textWidth: 100), m.dotStep))
        }
    }

    @Test("plateWidth and textBudget are inverses", arguments: Nameplates.sizes)
    func plateWidthRoundTrip(_ size: CGFloat) {
        let m = NameplateMetrics(diameter: size)
        for dots in 1...3 {
            for text: CGFloat in [0, 37.5, 140] {
                let width = m.plateWidth(dots: dots, textWidth: text)
                #expect(Nameplates.isClose(m.textBudget(plateWidth: width, dots: dots), text))
            }
            for budget: CGFloat in [size + 6, 1.5 * size] {
                let text = m.textBudget(plateWidth: budget, dots: dots)
                #expect(Nameplates.isClose(m.plateWidth(dots: dots, textWidth: text), budget))
            }
        }
    }

    @Test(arguments: [
        ("Claude Code", false), ("DeepSeek", false), ("omp", false), ("Café Crème", false), ("Работа", false),
        ("🚀 Rocket", false), ("", false),
        ("工作", true), ("簡體 简体", true), ("𠀀", true), ("クロード", true), ("しごと", true), ("ｸﾛｰﾄﾞ", true),
        ("작업실", true), ("ＡＢＣ", true), ("１２３", true), ("Codex 工作", true), ("Work ルーム", true), ("Team 팀", true),
    ])
    func containsCJK(_ text: String, _ expected: Bool) {
        #expect(NameplateText.containsCJK(text) == expected)
    }

    @Test func trackingIsWiderForCJK() {
        #expect(Nameplates.isClose(NameplateText.tracking(for: "Claude Code", fontSize: 10), 0.12))
        #expect(Nameplates.isClose(NameplateText.tracking(for: "Claude Code", fontSize: 12), 0.144))
        #expect(Nameplates.isClose(NameplateText.tracking(for: "工作", fontSize: 10), 0.4))
        #expect(Nameplates.isClose(NameplateText.tracking(for: "Codex 工作", fontSize: 12), 0.48))
        #expect(Nameplates.isClose(NameplateText.tracking(for: "ＡＢＣ", fontSize: 9), 0.36))
    }
}

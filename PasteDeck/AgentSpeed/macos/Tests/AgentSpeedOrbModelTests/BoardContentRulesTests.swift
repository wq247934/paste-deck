import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Board content rules")
struct BoardContentRulesTests {
    @Test func sparklineFollowsDrawSpark() {
        let points = BoardHistoryShape.sparkline([0, 50, 100], width: 104, height: 40)
        #expect(points.count == 3)
        #expect(points[0] == SIMD2(0, 38))
        #expect(points[1].x == 52)
        #expect(abs(points[2].y - (38 - 100 / 112.0 * 34)) < 1e-9)
        #expect(BoardHistoryShape.sparkline([5], width: 104, height: 40).isEmpty)
        // Below 10 tok/s the scale stays at 11.2, so a quiet board draws a low line instead of a full-height one.
        #expect(BoardHistoryShape.sparkline([1, 1], width: 10, height: 40)[0].y > 30)
    }

    @Test func barsPadTheStartAndKeepAFloor() {
        let bars = BoardHistoryShape.bars([10, 20, 40], count: 5, height: 38)
        #expect(bars == [2, 2, 9.5, 19, 38])
        #expect(BoardHistoryShape.bars(Array(repeating: 0, count: 40), count: 30, height: 38).allSatisfy { $0 == 2 })
        #expect(BoardHistoryShape.bars((0..<40).map(Double.init), count: 30, height: 38).last == 38)
    }

    @Test func ledMarksThePeakBeyondTheLitSegments() {
        let led = BoardHistoryShape.led(heat: 0.5, peakHeat: 0.9)
        #expect(led.lit == 12 && led.peak == 21)
        #expect(BoardHistoryShape.led(heat: 0.9, peakHeat: 0.5).peak == nil)
        #expect(BoardHistoryShape.led(heat: 0, peakHeat: 0).lit == 0)
        #expect(BoardHistoryShape.led(heat: 0, peakHeat: 0).peak == nil)
        #expect(BoardHistoryShape.led(heat: 1, peakHeat: 1) == (24, nil))
        #expect(BoardHistoryShape.led(heat: 0.2, peakHeat: 1).peak == 23)
    }

    @Test func valuesFlashOnlyBeyondFivePercent() {
        #expect(BoardValueChange(from: 100, to: 106) == .rise)
        #expect(BoardValueChange(from: 100, to: 105) == .steady)
        #expect(BoardValueChange(from: 100, to: 94) == .fall)
        #expect(BoardValueChange(from: 100, to: 0) == .fall)
        #expect(BoardValueChange(from: 0, to: 300) == .steady)
        #expect(BoardValueChange(from: nil, to: 300) == .steady)
    }

    @Test func punchNeedsEightPercentAndTwenty() {
        #expect(BoardContentRules.punches(from: 1000, to: 1101))
        #expect(!BoardContentRules.punches(from: 1000, to: 1100))
        #expect(!BoardContentRules.punches(from: 10, to: 30))
        #expect(BoardContentRules.punches(from: 10, to: 31))
        #expect(!BoardContentRules.punches(from: 0, to: 500))
    }

    @Test func onlyChangedDigitsRoll() {
        #expect(BoardContentRules.rollingDigits(from: "707", to: "717") == [1])
        #expect(BoardContentRules.rollingDigits(from: "9.12k", to: "9.20k") == [2, 3])
        #expect(BoardContentRules.rollingDigits(from: "999", to: "1.00k") == nil)
        #expect(BoardContentRules.rollingDigits(from: "42", to: "42") == [])
    }

    @Test func intervalSignsFollowTheTimingTower() {
        #expect(BoardContentRules.interval(ahead: 177, live: 148) == "−29")
        #expect(BoardContentRules.interval(ahead: 177, live: 197) == "+20")
        #expect(BoardContentRules.interval(ahead: 50, live: 50) == "−0")
    }

    @Test func nameKeepsItsWidthAndDetailTakesTheRest() {
        #expect(BoardContentRules.nameSplit(available: 200, name: 80) == (80, 114))
        #expect(BoardContentRules.nameSplit(available: 60, name: 80) == (54, 0))
        #expect(BoardContentRules.nameSplit(available: 20, name: 80) == (20, 0))
        #expect(BoardContentRules.nameSplit(available: 26, name: 80) == (22, 0))
    }

    @Test func shareIsClamped() {
        #expect(BoardContentRules.share(50, of: 200) == 0.25)
        #expect(BoardContentRules.share(300, of: 200) == 1)
        #expect(BoardContentRules.share(5, of: 0) == 0)
    }
}

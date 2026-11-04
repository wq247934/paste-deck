import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Minimal style math")
struct MinimalMathTests {
    @Test func ringWidthKeepsItsFloor() {
        #expect(MinimalMath.width(diameter: 64, increaseContrast: false) == 2.5)
        #expect(abs(MinimalMath.width(diameter: 148, increaseContrast: false) - 5.032) < 1e-9)
        #expect(abs(MinimalMath.width(diameter: 148, increaseContrast: true) - 6.29) < 1e-9)
    }

    @Test func secondLapRunsBeyondTheRedline() {
        #expect(MinimalMath.progress(heat: 0.6, overdrive: 0) == 0.6)
        #expect(MinimalMath.progress(heat: 1, overdrive: 1.5) == 2)
        let below = MinimalMath.laps(0.6)
        #expect(below.first == 0.6 && below.second == 0)
        let beyond = MinimalMath.laps(1.45)
        #expect(beyond.first == 1 && abs(beyond.second - 0.45) < 1e-12)
        #expect(abs(MinimalMath.head(1.45) - 0.45) < 1e-12)
        #expect(MinimalMath.head(0.3) == 0.3)
        #expect(MinimalMath.angle(0) == -90)
        #expect(MinimalMath.angle(0.25) == 0)
    }

    @Test func glowBreathesOnlyAtTheRedline() {
        let boost = MinimalMath.glow(redline: false, breath: 1, blink: 0, max: false)
        #expect(boost.sigma == 0.0125 && boost.alpha == 0.35)
        let full = MinimalMath.glow(redline: true, breath: 1, blink: 0, max: false)
        #expect(full.sigma == 0.025 && abs(full.alpha - 0.7) < 1e-12)
        let max = MinimalMath.glow(redline: false, breath: 0, blink: 0, max: true)
        #expect(abs(max.sigma - 0.01625) < 1e-12)
        #expect(MinimalMath.breath(phase: 0, reduceMotion: true) == 1)
        #expect(MinimalMath.breath(phase: -.pi / 2, reduceMotion: false) == 0)
    }

    @Test func blinkAndGoldTintFade() {
        #expect(MinimalMath.blink(age: 0, reduceMotion: false) == 1)
        #expect(abs(MinimalMath.blink(age: 0.2, reduceMotion: false) - 0.5) < 1e-12)
        #expect(MinimalMath.blink(age: 0.4, reduceMotion: false) == 0)
        #expect(MinimalMath.blink(age: 0.1, reduceMotion: true) == 1)
        #expect(abs(MinimalMath.goldTint(age: 0.35, reduceMotion: false) - 1) < 1e-12)
        #expect(MinimalMath.goldTint(age: 0.7, reduceMotion: false) == 0)
        #expect(MinimalMath.goldTint(age: 0.3, reduceMotion: true) == 1)
        #expect(MinimalMath.headDot(redline: true, breath: 1, blink: 0) == 0.6)
        #expect(MinimalMath.headDot(redline: false, breath: 1, blink: 0) == 0)
    }
}

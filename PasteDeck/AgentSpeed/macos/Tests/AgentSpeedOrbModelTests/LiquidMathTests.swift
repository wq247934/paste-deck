import AgentSpeedOrbModel
import Foundation
import Testing

@Suite("Liquid style math (DESIGN 2a.3)")
struct LiquidMathTests {
    @Test func levelFollowsHeatAndOverdrive() {
        #expect(LiquidMath.targetLevel(heat: 0.5, overdrive: 0, active: false) == 0.08)
        #expect(abs(LiquidMath.targetLevel(heat: 0, overdrive: 0, active: true) - 0.08) < 1e-12)
        #expect(abs(LiquidMath.targetLevel(heat: 1, overdrive: 1, active: true) - 0.88) < 1e-12)
        #expect(abs(LiquidMath.targetLevel(heat: 0.5, overdrive: 0, active: true) - 0.45) < 1e-12)
    }

    @Test func meanSurfaceSpansTheInnerGlass() {
        // Empty at the bottom of the glass, full at its top.
        #expect(abs(LiquidMath.meanSurface(centerY: 0, diameter: 100, level: 0) - 45.5) < 1e-9)
        #expect(abs(LiquidMath.meanSurface(centerY: 0, diameter: 100, level: 1) + 45.5) < 1e-9)
        #expect(abs(LiquidMath.meanSurface(centerY: 10, diameter: 100, level: 0.5) - 10) < 1e-9)
    }

    @Test func amplitudePerLevel() {
        let standard = LiquidMath.amplitude(heat: 1, overdrive: 1, active: true, level: 2, reduceMotion: false)
        #expect(abs(standard - 0.042) < 1e-12)
        let soft = LiquidMath.amplitude(heat: 1, overdrive: 1, active: true, level: 1, reduceMotion: false)
        #expect(abs(soft - 0.042 * 0.6) < 1e-12)
        #expect(LiquidMath.amplitude(heat: 0, overdrive: 0, active: false, level: 2, reduceMotion: false) == 0.002)
        #expect(LiquidMath.amplitude(heat: 1, overdrive: 1, active: true, level: 0, reduceMotion: false) == 0)
        #expect(LiquidMath.amplitude(heat: 1, overdrive: 1, active: true, level: 3, reduceMotion: true) == 0)
    }

    @Test func phaseRatesRiseWithHeat() {
        let cool = LiquidMath.phaseRates(heat: 0, overdrive: 0)
        let hot = LiquidMath.phaseRates(heat: 1, overdrive: 1)
        #expect(cool == SIMD4(0.25, 0.4, 0.9, 3.1))
        #expect(abs(hot[0] - 1.05) < 1e-12 && abs(hot[1] - 1.6) < 1e-12 && abs(hot[2] - 2.5) < 1e-12)
    }

    @Test func chopOnlyWhileBoilingAndHalvedWhenSmall() {
        #expect(LiquidMath.chop(overdrive: 1, boiling: false, small: false) == 0)
        #expect(abs(LiquidMath.chop(overdrive: 1, boiling: true, small: false) - 0.006) < 1e-12)
        #expect(abs(LiquidMath.chop(overdrive: 0, boiling: true, small: true) - 0.0015) < 1e-12)
    }

    @Test func waveIsFlatWithoutAmplitude() {
        let phases = SIMD4<Double>(1, 2, 3, 4)
        #expect(LiquidMath.wave(x: 17, diameter: 148, amplitude: 0, chop: 0, phases: phases) == 0)
        let wave = LiquidMath.wave(x: 17, diameter: 148, amplitude: 0.02, chop: 0, phases: phases)
        #expect(abs(wave) <= 0.02 * 148 + 1e-9)
    }

    @Test func rippleTravelsAndDecays() {
        let s = 148.0
        let amplitude = LiquidMath.rippleAmplitude(strength: 1)
        #expect(abs(amplitude - 0.022 * 1.2) < 1e-12)
        // The crest sits where the front is (d = 0.42 S τ) and lowers the surface (y up is negative).
        let crest = LiquidMath.ripple(distance: 0.42 * s * 0.5, tau: 0.5, amplitude: amplitude, diameter: s)
        #expect(crest < 0)
        let far = LiquidMath.ripple(distance: 0.42 * s * 0.5 + 0.3 * s, tau: 0.5, amplitude: amplitude, diameter: s)
        #expect(abs(far) < abs(crest) * 0.01)
        let later = LiquidMath.ripple(distance: 0.42 * s * 1.5, tau: 1.5, amplitude: amplitude, diameter: s)
        #expect(abs(later) < abs(crest))
    }

    @Test func moteRatesAndPools() {
        #expect(LiquidMath.moteRate(heat: 1, overdrive: 0, redline: false, active: false, level: 2, reduceMotion: false) == 0)
        #expect(abs(LiquidMath.moteRate(heat: 1, overdrive: 0, redline: false, active: true, level: 1, reduceMotion: false) - 3.6) < 1e-12)
        #expect(abs(LiquidMath.moteRate(heat: 1, overdrive: 1, redline: true, active: true, level: 2, reduceMotion: false) - 29.5) < 1e-12)
        #expect(abs(LiquidMath.moteRate(heat: 1, overdrive: 1, redline: true, active: true, level: 3, reduceMotion: false) - 29.5 * 1.6) < 1e-9)
        #expect(LiquidMath.moteRate(heat: 1, overdrive: 1, redline: true, active: true, level: 3, reduceMotion: true) == 0)
        #expect(LiquidMath.motePool(level: 1, small: false) == 6)
        #expect(LiquidMath.motePool(level: 2, small: false) == 32)
        #expect(LiquidMath.motePool(level: 2, small: true) == 16)
        #expect(LiquidMath.motePool(level: 3, small: false) == 48)
    }

    @Test func hotnessTurnsBubblesIntoMotes() {
        #expect(LiquidMath.hotness(heat: 0.3) == 0)
        #expect(LiquidMath.hotness(heat: 0.95) == 1)
        #expect(abs(LiquidMath.hotness(heat: 0.625) - 0.5) < 1e-12)
    }

    @Test func steamOnlyWhenBoilingAtStandard() {
        #expect(LiquidMath.steamRate(overdrive: 1, boiling: true, level: 1, reduceMotion: false) == 0)
        #expect(LiquidMath.steamRate(overdrive: 1, boiling: true, level: 2, reduceMotion: false) == 6)
        #expect(abs(LiquidMath.steamRate(overdrive: 0, boiling: true, level: 3, reduceMotion: false) - 3.2) < 1e-12)
    }

    @Test func dropStartsAboveTheSurfaceWithinLimits() {
        let s = 100.0
        #expect(LiquidMath.dropStart(surface: 20, diameter: s) == -30)
        #expect(LiquidMath.dropStart(surface: -35, diameter: s) == -41.4)
        #expect(abs(LiquidMath.dropStart(surface: -20, diameter: s) + 36) < 1e-9)
    }

    @Test func levelSpringSloshesThenSettles() {
        var spring = LiquidMath.levelSpring(0)
        var peak = 0.0
        for _ in 0..<(60 * 6) {
            spring.step(toward: 1, dt: 1.0 / 60)
            peak = max(peak, spring.value)
        }
        // Damping 0.62 overshoots by about 8 %.
        #expect(peak > 1.04 && peak < 1.12)
        #expect(spring.isSettled(at: 1, tolerance: 0.005))
    }

    @Test func easedLevelNeverOvershoots() {
        var spring = LiquidMath.CriticalSpring(settle: 0.9, value: 0)
        var peak = 0.0
        for _ in 0..<120 {
            spring.step(toward: 1, dt: 1.0 / 60)
            peak = max(peak, spring.value)
        }
        #expect(peak <= 1 + 1e-9)
        #expect(spring.value > 0.98)
    }

    @Test func surgeRaisesTheLevelAboutATenth() {
        var surge = LiquidMath.surgeSpring()
        surge.velocity += LiquidMath.surgeKick
        var peak = 0.0
        for _ in 0..<120 {
            surge.step(toward: 0, dt: 1.0 / 60)
            peak = max(peak, surge.value)
        }
        #expect(peak > 0.08 && peak < 0.14)
    }
}

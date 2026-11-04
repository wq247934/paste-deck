import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("LED effects levels")
struct LedEffectsTests {
    private func effects(_ level: Int, reduceMotion: Bool = false, floating: Bool = true, small: Bool = false,
                         thumbnail: Bool = false) -> LedEffects {
        LedEffects(level: level, reduceMotion: reduceMotion, floating: floating, small: small, thumbnail: thumbnail)
    }

    @Test func offIsStaticSilkOnly() {
        let fx = effects(0)
        #expect(fx.level == 0 && fx.lvl == 1)
        #expect(fx.silk && fx.silkRate == 0 && !fx.silkRipples && !fx.silkWaves)
        #expect(!fx.flow && !fx.tipFlare && !fx.corona && !fx.warp)
        #expect(fx.maxComets == 0 && !fx.pulses && !fx.particles && !fx.arcs && !fx.lightning)
        #expect(!fx.jitter && !fx.chromaticSplit && !fx.skew)
    }

    @Test func softHasHalfRateSilkOneCometAndPulses() {
        let fx = effects(1)
        #expect(fx.level == 1 && fx.lvl == 1)
        #expect(fx.silk && fx.silkRate == 0.5 && !fx.silkRipples && fx.silkWaves)
        #expect(fx.maxComets == 1 && fx.pulses)
        #expect(!fx.flow && !fx.tipFlare && !fx.corona && !fx.warp)
        #expect(!fx.particles && !fx.arcs && !fx.lightning && !fx.jitter && !fx.chromaticSplit && !fx.skew)
    }

    @Test func standardHasEverythingAtLevelOne() {
        let fx = effects(2)
        #expect(fx.level == 2 && fx.lvl == 1)
        #expect(fx.silk && fx.silkRate == 1 && fx.silkRipples && fx.silkWaves)
        #expect(fx.flow && fx.tipFlare && fx.corona && fx.warp)
        #expect(fx.maxComets == 2 && fx.pulses && fx.particles && fx.arcs && fx.lightning)
        #expect(fx.jitter && fx.chromaticSplit && fx.skew)
        #expect(fx.countScale == 1 && fx.boltCap == 16)
    }

    @Test func maxIsStandardAtOnePointSix() {
        var fx = effects(3)
        #expect(fx.level == 3 && fx.lvl == 1.6)
        fx.lvl = 1
        let standard = effects(2)
        #expect(fx.silkRate == standard.silkRate && fx.lightning && fx.corona && fx.maxComets == 2)
        #expect(effects(9).level == 3 && effects(-4).level == 0)
    }

    @Test func reduceMotionCapsAtSoftFreezesTheSilkAndStopsLightning() {
        for level in 0...3 {
            let fx = effects(level, reduceMotion: true)
            #expect(fx.level == min(level, 1))
            #expect(fx.lvl == 1 && fx.silkRate == 0 && !fx.silkWaves && !fx.silkRipples)
            #expect(!fx.lightning && !fx.particles && !fx.arcs && !fx.corona && !fx.warp && !fx.flow)
            #expect(fx.maxComets == 0)
            #expect(fx.pulses == (level >= 1))
            #expect(fx.silk)
        }
    }

    @Test func smallOrbsHalveTheCounts() {
        let fx = effects(2, small: true)
        #expect(fx.countScale == 0.5 && fx.boltCap == 8)
        #expect(fx.boltsPerDigit(1) == 1 && fx.boltsPerDigit(2) == 1 && fx.boltsPerDigit(3) == 2)
        let large = effects(2)
        #expect(large.boltsPerDigit(1) == 1 && large.boltsPerDigit(2) == 2 && large.boltsPerDigit(3) == 3)
        #expect(LedParticles.sparkRate(heat: 1, lvl: 1, countScale: fx.countScale) * 2
            == LedParticles.sparkRate(heat: 1, lvl: 1, countScale: large.countScale))
    }

    @Test func thumbnailsDrawStaticSilkWithoutCoronaOrWarp() {
        let fx = effects(3, thumbnail: true)
        #expect(fx.silk && fx.silkRate == 0)
        #expect(!fx.corona && !fx.warp)
        #expect(fx.flow && fx.tipFlare && fx.lvl == 1.6)
    }

    @Test func theDashboardHeroHasNoSilk() {
        let fx = effects(2, floating: false)
        #expect(!fx.silk && !fx.silkRipples && !fx.silkWaves)
        #expect(fx.corona && fx.warp && fx.lightning && fx.particles)
    }
}

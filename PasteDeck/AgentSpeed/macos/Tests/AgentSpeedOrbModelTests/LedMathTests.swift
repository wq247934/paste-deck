import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("LED effects math")
struct LedMathTests {
    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-12) -> Bool { abs(a - b) < tolerance }

    @Test func phaseRatesFollowTheTable() {
        let idle = LedMath.rates(heat: 0, overdrive: 0)
        #expect(idle.silk == 0.12 && idle.light == 0.05 && idle.flow == 0.35 && idle.warp == 0.2 && idle.corona == 0.5)
        #expect(near(idle.comet, 1.0 / 6) && idle.clock == 1)
        let full = LedMath.rates(heat: 1, overdrive: 1)
        #expect(near(full.silk, 3.72) && near(full.light, 1.75) && near(full.flow, 3.85))
        #expect(near(full.warp, 2.5) && near(full.corona, 4.0))
        #expect(near(full.comet, 1.6 / 0.7))
        #expect(near(LedMath.rates(heat: 1, overdrive: 0).comet, 1 / 0.7))
    }

    @Test func aLongStepAdvancesLikeTheMaximumStep() {
        var long = LedMath.Phases()
        var max = LedMath.Phases()
        let used = LedMath.advance(&long, heat: 0.6, overdrive: 0.2, dt: 0.5, silkRate: 1, comet: true)
        LedMath.advance(&max, heat: 0.6, overdrive: 0.2, dt: LedMath.maxStep, silkRate: 1, comet: true)
        #expect(used == LedMath.maxStep)
        #expect(long == max)
        let r = LedMath.rates(heat: 0.6, overdrive: 0.2)
        #expect(near(max.silk, r.silk / 15) && near(max.flow, r.flow / 15) && near(max.comet, r.comet / 15))
        #expect(near(max.clock, 1.0 / 15))
    }

    @Test func negativeOrInvalidStepsDoNothing() {
        var phases = LedMath.Phases()
        #expect(LedMath.advance(&phases, heat: 1, overdrive: 1, dt: -0.2, silkRate: 1, comet: true) == 0)
        #expect(LedMath.advance(&phases, heat: 1, overdrive: 1, dt: .nan, silkRate: 1, comet: true) == 0)
        #expect(LedMath.advance(&phases, heat: 1, overdrive: 1, dt: .infinity, silkRate: 1, comet: true) == 0)
        #expect(phases == LedMath.Phases())
    }

    @Test func silkRateScalesOnlyTheSilkAndItsLight() {
        var frozen = LedMath.Phases()
        var soft = LedMath.Phases()
        var full = LedMath.Phases()
        LedMath.advance(&frozen, heat: 0.5, overdrive: 0, dt: 0.05, silkRate: 0, comet: true)
        LedMath.advance(&soft, heat: 0.5, overdrive: 0, dt: 0.05, silkRate: 0.5, comet: true)
        LedMath.advance(&full, heat: 0.5, overdrive: 0, dt: 0.05, silkRate: 1, comet: true)
        #expect(frozen.silk == 0 && frozen.light == 0)
        #expect(near(soft.silk, full.silk / 2) && near(soft.light, full.light / 2))
        #expect(frozen.flow == full.flow && frozen.warp == full.warp && frozen.corona == full.corona)
        #expect(frozen.comet == full.comet && frozen.clock == full.clock)
    }

    @Test func theCometMovesOnlyWhenAllowedAndWarm() {
        var off = LedMath.Phases()
        var cold = LedMath.Phases()
        var warm = LedMath.Phases()
        LedMath.advance(&off, heat: 0.5, overdrive: 0, dt: 0.05, silkRate: 1, comet: false)
        LedMath.advance(&cold, heat: 0.005, overdrive: 0, dt: 0.05, silkRate: 1, comet: true)
        LedMath.advance(&warm, heat: 0.006, overdrive: 0, dt: 0.05, silkRate: 1, comet: true)
        #expect(off.comet == 0 && cold.comet == 0 && warm.comet > 0)
        #expect(off.flow > 0)
    }

    @Test func wrapsKeepTheSineTermsContinuous() {
        let dt = 1.0 / 60
        var phases = LedMath.Phases()
        phases.clock = 10 * .pi - 0.004
        phases.silk = 20000 * .pi - 0.001
        phases.light = 20000 * .pi - 0.0005
        phases.flow = 0.999
        phases.comet = 0.9999
        phases.warp = 4096 - 0.001
        phases.corona = 4096 - 0.001
        let before = phases
        LedMath.advance(&phases, heat: 1, overdrive: 1, dt: dt, silkRate: 1, comet: true)
        let r = LedMath.rates(heat: 1, overdrive: 1)
        #expect(phases.clock < 1 && phases.silk < 1 && phases.light < 1 && phases.flow < 1 && phases.comet < 1)
        #expect(phases.warp < 1 && phases.corona < 1)

        let clock = before.clock + dt
        for f in [2.6, 8, 16, 3] {
            #expect(near(sin(f * phases.clock), sin(f * clock), 1e-9), "sin(\(f) t)")
        }
        let silk = before.silk + r.silk * dt
        for f in [0.07, 0.3, 0.17, 0.2, 0.15, 0.1, 0.6, 0.35, 0.25, 0.8, 0.4] {
            #expect(near(sin(f * phases.silk), sin(f * silk), 1e-9), "silk sin(\(f) t)")
        }
        let light = before.light + r.light * dt
        for f in [0.35, 0.8] {
            #expect(near(sin(f * phases.light), sin(f * light), 1e-9), "light sin(\(f) t)")
        }
        let flow = before.flow + r.flow * dt
        for i in 0..<36 {
            #expect(near(LedMath.flow(segment: i, phase: phases.flow, heat: 1), LedMath.flow(segment: i, phase: flow, heat: 1), 1e-9))
        }
        #expect(near(phases.comet, before.comet + r.comet * dt - 1))
    }

    @Test func smoothstepHasGLSLSemantics() {
        #expect(LedMath.smoothstep(0, 1, -1) == 0)
        #expect(LedMath.smoothstep(0, 1, 2) == 1)
        #expect(LedMath.smoothstep(0, 1, 0.5) == 0.5)
        #expect(LedMath.smoothstep(1, 0, 0.25) == LedMath.smoothstep(0, 1, 0.75))
        #expect(LedMath.smoothstep(0.74, 0.64, 0.8) == 0 && LedMath.smoothstep(0.74, 0.64, 0.6) == 1)
        #expect(LedMath.smoothstep(0.3, 0.3, 0.29) == 0 && LedMath.smoothstep(0.3, 0.3, 0.3) == 1)
        #expect(LedMath.easeOut(0) == 0 && LedMath.easeOut(1) == 1 && LedMath.easeOut(2) == 1 && LedMath.easeOut(-1) == 0)
        #expect(near(LedMath.easeOut(0.5), 0.875))
    }

    @Test func silkFlowFlareAndComets() {
        #expect(LedMath.activity(heat: 0) == 0 && LedMath.activity(heat: 0.08) == 1 && LedMath.activity(heat: 0.04) == 0.5)
        #expect(near(LedMath.silkBrightness(heat: 0, overdrive: 0, lvl: 1), 0.3))
        #expect(near(LedMath.silkBrightness(heat: 1, overdrive: 1, lvl: 1.6), 1.5 * 1.21))
        #expect(LedMath.ripple(overdrive: 0.2) == 0.5 && LedMath.ripple(overdrive: 0.9) == 1)

        // The pulse sits where fract(2.2 i / 36 − φ) = 0.
        #expect(near(LedMath.flow(segment: 0, phase: 0, heat: 1), 1.4))
        #expect(LedMath.flow(segment: 9, phase: 0, heat: 1) < 0.01)
        #expect(near(LedMath.flow(segment: 18, phase: 2.2 * 18 / 36, heat: 0.5), 0.95))
        #expect(LedMath.flow(segment: 0, phase: 0, heat: 0) == 0)

        #expect(LedMath.flareAmount(heat: 0.5, overdrive: 1, lvl: 1) == 0)
        #expect(near(LedMath.flareAmount(heat: 0.85, overdrive: 1, lvl: 1.6), 1.45 * 1.6))
        let lengths = LedMath.flareLengths(overdrive: 1)
        #expect(near(lengths.tangential, 0.21) && near(lengths.radial, 0.125))

        #expect(LedMath.cometTail(heat: 0) == 40 && LedMath.cometTail(heat: 1) == 100)
        #expect(LedMath.cometCount(heat: 0.005, maxComets: 2) == 0)
        #expect(LedMath.cometCount(heat: 0.55, maxComets: 2) == 1)
        #expect(LedMath.cometCount(heat: 0.56, maxComets: 2) == 2)
        #expect(LedMath.cometCount(heat: 0.9, maxComets: 1) == 1)
        #expect(LedMath.cometCount(heat: 0.9, maxComets: 0) == 0)
    }

    @Test func coronaStaysInsideTheWindow() {
        #expect(LedMath.coronaAmount(heat: 0.45, overdrive: 1, lvl: 1) == 0)
        #expect(near(LedMath.coronaAmount(heat: 0.85, overdrive: 1, lvl: 1.6), 1.6))
        #expect(LedMath.coronaFade(radius: 0.47) == 0)
        #expect(LedMath.coronaFade(radius: 0.6) == 1)
        for r in stride(from: 0.74, through: 1.0, by: 0.01) {
            #expect(LedMath.coronaFade(radius: r) == 0, "r \(r)")
        }
        #expect(LedMath.coronaFade(radius: 0.7395) > 0)
        #expect(near(LedMath.coronaReach(heat: 1, overdrive: 1, body: 1), 0.02 + 0.18 * 1.7))
        #expect(LedMath.coronaReach(heat: 1, overdrive: 1, body: 0) == 0.02)
        #expect(LedMath.coronaReach(heat: 1, overdrive: 1, body: 4) == LedMath.coronaReach(heat: 1, overdrive: 1, body: 1))
    }

    @Test func warpHeadsStayBetweenTheRimAndTheWindowEdge() {
        #expect(near(LedMath.warpSeed(bin: 0), (sin(3 * 127.1) * 43758.5453) - (sin(3 * 127.1) * 43758.5453).rounded(.down)))
        var active = 0
        for bin in 0..<LedMath.warpBins {
            let seed = LedMath.warpSeed(bin: bin)
            #expect(seed >= 0 && seed < 1)
            if LedMath.warpActive(seed: seed, heat: 1) { active += 1 }
            for k in 0..<400 {
                let phase = Double(k) * 0.37 - 20
                let head = LedMath.warpHead(seed: seed, phase: phase)
                #expect(head >= 0.51 && head <= 0.74, "bin \(bin) phase \(phase) head \(head)")
            }
        }
        #expect(active > 30 && active < 96)
        #expect(LedMath.warpHead(seed: 0, phase: 0) == 0.74)
        #expect(LedMath.warpActive(seed: 0.17, heat: 0) && !LedMath.warpActive(seed: 0.18, heat: 0))
        #expect(LedMath.warpAmount(heat: 0.32, lvl: 1) == 0 && LedMath.warpAmount(heat: 0.62, lvl: 1.6) == 1.6)
        #expect(near(LedMath.warpLength(heat: 1, overdrive: 1, seed: 0.45), 0.17))
        #expect(near(LedMath.warpWidth(heat: 1), 0.0028))
        #expect(LedMath.warpFade(travel: 0) == 0 && LedMath.warpFade(travel: 1) == 0)
        #expect(LedMath.warpFade(travel: 0.3) == 1 && LedMath.warpFade(travel: 0.82) == 1)
    }

    @Test func pulseAndPeakReachTheWindowEdgeAtMost() {
        #expect(LedMath.shockRadius(age: 0, reach: 0.75) == 0.5)
        #expect(near(LedMath.shockRadius(age: 1, reach: 0.75), 0.74))
        #expect(near(LedMath.shockRadius(age: 1, reach: 0.6), 0.59))
        #expect(near(LedMath.wakeRadius(age: 1, reach: 0.75), 0.66))
        #expect(near(LedMath.wakeRadius(age: 1 / 1.3, reach: 0.75), 0.66))
        #expect(near(LedMath.wakeRadius(age: 1, reach: 0.6), 0.59))

        #expect(LedMath.peakRingRadius(age: 0, reach: 0.75) == 0.5)
        #expect(near(LedMath.peakRingRadius(age: 1.4, reach: 0.75), 0.74))
        #expect(near(LedMath.peakRingRadius(age: 1.4, reach: 0.9), 0.74))
        #expect(LedMath.peakRayReach(age: 0, reach: 0.75) == 0.55)
        #expect(near(LedMath.peakRayReach(age: 1.3 / 1.4, reach: 0.75), 0.74))
        #expect(near(LedMath.peakRayReach(age: 1.3, reach: 0.75), 0.74))
        #expect(LedMath.peakFlash(age: 0) == 0.75 && near(LedMath.peakFlash(age: 1), 0.75 * exp(-4.5)))
    }

    @Test func particlesFadeOutByTheWindowEdge() {
        #expect(LedMath.particleFade(radius: 0.3) == 1)
        #expect(LedMath.particleFade(radius: 0.66) == 1)
        #expect(LedMath.particleFade(radius: 0.7) > 0 && LedMath.particleFade(radius: 0.7) < 1)
        #expect(LedMath.particleFade(radius: 0.74) == 0)
        #expect(LedMath.particleFade(radius: 0.9) == 0)
    }

    @Test func readoutNumbers() {
        #expect(LedMath.leanDegrees(heat: 1) == 7.5)
        #expect(near(LedMath.jitter(overdrive: 1), 2.1))
        #expect(near(LedMath.chromaOffset(overdrive: 1, diameter: 150), 1.1))
        #expect(near(LedMath.glowScale(overdrive: 0.5), 1.4))
        #expect(LedMath.wideGlow == 2.4)
    }
}

import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Reactor style math")
struct ReactorMathTests {
    @Test func rotorAClosesIntoARingAtFullOverdrive() {
        #expect(ReactorMath.arcLengthA(heat: 0, overdrive: 0) == 20)
        #expect(ReactorMath.arcLengthA(heat: 1, overdrive: 0) == 110)
        #expect(ReactorMath.arcLengthA(heat: 1, overdrive: 1) == 120)
        #expect(ReactorMath.arcLengthA(heat: 1, overdrive: 1) * Double(ReactorMath.rotorAArcs) == 360)
    }

    @Test func rotorCArcsStopShortOfAHalfCircle() {
        #expect(ReactorMath.arcLengthC(heat: 0, overdrive: 0) == 14)
        #expect(ReactorMath.arcLengthC(heat: 1, overdrive: 0) == 144)
        #expect(ReactorMath.arcLengthC(heat: 1, overdrive: 1) == 164)
        #expect(ReactorMath.arcLengthC(heat: 1.2, overdrive: 1) == 175)
    }

    @Test func rotorCSpinsAboutOnePointTwoRevolutionsPerSecondAtTheRedline() {
        let atR = ReactorMath.speeds(heat: 1, overdrive: 0, kick: 0)
        #expect(abs(atR.c - 1.15) < 0.06, "c at R \(atR.c)")
        let full = ReactorMath.speeds(heat: 1, overdrive: 1, kick: 0)
        #expect(abs(full.c - 1.85) < 0.06, "c at full overdrive \(full.c)")
        #expect(full.a > 0 && full.c > 0 && full.b < 0)
    }

    @Test func pulseKickSpinsTheRotorsUpAndDecays() {
        let calm = ReactorMath.speeds(heat: 0.5, overdrive: 0, kick: 0)
        let kicked = ReactorMath.speeds(heat: 0.5, overdrive: 0, kick: ReactorMath.kickPerStrength)
        #expect(abs(kicked.a - calm.a - 0.25) < 1e-12)
        #expect(abs(kicked.b - calm.b + 0.15) < 1e-12)
        #expect(abs(kicked.c - calm.c - 0.30) < 1e-12)
        var kick = 0.25
        for _ in 0..<30 { kick = ReactorMath.decayedKick(kick, dt: 1.0 / 60) }
        #expect(abs(kick - 0.25 * exp(-1)) < 0.001)
        for _ in 0..<600 { kick = ReactorMath.decayedKick(kick, dt: 1.0 / 60) }
        #expect(kick == 0)
    }

    @Test func anglesAccumulateAndWrap() {
        #expect(ReactorMath.advance(350, speed: 0.5, dt: 0.1) == 8)
        #expect(ReactorMath.advance(10, speed: -0.5, dt: 0.1) == 352)
        #expect(ReactorMath.wrap(-720) == 0)
    }

    @Test func coilEnergyRunsFromTheFloorToFull() {
        #expect(abs(ReactorMath.coilEnergy(theta: 0, psi: 0, heat: 1) - 1) < 1e-12)
        #expect(abs(ReactorMath.coilEnergy(theta: .pi / 3, psi: 0, heat: 1) - 0.18) < 1e-12)
        #expect(abs(ReactorMath.coilEnergy(theta: 0, psi: 0, heat: 0) - (0.18 + 0.82 * 0.35)) < 1e-12)
        // Three bands around the rotor.
        #expect(abs(ReactorMath.coilEnergy(theta: 2 * .pi / 3, psi: 0, heat: 0.5) - ReactorMath.coilEnergy(theta: 0, psi: 0, heat: 0.5)) < 1e-12)
        #expect(ReactorMath.bandRate(heat: 1, overdrive: 1) == 2.15)
    }

    @Test func signOfLifeBandIsAboutASeventhWide() {
        #expect(abs(ReactorMath.signOfLifeBand(position: 0.3, progress: 0.3) - 0.6) < 1e-12)
        #expect(abs(ReactorMath.signOfLifeBand(position: 0.95, progress: 0.05) - ReactorMath.signOfLifeBand(position: 0.15, progress: 0.05)) < 1e-12)
        #expect(ReactorMath.signOfLifeBand(position: 0.3 + 1.0 / 7, progress: 0.3) < 0.6 * exp(-0.99))
        #expect(ReactorMath.signOfLifeBand(position: 0.8, progress: 0.3) < 0.001)
    }

    @Test func lightningBudgetFollowsTheEffectsLevel() {
        #expect(ReactorMath.boltRate(overdrive: 0, max: false) == 1.5)
        #expect(ReactorMath.boltRate(overdrive: 1, max: false) == 7.5)
        #expect(abs(ReactorMath.boltRate(overdrive: 1, max: true) - 12) < 1e-12)
        #expect(ReactorMath.maxBolts(max: false) == 3 && ReactorMath.maxBolts(max: true) == 4)
        #expect(ReactorMath.sparkPool(max: false) == 40 && ReactorMath.sparkPool(max: true) == 64)
        #expect(!ReactorMath.canLeapOutward(overdrive: 0.3) && ReactorMath.canLeapOutward(overdrive: 0.31))
        #expect(ReactorMath.boltAlpha(progress: 0.1) == 1)
        #expect(abs(ReactorMath.boltAlpha(progress: 0.6) - 0.5) < 1e-12)
        #expect(ReactorMath.boltAlpha(progress: 1) == 0)
    }

    @Test func coronaFlashesStayAtOrBelowThreePerSecond() {
        var last = -Double.infinity
        var flashes: [Double] = []
        var time = 0.0
        while time < 10 {
            if ReactorMath.mayFlash(at: time, lastFlash: last) {
                last = time
                flashes.append(time)
            }
            time += 0.05
        }
        for (index, flash) in flashes.enumerated() {
            let inWindow = flashes[index...].prefix { $0 < flash + 1 - 1e-9 }.count
            #expect(inWindow <= 3, "\(inWindow) flashes within 1 s from \(flash)")
        }
        #expect(flashes.count >= 29)
    }

    @Test func lockSwingsForwardToAHeadAtTwelveOClock() {
        let symmetryA = ReactorMath.lockSymmetry(rotor: 0, coils: 24)
        let symmetryB = ReactorMath.lockSymmetry(rotor: 1, coils: 24)
        let symmetryC = ReactorMath.lockSymmetry(rotor: 2, coils: 24)
        #expect(symmetryA == 120 && symmetryB == 15 && symmetryC == 180)
        #expect(ReactorMath.lockSymmetry(rotor: 1, coils: 12) == 30)
        for angle in stride(from: -400.0, through: 400, by: 7.3) {
            let a = ReactorMath.lockTarget(angle: angle, symmetry: symmetryA, clockwise: true)
            #expect(a >= angle - 1e-9 && a - angle < symmetryA)
            #expect(abs(ReactorMath.wrap(a - -90).truncatingRemainder(dividingBy: symmetryA)) < 1e-9)
            let b = ReactorMath.lockTarget(angle: angle, symmetry: symmetryB, clockwise: false)
            #expect(b <= angle + 1e-9 && angle - b < symmetryB)
            let c = ReactorMath.lockTarget(angle: angle, symmetry: symmetryC, clockwise: true)
            #expect(c >= angle - 1e-9 && c - angle < symmetryC)
        }
    }

    @Test func lockOvershootsHoldsAndFlashesGold() {
        #expect(abs(ReactorMath.lockProgress(age: 0)) < 1e-12)
        #expect(abs(ReactorMath.lockProgress(age: 0.42) - 1) < 1e-12)
        #expect(ReactorMath.lockProgress(age: 0.5) == 1)
        let peak = stride(from: 0.0, through: 0.42, by: 0.001).map { ReactorMath.lockProgress(age: $0) }.max() ?? 0
        #expect(peak > 1.05 && peak < 1.2, "overshoot \(peak)")
        #expect(ReactorMath.lockGold(age: 0.42) == 1)
        #expect(ReactorMath.lockGold(age: 0.2) == 0)
        #expect(ReactorMath.lockGold(age: 0.57) == 0)
        #expect(ReactorMath.reducedLockGold(age: 0.15) == 1)
        #expect(ReactorMath.reducedLockGold(age: 0.3) == 0)
    }

    @Test func flareRingTravelsFromTheCoreToTheDiscEdge() {
        let start = ReactorMath.flareRing(age: 0)
        #expect(start?.radius == 0.30)
        #expect(start?.alpha == 0.55)
        let end = ReactorMath.flareRing(age: 0.3199)
        #expect((end?.radius ?? 0) > 0.499)
        #expect(ReactorMath.flareRing(age: 0.32) == nil)
        #expect(ReactorMath.coronaFlare(age: 0) == 0.25)
        #expect(ReactorMath.coronaFlare(age: 0.35) == 0)
    }

    @Test func coronaAndLevelOfDetail() {
        #expect(abs(ReactorMath.coronaAlpha(heat: 1, dark: true, max: false) - 0.52) < 1e-12)
        #expect(abs(ReactorMath.coronaAlpha(heat: 1, dark: false, max: true) - 0.312) < 1e-12)
        #expect(ReactorMath.breathingRate(heat: 1) == 2)
        #expect(ReactorMath.notchCount(small: true) == 4 && ReactorMath.notchCount(small: false) == 24)
        #expect(ReactorMath.coilCount(small: true) == 12 && ReactorMath.coilLength(small: true) == 13)
        #expect(ReactorMath.strokeGlow(width: 100, sigma: 1) > 0.999)
        #expect(ReactorMath.strokeGlow(width: 1, sigma: 10) < 0.05)
    }
}

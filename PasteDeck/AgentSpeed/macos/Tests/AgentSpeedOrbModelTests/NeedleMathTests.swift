import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Needle style math")
struct NeedleMathTests {
    @Test func redZoneStartsAtTheRedlineTierThreshold() {
        #expect(abs(NeedleMath.redZoneStart - 0.8415) < 0.0001)
        #expect(NeedleMath.angle(0) == 135)
        #expect(NeedleMath.angle(1) == 405)
        #expect(NeedleMath.lampThresholds.last == NeedleMath.redZoneStart)
    }

    @Test func targetPressesIntoThePegBeyondTheRedline() {
        #expect(NeedleMath.target(rawHeat: 0.7, rawOverdrive: 0, idle: true) == 0)
        #expect(NeedleMath.target(rawHeat: 0.7, rawOverdrive: 0, idle: false) == 0.7)
        #expect(abs(NeedleMath.target(rawHeat: 1, rawOverdrive: 0.5, idle: false) - 1.045) < 1e-12)
        #expect(NeedleMath.direct(heat: 1, overdrive: 1) == NeedleMath.pegStop)
    }

    @Test func springOvershootsAboutTwelvePercentOnAStep() {
        var spring = NeedleMath.Spring()
        var peak = 0.0
        for _ in 0..<240 {
            spring.step(toward: 0.5, dt: 1.0 / 60)
            peak = max(peak, spring.position)
        }
        let overshoot = (peak - 0.5) / 0.5
        #expect(overshoot > 0.10 && overshoot < 0.14, "overshoot \(overshoot)")
        #expect(spring.isSettled(at: 0.5))
    }

    @Test func largeStepsMatchSmallStepsThanksToSubstepping() {
        var coarse = NeedleMath.Spring()
        var fine = NeedleMath.Spring()
        for _ in 0..<15 { coarse.step(toward: 0.6, dt: 1.0 / 15) }
        for _ in 0..<480 { fine.step(toward: 0.6, dt: 1.0 / 480) }
        #expect(abs(coarse.position - fine.position) < 1e-9)
    }

    @Test func stopsHoldTheNeedleAndBounceIt() {
        var spring = NeedleMath.Spring()
        var reversed = false
        var highest = 0.0
        for _ in 0..<180 {
            spring.step(toward: 1.07, dt: 1.0 / 60)
            highest = max(highest, spring.position)
            if spring.position >= NeedleMath.pegStop - 0.02, spring.velocity < 0 { reversed = true }
        }
        #expect(highest <= NeedleMath.pegStop)
        #expect(reversed)
        var down = NeedleMath.Spring(position: 0.5)
        var lowest = 1.0
        for _ in 0..<180 {
            down.step(toward: -0.5, dt: 1.0 / 60)
            lowest = min(lowest, down.position)
        }
        #expect(lowest >= NeedleMath.zeroStop)
    }

    @Test func trembleStartsAboveHalfHeat() {
        #expect(NeedleMath.trembleAmplitude(heat: 0.5, overdrive: 0, max: false) == 0)
        #expect(NeedleMath.trembleAmplitude(heat: 1, overdrive: 0, max: false) == 0.3)
        #expect(abs(NeedleMath.trembleAmplitude(heat: 1, overdrive: 1, max: true) - 1.3 * 1.4) < 1e-12)
        #expect(NeedleMath.trembleOffset(amplitude: 0, phases: (1, 2, 3)) == 0)
        let pinned = NeedleMath.displayed(spring: NeedleMath.pegStop, trembleDegrees: 1.5)
        #expect(pinned == NeedleMath.pegStop)
    }

    @Test func wakeTrailsFastNeedlesOnly() {
        #expect(NeedleMath.wakeLength(angularSpeed: 10) == 0)
        #expect(abs(NeedleMath.wakeLength(angularSpeed: -100) - 12.5) < 1e-12)
        #expect(NeedleMath.wakeLength(angularSpeed: 2000) == 55)
    }

    @Test func lampsLightInOrderAndFlashWithinTheirRange() {
        #expect(NeedleMath.lampThresholds == NeedleMath.lampThresholds.sorted())
        #expect(NeedleMath.lampLit(0, needle: 0.7))
        #expect(!NeedleMath.lampLit(4, needle: 0.84))
        var low = 1.0
        var high = 0.0
        for step in 0..<360 {
            let value = NeedleMath.lampFlash(phase: Double(step) * .pi / 180)
            low = min(low, value)
            high = max(high, value)
        }
        #expect(abs(low - 0.28) < 1e-9 && abs(high - 1) < 1e-9)
    }

    @Test func pegSparksNeedThePinnedNeedle() {
        #expect(NeedleMath.isPinned(needle: 1.011, target: 1.03))
        #expect(!NeedleMath.isPinned(needle: 1.011, target: 1.0))
        #expect(!NeedleMath.isPinned(needle: 0.99, target: 1.03))
        #expect(NeedleMath.pegSparkRate(overdrive: 1, max: false) == 95)
        #expect(abs(NeedleMath.pegSparkRate(overdrive: 0, max: true) - 40) < 1e-12)
        #expect(NeedleMath.pegSparkPool(max: false) == 48 && NeedleMath.pegSparkPool(max: true) == 80)
    }

    @Test func newPeakSweepSwingsToThePegAndBack() {
        #expect(NeedleMath.peakSweep(0.4, age: 0) == 0.4)
        #expect(abs(NeedleMath.peakSweep(0.4, age: 0.45) - NeedleMath.pegStop) < 1e-12)
        #expect(abs(NeedleMath.peakSweep(0.4, age: 0.999) - 0.4) < 1e-4)
        #expect(NeedleMath.peakSweep(0.4, age: 1.2) == 0.4)
    }
}

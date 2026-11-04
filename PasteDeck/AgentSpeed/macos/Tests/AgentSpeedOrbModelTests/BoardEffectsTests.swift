import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Board effects")
struct BoardEffectsTests {
    static func effects(_ style: BoardStyle = .glass, side: Double = 340) -> BoardEffects {
        BoardEffects(style: style, side: side, seed: 7) { h in BoardFXColor(Float(h), 0.5, 0.5, 1) }
    }

    static func run(_ fx: inout BoardEffects, seconds: Double, step: Double = 1.0 / 60) {
        var t = 0.0
        while t < seconds - 1e-9 {
            fx.advance(step)
            t += step
        }
    }

    static func visibleComets(_ fx: BoardEffects) -> Int { fx.comets.filter { $0.targetOpacity > 0 }.count }

    @Test func tiersFollowTheHeatThresholds() {
        #expect(BoardHeatTier(heat: 0.04) == .idle)
        #expect(BoardHeatTier(heat: 0.05) == .cruise)
        #expect(BoardHeatTier(heat: 0.32) == .boost)
        #expect(BoardHeatTier(heat: 0.56) == .overdrive)
        #expect(BoardHeatTier(heat: 0.78) == .redline)
    }

    @Test func cometCountsPerStyleAndTier() {
        let heats = [0.0, 0.2, 0.4, 0.6, 0.9]
        let expected: [BoardStyle: [Int]] = [.glass: [1, 1, 2, 3, 4], .timing: [1, 1, 2, 2, 3], .neon: [1, 2, 3, 4, 4]]
        for (style, counts) in expected {
            var fx = Self.effects(style)
            for (heat, count) in zip(heats, counts) {
                fx.setHeat(heat, overdrive: 0, active: true)
                #expect(Self.visibleComets(fx) == count, "\(style) at \(heat)")
            }
        }
    }

    @Test func idleCometIsDimAndVisibleCometsAreEvenlySpaced() {
        var fx = Self.effects(.neon)
        fx.setHeat(0, overdrive: 0, active: false)
        #expect(fx.comets[0].targetOpacity == 0.35)
        fx.setHeat(0.6, overdrive: 0, active: true)
        Self.run(&fx, seconds: 3)
        let offsets = fx.comets.map(\.offset)
        #expect(offsets.map { ($0 * 100).rounded() } == [0, 25, 50, 75])
        fx.setHeat(0.4, overdrive: 0, active: true)
        Self.run(&fx, seconds: 3)
        #expect(Self.visibleComets(fx) == 3)
        #expect(fx.comets.prefix(3).map { ($0.offset * 1000).rounded() } == [0, 333, 667])
    }

    @Test func intensityAndReduceMotionLimitComets() {
        var fx = Self.effects(.glass)
        fx.setHeat(0.9, overdrive: 0, active: true)
        fx.setIntensity(.soft)
        #expect(Self.visibleComets(fx) == 1)
        fx.setIntensity(.off)
        #expect(Self.visibleComets(fx) == 0)
        fx.setIntensity(.standard)
        fx.setReduceMotion(true)
        #expect(Self.visibleComets(fx) == 0)
    }

    @Test func lapTimeRunsFromSevenSecondsToOnePointSixAndGoldIsFaster() {
        var fx = Self.effects()
        fx.setIntensity(.off)
        fx.setHeat(0, overdrive: 0, active: true)
        #expect(abs(fx.lapSeconds - 7) < 1e-9)
        fx.setHeat(1, overdrive: 0, active: true)
        #expect(abs(fx.lapSeconds - 1.6) < 1e-9)
        fx.setIntensity(.standard)
        fx.celebrate(x: 20, y: 20)
        #expect(abs(fx.lapSeconds - 1.6 / 1.8) < 1e-9)
        Self.run(&fx, seconds: 2.3)
        #expect(fx.gold == 0)
    }

    @Test func frameClassesFollowTheBoardPolicy() {
        var fx = Self.effects()
        #expect(fx.frameClass == .none)
        fx.setHeat(0.2, overdrive: 0, active: true)
        Self.run(&fx, seconds: 2)
        #expect(fx.frameClass == .fps30)
        fx.setHeat(0.6, overdrive: 0, active: true)
        Self.run(&fx, seconds: 2)
        #expect(fx.frameClass == .fps60)
        fx.setHeat(0, overdrive: 0, active: false)
        Self.run(&fx, seconds: 3)
        #expect(fx.particles.isEmpty)
        #expect(fx.frameClass == .none)
        fx.shockwave(x: 10, y: 10, color: .fxGold)
        #expect(fx.frameClass == .fps60)
        Self.run(&fx, seconds: 1)
        #expect(fx.frameClass == .none)
    }

    @Test func redlineSparksLeaveEveryCometHeadEvery120ms() {
        var fx = Self.effects(.glass)
        fx.setHeat(0.9, overdrive: 0, active: true)
        Self.run(&fx, seconds: 1.5)
        let before = fx.particles.count
        #expect(before > 0)
        // Four comets × 3 sparks per 120 ms, each living at most 0.72 s.
        #expect(before <= 4 * 3 * 7)
        fx.setIntensity(.soft)
        #expect(fx.particles.isEmpty)
        Self.run(&fx, seconds: 0.5)
        #expect(fx.particles.isEmpty)
    }

    @Test func intensityScalesParticles() {
        var fx = Self.effects()
        fx.burst(x: 0, y: 0, BoardBurst(count: 20, colors: BoardFXPalette(.fxWhite)))
        #expect(fx.particles.count == 20)
        fx.setIntensity(.max)
        fx.burst(x: 0, y: 0, BoardBurst(count: 20, colors: BoardFXPalette(.fxWhite)))
        #expect(fx.particles.count == 50)
        fx.setIntensity(.soft)
        fx.burst(x: 0, y: 0, BoardBurst(count: 20, colors: BoardFXPalette(.fxWhite)))
        #expect(fx.particles.isEmpty)
        fx.shockwave(x: 0, y: 0, color: .fxGold)
        #expect(fx.waves.count == 1)
    }

    @Test func poolsNeverGrowPastTheirCapacity() {
        var fx = Self.effects()
        fx.setIntensity(.max)
        let capacity = fx.particles.capacity
        for _ in 0..<20 { fx.celebrate(x: 100, y: 100) }
        for _ in 0..<20 { fx.lightning(from: SIMD2(0, 0), to: SIMD2(100, 100), color: .fxGold, branches: 3) }
        #expect(fx.particles.count == BoardEffects.particleCapacity)
        #expect(fx.waves.count == BoardEffects.waveCapacity)
        #expect(fx.liveBolts == BoardEffects.boltCapacity)
        #expect(fx.particles.capacity == capacity)
        Self.run(&fx, seconds: 0.5)
        #expect(fx.particles.capacity == capacity)
    }

    @Test func lightningPathsStartAndEndOnTheirPoints() {
        var fx = Self.effects(.neon)
        fx.lightning(from: SIMD2(10, 20), to: SIMD2(200, 40), color: .fxGold, branches: 3, life: 0.45)
        let slot = fx.bolts.firstIndex { $0.alive }!
        #expect(fx.bolts[slot].pathCount == 4)
        let main = Array(fx.boltPath(slot, 0))
        #expect(main.count >= 8 && main.count <= BoardBolt.maxPoints)
        #expect(main.first == SIMD2(10, 20))
        #expect(main.last == SIMD2(200, 40))
        for k in 1..<4 { #expect(fx.boltPath(slot, k).count >= 8) }
        Self.run(&fx, seconds: 0.5)
        #expect(fx.liveBolts == 0)
    }

    @Test func newLeaderCelebratesOnlyWhenCelebrationsAreOn() {
        var fx = Self.effects(.neon)
        let row = CGRect(x: 14, y: 100, width: 312, height: 32)
        fx.newLeader(row: row, rank: CGPoint(x: 30, y: 116), color: .fxGreen)
        #expect(fx.gold > 0)
        #expect(fx.flash == 1)
        #expect(fx.waves.count == 2)
        #expect(fx.liveBolts == 1)
        var plain = Self.effects(.neon)
        plain.celebrations = false
        plain.newLeader(row: row, rank: CGPoint(x: 30, y: 116), color: .fxGreen, passedRankY: 150)
        #expect(plain.gold == 0)
        #expect(plain.waves.isEmpty)
        #expect(plain.liveBolts == 1)
        #expect(plain.particles.count == 26 + 16)
    }

    @Test func reduceMotionDropsEverythingThatTravels() {
        var fx = Self.effects(.neon)
        fx.setReduceMotion(true)
        fx.setHeat(0.9, overdrive: 0.5, active: true)
        fx.overtake(row: CGRect(x: 0, y: 0, width: 100, height: 30), rank: CGPoint(x: 10, y: 15), color: .fxGreen,
                    passedRankY: 50)
        fx.shockwave(x: 0, y: 0, color: .fxGold)
        Self.run(&fx, seconds: 0.5)
        #expect(fx.particles.isEmpty && fx.waves.isEmpty && fx.liveBolts == 0 && fx.starCount == 0)
        #expect(fx.frameClass == .none)
        #expect(fx.shownHeat == 0.9)
    }

    @Test func warpStreaksFollowHeatOnNeonOnly() {
        var neon = Self.effects(.neon)
        neon.setHeat(0.5, overdrive: 0, active: true)
        Self.run(&neon, seconds: 2)
        #expect(neon.starCount == 55)
        neon.setIntensity(.max)
        Self.run(&neon, seconds: 0.1)
        #expect(neon.starCount == 83)
        neon.setIntensity(.soft)
        Self.run(&neon, seconds: 0.1)
        #expect(neon.starCount == 0)
        var glass = Self.effects(.glass)
        glass.setHeat(0.5, overdrive: 0, active: true)
        Self.run(&glass, seconds: 2)
        #expect(glass.starCount == 0)
    }

    @Test func warpAnimatedByThePlatformNeedsNoFrames() {
        var neon = Self.effects(.neon)
        neon.simulatesWarp = false
        neon.setHeat(0.5, overdrive: 0, active: true)
        #expect(neon.warpRequested)
        Self.run(&neon, seconds: 2)
        #expect(neon.starCount == 0 && !neon.warpOn)
        neon.setHeat(0.15, overdrive: 0, active: true)
        #expect(!neon.warpRequested)
        neon.setHeat(0.5, overdrive: 0, active: true)
        neon.setReduceMotion(true)
        #expect(!neon.warpRequested)
        neon.setReduceMotion(false)
        neon.setIntensity(.off)
        #expect(!neon.warpRequested)
        var glass = Self.effects(.glass)
        glass.setHeat(0.9, overdrive: 0, active: true)
        #expect(!glass.warpRequested)
    }

    @Test func cometsStopWhenNothingGenerates() {
        var fx = Self.effects()
        fx.setHeat(0.3, overdrive: 0, active: true)
        Self.run(&fx, seconds: 1)
        fx.setHeat(0, overdrive: 0, active: false)
        Self.run(&fx, seconds: 3)
        let phase = fx.phase
        Self.run(&fx, seconds: 1)
        #expect(fx.phase == phase)
        #expect(fx.settled)
    }

    @Test func outlinePointsLieOnTheInsetRoundedSquare() {
        let fx = Self.effects(.glass, side: 340)
        let top = fx.outlinePoint(0.01)
        #expect(abs(top.y - BoardEffects.outlineInset) < 1e-9)
        #expect(top.outward < 0)
        let length = fx.outline.length
        let right = fx.outlinePoint((fx.outline.length / 4 + 1) / length)
        #expect(abs(right.x - (340 - BoardEffects.outlineInset)) < 1e-6)
    }
}

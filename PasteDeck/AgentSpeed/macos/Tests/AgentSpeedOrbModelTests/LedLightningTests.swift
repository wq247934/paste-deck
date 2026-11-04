import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("LED digit lightning")
struct LedLightningTests {
    private let s = 148.0
    private let standard = LedEffects(level: 2, reduceMotion: false, floating: true, small: false, thumbnail: false)
    private let maxed = LedEffects(level: 3, reduceMotion: false, floating: true, small: false, thumbnail: false)
    private let prototypeDraws = [0.13, 0.77, 0.42, 0.91, 0.05, 0.66, 0.38, 0.29, 0.84, 0.57, 0.21]

    private func cells(_ text: String) -> ContiguousArray<LedDigitCell> {
        ContiguousArray((0..<text.count).map { LedDigitCell(x: -30 + 20 * Double($0), y: 4, width: 20, height: 34) })
    }

    private func fire(_ lightning: inout LedLightning, _ previous: String, _ current: String, time: Double = 1,
                      heat: Double = 0.3, overdrive: Double = 0, redline: Bool = false, value: Double = 900,
                      effects: LedEffects? = nil, force: Bool = false) {
        lightning.trigger(previous: previous, current: current, cells: cells(current), time: time, heat: heat,
                          overdrive: overdrive, redline: redline, value: value, effects: effects ?? standard,
                          diameter: s, force: force)
    }

    private func always() -> LedLightning { LedLightning(random: LedRandom(sequence: [0])) }

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) < tolerance }

    @Test func chancePowerAndCounts() {
        #expect(LedLightning.chance(significance: 0, heat: 0) == 0.3)
        #expect(near(LedLightning.chance(significance: 1, heat: 0.5), 0.8))
        #expect(LedLightning.chance(significance: 3, heat: 0) == 1)
        #expect(near(LedLightning.chance(significance: 1, heat: 1), 1))
        #expect(near(LedLightning.power(significance: 0, heat: 0, overdrive: 0, lvl: 1), 0.33))
        #expect(near(LedLightning.power(significance: 2, heat: 0.5, overdrive: 0.25, lvl: 1.6), 0.99 * 1.05 * 1.6))
        #expect(LedLightning.boltCount(heat: 0.55, redline: false, roll: 0) == 1)
        #expect(LedLightning.boltCount(heat: 0.56, redline: false, roll: 0) == 2)
        #expect(LedLightning.boltCount(heat: 0.6, redline: true, roll: 0.59) == 3)
        #expect(LedLightning.boltCount(heat: 0.6, redline: true, roll: 0.6) == 2)
        #expect(LedLightning.boltCount(heat: 0.3, redline: true, roll: 0.1) == 2)
        #expect(near(LedLightning.boltWidth(power: 1, diameter: 100), 0.384))
        #expect(near(LedLightning.boltLife(power: 1, roll: 0.5), 0.24))
        #expect(near(LedLightning.zapLife(power: 1), 0.22))
    }

    @Test func boltsPerDigitFollowHeatAndTheRedlineRoll() {
        var cool = always()
        fire(&cool, "1", "2", heat: 0.3)
        #expect(cool.zaps.count == 1 && cool.bolts.count == 1)

        var hot = always()
        fire(&hot, "1", "2", heat: 0.6)
        #expect(hot.bolts.count == 2)

        var redline = always()
        fire(&redline, "1", "2", heat: 0.6, redline: true)
        #expect(redline.bolts.count == 3)

        var missed = LedLightning(random: LedRandom(sequence: [0, 0.7]))
        fire(&missed, "1", "2", heat: 0.6, redline: true)
        #expect(missed.bolts.count == 2)

        let small = LedEffects(level: 2, reduceMotion: false, floating: true, small: true, thumbnail: false)
        var lod = always()
        fire(&lod, "1", "2", heat: 0.6, redline: true, effects: small)
        #expect(lod.bolts.count == 2)
    }

    @Test func matchesThePrototypeOnTheSameDraws() {
        var lightning = LedLightning(random: LedRandom(sequence: prototypeDraws))
        fire(&lightning, "1199", "1234", heat: 0.9, overdrive: 0.6, redline: true, effects: maxed)
        #expect(lightning.zaps.count == 3 && lightning.bolts.count == 7)
        let zap = lightning.zaps[0]
        #expect(zap.x == -10 && zap.y == 4 && near(zap.radius, 28.8) && near(zap.power, 2.376) && near(zap.life, 0.30256))
        #expect(near(lightning.zaps[1].power, 1.848) && near(lightning.zaps[2].power, 1.32))

        let b = lightning.bolts[0]
        #expect(near(b.x0, -5.1784) && near(b.y0, -8.24) && near(b.x1, -11.664327665234165) && near(b.y1, -39.591491483675064))
        #expect(near(b.length, 32.01536) && near(b.life, 0.2878) && near(b.width, 0.8941568) && b.forks == 2)
        let main = lightning.mainPath(0)
        #expect(near(main[main.startIndex + 16].x, -5.223511701282226) && near(main[main.startIndex + 16].y, -24.577310363691417))
        let fork0 = lightning.forkPath(0, 0)
        #expect(near(fork0[fork0.startIndex + 16].x, -12.450495085460693) && near(fork0[fork0.startIndex + 16].y, -32.44994919153849))
        let fork1 = lightning.forkPath(0, 1)
        #expect(near(fork1[fork1.startIndex + 8].x, -2.6268099220027317) && near(fork1[fork1.startIndex + 8].y, -24.110337318372277))

        // To the same edge of the neighboring digit.
        let n = lightning.bolts[3]
        #expect(near(n.x0, 4.708) && near(n.y0, 16.24) && near(n.x1, 28.236) && near(n.y1, 16.4848))
        let nMain = lightning.mainPath(3)
        #expect(near(nMain[nMain.startIndex + 16].x, 16.4932976) && near(nMain[nMain.startIndex + 16].y, 14.315464))
        // To the LED ring.
        let ring = lightning.bolts[2]
        #expect(near(hypot(ring.x1, ring.y1), 0.39 * s))
    }

    @Test func aPositionCoolsDownForElevenHundredths() {
        var lightning = always()
        fire(&lightning, "10", "11", time: 1)
        #expect(lightning.zaps.count == 1)
        fire(&lightning, "11", "21", time: 1.05)
        #expect(lightning.zaps.count == 2, "another position is not cooling down")
        fire(&lightning, "21", "22", time: 1.06)
        #expect(lightning.zaps.count == 2)
        fire(&lightning, "22", "23", time: 1.12)
        #expect(lightning.zaps.count == 3)
        fire(&lightning, "23", "24", time: 1.13, force: true)
        #expect(lightning.zaps.count == 4, "force skips the cooldown")
        fire(&lightning, "24", "25", time: 0.01)
        #expect(lightning.zaps.count == 5, "a clock that jumped back lifts the cooldown")
    }

    @Test func theChanceRollGatesTheZapWithoutStartingTheCooldown() {
        var lightning = LedLightning(random: LedRandom(sequence: [0.99]))
        fire(&lightning, "1", "2", heat: 0)
        #expect(lightning.isEmpty)
        lightning.random = LedRandom(sequence: [0.29])
        fire(&lightning, "2", "3", heat: 0)
        #expect(lightning.zaps.count == 1)

        var certain = LedLightning(random: LedRandom(sequence: [0.999999]))
        fire(&certain, "1000", "2000", heat: 0)
        #expect(certain.zaps.count == 1, "three digits to the right make it certain")
    }

    @Test func neverMoreThanTheBoltCapAlive() {
        var lightning = LedLightning(seed: 21)
        fire(&lightning, "000000000000", "999999999999", heat: 1, overdrive: 1, redline: true, effects: maxed, force: true)
        #expect(lightning.bolts.count == 16)
        var time = 1.0
        for k in 0..<300 {
            time += 0.03
            let a = String(repeating: String(k % 10), count: 12)
            let b = String(repeating: String((k + 1) % 10), count: 12)
            fire(&lightning, a, b, time: time, heat: 1, overdrive: 1, redline: true, effects: maxed, force: k % 3 == 0)
            #expect(lightning.bolts.count <= LedLightning.maxBolts)
            lightning.step(dt: 0.03)
        }

        let small = LedEffects(level: 3, reduceMotion: false, floating: true, small: true, thumbnail: false)
        var lod = LedLightning(seed: 22)
        fire(&lod, "000000000000", "999999999999", heat: 1, overdrive: 1, redline: true, effects: small, force: true)
        #expect(lod.bolts.count == 8)
    }

    @Test func aLengthChangeZapsEveryDigit() {
        var grown = always()
        fire(&grown, "999", "1.00k")
        #expect(grown.zaps.map(\.x) == [-30, 10, 30])
        var same = always()
        fire(&same, "123", "124")
        #expect(same.zaps.map(\.x) == [10])
        var unchanged = always()
        fire(&unchanged, "124", "124")
        #expect(unchanged.isEmpty)
    }

    @Test func nonDigitsNeverZap() {
        var lightning = always()
        fire(&lightning, "12k", "12M")
        fire(&lightning, "1.5k", "1,5k")
        fire(&lightning, "abc", "abd")
        fire(&lightning, "k", "kk")
        fire(&lightning, "—", "–")
        #expect(lightning.isEmpty)
        fire(&lightning, "—1", "—2")
        #expect(lightning.zaps.count == 1 && lightning.zaps[0].x == -10, "multi-byte characters keep the cell index")
    }

    @Test func nothingBelowHalfATokenOrWithoutLightning() {
        var idle = always()
        fire(&idle, "1", "0", value: 0.49)
        #expect(idle.isEmpty)
        let soft = LedEffects(level: 1, reduceMotion: false, floating: true, small: false, thumbnail: false)
        let reduced = LedEffects(level: 3, reduceMotion: true, floating: true, small: false, thumbnail: false)
        var gated = always()
        fire(&gated, "1", "2", effects: soft, force: true)
        fire(&gated, "1", "2", effects: reduced, force: true)
        #expect(gated.isEmpty)
    }

    @Test func boltPathsHaveExactEndsAndForks() {
        var weak = always()
        fire(&weak, "1", "2", heat: 0)
        let w = weak.bolts[0]
        #expect(w.forks == 1)
        #expect(weak.mainPath(0).count == 33 && weak.forkPath(0, 0).count == 17 && weak.forkPath(0, 1).isEmpty)
        #expect(weak.mainPath(1).isEmpty && weak.forkPath(-1, 0).isEmpty)

        var strong = LedLightning(seed: 5)
        fire(&strong, "1000", "2000", heat: 1, overdrive: 1, redline: true, effects: maxed)
        #expect(!strong.bolts.isEmpty)
        for (i, b) in strong.bolts.enumerated() {
            #expect(b.forks == 2)
            checkShape(strong, i)
        }
    }

    private func checkShape(_ lightning: LedLightning, _ i: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let b = lightning.bolts[i]
        let main = Array(lightning.mainPath(i))
        #expect(main.count == LedLightning.mainPoints, sourceLocation: sourceLocation)
        #expect(main.first == SIMD2(b.x0, b.y0) && main.last == SIMD2(b.x1, b.y1), sourceLocation: sourceLocation)
        #expect(near(b.length, hypot(b.x1 - b.x0, b.y1 - b.y0)), sourceLocation: sourceLocation)
        for f in 0..<b.forks {
            let fork = Array(lightning.forkPath(i, f))
            #expect(fork.count == LedLightning.forkPoints, sourceLocation: sourceLocation)
            #expect(main[3...27].contains(fork[0]), sourceLocation: sourceLocation)
            let reach = hypot(fork[16].x - fork[0].x, fork[16].y - fork[0].y)
            #expect(reach >= 0.2 * b.length - 1e-9 && reach <= 0.5 * b.length + 1e-9, sourceLocation: sourceLocation)
        }
    }

    @Test func boltsStartOnTheDigitEdgeAndEndPerTheirCase() {
        var random = LedLightning(seed: 9)
        for k in 0..<40 {
            fire(&random, "0000", "1111", time: Double(k), heat: 0.7, overdrive: 0.5, redline: true, effects: maxed, force: true)
            for b in random.bolts where b.age == 0 {
                let i = Int(((b.x0 + 30) / 20).rounded())
                let cell = cells("1111")[max(0, min(3, i))]
                #expect(near(abs(b.y0 - cell.y), 0.36 * 34))
                #expect(abs(b.x0 - cell.x) <= 0.294 * 20 + 1e-9)
            }
            random.removeAll()
        }

        // Draws of 0: top edge, left neighbor, roll 0.
        var ring = always()
        fire(&ring, "1", "2", redline: true)
        #expect(near(hypot(ring.bolts[0].x1, ring.bolts[0].y1), 0.39 * s))
        #expect(near(ring.bolts[0].y0, 4 - 0.36 * 34) && near(ring.bolts[0].x0, -30 - 0.294 * 20))

        var neighbor = always()
        fire(&neighbor, "12", "13")
        #expect(near(neighbor.bolts[0].x1, -30 - 0.5 * 0.42 * 20) && near(neighbor.bolts[0].y1, 4 - 0.36 * 34 * 0.6))

        var crackle = always()
        fire(&crackle, "1", "2", heat: 0.3)
        let p = LedLightning.power(significance: 0, heat: 0.3, overdrive: 0, lvl: 1)
        let c = crackle.bolts[0]
        #expect(near(c.length, s * (0.05 + 0.07 * p)))
        #expect(near(atan2(c.y1 - c.y0, c.x1 - c.x0), -.pi / 2 - 0.85))
    }

    @Test func boltsReshapeEveryFortyFiveMillisecondsAndDie() {
        var lightning = LedLightning(seed: 31)
        fire(&lightning, "1000", "2000", heat: 1, overdrive: 1, redline: true, effects: maxed)
        let before = Array(lightning.mainPath(0))
        lightning.step(dt: 0.03)
        #expect(Array(lightning.mainPath(0)) == before)
        lightning.step(dt: 0.02)
        let after = Array(lightning.mainPath(0))
        #expect(after != before && after.first == before.first && after.last == before.last)
        #expect(near(lightning.bolts[0].regen, LedLightning.reshape))
        for _ in 0..<20 { lightning.step(dt: 1.0 / 15) }
        #expect(lightning.isEmpty)
    }

    @Test func pathsFollowTheirBoltsThroughRemovals() {
        var lightning = LedLightning(seed: 41)
        var time = 0.0
        for k in 0..<240 {
            time += 1.0 / 60
            if k % 4 == 0 {
                fire(&lightning, "0000", k % 8 == 0 ? "1111" : "2222", time: time, heat: 0.8, overdrive: 0.7,
                     redline: true, effects: maxed, force: true)
            }
            lightning.step(dt: 1.0 / 60)
            for i in lightning.bolts.indices { checkShape(lightning, i) }
        }
    }

    @Test func alphas() {
        let bolt = LedBolt(x0: 0, y0: 0, x1: 0, y1: 0, length: 0, width: 1, age: 0, life: 0.2, regen: 0, forks: 1)
        #expect(LedLightning.boltAlpha(bolt) == 1)
        var half = bolt
        half.age = 0.1
        #expect(near(LedLightning.boltAlpha(half), 0.8))
        half.age = 0.2
        #expect(LedLightning.boltAlpha(half) == 0)
        let zap = LedZap(x: 0, y: 0, radius: 10, power: 1, age: 0, life: 0.22)
        #expect(near(LedLightning.zapAlpha(zap), 0.35))
        #expect(near(LedLightning.zapAlpha(LedZap(x: 0, y: 0, radius: 10, power: 4, age: 0.19, life: 0.38)), 0.2))
        #expect(LedLightning.zapAlpha(LedZap(x: 0, y: 0, radius: 10, power: 4, age: 1, life: 0.38)) == 0)
    }

    @Test func jagWritesTwoToTheDepthPlusOnePoints() {
        var buffer = ContiguousArray(repeating: SIMD2<Double>(-1, -1), count: 40)
        var straight = LedRandom(sequence: [0.5])
        LedLightning.jag(from: SIMD2(0, 0), to: SIMD2(32, 64), roughness: 0.3, depth: 5, random: &straight, into: &buffer, at: 3)
        #expect(buffer[0..<3].allSatisfy { $0 == SIMD2(-1, -1) } && buffer[36...].allSatisfy { $0 == SIMD2(-1, -1) })
        for k in 0...32 { #expect(buffer[3 + k] == SIMD2(Double(k), Double(2 * k))) }

        var random = LedRandom(seed: 3)
        LedLightning.jag(from: SIMD2(1, 2), to: SIMD2(9, -4), roughness: 0.35, depth: 4, random: &random, into: &buffer, at: 0)
        #expect(buffer[0] == SIMD2(1, 2) && buffer[16] == SIMD2(9, -4))
        #expect(buffer[1..<16].contains { abs($0.x * 6 + $0.y * 8 - 22) > 1e-6 }, "jagged off the straight line")
        #expect(buffer[17] == SIMD2(14, 28))

        LedLightning.jag(from: SIMD2(5, 5), to: SIMD2(6, 6), roughness: 0.3, depth: 0, random: &random, into: &buffer, at: 0)
        #expect(buffer[0] == SIMD2(5, 5) && buffer[1] == SIMD2(6, 6))

        var short = ContiguousArray(repeating: SIMD2<Double>.zero, count: 32)
        LedLightning.jag(from: SIMD2(1, 1), to: SIMD2(2, 2), roughness: 0.3, depth: 5, random: &random, into: &short, at: 0)
        #expect(short.allSatisfy { $0 == .zero })
    }

    @Test func zapsFadeAndEnd() {
        var lightning = always()
        fire(&lightning, "1", "2", heat: 0)
        #expect(near(lightning.zaps[0].life, 0.16 + 0.06 * 0.33) && near(lightning.zaps[0].radius, 1.44 * 20))
        for _ in 0..<17 { lightning.step(dt: 0.01) }
        #expect(lightning.zaps.count == 1)
        lightning.step(dt: 0.01)
        #expect(lightning.zaps.isEmpty)
    }
}

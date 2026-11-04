import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("LED particles")
struct LedParticlesTests {
    private let s = 148.0
    private let dt = 0.0625

    @Test func ratesFollowTheSpec() {
        #expect(LedParticles.sparkRate(heat: 0.449, lvl: 1, countScale: 1) == 0)
        #expect(LedParticles.sparkRate(heat: 0.45, lvl: 1, countScale: 1) == 0)
        #expect(abs(LedParticles.sparkRate(heat: 1, lvl: 1, countScale: 1) - 192) < 1e-9)
        #expect(abs(LedParticles.sparkRate(heat: 1, lvl: 1.6, countScale: 0.5) - 153.6) < 1e-9)
        #expect(LedParticles.emberRate(overdrive: 1, redline: false, lvl: 1, countScale: 1) == 0)
        #expect(abs(LedParticles.emberRate(overdrive: 0, redline: true, lvl: 1, countScale: 1) - 37.8) < 1e-9)
        #expect(abs(LedParticles.emberRate(overdrive: 1, redline: true, lvl: 1.6, countScale: 1) - 201.6) < 1e-9)
    }

    @Test func carryAccumulationEmitsDeterministically() {
        var pool = LedParticles(seed: 1)
        for k in 1...8 {
            pool.step(dt: dt, time: 0, diameter: s, sparkRate: 16, emberRate: 0, lead: 0.7, overdrive: 0)
            #expect(pool.particles.count == k)
        }
        var slow = LedParticles(seed: 1)
        for _ in 0..<3 { slow.step(dt: dt, time: 0, diameter: s, sparkRate: 4, emberRate: 0, lead: 0.7, overdrive: 0) }
        #expect(slow.isEmpty)
        slow.step(dt: dt, time: 0, diameter: s, sparkRate: 4, emberRate: 0, lead: 0.7, overdrive: 0)
        #expect(slow.particles.count == 1)
    }

    @Test func sparksLeaveTheLitArcAtTheGaugeRadius() {
        // Matches the prototype's emitSpark run on the same draws (0.13 < 0.6: from the tip).
        var pool = LedParticles(random: LedRandom(sequence: [0.13, 0.77, 0.42, 0.91, 0.05, 0.66, 0.38, 0.29, 0.84, 0.57, 0.21]))
        pool.step(dt: dt, time: 0, diameter: s, sparkRate: 16, emberRate: 0, lead: 0.8, overdrive: 0.3)
        let p = pool.particles[0]
        #expect(p.kind == .spark && p.streak && p.age == 0 && p.drag == 2.2)
        #expect(abs(p.x - 59.93292850731295) < 1e-9 && abs(p.y - -9.492443338641223) < 1e-9)
        #expect(abs(p.vx - 180.8208305870162) < 1e-9 && abs(p.vy - -20.457677863074707) < 1e-9)
        #expect(abs(p.life - 1.137) < 1e-12 && abs(p.size - 1.28) < 1e-12 && abs(p.heat - 0.9) < 1e-12)
        #expect(abs(hypot(p.x, p.y) - 0.41 * s) < 1e-9)

        var random = LedParticles(seed: 7)
        for _ in 0..<40 { random.step(dt: dt, time: 0, diameter: s, sparkRate: 32, emberRate: 0, lead: 0.6, overdrive: 0) }
        for p in random.particles where p.age == 0 {
            let angle = atan2(p.y, p.x) * 180 / .pi
            let fromStart = (angle - 135 + 720).truncatingRemainder(dividingBy: 360)
            #expect(fromStart <= 0.6 * 270 + 1e-9)
            #expect(p.life >= 0.5 && p.life < 1.2 && p.size >= 1.2 && p.size < 2.8)
        }
    }

    @Test func dragSlowsAndLifeEnds() {
        var pool = LedParticles(seed: 3)
        pool.step(dt: dt, time: 0, diameter: s, sparkRate: 16, emberRate: 0, lead: 0.7, overdrive: 0)
        let first = pool.particles[0]
        pool.step(dt: dt, time: 0, diameter: s, sparkRate: 0, emberRate: 0, lead: 0.7, overdrive: 0)
        let moved = pool.particles[0]
        let k = exp(-2.2 * dt)
        #expect(abs(moved.vx - first.vx * k) < 1e-9 && abs(moved.vy - first.vy * k) < 1e-9)
        #expect(abs(moved.x - (first.x + first.vx * k * dt)) < 1e-9)
        #expect(moved.age == dt)
        for _ in 0..<40 { pool.step(dt: dt, time: 0, diameter: s, sparkRate: 0, emberRate: 0, lead: 0.7, overdrive: 0) }
        #expect(pool.isEmpty)
    }

    @Test func embersRiseFromTheTopOfTheRim() {
        var pool = LedParticles(seed: 5)
        pool.step(dt: dt, time: 0, diameter: s, sparkRate: 0, emberRate: 64, lead: 1, overdrive: 0.5)
        #expect(pool.particles.count == 4)
        for p in pool.particles {
            #expect(p.kind == .ember && !p.streak && p.drag == 0.4)
            #expect(abs(hypot(p.x, p.y) - 0.47 * s) < 1e-9)
            let angle = (atan2(p.y, p.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            #expect(angle >= 200 && angle < 340)
            #expect(p.vy < 0 && p.size >= 1.2 && p.size < 3.0 && p.heat >= 0.85 && p.life >= 0.9 && p.life < 2.0)
        }
        let before = pool.particles[0]
        pool.step(dt: dt, time: 0.5, diameter: s, sparkRate: 0, emberRate: 0, lead: 1, overdrive: 0.5)
        let after = pool.particles[0]
        let k = exp(-0.4 * dt)
        #expect(abs(after.vy - (before.vy - 0.12 * s * dt) * k) < 1e-9)
        #expect(abs(after.vx - (before.vx + sin(0.5 * 3 + before.seed) * 0.3 * s * dt) * k) < 1e-9)
    }

    @Test func theBurstFillsOnlyTheRoomLeft() {
        var pool = LedParticles(seed: 11)
        pool.burst(diameter: s, count: LedParticles.burstCount)
        #expect(pool.particles.count == 160)
        let gold = pool.particles.filter { $0.kind == .gold }.count
        #expect(gold > 25 && gold < 75)
        for p in pool.particles {
            #expect(abs(hypot(p.x, p.y) - 0.48 * s) < 1e-9)
            let speed = hypot(p.vx, p.vy)
            #expect(speed >= 0.5 * s - 1e-9 && speed < 1.8 * s)
            #expect(p.life >= 0.7 && p.life < 1.6 && p.streak && p.drag == 2.4 && p.heat >= 0.9)
            #expect(abs(atan2(p.vy, p.vx) - atan2(p.y, p.x)) < 1e-9 || abs(abs(atan2(p.vy, p.vx) - atan2(p.y, p.x)) - 2 * .pi) < 1e-9)
        }
        for _ in 0..<4 { pool.burst(diameter: s, count: LedParticles.burstCount) }
        #expect(pool.particles.count == LedParticles.capacity)
        pool.burst(diameter: s, count: 50)
        #expect(pool.particles.count == LedParticles.capacity)
        pool.removeAll()
        #expect(pool.isEmpty)
    }

    @Test func thePoolNeverExceedsItsCapacity() {
        var pool = LedParticles(seed: 13)
        let capacity = pool.particles.capacity
        var peak = 0
        for frame in 0..<600 {
            if frame % 17 == 0 { pool.burst(diameter: s, count: LedParticles.burstCount) }
            pool.step(dt: 1.0 / 60, time: Double(frame) / 60, diameter: s, sparkRate: 20000, emberRate: 9000, lead: 1,
                      overdrive: 1)
            peak = max(peak, pool.particles.count)
            #expect(pool.particles.count <= LedParticles.capacity)
        }
        #expect(peak == LedParticles.capacity)
        #expect(pool.particles.capacity == capacity)
        pool.step(dt: 1.0 / 60, time: 0, diameter: s, sparkRate: .infinity, emberRate: .greatestFiniteMagnitude, lead: 1,
                  overdrive: 1)
        #expect(pool.particles.count <= LedParticles.capacity)
    }

    @Test func invalidStepsDoNothingAndLongOnesAreClamped() {
        var pool = LedParticles(seed: 17)
        pool.step(dt: -1, time: 0, diameter: s, sparkRate: 1000, emberRate: 1000, lead: 1, overdrive: 1)
        pool.step(dt: .nan, time: 0, diameter: s, sparkRate: 1000, emberRate: 1000, lead: 1, overdrive: 1)
        #expect(pool.isEmpty)
        pool.step(dt: 2, time: 0, diameter: s, sparkRate: 150, emberRate: 0, lead: 1, overdrive: 1)
        #expect(pool.particles.count == 10)
    }
}

@Suite("LED arcs")
struct LedArcsTests {
    private let s = 148.0

    @Test func arcsStartOnlyWhileActive() {
        var arcs = LedArcs(seed: 2)
        for _ in 0..<30 { arcs.step(dt: 1.0 / 60, active: false, heat: 1, overdrive: 1, lvl: 1, diameter: s) }
        #expect(arcs.isEmpty)
        arcs.step(dt: 1.0 / 60, active: true, heat: 1, overdrive: 1, lvl: 1, diameter: s)
        #expect(arcs.arcs.count == 1)
        for _ in 0..<30 { arcs.step(dt: 1.0 / 60, active: false, heat: 1, overdrive: 1, lvl: 1, diameter: s) }
        #expect(arcs.isEmpty)
    }

    @Test func arcGeometryFollowsTheSpec() {
        var arcs = LedArcs(seed: 4)
        var seen = 0
        for _ in 0..<3000 {
            arcs.step(dt: 1.0 / 60, active: true, heat: 0.8, overdrive: 0.5, lvl: 1.6, diameter: s)
            for arc in arcs.arcs where arc.age == 0 {
                seen += 1
                let start = arc.a0 * 180 / .pi
                #expect(start >= 135 && start <= 135 + 0.8 * 270)
                #expect(abs(arc.a1 - arc.a0) <= 0.45)
                #expect(arc.r0 == 0.41 * s && arc.r1 >= 0.5 * s && arc.r1 < 0.6 * s)
                #expect(arc.life >= 0.09 && arc.life < 0.19)
            }
            #expect(arcs.arcs.count <= LedArcs.capacity)
        }
        // One every (0.28 − 0.1) / 1.6 · (0.5…1.5) s on average, quantised up to whole frames.
        let interval = 50.0 / Double(seen)
        #expect(interval > 0.11 && interval < 0.14, "interval \(interval)")
    }

    @Test func theRhythmComesFromTheFormula() {
        var arcs = LedArcs(random: LedRandom(sequence: [0.5]))
        var starts = 0
        for _ in 0..<10000 {
            arcs.step(dt: 0.001, active: true, heat: 1, overdrive: 0, lvl: 1, diameter: s)
            starts += arcs.arcs.filter { $0.age == 0 }.count
            #expect(arcs.arcs.count <= 1)
        }
        // 0.28 × (0.5 + 0.5) s apart over 10 s, the first at once.
        #expect(starts == 36)
    }

    @Test func neverMoreThanEightAlive() {
        var arcs = LedArcs(seed: 6)
        var peak = 0
        for _ in 0..<2000 {
            arcs.step(dt: 0.01, active: true, heat: 1, overdrive: 1, lvl: 100, diameter: s)
            peak = max(peak, arcs.arcs.count)
            #expect(arcs.arcs.count <= LedArcs.capacity)
        }
        #expect(peak == LedArcs.capacity)
        arcs.removeAll()
        #expect(arcs.isEmpty)
    }

    @Test func pathsAreTenPointsWithFixedEnds() {
        var arcs = LedArcs(seed: 8)
        arcs.step(dt: 1.0 / 60, active: true, heat: 0.9, overdrive: 0.4, lvl: 1, diameter: s)
        var buffer = ContiguousArray(repeating: SIMD2<Double>(.nan, .nan), count: 12)
        arcs.path(of: 0, diameter: s, into: &buffer)
        let arc = arcs.arcs[0]
        #expect(LedArcs.points == 10)
        #expect(buffer[0] == SIMD2(cos(arc.a0) * arc.r0, sin(arc.a0) * arc.r0))
        #expect(buffer[9] == SIMD2(cos(arc.a1) * arc.r1, sin(arc.a1) * arc.r1))
        #expect(buffer[10].x.isNaN && buffer[11].x.isNaN)
        for i in 1..<9 {
            let k = Double(i) / 9
            let a = arc.a0 + (arc.a1 - arc.a0) * k
            let r = arc.r0 + (arc.r1 - arc.r0) * k
            let jx = buffer[i].x - cos(a) * r
            let jy = buffer[i].y - sin(a) * r
            #expect(abs(jx - jy) < 1e-9)
            #expect(abs(jx) <= 0.0225 * s)
        }
        let first = buffer
        arcs.path(of: 0, diameter: s, into: &buffer)
        #expect(buffer[0] == first[0] && buffer[9] == first[9] && buffer[4] != first[4])

        var short = ContiguousArray(repeating: SIMD2<Double>.zero, count: 9)
        arcs.path(of: 0, diameter: s, into: &short)
        arcs.path(of: 5, diameter: s, into: &buffer)
        #expect(short.allSatisfy { $0 == .zero })
    }

    @Test func fadeRunsFromOneToZero() {
        let arc = LedArc(a0: 0, a1: 0, r0: 0, r1: 0, age: 0.05, life: 0.1)
        #expect(LedArcs.fade(arc) == 0.5)
        #expect(LedArcs.fade(LedArc(a0: 0, a1: 0, r0: 0, r1: 0, age: 0.2, life: 0.1)) == 0)
        #expect(LedArcs.fade(LedArc(a0: 0, a1: 0, r0: 0, r1: 0, age: 0, life: 0.1)) == 1)
    }
}

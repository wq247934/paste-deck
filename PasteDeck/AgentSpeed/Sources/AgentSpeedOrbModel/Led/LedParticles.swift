import Foundation

/// One spark, ember or burst particle (prototype `emitSpark`, `emitEmber`, `burst`).
public struct LedParticle: Sendable {
    public enum Kind: Sendable { case spark, ember, gold }

    public var kind: Kind
    /// Points and points per second, relative to the center, y down.
    public var x, y, vx, vy: Double
    public var age, life: Double
    /// Points.
    public var size: Double
    /// Palette position of its color.
    public var heat: Double
    public var drag: Double
    public var seed: Double
    /// Sparks and burst particles draw as streaks; embers as glowing dots.
    public var streak: Bool
}

/// Sparks, embers and the new-peak burst (DESIGN 2.1 Sparks / New peak; prototype emitSpark, emitEmber, burst, step)
/// in a fixed pool: nothing allocates after `init`. Read `particles` in place; holding a copy while stepping would
/// force a copy of the pool.
public struct LedParticles: Sendable {
    public static let capacity = 640
    public static let burstCount = 160

    public private(set) var particles: ContiguousArray<LedParticle>
    public var random: LedRandom
    private var sparkCarry = 0.0
    private var emberCarry = 0.0

    public init(seed: UInt64 = 0x5EED_0005) {
        self.init(random: LedRandom(seed: seed))
    }

    public init(random: LedRandom) {
        self.random = random
        particles = []
        particles.reserveCapacity(Self.capacity)
    }

    public var isEmpty: Bool { particles.isEmpty }

    public mutating func removeAll() {
        particles.removeAll(keepingCapacity: true)
        sparkCarry = 0
        emberCarry = 0
    }

    /// Spark rate 120 ((h − 0.45)/0.55) · lvl · 1.6 · countScale when h ≥ 0.45, else 0.
    public static func sparkRate(heat h: Double, lvl: Double, countScale: Double) -> Double {
        h >= 0.45 ? 120 * ((h - 0.45) / 0.55) * lvl * 1.6 * countScale : 0
    }

    /// Ember rate 90 max(o, 0.3) · lvl · 1.4 · countScale at the redline tier, else 0.
    public static func emberRate(overdrive o: Double, redline: Bool, lvl: Double, countScale: Double) -> Double {
        redline ? 90 * max(o, 0.3) * lvl * 1.4 * countScale : 0
    }

    /// Ages, applies drag (and the embers' sway and upward pull), moves, drops dead ones, then emits; never exceeds capacity.
    /// `lead` = the gauge fraction of the leading segment (h, or the swept display heat). `dt` is clamped to
    /// 0...`LedMath.maxStep`; `time` is the free clock that drives the embers' sway.
    public mutating func step(dt: Double, time: Double, diameter s: Double, sparkRate: Double, emberRate: Double,
                              lead: Double, overdrive o: Double) {
        let dt = LedMath.clampedStep(dt)
        guard dt > 0 else { return }
        var i = 0
        while i < particles.count {
            var p = particles[i]
            p.age += dt
            if p.age >= p.life {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
                continue
            }
            if p.kind == .ember {
                p.vx += sin(time * 3 + p.seed) * 0.3 * s * dt
                p.vy -= 0.12 * s * dt
            }
            let k = exp(-p.drag * dt)
            p.vx *= k
            p.vy *= k
            p.x += p.vx * dt
            p.y += p.vy * dt
            particles[i] = p
            i += 1
        }

        var sparks = Self.due(&sparkCarry, rate: sparkRate, dt: dt)
        while sparks > 0, particles.count < Self.capacity {
            sparks -= 1
            emitSpark(diameter: s, lead: lead, overdrive: o)
        }
        var embers = Self.due(&emberCarry, rate: emberRate, dt: dt)
        while embers > 0, particles.count < Self.capacity {
            embers -= 1
            emitEmber(diameter: s)
        }
    }

    /// Carry accumulation: the whole emissions due this step, keeping the fraction for the next one.
    static func due(_ carry: inout Double, rate: Double, dt: Double) -> Int {
        guard rate.isFinite, rate > 0 else { return 0 }
        carry += rate * dt
        guard carry >= 1 else { return 0 }
        let whole = carry.rounded(.down)
        carry -= whole
        return Int(min(whole, Double(capacity)))
    }

    /// The new-peak burst: `count` particles (≤ capacity left) from 0.48 S outward, 30 % gold, 0.5–1.8 S/s, 0.7–1.6 s.
    public mutating func burst(diameter s: Double, count: Int) {
        let n = min(max(0, count), Self.capacity - particles.count)
        for _ in 0..<n {
            let a = random.next() * 2 * .pi
            let speed = (0.5 + random.next() * 1.3) * s
            let life = 0.7 + random.next() * 0.9
            let size = 1.4 + random.next() * 2.2
            let heat = 0.9 + random.next() * 0.1
            let kind: LedParticle.Kind = random.next() < 0.3 ? .gold : .spark
            particles.append(LedParticle(
                kind: kind, x: cos(a) * 0.48 * s, y: sin(a) * 0.48 * s, vx: cos(a) * speed, vy: sin(a) * speed,
                age: 0, life: life, size: size, heat: heat, drag: 2.4, seed: 0, streak: true))
        }
    }

    private mutating func emitSpark(diameter s: Double, lead: Double, overdrive o: Double) {
        guard particles.count < Self.capacity else { return }
        let lead = min(1, max(0, lead))
        let fromTip = random.next() < 0.6
        let pos = fromTip ? lead : random.next() * lead
        let a = (135 + pos * 270) * .pi / 180
        let speed = (0.3 + random.next() * 0.6) * s * (1 + o * 0.8) * 1.3
        let tangential = (random.next() - 0.35) * 0.6 * s * 1.3
        let life = 0.5 + random.next() * 0.7
        let size = 1.2 + random.next() * 1.6
        particles.append(LedParticle(
            kind: .spark, x: cos(a) * 0.41 * s, y: sin(a) * 0.41 * s,
            vx: cos(a) * speed - sin(a) * tangential, vy: sin(a) * speed + cos(a) * tangential,
            age: 0, life: life, size: size, heat: min(1, pos + 0.1), drag: 2.2, seed: 0, streak: true))
    }

    private mutating func emitEmber(diameter s: Double) {
        guard particles.count < Self.capacity else { return }
        let a = (200 + random.next() * 140) * .pi / 180
        let vx = (random.next() - 0.5) * 0.1 * s
        let vy = -(0.12 + random.next() * 0.2) * s
        let life = 0.9 + random.next() * 1.1
        let size = 1.2 + random.next() * 1.8
        let heat = 0.85 + random.next() * 0.15
        let seed = random.next() * 100
        particles.append(LedParticle(
            kind: .ember, x: cos(a) * 0.47 * s, y: sin(a) * 0.47 * s, vx: vx, vy: vy,
            age: 0, life: life, size: size, heat: heat, drag: 0.4, seed: seed, streak: false))
    }
}

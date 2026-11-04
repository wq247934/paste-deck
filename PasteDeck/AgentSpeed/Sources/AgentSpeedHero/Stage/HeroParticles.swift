import Foundation

public struct HeroParticle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Dust or exhaust: an outline circle growing while it fades and drifts back with the road.
        case puff
        /// Rocket ignition ring.
        case ring
        /// Electric arc around the e-bike's hub motor.
        case arc
        /// Sports-car exhaust flame pop.
        case pop
        /// A short hot streak (nozzle, race-car floor, afterburner).
        case spark
    }

    public var alive = false
    public var kind = Kind.puff
    public var age = 0.0
    public var life = 1.0
    /// Seconds before it appears (arcs fire 30 ms apart).
    public var delay = 0.0
    public var x = 0.0, y = 0.0
    public var vx = 0.0, vy = 0.0
    public var size = 1.0
    public var grow = 0.0
    public var angle = 0.0
    public var seed = 0.0
    public var gravity = 0.0

    public init() {}

    /// Life progress 0…1 after the delay, or nil while waiting.
    public var progress: Double? {
        let shown = age - delay
        guard shown >= 0 else { return nil }
        return min(1, shown / life)
    }
}

/// The fixed pool of 64 particles (DESIGN 4c, Particle streams and start-up bursts).
public struct HeroParticles: Sendable {
    public static let capacity = 64
    public private(set) var pool = [HeroParticle](repeating: HeroParticle(), count: capacity)
    private var accumulator = 0.0

    public init() {}

    public var isEmpty: Bool { !pool.contains { $0.alive } }

    public mutating func clear() {
        for index in pool.indices where pool[index].alive { pool[index].alive = false }
        accumulator = 0
    }

    private func free() -> Int? { pool.firstIndex { !$0.alive } }

    /// A start-up burst of `count` particles from `at` toward `dir` (Soft caps each burst at 6).
    public mutating func burst(_ kind: HeroParticle.Kind, at: SIMD2<Double>, dir: SIMD2<Double>, count: Int, cap: Int,
                               random: inout HeroRandom) {
        for index in 0..<min(count, cap) {
            guard let slot = free() else { return }
            var p = HeroParticle()
            p.alive = true
            p.kind = kind
            p.x = at.x
            p.y = at.y
            switch kind {
            case .puff:
                let speed = 8 + 14 * random.next()
                let angle = atan2(dir.y, dir.x) + (random.next() - 0.5) * 0.9
                p.vx = cos(angle) * speed
                p.vy = sin(angle) * speed - 3 * random.next()
                p.life = 0.5 + 0.35 * random.next()
                p.size = 0.8 + 0.5 * random.next()
                p.grow = 2.6 + 1.6 * random.next()
            case .arc:
                p.angle = random.next() * 2 * .pi
                p.life = 0.16 + 0.14 * random.next()
                p.size = 3.8 + 2 * random.next()
                p.seed = random.next()
                p.delay = Double(index) * 0.03
            case .pop:
                p.vx = dir.x * 4
                p.life = 0.22
                p.angle = atan2(dir.y, dir.x)
            case .ring:
                let side = index % 2 == 1 ? 1.0 : -1.0
                let angle = atan2(dir.y, dir.x) + side * (0.55 + 0.45 * random.next())
                let speed = 22 + 14 * random.next()
                p.vx = cos(angle) * speed
                p.vy = sin(angle) * speed
                p.life = 0.45 + 0.2 * random.next()
                p.grow = 3 + 2 * random.next()
            case .spark:
                p.life = 0.3
            }
            pool[slot] = p
        }
    }

    /// Continuous sparks at `rate` per second from `at` toward `dir`.
    public mutating func emit(rate: Double, dt: Double, at: SIMD2<Double>, dir: SIMD2<Double>, speed: Double, spread: Double,
                              gravity: Double, life: Double, random: inout HeroRandom) {
        accumulator += rate * dt
        while accumulator >= 1 {
            accumulator -= 1
            guard let slot = free() else { return }
            let angle = atan2(dir.y, dir.x) + (random.next() - 0.5) * spread
            let velocity = speed * (0.6 + 0.6 * random.next())
            var p = HeroParticle()
            p.alive = true
            p.kind = .spark
            p.x = at.x
            p.y = at.y
            p.vx = cos(angle) * velocity
            p.vy = sin(angle) * velocity
            p.life = life * (0.7 + 0.6 * random.next())
            p.gravity = gravity
            pool[slot] = p
        }
    }

    /// Ages and moves every particle; puffs drift back with the ground speed `ground`.
    public mutating func step(dt: Double, ground: Double) {
        for index in pool.indices where pool[index].alive {
            var p = pool[index]
            p.age += dt
            if p.age > p.life + p.delay {
                p.alive = false
                pool[index] = p
                continue
            }
            switch p.kind {
            case .puff, .ring:
                let drag = exp(-dt * 3)
                p.vx *= drag
                p.vy *= drag
                p.vx -= 0.15 * ground * dt
            case .spark:
                p.vy += p.gravity * dt
            case .arc, .pop:
                break
            }
            p.x += p.vx * dt
            p.y += p.vy * dt
            pool[index] = p
        }
    }
}

import Foundation

public struct HeroSpeedLine: Sendable, Equatable {
    public var alive = false
    public var age = 0.0
    /// Head position (canvas units) and travel direction.
    public var x = 0.0, y = 0.0
    public var dx = -1.0, dy = 0.0
    public var length = 0.0
    public var speed = 0.0
    public var opacity = 0.0

    public init() {}
}

/// The pool of 16 ambient speed lines (DESIGN 4c, Speed lines).
public struct HeroSpeedLines: Sendable {
    public static let capacity = 16
    public private(set) var pool = [HeroSpeedLine](repeating: HeroSpeedLine(), count: capacity)
    private var timer = 0.0

    public init() {}

    public var isEmpty: Bool { !pool.contains { $0.alive } }

    public mutating func clear() {
        for index in pool.indices where pool[index].alive { pool[index].alive = false }
        timer = 0
    }

    /// Live count for the level: `N = round((2 + 8 h) · clamp(G / lo, 0, 1))`, capped at 5 / 9 / 14.
    public static func cap(level: HeroLevel, heat: Double, ground: Double, low: Double) -> Int {
        let n = ((2 + 8 * heat) * HeroMath.clamp(ground / low, 0, 1)).rounded()
        switch level {
        case .off: return 0
        case .soft: return min(5, Int((n * 0.6).rounded()))
        case .standard: return min(9, Int(n))
        case .max: return min(14, Int((n * 1.4).rounded()))
        }
    }

    /// A new line; a line whose height crosses the vehicle is born at its tail so it peels off the body. Bursts are
    /// longer, faster and brighter.
    public mutating func spawn(burst: Bool, heat: Double, ground: Double, bounds: SIMD4<Double>, heading: Double?,
                               random: inout HeroRandom) {
        guard let slot = pool.firstIndex(where: { !$0.alive }) else { return }
        var line = HeroSpeedLine()
        line.alive = true
        line.length = (6 + 20 * heat) * (0.7 + 0.6 * random.next()) * (burst ? 1.4 : 1)
        line.speed = 1.25 * max(ground, 40) * (0.85 + 0.3 * random.next()) * (burst ? 1.3 : 1)
        line.opacity = (0.16 + 0.32 * heat) * (0.7 + 0.6 * random.next()) * (burst ? 1.4 : 1)
        if let heading {
            let lateral = (random.next() - 0.5) * 80
            let ux = cos(heading), uy = sin(heading)
            line.dx = -ux
            line.dy = -uy
            line.x = 50 + ux * 52 - uy * lateral
            line.y = 50 + uy * 52 + ux * lateral
        } else {
            let y = 16 + 68 * random.next()
            line.y = y
            line.x = y > bounds.y - 2 && y < bounds.w + 2 ? bounds.x - 2 : 102 + line.length * random.next() * 0.5
        }
        pool[slot] = line
    }

    /// Moves the lines and keeps the live count near `cap`, a new line every `0.9 / N × (0.5…1.5)` s.
    public mutating func step(dt: Double, cap: Int, heat: Double, ground: Double, bounds: SIMD4<Double>, heading: Double?,
                              random: inout HeroRandom) {
        var alive = 0
        for index in pool.indices where pool[index].alive {
            var line = pool[index]
            line.age += dt
            line.x += line.dx * line.speed * dt
            line.y += line.dy * line.speed * dt
            if line.x < -line.length - 4 || line.x > 140 || line.y < -40 || line.y > 140 {
                line.alive = false
            } else {
                alive += 1
            }
            pool[index] = line
        }
        timer -= dt
        if alive < cap, timer <= 0 {
            spawn(burst: false, heat: heat, ground: ground, bounds: bounds, heading: heading, random: &random)
            timer = 0.9 / Double(max(cap, 1)) * (0.5 + random.next())
        }
    }
}

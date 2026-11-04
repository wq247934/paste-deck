import Foundation

/// Sparks thrown where the needle grinds against the peg (DESIGN 2a.2, Peg sparks). Fixed capacity, swap-removed, so
/// stepping never allocates. Positions and speeds are in diameters relative to the disc center (y down).
struct NeedleSparks {
    struct Spark {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age: Double
        var life: Double
        /// Stroke width in points at the 148 pt reference size.
        var width: Double
    }

    static let capacity = 80

    private(set) var sparks = ContiguousArray<Spark>()
    private var carry = 0.0
    private var random = OrbRandom(seed: 0x51A7_C0DE_77E1_0B11)

    init() {
        sparks.reserveCapacity(Self.capacity)
    }

    var isEmpty: Bool { sparks.isEmpty }

    mutating func removeAll() {
        sparks.removeAll(keepingCapacity: true)
        carry = 0
    }

    /// Advances the sparks and emits `rate` per second at the contact point (`angle` degrees, radius 0.405 S), up to `pool`.
    mutating func step(dt: Double, rate: Double, angle: Double, pool: Int) {
        guard dt > 0 else { return }
        var index = 0
        let drag = exp(-2 * dt)
        while index < sparks.count {
            sparks[index].age += dt
            if sparks[index].age >= sparks[index].life {
                sparks.swapAt(index, sparks.count - 1)
                sparks.removeLast()
                continue
            }
            sparks[index].vy += 1.1 * dt
            sparks[index].vx *= drag
            sparks[index].vy *= drag
            sparks[index].x += sparks[index].vx * dt
            sparks[index].y += sparks[index].vy * dt
            index += 1
        }
        carry += rate * dt
        let limit = min(pool, Self.capacity)
        while carry >= 1 {
            carry -= 1
            guard sparks.count < limit else { continue }
            emit(angle: angle)
        }
    }

    private mutating func emit(angle degrees: Double) {
        let a = degrees * .pi / 180
        let radius = 0.405
        let direction = a + .pi / 2 + random.range(-(.pi / 6)...(.pi / 6))
        let speed = random.range(0.35...0.9)
        sparks.append(Spark(
            x: radius * cos(a),
            y: radius * sin(a),
            vx: cos(direction) * speed + cos(a) * 0.2,
            vy: sin(direction) * speed + sin(a) * 0.2,
            age: 0,
            life: random.range(0.22...0.55),
            width: random.range(0.8...1.6)
        ))
    }
}

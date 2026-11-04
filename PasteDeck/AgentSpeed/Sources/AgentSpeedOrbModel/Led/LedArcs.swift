import Foundation

/// One electric arc: angles in radians (clockwise from 3 o'clock, y down), radii in points.
public struct LedArc: Sendable {
    public var a0, a1, r0, r1, age, life: Double
}

/// Electric arcs (redline tier, Standard and Max; prototype makeArc / drawArc). Up to 8 alive.
public struct LedArcs: Sendable {
    public static let capacity = 8
    public static let points = 10

    public private(set) var arcs: ContiguousArray<LedArc>
    public var random: LedRandom
    private var timer = 0.0

    public init(seed: UInt64 = 0x5EED_00A2) {
        self.init(random: LedRandom(seed: seed))
    }

    public init(random: LedRandom) {
        self.random = random
        arcs = []
        arcs.reserveCapacity(Self.capacity)
    }

    public var isEmpty: Bool { arcs.isEmpty }

    public mutating func removeAll() {
        arcs.removeAll(keepingCapacity: true)
        timer = 0
    }

    /// Ages and drops arcs; while `active`, starts one every (0.28 − 0.2 o) / lvl · (0.5…1.5) s from a random lit point
    /// (135° + rand · h · 270°) at 0.41 S out to 0.50–0.60 S and ±0.45 rad, living 0.09–0.19 s. `dt` is clamped to
    /// 0...`LedMath.maxStep`; a full pool skips the start but keeps the rhythm.
    public mutating func step(dt: Double, active: Bool, heat h: Double, overdrive o: Double, lvl: Double,
                              diameter s: Double) {
        let dt = LedMath.clampedStep(dt)
        guard dt > 0 else { return }
        var i = 0
        while i < arcs.count {
            arcs[i].age += dt
            if arcs[i].age >= arcs[i].life {
                arcs.swapAt(i, arcs.count - 1)
                arcs.removeLast()
            } else {
                i += 1
            }
        }
        guard active else { return }
        timer -= dt
        guard timer <= 0 else { return }
        if arcs.count < Self.capacity {
            let a0 = (135 + random.next() * min(1, max(0, h)) * 270) * .pi / 180
            let a1 = a0 + (random.next() - 0.5) * 0.9
            let r1 = (0.5 + random.next() * 0.1) * s
            let life = 0.09 + random.next() * 0.1
            _ = random.next() // the prototype's unused arc seed, kept so the draws line up
            arcs.append(LedArc(a0: a0, a1: a1, r0: 0.41 * s, r1: r1, age: 0, life: life))
        }
        timer = (0.28 - 0.2 * o) / max(lvl, 0.1) * (0.5 + random.next())
    }

    /// Writes the 10-point polyline of arc `index` re-jittered for this frame (the prototype's ±0.0225 S, the same
    /// offset on x and y, endpoints fixed) into `buffer` (count ≥ 10). Does nothing for a bad index or a short buffer.
    public mutating func path(of index: Int, diameter s: Double, into buffer: inout ContiguousArray<SIMD2<Double>>) {
        guard arcs.indices.contains(index), buffer.count >= Self.points else { return }
        let arc = arcs[index]
        let steps = Double(Self.points - 1)
        let last = Self.points - 1
        buffer[0] = SIMD2(cos(arc.a0) * arc.r0, sin(arc.a0) * arc.r0)
        for i in 1..<last {
            let k = Double(i) / steps
            let a = arc.a0 + (arc.a1 - arc.a0) * k
            let r = arc.r0 + (arc.r1 - arc.r0) * k
            let j = (random.next() - 0.5) * s * 0.045
            buffer[i] = SIMD2(cos(a) * r + j, sin(a) * r + j)
        }
        buffer[last] = SIMD2(cos(arc.a1) * arc.r1, sin(arc.a1) * arc.r1)
    }

    /// 1 − age / life
    public static func fade(_ arc: LedArc) -> Double {
        guard arc.life > 0 else { return 0 }
        return min(1, max(0, 1 - arc.age / arc.life))
    }
}

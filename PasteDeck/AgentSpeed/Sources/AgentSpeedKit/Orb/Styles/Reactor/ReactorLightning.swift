import AgentSpeedOrbModel
import Foundation

/// The reactor's lightning (DESIGN 2a.4, layer 8): bolts between the core rim and rotor A or out into the aura, and the
/// sparks thrown at their far ends. Fixed capacity, swap-removed, so stepping never allocates. Radii are in diameters,
/// angles in radians (clockwise from 3 o'clock, y down), positions relative to the disc center.
struct ReactorLightning {
    struct Bolt {
        var start: Double
        var life: Double
        var from: Double
        var to: Double
        var inner: Double
        var outer: Double
        var seed: Int
    }

    struct Spark {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age: Double
        var life: Double
        /// Radius factor (points at the 148 pt reference size × 0.6).
        var size: Double
    }

    static let boltCapacity = 4
    static let sparkCapacity = 64

    private(set) var bolts = ContiguousArray<Bolt>()
    private(set) var sparks = ContiguousArray<Spark>()
    private var carry = 0.0
    private var random = OrbRandom(seed: 0x0B07_7EA5_E1EC_7A1C)

    init() {
        bolts.reserveCapacity(Self.boltCapacity)
        sparks.reserveCapacity(Self.sparkCapacity)
    }

    var isEmpty: Bool { bolts.isEmpty && sparks.isEmpty }

    /// Advances to `time`: drops finished bolts, moves sparks and emits new bolts at `rate` per second (at most
    /// `maxBolts` alive, `sparkPool` sparks). Returns how many bolts started.
    mutating func step(time: Double, dt: Double, rate: Double, maxBolts: Int, sparkPool: Int, overdrive: Double) -> Int {
        var index = 0
        while index < bolts.count {
            if time - bolts[index].start >= bolts[index].life {
                bolts.swapAt(index, bolts.count - 1)
                bolts.removeLast()
            } else {
                index += 1
            }
        }
        if dt > 0 {
            index = 0
            let drag = exp(-ReactorMath.sparkDrag * dt)
            while index < sparks.count {
                sparks[index].age += dt
                if sparks[index].age >= sparks[index].life {
                    sparks.swapAt(index, sparks.count - 1)
                    sparks.removeLast()
                    continue
                }
                sparks[index].vx *= drag
                sparks[index].vy *= drag
                sparks[index].x += sparks[index].vx * dt
                sparks[index].y += sparks[index].vy * dt
                index += 1
            }
        }
        guard rate > 0, dt > 0 else {
            carry = 0
            return 0
        }
        carry += rate * dt
        var started = 0
        while carry >= 1 {
            carry -= 1
            guard bolts.count < min(maxBolts, Self.boltCapacity) else { continue }
            emit(time: time, overdrive: overdrive, sparkPool: min(sparkPool, Self.sparkCapacity))
            started += 1
        }
        return started
    }

    mutating func removeAll() {
        bolts.removeAll(keepingCapacity: true)
        sparks.removeAll(keepingCapacity: true)
        carry = 0
    }

    private mutating func emit(time: Double, overdrive: Double, sparkPool: Int) {
        let theta = random.next() * 2 * .pi
        let outward = ReactorMath.canLeapOutward(overdrive: overdrive) && random.next() < ReactorMath.outerBoltShare
        let spread = ReactorMath.innerBoltSpread * .pi / 180
        let bolt = Bolt(
            start: time,
            life: random.range(ReactorMath.boltLife),
            from: theta,
            to: theta + random.range(-spread...spread) * (outward ? 0.6 : 1),
            inner: outward ? ReactorMath.outerBoltFrom : ReactorMath.innerBoltFrom,
            outer: outward ? random.range(ReactorMath.outerBoltTo) : ReactorMath.innerBoltTo,
            seed: Int(random.next() * 1_000_000)
        )
        bolts.append(bolt)
        for _ in 0..<ReactorMath.sparksPerBolt {
            guard sparks.count < sparkPool else { break }
            let speed = random.range(ReactorMath.sparkSpeed)
            let direction = bolt.to + random.range(-1.2...1.2)
            sparks.append(Spark(
                x: bolt.outer * cos(bolt.to),
                y: bolt.outer * sin(bolt.to),
                vx: cos(direction) * speed,
                vy: sin(direction) * speed,
                age: 0,
                life: random.range(ReactorMath.sparkLife),
                size: random.range(0.8...1.5)
            ))
        }
    }

    /// Point `i` (0...8) of a bolt's polyline at `time`, in diameters from the center; re-randomized every 50 ms.
    static func point(_ bolt: Bolt, _ i: Int, time: Double) -> (x: Double, y: Double) {
        let segments = ReactorMath.boltSegments
        let u = Double(i) / Double(segments)
        let theta = bolt.from + (bolt.to - bolt.from) * u
        let radius = bolt.inner + (bolt.outer - bolt.inner) * u
        let step = Int(((time - bolt.start) / ReactorMath.boltRefresh).rounded(.down))
        let jitter = i == 0 || i == segments ? 0
            : (Noise.hash(bolt.seed &+ step &* 31, i) - 0.5) * 2 * ReactorMath.boltJitter * sin(.pi * u)
        return (radius * cos(theta) - sin(theta) * jitter, radius * sin(theta) + cos(theta) * jitter)
    }
}

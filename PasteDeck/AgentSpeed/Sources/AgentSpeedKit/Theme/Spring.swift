import Foundation

/// Critically damped spring evaluated in closed form, so it can be sampled at any frame time.
struct SpringValue: Sendable {
    /// Angular frequency; 10 settles within 2 % in ≈ 0.6 s.
    var omega: Double
    private(set) var target: Double
    private var origin: Double
    private var velocity: Double
    private var startTime: TimeInterval

    init(_ value: Double = 0, omega: Double = 10) {
        self.omega = omega
        target = value
        origin = value
        velocity = 0
        startTime = 0
    }

    func value(at time: TimeInterval) -> Double {
        let t = max(0, time - startTime)
        let c1 = origin - target
        let c2 = velocity + omega * c1
        return target + (c1 + c2 * t) * exp(-omega * t)
    }

    func velocity(at time: TimeInterval) -> Double {
        let t = max(0, time - startTime)
        let c1 = origin - target
        let c2 = velocity + omega * c1
        return (c2 - omega * (c1 + c2 * t)) * exp(-omega * t)
    }

    func isSettled(at time: TimeInterval, tolerance: Double = 0.002) -> Bool {
        abs(value(at: time) - target) < tolerance && abs(velocity(at: time)) < tolerance * omega
    }

    mutating func retarget(_ newTarget: Double, at time: TimeInterval) {
        guard newTarget != target else { return }
        origin = value(at: time)
        velocity = velocity(at: time)
        startTime = time
        target = newTarget
    }

    mutating func snap(to value: Double, at time: TimeInterval) {
        origin = value
        target = value
        velocity = 0
        startTime = time
    }
}

enum Easing {
    static func easeOut(_ t: Double) -> Double {
        let t = t.clamped(to: 0...1)
        return 1 - pow(1 - t, 3)
    }

    static func easeInOut(_ t: Double) -> Double {
        let t = t.clamped(to: 0...1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    /// Underdamped spring from 0 to 1 (overshoots slightly), for pop-in labels.
    static func springPop(_ t: Double, response: Double = 0.45, damping: Double = 0.62) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = damping
        let wd = omega * sqrt(1 - zeta * zeta)
        return 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta * omega / wd * sin(wd * t))
    }
}

/// Deterministic per-key noise in 0...1, for shimmer and jitter that must not allocate per frame.
enum Noise {
    static func hash(_ a: Int, _ b: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        x &*= 0xc4ceb9fe1a85ec53
        x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }
}

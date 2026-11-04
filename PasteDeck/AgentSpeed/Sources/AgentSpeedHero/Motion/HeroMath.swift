import Foundation

/// Easing and shaping functions of DESIGN 4c. Inputs outside 0…1 are clamped.
public enum HeroMath {
    @inlinable public static func clamp(_ x: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, x))
    }

    @inlinable public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Smoothstep of `t` over 0…1.
    @inlinable public static func smooth(_ t: Double) -> Double {
        let t = clamp(t, 0, 1)
        return t * t * (3 - 2 * t)
    }

    @inlinable public static func easeInCubic(_ t: Double) -> Double {
        let t = clamp(t, 0, 1)
        return t * t * t
    }

    @inlinable public static func easeOutCubic(_ t: Double) -> Double {
        let u = 1 - clamp(t, 0, 1)
        return 1 - u * u * u
    }

    @inlinable public static func easeInOutSine(_ t: Double) -> Double {
        0.5 - 0.5 * cos(Double.pi * clamp(t, 0, 1))
    }

    /// `bump(a, p, e)`: smoothstep from 0 at `a` to 1 at `p`, back to 0 at `e` (seconds).
    @inlinable public static func bump(_ tau: Double, _ start: Double, _ peak: Double, _ end: Double) -> Double {
        if tau < start { return 0 }
        if tau < peak { return smooth((tau - start) / (peak - start)) }
        return 1 - smooth((tau - peak) / (end - peak))
    }

    /// An underdamped spring from `from` to `to` with initial velocity `velocity`, at time `t`
    /// (SwiftUI response / damping-fraction semantics).
    public static func spring(at t: Double, from: Double, to: Double, velocity: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return from }
        let omega = 2 * Double.pi / response
        let zeta = damping
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let a = from - to
        let b = (velocity + zeta * omega * a) / wd
        return to + exp(-zeta * omega * t) * (a * cos(wd * t) + b * sin(wd * t))
    }

    /// Reduces an angle to −π…π before it is applied, so large distances keep full precision.
    @inlinable public static func wrapAngle(_ angle: Double) -> Double {
        angle - 2 * Double.pi * (angle / (2 * Double.pi)).rounded()
    }
}

/// A critically damped spring evaluated exactly per step (DESIGN 4c, Speed model): `ω = 6.2 / settle`.
public struct HeroCriticalSpring: Sendable, Equatable {
    public let omega: Double
    public private(set) var value: Double
    /// d(value)/dt.
    public private(set) var velocity: Double

    public init(settle: Double, value: Double = 0) {
        omega = 6.2 / settle
        self.value = value
        velocity = 0
    }

    @discardableResult
    public mutating func step(toward target: Double, dt: Double) -> Double {
        let c1 = value - target
        let c2 = velocity + omega * c1
        let decay = exp(-omega * dt)
        value = target + (c1 + c2 * dt) * decay
        velocity = (c2 - omega * (c1 + c2 * dt)) * decay
        return value
    }

    public mutating func snap(to target: Double) {
        value = target
        velocity = 0
    }
}

/// Small deterministic generator (xorshift32) for particles and speed lines.
public struct HeroRandom: Sendable, Equatable {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed == 0 ? 1 : seed
    }

    /// Uniform in 0..<1.
    public mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / 4_294_967_296
    }
}

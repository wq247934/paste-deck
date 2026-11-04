import Foundation

/// Pure numbers of the `liquid` style (DESIGN 2a.3). Lengths are fractions of the diameter S unless stated; the
/// effects level is its rank (0 Off, 1 Soft, 2 Standard, 3 Max).
public enum LiquidMath {
    /// Radius of the inner glass, which clips the liquid.
    public static let glassRadius = 0.455
    public static let idleLevel = 0.08
    public static let maxRipples = 4
    public static let maxDrops = 3
    public static let splashPool = 40
    public static let steamPool = 12
    public static let goldMotes = 22
    /// A ripple is forgotten after this long.
    public static let rippleLife = 2.2

    /// Target level (fraction of the inner diameter): `0.08 + 0.74 h + 0.06 o`, 0.08 at idle.
    public static func targetLevel(heat: Double, overdrive: Double, active: Bool) -> Double {
        active ? idleLevel + 0.74 * heat + 0.06 * overdrive : idleLevel
    }

    /// Mean surface height (y down): `c_y + 0.455 S − 0.91 S f`.
    public static func meanSurface(centerY: Double, diameter: Double, level: Double) -> Double {
        centerY + glassRadius * diameter - 2 * glassRadius * diameter * level
    }

    /// Wave amplitude target in S: `0.004 + 0.02 h + 0.018 o` (Soft × 0.6, idle 0.002, Off and Reduce Motion 0).
    public static func amplitude(heat: Double, overdrive: Double, active: Bool, level: Int, reduceMotion: Bool) -> Double {
        guard level > 0, !reduceMotion else { return 0 }
        let base = active ? 0.004 + 0.02 * heat + 0.018 * overdrive : 0.002
        return base * (level == 1 ? 0.6 : 1)
    }

    /// Phase rates (Hz) of the three wave components and the boil chop.
    public static func phaseRates(heat: Double, overdrive: Double) -> SIMD4<Double> {
        SIMD4(0.25 + 0.5 * heat + 0.3 * overdrive, 0.4 + 0.8 * heat + 0.4 * overdrive, 0.9 + 1.6 * heat, 3.1)
    }

    /// Boil chop amplitude in S at the redline (Standard and up): `0.006 (0.5 + 0.5 o)`, halved below S 120.
    public static func chop(overdrive: Double, boiling: Bool, small: Bool) -> Double {
        guard boiling else { return 0 }
        return 0.006 * (0.5 + 0.5 * overdrive) * (small ? 0.5 : 1)
    }

    /// Surface offset (points, y down) of the wave and chop at `x` points from the center; the back wave uses 75 % of
    /// the amplitude and its own phase offsets.
    public static func wave(x: Double, diameter s: Double, amplitude: Double, chop: Double, phases: SIMD4<Double>, back: Bool = false) -> Double {
        let tau = 2 * Double.pi
        let a = amplitude * s * (back ? 0.75 : 1)
        let offset = back ? 1.7 : 0
        var y = a * (0.55 * sin(x / (0.9 * s) * tau + phases[0] + offset)
            + 0.30 * sin(x / (0.47 * s) * tau - phases[1] + offset * 1.3)
            + 0.15 * sin(x / (0.23 * s) * tau + phases[2] + offset * 0.7))
        y += chop * s * sin(x / (0.11 * s) * tau + phases[3] + offset) * (0.7 + 0.3 * sin(x / (0.05 * s) + 1.7 * phases[3]))
        return y
    }

    /// Ripple amplitude in S for a pulse of `strength` (0...1): `0.022 (0.6 + 0.6 strength)`.
    public static func rippleAmplitude(strength: Double) -> Double {
        0.022 * (0.6 + 0.6 * strength)
    }

    /// Ripple offset (points, y down) at `distance` points from the impact, `tau` seconds after it:
    /// `−A_r e^(−τ/0.75) exp(−((d − 0.42 S τ) / 0.075 S)²) cos(2π (d − 0.42 S τ) / 0.1 S)`.
    public static func ripple(distance: Double, tau: Double, amplitude: Double, diameter s: Double) -> Double {
        let u = distance - 0.42 * s * tau
        let envelope = exp(-tau / 0.75) * exp(-pow(u / (0.075 * s), 2))
        return -amplitude * s * envelope * cos(2 * Double.pi * u / (0.1 * s))
    }

    /// Motes and bubbles per second: Soft `0.6 + 3 h`; Standard `1.5 + 12 h` (+ `6 + 10 o` in the redline tier);
    /// Max × 1.6; none at idle, Off or with Reduce Motion.
    public static func moteRate(heat: Double, overdrive: Double, redline: Bool, active: Bool, level: Int, reduceMotion: Bool) -> Double {
        guard active, level > 0, !reduceMotion else { return 0 }
        if level == 1 { return 0.6 + 3 * heat }
        let rate = 1.5 + 12 * heat + (redline ? 6 + 10 * overdrive : 0)
        return rate * (level == 3 ? 1.6 : 1)
    }

    /// Most motes alive at once: Soft 6, Standard 32, Max 48; 16 below S 120 (Soft stays 6).
    public static func motePool(level: Int, small: Bool) -> Int {
        if level <= 1 { return 6 }
        if small { return 16 }
        return level == 3 ? 48 : 32
    }

    /// Rise speed of a mote in S/s before its random factor U(0.7, 1.3).
    public static func moteSpeed(heat: Double, overdrive: Double) -> Double { 0.08 + 0.35 * heat + 0.25 * overdrive }

    /// Upward acceleration of motes in S/s².
    public static func moteAcceleration(heat: Double) -> Double { 0.12 + 0.2 * heat }

    /// Mote radius in S before its random factor U(0.6, 1.4) (never below 0.9 pt).
    public static func moteRadius(heat: Double) -> Double { 0.006 + 0.01 * heat }

    /// Cool glass bubbles turn into luminous motes with heat.
    public static func hotness(heat: Double) -> Double {
        let t = min(1, max(0, (heat - 0.35) / (0.9 - 0.35)))
        return t * t * (3 - 2 * t)
    }

    /// Steam wisps per second in the redline tier (Standard and up): `2 + 4 o`, Max × 1.6.
    public static func steamRate(overdrive: Double, boiling: Bool, level: Int, reduceMotion: Bool) -> Double {
        guard boiling, level >= 2, !reduceMotion else { return 0 }
        return (2 + 4 * overdrive) * (level == 3 ? 1.6 : 1)
    }

    /// Where a pulse droplet appears: 0.16 S above the surface, never above c − 0.414 S nor below c − 0.3 S (y down,
    /// points from the center).
    public static func dropStart(surface: Double, diameter s: Double) -> Double {
        min(max(surface - 0.16 * s, -0.414 * s), -0.3 * s)
    }

    /// The level's slosh: an underdamped spring at 0.75 Hz, damping 0.62.
    public static func levelSpring(_ value: Double = idleLevel) -> Oscillator { Oscillator(frequency: 0.75, damping: 0.62, value: value) }

    /// The new-peak surge: 0.9 Hz, damping 0.45, kicked by +0.9 /s (≈ +0.1 of the diameter).
    public static func surgeSpring() -> Oscillator { Oscillator(frequency: 0.9, damping: 0.45) }
    public static let surgeKick = 0.9

    /// An underdamped spring integrated in sub-steps of at most 1/480 s.
    public struct Oscillator: Equatable, Sendable {
        public var value: Double
        public var velocity = 0.0
        public let omega: Double
        public let damping: Double

        public init(frequency: Double, damping: Double, value: Double = 0) {
            omega = 2 * Double.pi * frequency
            self.damping = damping
            self.value = value
        }

        public mutating func step(toward target: Double, dt: Double) {
            guard dt > 0 else { return }
            let count = max(1, Int((dt * 480).rounded(.up)))
            let h = dt / Double(count)
            for _ in 0..<count {
                let acceleration = -omega * omega * (value - target) - 2 * damping * omega * velocity
                velocity += acceleration * h
                value += velocity * h
            }
        }

        public func isSettled(at target: Double, tolerance: Double = 0.0005) -> Bool {
            abs(value - target) < tolerance && abs(velocity) < tolerance * 4
        }
    }

    /// A critically damped spring that settles in `settle` seconds (ω = 6.2 / settle), stepped exactly.
    public struct CriticalSpring: Equatable, Sendable {
        public var value: Double
        public var velocity = 0.0
        public let omega: Double

        public init(settle: Double, value: Double = 0) {
            omega = 6.2 / settle
            self.value = value
        }

        public mutating func step(toward target: Double, dt: Double) {
            guard dt > 0 else { return }
            let c1 = value - target
            let c2 = velocity + omega * c1
            let decay = exp(-omega * dt)
            value = target + (c1 + c2 * dt) * decay
            velocity = (c2 - omega * (c1 + c2 * dt)) * decay
        }

        public func isSettled(at target: Double, tolerance: Double = 0.0002) -> Bool {
            abs(value - target) < tolerance && abs(velocity) < tolerance * omega
        }
    }
}

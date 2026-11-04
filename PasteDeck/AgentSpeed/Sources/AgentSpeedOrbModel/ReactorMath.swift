import Foundation

/// The pure numbers of the `reactor` style (DESIGN 2a.4): ring geometry, the arc lengths and speeds of the three
/// rotors, the pulse kick, the energy bands of rotor B, the lightning budget, the new-peak lock and the corona.
/// Angles are degrees clockwise from 3 o'clock in screen space; speeds are revolutions per second (positive =
/// clockwise); radii are fractions of the diameter S.
public enum ReactorMath {
    public static let coreRadius = 0.30
    public static let statorRadius = 0.468
    public static let statorWidth = 0.006
    public static let notchInner = 0.456
    public static let notchOuter = 0.474
    public static let notchWidth = 0.005
    public static let rotorARadius = 0.425
    public static let rotorAWidth = 0.024
    public static let rotorBRadius = 0.383
    public static let rotorBWidth = 0.018
    public static let rotorCRadius = 0.338
    public static let rotorCWidth = 0.009
    public static let coronaOuter = 0.40
    public static let coreRimWidth = 0.009
    /// Arcs of rotors A and C, 120° and 180° apart.
    public static let rotorAArcs = 3
    public static let rotorCArcs = 2

    /// 24 notches (every 6th brighter), 4 below S 120.
    public static func notchCount(small: Bool) -> Int { small ? 4 : 24 }
    /// 24 coils of 7.5°, 12 of 13° below S 120.
    public static func coilCount(small: Bool) -> Int { small ? 12 : 24 }
    public static func coilLength(small: Bool) -> Double { small ? 13 : 7.5 }

    // MARK: Arcs

    /// Rotor A arc length: `20° + 90° h + 10° o`, capped at 120° (at full overdrive the three arcs close the ring).
    public static func arcLengthA(heat h: Double, overdrive o: Double) -> Double {
        min(120, 20 + 90 * h + 10 * o)
    }

    /// Rotor C arc length: `14° + 130° h + 20° o`, at most 175°.
    public static func arcLengthC(heat h: Double, overdrive o: Double) -> Double {
        min(175, 14 + 130 * h + 20 * o)
    }

    // MARK: Rotation

    public struct Speeds: Equatable, Sendable {
        public var a: Double
        public var b: Double
        public var c: Double
    }

    /// Rotor speeds (rev/s): A `0.03 + 0.45 h^1.3 + 0.35 o + k`, B `−(0.02 + 0.30 h^1.3 + 0.25 o + 0.6 k)`, C
    /// `0.05 + 1.1 h^1.3 + 0.7 o + 1.2 k`.
    public static func speeds(heat h: Double, overdrive o: Double, kick k: Double) -> Speeds {
        let p = pow(max(0, h), 1.3)
        return Speeds(
            a: 0.03 + 0.45 * p + 0.35 * o + k,
            b: -(0.02 + 0.30 * p + 0.25 * o + 0.6 * k),
            c: 0.05 + 1.1 * p + 0.7 * o + 1.2 * k
        )
    }

    /// Each completed response kicks the rotors: `k += 0.25 × strength`, decaying with τ 0.5 s.
    public static let kickPerStrength = 0.25
    public static let kickTimeConstant = 0.5

    public static func decayedKick(_ kick: Double, dt: Double) -> Double {
        let next = kick * exp(-max(0, dt) / kickTimeConstant)
        return next < 0.0005 ? 0 : next
    }

    /// Advances an angle (degrees) by `speed` rev/s over `dt`, kept in 0..<360.
    public static func advance(_ angle: Double, speed: Double, dt: Double) -> Double {
        wrap(angle + 360 * speed * dt)
    }

    public static func wrap(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    // MARK: Rotor B energy bands

    /// The bands' phase rate ψ̇ (rev/s): `0.15 + 1.4 h + 0.6 o`.
    public static func bandRate(heat h: Double, overdrive o: Double) -> Double {
        0.15 + 1.4 * h + 0.6 * o
    }

    /// Energy of a coil at `theta` (radians, its place on the rotor) with band phase `psi` (radians):
    /// `0.18 + 0.82 (½ + ½ cos(3θ − ψ))^2.2 (0.35 + 0.65 h)`.
    public static func coilEnergy(theta: Double, psi: Double, heat h: Double) -> Double {
        let wave = 0.5 + 0.5 * cos(3 * theta - psi)
        return 0.18 + 0.82 * pow(wave, 2.2) * (0.35 + 0.65 * h)
    }

    /// The idle sign of life: a +60 % Gaussian band about 1/7 of the circle wide running once around rotor B
    /// (`position` and `progress` as fractions of the circle).
    public static func signOfLifeBand(position: Double, progress: Double) -> Double {
        var d = (position - progress).truncatingRemainder(dividingBy: 1)
        if d < 0 { d += 1 }
        let distance = min(d, 1 - d) * 7
        return 0.6 * exp(-distance * distance)
    }

    // MARK: Lightning

    /// Bolts per second at the redline tier (Standard and up): `1.5 + 6 o`, × 1.6 at Max.
    public static func boltRate(overdrive o: Double, max: Bool) -> Double {
        (1.5 + 6 * o) * (max ? 1.6 : 1)
    }

    public static func maxBolts(max: Bool) -> Int { max ? 4 : 3 }
    public static let boltLife: ClosedRange<Double> = 0.09...0.18
    /// A bolt's path is re-randomized this often.
    public static let boltRefresh = 0.05
    public static let boltSegments = 8
    /// Inner bolts run from the core rim to rotor A within ±29°.
    public static let innerBoltFrom = 0.306
    public static let innerBoltTo = rotorARadius
    public static let innerBoltSpread = 29.0
    /// From `o > 0.3`, 40 % of bolts leap outward from just outside rotor A into the aura.
    public static let outerBoltFrom = 0.437
    public static let outerBoltTo: ClosedRange<Double> = 0.56...0.66
    public static let outerBoltShare = 0.4
    public static let outerBoltThreshold = 0.3
    /// Perpendicular jitter `±0.048 S sin(π u)` along the bolt.
    public static let boltJitter = 0.048

    public static func canLeapOutward(overdrive o: Double) -> Bool { o > outerBoltThreshold }

    /// Bolt opacity over its life: full for the first 20 %, then fading.
    public static func boltAlpha(progress u: Double) -> Double {
        guard u >= 0, u < 1 else { return 0 }
        return u < 0.2 ? 1 : 1 - (u - 0.2) / 0.8
    }

    public static let sparksPerBolt = 6
    public static func sparkPool(max: Bool) -> Int { max ? 64 : 40 }
    public static let sparkSpeed: ClosedRange<Double> = 0.2...0.6
    public static let sparkDrag = 3.0
    public static let sparkLife: ClosedRange<Double> = 0.15...0.4

    /// At most three flashes per second (DESIGN 7): a bolt brightens the corona only this long after the last flash.
    public static let flashInterval = 1.0 / 3

    public static func mayFlash(at time: Double, lastFlash: Double) -> Bool {
        time - lastFlash >= flashInterval - 1e-9
    }

    // MARK: New-peak lock

    /// Rotational symmetry of each rotor (degrees): three arcs, the coils, two arcs.
    public static func lockSymmetry(rotor: Int, coils: Int) -> Double {
        switch rotor {
        case 0: 360.0 / Double(rotorAArcs)
        case 1: 360.0 / Double(max(1, coils))
        default: 360.0 / Double(rotorCArcs)
        }
    }

    /// The nearest pose ahead in the direction of travel with an arc head at 12 o'clock (−90°): never backwards.
    public static func lockTarget(angle: Double, symmetry: Double, clockwise: Bool) -> Double {
        let base = -90.0
        let steps = (angle - base) / symmetry
        let k = clockwise ? steps.rounded(.up) : steps.rounded(.down)
        return k * symmetry + base
    }

    public static let lockSwing = 0.42
    public static let lockEnd = 0.57
    public static let lockOvershoot = 1.2

    /// Swing progress: `easeOutBack` with overshoot 1.2 over 0.42 s, holding at 1 until 0.57 s.
    public static func lockProgress(age: Double) -> Double {
        easeOutBack(min(1, max(0, age / lockSwing)), overshoot: lockOvershoot)
    }

    /// Gold intensity of the lock: `1 − |τ/0.42 − 1| / 0.35`.
    public static func lockGold(age: Double) -> Double {
        guard age >= 0, age < lockEnd else { return 0 }
        return max(0, 1 - abs(age / lockSwing - 1) / 0.35)
    }

    /// Reduce Motion: the lock is a 0.3 s gold crossfade.
    public static let reducedLockDuration = 0.3

    public static func reducedLockGold(age: Double) -> Double {
        guard age >= 0, age < reducedLockDuration else { return 0 }
        return sin(.pi * age / reducedLockDuration)
    }

    public static func easeOutBack(_ u: Double, overshoot k: Double) -> Double {
        let x = u - 1
        return 1 + (k + 1) * x * x * x + k * x * x
    }

    // MARK: Corona and flare

    /// Corona opacity before breathing and flare: `0.10 + 0.42 h` additive on dark, `0.06 + 0.2 h` on light, × 1.2 at Max.
    public static func coronaAlpha(heat h: Double, dark: Bool, max: Bool) -> Double {
        (dark ? 0.10 + 0.42 * h : 0.06 + 0.2 * h) * (max ? 1.2 : 1)
    }

    /// Corona breathing frequency (Hz) for ±15 %.
    public static func breathingRate(heat h: Double) -> Double { 0.3 + 1.7 * h }

    /// Pulse flare: +0.25 on the corona fading over 0.35 s.
    public static let coronaFlareDuration = 0.35

    public static func coronaFlare(age: Double) -> Double {
        guard age >= 0, age < coronaFlareDuration else { return 0 }
        return 0.25 * (1 - age / coronaFlareDuration)
    }

    /// The pulse flare ring from r 0.30 to 0.50 S in 0.32 s (ease-out), width 0.012 S → 0, at 55 %.
    public static let flareRingDuration = 0.32

    public static func flareRing(age: Double) -> (radius: Double, width: Double, alpha: Double)? {
        guard age >= 0, age < flareRingDuration else { return nil }
        let u = age / flareRingDuration
        let eased = 1 - pow(1 - u, 3)
        return (coreRadius + (0.5 - coreRadius) * eased, 0.012 * (1 - u), 0.55 * (1 - u))
    }

    // MARK: Glow strength

    /// Peak strength of a canvas shadow of σ around a stroke `width` wide, relative to the analytic glow (full strength
    /// at the edge whatever the size): thin strokes glow only faintly.
    public static func strokeGlow(width: Double, sigma: Double) -> Double {
        guard sigma > 0 else { return 1 }
        return erf(width / (2 * 1.41421356 * sigma))
    }
}

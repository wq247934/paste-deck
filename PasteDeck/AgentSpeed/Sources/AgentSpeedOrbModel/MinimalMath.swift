import Foundation

/// The pure numbers of the `minimal` style (DESIGN 2a.5): one progress ring that passes 100 % like an activity ring.
public enum MinimalMath {
    /// Ring radius in diameters.
    public static let radius = 0.425
    public static let minimumWidth = 2.5
    public static let blinkDuration = 0.4
    public static let tintDuration = 0.7
    public static let breathHz = 1.0
    /// Shadow of the second lap's head onto the lap below, in radians behind / ahead of the head.
    public static let shadowBehind = 0.02
    public static let shadowAhead = 0.07

    /// Ring width in points: `max(2.5 pt, 0.034 S)`, × 1.25 with Increase Contrast.
    public static func width(diameter: Double, increaseContrast: Bool) -> Double {
        max(minimumWidth, 0.034 * diameter) * (increaseContrast ? 1.25 : 1)
    }

    /// Progress `p = h + o` (0 → 2): the first lap fills to the redline, the second lap runs over it beyond.
    public static func progress(heat: Double, overdrive: Double) -> Double {
        min(2, max(0, heat + overdrive))
    }

    /// The first lap's and the second lap's extent (0...1 each).
    public static func laps(_ progress: Double) -> (first: Double, second: Double) {
        (min(1, max(0, progress)), min(1, max(0, progress - 1)))
    }

    /// Angle (degrees, clockwise from 3 o'clock) of a ring fraction, starting at 12 o'clock.
    public static func angle(_ fraction: Double) -> Double { -90 + 360 * fraction }

    /// The head of the ring (fraction of a lap) for a progress.
    public static func head(_ progress: Double) -> Double {
        let laps = laps(progress)
        return laps.second > 0 ? laps.second : laps.first
    }

    /// The redline breathing (0...1) for an accumulated phase; Reduce Motion holds it steady.
    public static func breath(phase: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : 0.5 + 0.5 * sin(phase)
    }

    /// Glow σ (diameters) and opacity: σ 0.0125 S at 35 % from boost up; in the redline tier it breathes up to
    /// σ 0.025 S at 70 %; a pulse adds 30 %. × 1.3 at Max.
    public static func glow(redline: Bool, breath: Double, blink: Double, max: Bool) -> (sigma: Double, alpha: Double) {
        let b = redline ? breath : 0
        let sigma = (0.0125 + 0.0125 * b + 0.01 * blink) * (max ? 1.3 : 1)
        let alpha = Swift.min(1, 0.35 + 0.35 * b + 0.3 * blink)
        return (sigma, alpha)
    }

    /// Head-dot opacity: the pulse blink, or 0.6 × the breath in the redline tier.
    public static func headDot(redline: Bool, breath: Double, blink: Double) -> Double {
        max(blink, redline ? 0.6 * breath : 0)
    }

    /// The pulse blink (1 → 0 over 0.4 s); Reduce Motion fades it as a 0.2 s crossfade.
    public static func blink(age: Double, reduceMotion: Bool) -> Double {
        guard age >= 0, age < blinkDuration else { return 0 }
        if reduceMotion { return 1 - NeedleMath.smoothstep(0.2, 0.4, age) }
        return 1 - age / blinkDuration
    }

    /// The new-peak gold tint: `sin(π τ / 0.7)` over 0.7 s; Reduce Motion crossfades in and out over 0.2 s.
    public static func goldTint(age: Double, reduceMotion: Bool) -> Double {
        guard age >= 0, age < tintDuration else { return 0 }
        if reduceMotion { return NeedleMath.smoothstep(0, 0.2, age) * (1 - NeedleMath.smoothstep(0.5, 0.7, age)) }
        return sin(.pi * age / tintDuration)
    }
}

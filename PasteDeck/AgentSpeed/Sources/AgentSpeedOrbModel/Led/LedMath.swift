import Foundation

/// The pure numbers of the v1.4 `led` effects (DESIGN 2.1; prototype `spec/prototypes/led-effects.html`). Radii and
/// lengths are fractions of the diameter S unless a function takes `diameter`; `h` is heat and `o` overdrive, both 0...1.
public enum LedMath {
    /// Phases advance only on rendered frames, by at most this much, so a static orb never jumps when it renders again.
    public static let maxStep = 1.0 / 15
    /// Everything outside the disc fades to zero by this radius (fraction of S) — the apps' 1.5 S window.
    public static let outerReach = 0.74

    // MARK: Phases

    /// Accumulated phases (DESIGN 2.1 table) plus the comet (turns) and a free clock (seconds) for the silk's ripple terms.
    public struct Phases: Equatable, Sendable {
        public var silk, light, flow, warp, corona, comet, clock: Double

        public init() {
            silk = 0; light = 0; flow = 0; warp = 0; corona = 0; comet = 0; clock = 0
        }
    }

    static let silkPeriod = 20000 * Double.pi
    static let clockPeriod = 10 * Double.pi
    static let streakPeriod = 4096.0

    /// Per-second rates: silk 0.12+1.4h+2.2o, light 0.05+0.5h+1.2o, flow 0.35+1.9h+1.6o, warp 0.2+1.1h+1.2o,
    /// corona 0.5+1.7h+1.8o, comet 1 / lerp(6, 0.7, h) × (1 + 0.6 o) (prototype `st.comet`), clock 1.
    public static func rates(heat h: Double, overdrive o: Double) -> Phases {
        var r = Phases()
        r.silk = 0.12 + 1.4 * h + 2.2 * o
        r.light = 0.05 + 0.5 * h + 1.2 * o
        r.flow = 0.35 + 1.9 * h + 1.6 * o
        r.warp = 0.2 + 1.1 * h + 1.2 * o
        r.corona = 0.5 + 1.7 * h + 1.8 * o
        let period = 6 + (0.7 - 6) * min(1, max(0, h))
        r.comet = (1 + 0.6 * o) / period
        r.clock = 1
        return r
    }

    /// Clamps dt to 0...maxStep, scales silk and light by `silkRate` (0 frozen, 0.5 Soft, 1), advances the comet only
    /// when `comet` is true and heat > 0.005 (prototype), then wraps: silk and light at 20000π, flow and comet at 1,
    /// warp and corona at 4096, clock at 10π (so sin(2.6 t), sin(8 t), sin(16 t) stay continuous). Returns the clamped dt.
    @discardableResult
    public static func advance(_ phases: inout Phases, heat: Double, overdrive: Double, dt: Double, silkRate: Double,
                               comet: Bool) -> Double {
        let step = clampedStep(dt)
        guard step > 0 else { return 0 }
        let r = rates(heat: heat, overdrive: overdrive)
        let silk = max(0, silkRate) * step
        phases.silk = wrap(phases.silk + r.silk * silk, silkPeriod)
        phases.light = wrap(phases.light + r.light * silk, silkPeriod)
        phases.flow = wrap(phases.flow + r.flow * step, 1)
        phases.warp = wrap(phases.warp + r.warp * step, streakPeriod)
        phases.corona = wrap(phases.corona + r.corona * step, streakPeriod)
        if comet && heat > 0.005 {
            phases.comet = wrap(phases.comet + r.comet * step, 1)
        }
        phases.clock = wrap(phases.clock + step, clockPeriod)
        return step
    }

    static func clampedStep(_ dt: Double) -> Double {
        dt.isFinite ? min(max(dt, 0), maxStep) : 0
    }

    static func wrap(_ x: Double, _ period: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    // MARK: Shaping

    /// GLSL `smoothstep`; `e0 > e1` gives the falling edge.
    public static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        guard e0 != e1 else { return x < e0 ? 0 : 1 }
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// 1 − (1 − clamp(t))³
    public static func easeOut(_ t: Double) -> Double {
        let u = 1 - min(1, max(0, t))
        return 1 - u * u * u
    }

    static func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    // MARK: Silk, flow, flare, comets

    /// act = smoothstep(0, 0.08, h)
    public static func activity(heat: Double) -> Double { smoothstep(0, 0.08, heat) }

    /// Silk brightness (0.3 + 0.65 act + 0.3 h + 0.25 o)(1 + 0.35 (lvl − 1)).
    public static func silkBrightness(heat h: Double, overdrive o: Double, lvl: Double) -> Double {
        (0.3 + 0.65 * activity(heat: h) + 0.3 * h + 0.25 * o) * (1 + 0.35 * (lvl - 1))
    }

    /// rip = min(1, 2.5 o).
    public static func ripple(overdrive o: Double) -> Double { min(1, max(0, 2.5 * o)) }

    public static let segments = 36

    /// Gauge flow of segment i (0...35): (1 − fract(2.2 i / 36 − φflow))^9 · act · (0.5 + 0.9 h).
    public static func flow(segment i: Int, phase: Double, heat h: Double) -> Double {
        let ph = fract(2.2 * Double(i) / Double(segments) - phase)
        return pow(1 - ph, 9) * activity(heat: h) * (0.5 + 0.9 * h)
    }

    /// Tip flare amount smoothstep(0.5, 0.85, h)(0.55 + 0.9 o) lvl, and its two line scales (fractions of S):
    /// tangential length 0.05 + 0.16 o, radial length 0.035 + 0.09 o; thin widths 0.0032 and 0.0028.
    public static func flareAmount(heat h: Double, overdrive o: Double, lvl: Double) -> Double {
        smoothstep(0.5, 0.85, h) * (0.55 + 0.9 * o) * lvl
    }

    public static func flareLengths(overdrive o: Double) -> (tangential: Double, radial: Double) {
        (0.05 + 0.16 * o, 0.035 + 0.09 * o)
    }

    /// The thin widths of the tangential and the radial line.
    public static let flareTangentialWidth = 0.0032
    public static let flareRadialWidth = 0.0028

    /// Comet tail in degrees: 40° + 60° h.
    public static func cometTail(heat h: Double) -> Double { 40 + 60 * h }

    /// No comet up to h 0.01 (prototype); a second one (half a turn behind, 70 %) only when h > 0.55 and allowed.
    public static func cometCount(heat h: Double, maxComets: Int) -> Int {
        guard maxComets > 0, h > 0.01 else { return 0 }
        return maxComets >= 2 && h > 0.55 ? 2 : 1
    }

    public static let secondCometOpacity = 0.7

    // MARK: Corona

    /// Corona amount smoothstep(0.45, 0.85, h)(0.45 + 0.55 o) lvl; corona annulus 0.47...0.74 S and its outer fade
    /// smoothstep(0.74, 0.64, r) (prototype fades by 0.81 — the app clamps to 0.74).
    public static func coronaAmount(heat h: Double, overdrive o: Double, lvl: Double) -> Double {
        smoothstep(0.45, 0.85, h) * (0.45 + 0.55 * o) * lvl
    }

    public static let coronaInner = 0.47
    public static let coronaOuter = outerReach

    /// The outer fade of the corona at radius `r` (fraction of S), zero outside the annulus.
    public static func coronaFade(radius r: Double) -> Double {
        guard r > coronaInner, r < coronaOuter else { return 0 }
        return smoothstep(0.74, 0.64, r)
    }

    /// Corona flame reach 0.02 + (0.06 h + 0.12 o) · 1.7 · body^1.4 (body in 0...1).
    public static func coronaReach(heat h: Double, overdrive o: Double, body: Double) -> Double {
        0.02 + (0.06 * h + 0.12 * o) * 1.7 * pow(min(1, max(0, body)), 1.4)
    }

    // MARK: Warp streaks

    /// Warp streaks: amount smoothstep(0.32, 0.62, h) lvl; 96 bins; a bin is active when hash < 0.18 + 0.42 h; head from
    /// 0.74 (prototype 0.9) to 0.51 at fract(seed·7.3 + φwarp (0.55 + 0.9 seed)); length (0.02 + 0.08h + 0.07o)(0.55+seed);
    /// width 0.0018 + 0.001 h; fade-in over the first 30 % of travel, out over the last 18 %.
    public static let warpBins = 96
    public static let warpStart = 0.74, warpEnd = 0.51

    public static func warpAmount(heat h: Double, lvl: Double) -> Double { smoothstep(0.32, 0.62, h) * lvl }

    /// hash11(bin + 3) = fract(sin((bin+3)·127.1)·43758.5453)
    public static func warpSeed(bin: Int) -> Double { fract(sin(Double(bin + 3) * 127.1) * 43758.5453) }

    public static func warpActive(seed: Double, heat h: Double) -> Bool { seed < 0.18 + 0.42 * h }

    /// 0...1
    public static func warpHeadTravel(seed: Double, phase: Double) -> Double {
        fract(seed * 7.3 + phase * (0.55 + 0.9 * seed))
    }

    /// radius / S, always within 0.51...0.74
    public static func warpHead(seed: Double, phase: Double) -> Double {
        let travel = min(1, max(0, warpHeadTravel(seed: seed, phase: phase)))
        return min(warpStart, max(warpEnd, warpStart + (warpEnd - warpStart) * travel))
    }

    public static func warpLength(heat h: Double, overdrive o: Double, seed: Double) -> Double {
        (0.02 + 0.08 * h + 0.07 * o) * (0.55 + seed)
    }

    public static func warpWidth(heat h: Double) -> Double { 0.0018 + 0.001 * h }

    public static func warpFade(travel: Double) -> Double {
        smoothstep(0, 0.3, travel) * smoothstep(1, 0.82, travel)
    }

    // MARK: Pulse and new peak

    /// Response pulse (0.85 s): shock ring radius 0.5 + travel·easeOut(age) with travel = min(0.24, reach − 0.51) (reach
    /// 0.75 floating → 0.74), wake 0.5 + min(0.16, reach − 0.51)·easeOut(1.3 age); age in 0...1.
    public static let pulseDuration = 0.85

    public static func shockRadius(age: Double, reach: Double) -> Double {
        0.5 + min(0.24, max(0, reach - 0.51)) * easeOut(age)
    }

    public static func wakeRadius(age: Double, reach: Double) -> Double {
        0.5 + min(0.16, max(0, reach - 0.51)) * easeOut(1.3 * age)
    }

    /// New peak: gold ring 0.5 → min(0.74, reach − 0.01) S over 1.4 s (easeOut); rays from 0.5 S to
    /// 0.55 + (reach − 0.56)·easeOut(1.4 k) with k = t / 1.3 (prototype 0.55 + 0.35, clamped to 0.74); disc flash 0.75 e^(−4.5 t).
    /// `age` is seconds since the peak.
    public static let peakRingDuration = 1.4
    public static let peakRayDuration = 1.3

    public static func peakRingRadius(age: Double, reach: Double) -> Double {
        let end = min(outerReach, reach - 0.01)
        return 0.5 + max(0, end - 0.5) * easeOut(age / peakRingDuration)
    }

    public static func peakRayReach(age: Double, reach: Double) -> Double {
        let end = min(outerReach, reach - 0.01)
        return 0.55 + max(0, end - 0.55) * easeOut(1.4 * age / peakRayDuration)
    }

    public static func peakFlash(age: Double) -> Double {
        guard age >= 0 else { return 0 }
        return 0.75 * exp(-4.5 * age)
    }

    // MARK: Particles and readout

    /// Particles fade out by 0.74 S: 1 up to 0.66 S, smoothstep down to 0 at 0.74 S (`r` = distance / S).
    public static func particleFade(radius r: Double) -> Double { smoothstep(outerReach, 0.66, r) }

    /// Readout (layer 6): lean 7.5° h, jitter 0.9 + 1.2 o (points at 148), chromatic offset (0.6 + 1.6 o) S / 300,
    /// glow σ factor 1 + 0.8 o, wide glow 2.4×.
    /// The lean is the italic slant magnitude (the prototype's CSS `skewX(−7.5° h)`).
    public static func leanDegrees(heat h: Double) -> Double { 7.5 * h }

    public static func jitter(overdrive o: Double) -> Double { 0.9 + 1.2 * o }

    public static func chromaOffset(overdrive o: Double, diameter: Double) -> Double { (0.6 + 1.6 * o) * diameter / 300 }

    public static func glowScale(overdrive o: Double) -> Double { 1 + 0.8 * o }

    public static let wideGlow = 2.4
}

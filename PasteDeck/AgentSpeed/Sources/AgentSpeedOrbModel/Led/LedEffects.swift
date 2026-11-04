import Foundation

/// The effects-level table of DESIGN 2.1 for `led`, after the caps. `level`: 0 Off, 1 Soft, 2 Standard, 3 Max.
/// Reduce Motion caps at Soft (and freezes the silk, no lightning); `floating` false = dashboard hero (no silk);
/// `small` = S < 120 (LOD: spark, ember and bolt counts halved); `thumbnail` = Settings previews (silk static, no
/// corona or warp streaks).
public struct LedEffects: Equatable, Sendable {
    /// After the Reduce Motion cap.
    public let level: Int
    /// 1.6 at Max, else 1.
    public var lvl: Double
    /// Floating orbs only (every level).
    public var silk: Bool
    /// 0 Off / Reduce Motion / thumbnail, 0.5 Soft, 1 Standard and Max.
    public var silkRate: Double
    /// Overdrive ripple packets in the silk: Standard and Max.
    public var silkRipples: Bool
    /// The response-pulse ripple in the cloth: Soft and up, not Reduce Motion.
    public var silkWaves: Bool
    public var flow: Bool
    public var tipFlare: Bool
    public var corona: Bool
    public var warp: Bool
    /// 0 Off or Reduce Motion, 1 Soft, 2 Standard and Max.
    public var maxComets: Int
    public var pulses: Bool
    public var particles: Bool
    public var arcs: Bool
    public var lightning: Bool
    public var jitter: Bool
    public var chromaticSplit: Bool
    public var skew: Bool
    /// 0.5 when small, else 1.
    public var countScale: Double
    /// 16, 8 when small.
    public var boltCap: Int

    public init(level: Int, reduceMotion: Bool, floating: Bool, small: Bool, thumbnail: Bool) {
        let capped = min(max(level, 0), reduceMotion ? 1 : 3)
        let standard = capped >= 2
        self.level = capped
        lvl = capped == 3 ? 1.6 : 1
        silk = floating
        silkRate = capped == 0 || reduceMotion || thumbnail ? 0 : (standard ? 1 : 0.5)
        silkRipples = floating && standard
        silkWaves = floating && capped >= 1 && !reduceMotion
        flow = standard
        tipFlare = standard
        corona = standard && !thumbnail
        warp = standard && !thumbnail
        maxComets = capped == 0 || reduceMotion ? 0 : (standard ? 2 : 1)
        pulses = capped >= 1
        particles = standard
        arcs = standard
        lightning = standard && !reduceMotion
        jitter = standard
        chromaticSplit = standard
        skew = standard
        countScale = small ? 0.5 : 1
        boltCap = small ? LedLightning.maxBolts / 2 : LedLightning.maxBolts
    }

    /// Bolts per changed digit after LOD: `(n + 1) / 2` when small.
    public func boltsPerDigit(_ n: Int) -> Int {
        countScale < 1 ? (max(0, n) + 1) / 2 : max(0, n)
    }
}

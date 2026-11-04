import Foundation
import simd

/// Straight-alpha sRGB colors of the vehicle layer and the OKLab mix DESIGN 4c asks for.
public enum HeroColor {
    public static func rgb(_ hex: UInt32, alpha: Float = 1) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, alpha)
    }

    public static let whiteHot = rgb(0xFFF7D6)
    public static let amberHot = rgb(0xFFB020)

    /// Perceptual blend through OKLab (alpha blends linearly).
    public static func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Double) -> SIMD4<Float> {
        let t = Float(HeroMath.clamp(t, 0, 1))
        if t == 0 { return a }
        if t == 1 { return b }
        let la = lab(a), lb = lab(b)
        let mixed = la + (lb - la) * t
        var out = rgb(fromLab: mixed)
        out.w = a.w + (b.w - a.w) * t
        return out
    }

    @inlinable public static func withAlpha(_ color: SIMD4<Float>, _ alpha: Double) -> SIMD4<Float> {
        SIMD4(color.x, color.y, color.z, color.w * Float(alpha))
    }

    private static func linear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Float) -> Float {
        let c = min(1, max(0, c))
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func lab(_ color: SIMD4<Float>) -> SIMD3<Float> {
        let r = linear(color.x), g = linear(color.y), b = linear(color.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    private static func rgb(fromLab lab: SIMD3<Float>) -> SIMD4<Float> {
        let l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return SIMD4(
            gamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            gamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            gamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3),
            1
        )
    }
}

/// The colors of one frame (DESIGN 4c, Color and glow), resolved by the app from the heat palette.
public struct HeroPaint: Sendable, Equatable {
    /// Stroke color `C` (already mixed from the idle slate by `wake`).
    public var stroke: SIMD4<Float>
    /// Accent `H` for `light` and `glow` roles and flame outlines.
    public var hot: SIMD4<Float>
    /// Flame core fill.
    public var core: SIMD4<Float>
    /// Idle light band color and peak strength.
    public var sweep: SIMD4<Float>
    public var dark: Bool
    public var increaseContrast: Bool

    public init(stroke: SIMD4<Float>, hot: SIMD4<Float>, core: SIMD4<Float>, sweep: SIMD4<Float>, dark: Bool,
                increaseContrast: Bool) {
        self.stroke = stroke
        self.hot = hot
        self.core = core
        self.sweep = sweep
        self.dark = dark
        self.increaseContrast = increaseContrast
    }
}

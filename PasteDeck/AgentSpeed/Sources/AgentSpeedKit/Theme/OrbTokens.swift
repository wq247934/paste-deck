import SwiftUI

/// Appearance tokens of the orb (DESIGN section 2 token table).
struct OrbTokens: Sendable {
    let isDark: Bool
    let bodyTop: RGBColor
    let bodyBottom: RGBColor
    let bodyOpacity: Double
    let rimTop: RGBColor
    let outerStroke: RGBColor?
    let shadow: RGBColor
    let shadowOffset: Double
    let shadowBlur: Double
    let unlitSegment: RGBColor
    let valueText: RGBColor
    let idleValueText: RGBColor
    let secondaryText: RGBColor
    let auraOpacity: Double
    let additive: Bool
    let particleScale: Double
    let lens: RGBColor
    let innerShadow: RGBColor

    static let dark = OrbTokens(
        isDark: true,
        bodyTop: RGBColor(hex: 0x1B2030),
        bodyBottom: RGBColor(hex: 0x090B10),
        bodyOpacity: 0.88,
        rimTop: RGBColor.white.opacity(0.14),
        outerStroke: RGBColor.black.opacity(0.35),
        shadow: RGBColor.black.opacity(0.45),
        shadowOffset: 0.03,
        shadowBlur: 0.10,
        unlitSegment: RGBColor.white.opacity(0.07),
        valueText: RGBColor.white.opacity(0.96),
        idleValueText: RGBColor.white.opacity(0.60),
        secondaryText: RGBColor.white.opacity(0.55),
        auraOpacity: 0.55,
        additive: true,
        particleScale: 1,
        lens: RGBColor.white.opacity(0.06),
        innerShadow: RGBColor.black.opacity(0.55)
    )

    static let light = OrbTokens(
        isDark: false,
        bodyTop: RGBColor(hex: 0xFFFFFF),
        bodyBottom: RGBColor(hex: 0xE7EBF3),
        bodyOpacity: 0.86,
        rimTop: RGBColor.white.opacity(0.95),
        outerStroke: RGBColor.black.opacity(0.08),
        shadow: RGBColor.black.opacity(0.16),
        shadowOffset: 0.04,
        shadowBlur: 0.12,
        unlitSegment: RGBColor.black.opacity(0.08),
        valueText: RGBColor(hex: 0x0B0D12, alpha: 0.92),
        idleValueText: RGBColor(hex: 0x0B0D12, alpha: 0.55),
        secondaryText: RGBColor.black.opacity(0.50),
        auraOpacity: 0.32,
        additive: false,
        particleScale: 1.2,
        lens: RGBColor.white.opacity(0.7),
        innerShadow: RGBColor(hex: 0x1B2340, alpha: 0.16)
    )

    static func forScheme(_ scheme: ColorScheme) -> OrbTokens {
        scheme == .dark ? .dark : .light
    }

    func heat(_ h: Double) -> RGBColor { HeatPalette.color(h, dark: isDark) }

    /// Tier label color: heat color on dark, darkened 18 % (OKLab L) on light.
    func tierColor(_ h: Double) -> RGBColor { HeatPalette.color(h, dark: isDark) }

    func leadingSegment(_ h: Double, overdrive: Double) -> RGBColor {
        isDark ? HeatPalette.whiteHot.mixOKLab(.white, overdrive * 0.4) : HeatPalette.color(h).mixOKLab(HeatPalette.amberHot, 0.2 + 0.3 * overdrive)
    }

    func sparkHot(_ h: Double) -> RGBColor { isDark ? HeatPalette.whiteHot : HeatPalette.amberHot }
}

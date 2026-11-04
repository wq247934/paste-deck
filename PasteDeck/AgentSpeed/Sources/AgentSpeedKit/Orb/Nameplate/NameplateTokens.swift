import AppKit

/// The plate's material (DESIGN 2b, Name plate, Material): the orb's own glass, with the Reduce Transparency and
/// Increase Contrast variants. Colors are sRGB.
struct NameplateTokens: Equatable {
    let isDark: Bool
    /// No desktop blur behind: the solid fills of Reduce Transparency.
    let solid: Bool
    let increaseContrast: Bool
    let fillTop: RGBColor
    let fillBottom: RGBColor
    let rimTop: RGBColor
    let rimBottom: RGBColor
    let outerStroke: RGBColor
    let outerWidth: CGFloat
    let shadow: RGBColor
    let text: RGBColor
    let secondary: RGBColor
    /// The 1 pt ring that separates overlapping dots, in the plate color.
    let separator: RGBColor
    let accent: RGBColor

    init(dark: Bool, reduceTransparency: Bool, increaseContrast: Bool) {
        isDark = dark
        solid = reduceTransparency
        self.increaseContrast = increaseContrast
        let contrast = increaseContrast
        if dark {
            fillTop = reduceTransparency ? RGBColor(hex: 0x1F2432) : RGBColor(red: 32 / 255, green: 37 / 255, blue: 52 / 255, alpha: contrast ? 0.92 : 0.72)
            fillBottom = reduceTransparency ? RGBColor(hex: 0x0E1016) : RGBColor(red: 12 / 255, green: 14 / 255, blue: 20 / 255, alpha: contrast ? 0.96 : 0.80)
            rimTop = RGBColor.white.opacity(0.16)
            rimBottom = RGBColor.white.opacity(0.04)
            outerStroke = contrast ? RGBColor.white.opacity(0.42) : RGBColor.black.opacity(0.35)
            shadow = RGBColor.black.opacity(0.38)
            text = RGBColor.white.opacity(contrast ? 1 : 0.92)
            secondary = RGBColor.white.opacity(contrast ? 0.78 : 0.66)
            separator = RGBColor(red: 22 / 255, green: 25 / 255, blue: 34 / 255)
        } else {
            fillTop = reduceTransparency ? RGBColor(hex: 0xFFFFFF) : RGBColor(red: 1, green: 1, blue: 1, alpha: contrast ? 0.96 : 0.80)
            fillBottom = reduceTransparency ? RGBColor(hex: 0xF0F2F6) : RGBColor(red: 241 / 255, green: 243 / 255, blue: 248 / 255, alpha: contrast ? 0.96 : 0.84)
            rimTop = RGBColor.white.opacity(0.95)
            rimBottom = RGBColor.white.opacity(0)
            outerStroke = RGBColor.black.opacity(contrast ? 0.45 : 0.10)
            shadow = RGBColor.black.opacity(0.14)
            text = RGBColor(hex: 0x0B0D12, alpha: contrast ? 1 : 0.88)
            secondary = RGBColor.black.opacity(contrast ? 0.72 : 0.60)
            separator = RGBColor(red: 246 / 255, green: 247 / 255, blue: 250 / 255)
        }
        outerWidth = contrast ? 1 : 0.5
        accent = Self.accent(dark: dark)
    }

    /// The system accent as it resolves on this plate's appearance.
    private static func accent(dark: Bool) -> RGBColor {
        var color = RGBColor(hex: dark ? 0x4D9CFF : 0x0A64D6)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            if let resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                color = RGBColor(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
            }
        }
        return color
    }

    /// A source's dot color: the bezel's (light: darkened 10 %).
    func dotColor(_ tint: RGBColor) -> RGBColor {
        isDark ? tint : tint.darkened(0.1)
    }
}

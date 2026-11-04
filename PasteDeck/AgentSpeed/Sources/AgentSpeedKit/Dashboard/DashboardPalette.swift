import SwiftUI

/// De-emphasized text that keeps at least 4.5:1 contrast on the popover in both appearances
/// (the system secondary label color falls just short of that on light glass).
struct DashboardSecondaryStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        DashboardPalette.secondary(
            dark: environment.colorScheme == .dark,
            increasedContrast: environment.colorSchemeContrast == .increased
        )
    }
}

extension ShapeStyle where Self == DashboardSecondaryStyle {
    static var dashboardSecondary: DashboardSecondaryStyle { DashboardSecondaryStyle() }
}

enum DashboardPalette {
    /// Conservative stand-ins for the popover material, used to verify text contrast.
    static let lightSurface = RGBColor(hex: 0xE6E6E6)
    static let darkSurface = RGBColor(hex: 0x3A3A3A)

    static func secondary(dark: Bool, increasedContrast: Bool) -> Color {
        if dark {
            return Color.white.opacity(increasedContrast ? 0.82 : 0.64)
        }
        return Color.black.opacity(increasedContrast ? 0.8 : 0.62)
    }

    /// Faint strokes: grid lines, connectors, tracks.
    static func rule(dark: Bool, increasedContrast: Bool) -> Color {
        let base = dark ? Color.white : Color.black
        return base.opacity(increasedContrast ? 0.34 : (dark ? 0.16 : 0.13))
    }

    /// The amber of speed bolts and the looping mark (DESIGN 4).
    static func amber(dark: Bool) -> RGBColor { RGBColor(hex: dark ? 0xF5A524 : 0xB86E00) }

    /// Heat color legible as text: the palette color, pushed in OKLab lightness until it reaches the contrast target.
    static func heatText(_ heat: Double, dark: Bool, increasedContrast: Bool) -> Color {
        legible(HeatPalette.color(heat, dark: dark), dark: dark, minimum: increasedContrast ? 7 : 4.5).color
    }

    /// Heat color for strokes and glyphs (3:1 is enough for non-text graphics).
    static func heatGraphic(_ heat: Double, dark: Bool, increasedContrast: Bool) -> RGBColor {
        legible(HeatPalette.color(heat, dark: dark), dark: dark, minimum: increasedContrast ? 4.5 : 3)
    }

    static func legible(_ color: RGBColor, dark: Bool, minimum: Double) -> RGBColor {
        let surface = dark ? darkSurface : lightSurface
        var lab = OKLab(color)
        var candidate = color
        for _ in 0..<40 {
            if contrast(candidate, surface) >= minimum { return candidate }
            lab.l = (lab.l + (dark ? 0.015 : -0.015)).clamped(to: 0...1)
            candidate = lab.rgb(alpha: color.alpha)
        }
        return candidate
    }

    static func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ color: RGBColor) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}

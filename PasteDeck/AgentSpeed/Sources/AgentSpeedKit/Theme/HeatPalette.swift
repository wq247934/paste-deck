import SwiftUI

/// Speed → heat mapping and the heat color ramp (DESIGN section 1).
enum HeatPalette {
    static let stops: [(Double, RGBColor)] = [
        (0.00, RGBColor(hex: 0x7C8798)),
        (0.10, RGBColor(hex: 0x2DD4BF)),
        (0.30, RGBColor(hex: 0x38BDF8)),
        (0.48, RGBColor(hex: 0x818CF8)),
        (0.64, RGBColor(hex: 0xE879F9)),
        (0.78, RGBColor(hex: 0xFB7185)),
        (0.90, RGBColor(hex: 0xFB923C)),
        (1.00, RGBColor(hex: 0xFACC15)),
    ]

    static let whiteHot = RGBColor(hex: 0xFFF7D6)
    static let amberHot = RGBColor(hex: 0xFFB020)
    static let gold = RGBColor(hex: 0xFACC15)

    private static let lut: [RGBColor] = (0...255).map { index in
        interpolate(Double(index) / 255)
    }

    static func heat(value: Double, redline: Double) -> Double {
        guard value > 0, redline > 0 else { return 0 }
        return min(1, pow(value / redline, 0.6))
    }

    static func overdrive(value: Double, redline: Double) -> Double {
        guard redline > 0 else { return 0 }
        return ((value - redline) / redline).clamped(to: 0...1)
    }

    /// Inverse of `heat` for placing threshold ticks.
    static func heat(forFraction fraction: Double) -> Double {
        min(1, pow(max(fraction, 0), 0.6))
    }

    static func color(_ h: Double) -> RGBColor {
        guard h.isFinite else { return stops[0].1 }
        let position = h.clamped(to: 0...1) * 255
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, 255)
        return lut[lower].mix(lut[upper], position - Double(lower))
    }

    /// Heat color tuned for the current appearance (darker on light surfaces for ≥ 3:1 contrast).
    static func color(_ h: Double, dark: Bool) -> RGBColor {
        dark ? color(h) : color(h).darkened(0.18)
    }

    /// Highlight color for the leading edge: white-hot core, blended further toward white-hot with overdrive.
    static func highlight(_ h: Double, overdrive: Double, dark: Bool) -> RGBColor {
        if dark {
            return color(h).mixOKLab(whiteHot, 0.7 + 0.3 * overdrive)
        }
        return color(h).mixOKLab(amberHot, 0.25 * overdrive)
    }

    private static func interpolate(_ h: Double) -> RGBColor {
        for index in 1..<stops.count where h <= stops[index].0 {
            let (h0, c0) = stops[index - 1]
            let (h1, c1) = stops[index]
            return c0.mixOKLab(c1, (h - h0) / (h1 - h0))
        }
        return stops[stops.count - 1].1
    }
}

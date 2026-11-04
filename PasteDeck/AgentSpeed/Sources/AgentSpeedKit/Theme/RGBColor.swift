import AppKit
import SwiftUI

/// Linear-light friendly sRGB color with OKLab interpolation helpers.
public struct RGBColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public func opacity(_ value: Double) -> RGBColor {
        var copy = self
        copy.alpha = alpha * value
        return copy
    }

    /// Blends in sRGB space (used for small highlight mixes).
    public func mix(_ other: RGBColor, _ t: Double) -> RGBColor {
        let t = t.clamped(to: 0...1)
        return RGBColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    /// Perceptual blend through OKLab.
    public func mixOKLab(_ other: RGBColor, _ t: Double) -> RGBColor {
        let t = t.clamped(to: 0...1)
        let a = OKLab(self), b = OKLab(other)
        let lab = OKLab(
            l: a.l + (b.l - a.l) * t,
            a: a.a + (b.a - a.a) * t,
            b: a.b + (b.b - a.b) * t
        )
        return lab.rgb(alpha: alpha + (other.alpha - alpha) * t)
    }

    /// Lowers OKLab lightness by a relative amount (e.g. 0.18 for 18 %).
    public func darkened(_ amount: Double) -> RGBColor {
        var lab = OKLab(self)
        lab.l *= (1 - amount)
        return lab.rgb(alpha: alpha)
    }

    public func brightened(_ amount: Double) -> RGBColor {
        mix(.white, amount)
    }

    public func scaled(_ factor: Double) -> RGBColor {
        RGBColor(
            red: (red * factor).clamped(to: 0...1),
            green: (green * factor).clamped(to: 0...1),
            blue: (blue * factor).clamped(to: 0...1),
            alpha: alpha
        )
    }
}

struct OKLab {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ color: RGBColor) {
        let r = Self.linear(color.red), g = Self.linear(color.green), bl = Self.linear(color.blue)
        let lc = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let mc = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let sc = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc
        a = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc
        b = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
    }

    func rgb(alpha: Double) -> RGBColor {
        let lc = l + 0.3963377774 * a + 0.2158037573 * b
        let mc = l - 0.1055613458 * a - 0.0638541728 * b
        let sc = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = lc * lc * lc, m3 = mc * mc * mc, s3 = sc * sc * sc
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        return RGBColor(red: Self.gamma(r), green: Self.gamma(g), blue: Self.gamma(bl), alpha: alpha)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        let c = c.clamped(to: 0...1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

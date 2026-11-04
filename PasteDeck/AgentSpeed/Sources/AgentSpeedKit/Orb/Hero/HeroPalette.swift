import AgentSpeedHero
import Foundation

/// The vehicle layer's colors (DESIGN 4c, Color and glow): the stroke follows the title label (heat color on dark,
/// `heatText` on light), the accent mixes toward white-hot (dark) or amber (light), and a parked vehicle is slate.
struct HeroPalette {
    private struct Key: Equatable {
        var heat: Double
        var overdrive: Double
        var wake: Double
        var dark: Bool
        var increaseContrast: Bool
    }

    private var key: Key?
    private var cached: HeroPaint?

    /// `C` for heat `h` before the idle mix.
    static func stroke(_ h: Double, dark: Bool, increaseContrast: Bool) -> RGBColor {
        if dark {
            let color = HeatPalette.color(h)
            return increaseContrast ? DashboardPalette.legible(color, dark: true, minimum: 4.5) : color
        }
        return DashboardPalette.legible(HeatPalette.color(h, dark: false), dark: false, minimum: increaseContrast ? 7 : 4.5)
    }

    mutating func paint(heat: Double, overdrive: Double, wake: Double, dark: Bool, increaseContrast: Bool) -> HeroPaint {
        let key = Key(
            heat: (heat * 2000).rounded() / 2000,
            overdrive: (overdrive * 2000).rounded() / 2000,
            wake: (wake * 1000).rounded() / 1000,
            dark: dark,
            increaseContrast: increaseContrast
        )
        if key == self.key, let cached { return cached }
        let idle = Self.stroke(0, dark: dark, increaseContrast: increaseContrast)
        let awake = Self.stroke(key.heat, dark: dark, increaseContrast: increaseContrast)
        let hot = dark
            ? awake.mixOKLab(HeatPalette.whiteHot, 0.65 + 0.35 * key.overdrive)
            : awake.mixOKLab(HeatPalette.amberHot, 0.45)
        let core = dark ? HeatPalette.whiteHot.mixOKLab(.white, key.overdrive) : HeatPalette.amberHot
        let sweep = dark ? HeatPalette.whiteHot.opacity(0.75) : idle.opacity(0.6)
        let paint = HeroPaint(
            stroke: idle.mixOKLab(awake, key.wake).simd,
            hot: idle.mixOKLab(hot, key.wake).simd,
            core: core.simd,
            sweep: sweep.simd,
            dark: dark,
            increaseContrast: increaseContrast
        )
        self.key = key
        cached = paint
        return paint
    }
}

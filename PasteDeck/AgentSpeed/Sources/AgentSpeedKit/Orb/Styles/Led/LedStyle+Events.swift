import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// Response pulses and the new peak of `led` (DESIGN 2 layers 7–8 with 2.1): the shockwave with its soft wake, and the
/// disc flash, gold ring, 24 turning rays and spark burst of a new peak. Reduce Motion keeps the v1.3 crossfades.
extension LedStyle {
    static let ringGold = RGBColor(red: 1, green: 0.78, blue: 0.3)

    func addPulses(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !pulses.isEmpty else { return }
        let s = frame.s
        for pulse in pulses {
            let age = pulseAge(pulse, at: frame.time)
            guard age >= 0, age < 1 else { continue }
            let heat = HeatPalette.color(pulse.heat)
            if frame.effects.reduceMotion {
                let color = frame.dark ? heat.mixOKLab(HeatPalette.whiteHot, 0.18) : HeatPalette.color(pulse.heat, dark: false)
                scene.add(.ring(center: frame.center, radius: 0.53 * s, width: 2 * frame.unit,
                                color: color.opacity(0.5 * sin(.pi * age) * pulse.strength), glow: 3 * frame.unit, glowAlpha: 0.35),
                          blend: frame.glowBlend)
                continue
            }
            let width = ((0.005 + 0.005 * pulse.strength) * (1 - age) + 0.001) * s
            let shock = frame.dark ? heat.mix(HeatPalette.whiteHot, 0.3) : heat.inked
            scene.add(.ring(center: frame.center, radius: LedMath.shockRadius(age: age, reach: frame.reach) * s, width: 0,
                            color: shock.opacity((1 - age) * 0.7 * pulse.strength * (frame.dark ? 1 : 0.6)), core: 0,
                            glow: width, glowAlpha: 1), blend: frame.glowBlend)
            let wake = frame.dark ? heat : heat.inked
            scene.add(.ring(center: frame.center, radius: LedMath.wakeRadius(age: age, reach: frame.reach) * s, width: 0,
                            color: wake.opacity((1 - age) * 0.3 * pulse.strength), core: 0, glow: width * 3.5, glowAlpha: 1),
                      blend: frame.glowBlend)
        }
    }

    func addPeak(_ scene: inout OrbScene, _ frame: OrbFrame) {
        let t = frame.peakAge
        guard frame.effects.celebrate, t >= 0, t < 1.4 else { return }
        let s = frame.s
        // The disc flashes: full within 0.15 S, fading to zero at 0.6 S.
        let flash = LedMath.peakFlash(age: t)
        if flash > 0.0075 {
            let color = frame.dark ? HeatPalette.whiteHot.opacity(flash) : RGBColor(hex: 0xFFB021).opacity(0.35 / 0.75 * flash)
            scene.add(.softDisc(center: frame.center, inner: 0.15 * s, outer: 0.6 * s, color: color), blend: frame.glowBlend)
        }
        if frame.effects.reduceMotion {
            let p = t / 1.4
            let gold = frame.dark ? HeatPalette.gold.mixOKLab(HeatPalette.whiteHot, 0.25) : HeatPalette.gold.darkened(0.1)
            scene.add(.ring(center: frame.center, radius: 0.54 * s, width: 3 * frame.unit, color: gold.opacity(0.45 * sin(.pi * p)),
                            glow: 4 * frame.unit, glowAlpha: 0.4), blend: frame.glowBlend)
            return
        }
        // A gold ring blows outward.
        let ring = LedMath.peakRingRadius(age: t, reach: frame.reach)
        scene.add(.ring(center: frame.center, radius: ring * s, width: 0, color: Self.ringGold.opacity(1 - t / 1.4), core: 0,
                        glow: (0.012 + 0.02 * t) * s, glowAlpha: 1), blend: frame.glowBlend)
        addPeakRays(&scene, frame, age: t)
    }

    /// 24 gold rays turning at 0.4 rad/s, each a gradient 0 → 75 % at 30 % of its length → 0.
    private func addPeakRays(_ scene: inout OrbScene, _ frame: OrbFrame, age t: Double) {
        guard t < 1.3 else { return }
        let s = frame.s
        let k = t / 1.3
        let r0 = 0.5 * s
        let r1 = LedMath.peakRayReach(age: t, reach: frame.reach) * s
        let peak = 0.75 * (1 - k)
        let width = s * 0.014 * (1 - 0.5 * k)
        let start = RGBColor(red: 1, green: 0.85, blue: 0.35, alpha: 0)
        let middle = RGBColor(red: 1, green: 0.8, blue: 0.3, alpha: peak)
        let end = RGBColor(red: 1, green: 0.7, blue: 0.2, alpha: 0)
        let rm = r0 + 0.3 * (r1 - r0)
        for index in 0..<24 {
            let angle = t * 0.4 + Double(index) / 24 * 2 * .pi
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let degrees = angle * 180 / .pi
            // Two abutting butt-ended pieces, so the peak is not drawn twice where they meet.
            func piece(_ from: CGFloat, _ to: CGFloat, _ a: RGBColor, _ b: RGBColor) {
                let length = to - from
                guard length > 0.1 else { return }
                let mid = (from + to) / 2
                let center = CGPoint(x: frame.center.x + direction.x * mid, y: frame.center.y + direction.y * mid)
                scene.add(OrbInstance.roundedRect(center: center, halfSize: CGSize(width: length / 2, height: width / 2),
                                                  rotation: angle, corner: 0, color: a)
                    .linearGradient(to: b, angle: degrees, halfLength: length / 2), blend: frame.glowBlend)
            }
            piece(r0, rm, start, middle)
            piece(rm, r1, middle, end)
        }
    }
}

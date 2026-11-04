import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// The gauge (DESIGN 2 layers 3–4, 2.1): 36 segments with the energy flow, tier tick dots, the tip flare and the comets.
extension LedStyle {
    private struct SegmentLight {
        var brightness: Double
        var whiteness: Double
    }

    /// Brightness of each segment (the last lit one partially) and its share of white-hot near the leading edge.
    private static func light(_ index: Int, lit: Double) -> SegmentLight {
        let brightness = (lit - Double(index)).clamped(to: 0...1)
        guard brightness > 0 else { return SegmentLight(brightness: 0, whiteness: 0) }
        let distance = lit - Double(index + 1)
        let whiteness = distance < 0 ? 1 : (1 - distance).clamped(to: 0...1)
        return SegmentLight(brightness: brightness, whiteness: whiteness)
    }

    /// Segment `i` takes the heat color of its own position (`i / 35`); the first few are lifted off the idle slate
    /// so a lit segment never reads as unlit.
    private static func segmentColor(_ index: Int, _ frame: OrbFrame) -> RGBColor {
        let h = max(0.07, Double(index) / Double(OrbGeometry.segmentCount - 1))
        return frame.dark ? HeatPalette.color(h) : HeatPalette.color(h).darkened(0.06)
    }

    private static func shimmer(_ index: Int, _ frame: OrbFrame) -> Double {
        guard frame.effects.shimmer, frame.redlineAmount > 0.001 else { return 1 }
        let tick = Int((frame.time * 12).rounded(.down))
        let random = 0.75 + 0.25 * Noise.hash(index, tick)
        return 1 - (1 - random) * frame.redlineAmount
    }

    private static func segment(_ index: Int, _ frame: OrbFrame, color: RGBColor, core: Double = 1, glow: CGFloat = 0,
                                glowAlpha: Double = 0) -> OrbInstance {
        let g = frame.geometry
        let angle = OrbGeometry.segmentAngle(index)
        return .roundedRect(
            center: g.point(angle: angle, radius: g.gaugeRadius),
            halfSize: CGSize(width: g.segmentLength / 2, height: g.segmentWidth / 2),
            rotation: angle * .pi / 180,
            corner: g.segmentCorner,
            color: color,
            core: core,
            glow: glow,
            glowAlpha: glowAlpha
        )
    }

    /// The idle sign of life: a band of light travelling along the unlit segments (in step with `needle`).
    private static func sweepBoost(_ index: Int, _ frame: OrbFrame) -> Double {
        guard let u = frame.signOfLife else { return 0 }
        let position = Double(index) / Double(OrbGeometry.segmentCount - 1)
        let d = position - (u * 1.3 - 0.15)
        if frame.effects.reduceMotion { return (frame.dark ? 0.1 : 0.06) * sin(.pi * u) }
        return (frame.dark ? 0.16 : 0.1) * exp(-d * d * 90)
    }

    /// Energy flow of segment `index` (DESIGN 2.1): pulses running toward the leading segment.
    private func flow(_ index: Int, _ frame: OrbFrame, gate: LedEffects) -> Double {
        guard gate.flow, !frame.unavailable else { return 0 }
        return LedMath.flow(segment: index, phase: phases.flow, heat: frame.instrumentHeat)
    }

    func addSegments(_ scene: inout OrbScene, _ frame: OrbFrame, gate: LedEffects) {
        let lit = (frame.unavailable ? 0 : frame.displayHeat) * Double(OrbGeometry.segmentCount)
        let bloom = frame.effects.bloom
        let glowRadius = 0.02 * frame.s * bloom
        let thumbnail = frame.content.isThumbnail
        let hot = frame.dark ? HeatPalette.whiteHot : nil

        if !thumbnail {
            // Bloom under the lit segments, white-hot at the leading edge; 30 % stronger than v1.3.
            for index in 0..<OrbGeometry.segmentCount {
                let light = Self.light(index, lit: lit)
                guard light.brightness > 0.01 else { continue }
                let flow = flow(index, frame, gate: gate)
                var color = Self.segmentColor(index, frame)
                if flow > 0 { color = color.mix(hot ?? color.scaled(1.15), 0.75 * flow) }
                if light.whiteness > 0 {
                    color = color.mixOKLab(frame.tokens.leadingSegment(Double(index) / 35, overdrive: frame.overdrive), light.whiteness * 0.8)
                }
                let base = (frame.dark ? 0.3 : 0.2) + 0.45 * light.whiteness
                let alpha = light.brightness * base * Self.shimmer(index, frame) * (1 + 0.5 * frame.flash) * (1 + 0.9 * flow) * 1.3
                scene.add(Self.segment(index, frame, color: color.opacity(min(1, alpha * bloom)), core: 0,
                                       glow: glowRadius * (1 + 0.7 * light.whiteness), glowAlpha: 0.6), blend: frame.glowBlend)
            }
            if frame.redlineAmount > 0.01 {
                let pulse = 0.55 + 0.45 * sin(2 * .pi * frame.breathPhase)
                let color = HeatPalette.highlight(frame.heat, overdrive: frame.overdrive, dark: frame.dark)
                let end = OrbGeometry.angle(forFraction: frame.displayHeat)
                let alpha = min(1, 0.5 * 1.3 * frame.redlineAmount * pulse * bloom)
                scene.add(.arc(center: frame.center, radius: 0.447 * frame.s, width: 0.012 * frame.s,
                               start: OrbGeometry.startAngle, sweep: end - OrbGeometry.startAngle,
                               color: color.opacity(alpha), tailColor: color.opacity(alpha),
                               glow: 0.02 * frame.s, glowAlpha: 0.8), blend: frame.glowBlend)
            }
        }

        // Crisp segments.
        let unlit = frame.content.increaseContrast ? frame.tokens.unlitSegment.opacity(1.8) : frame.tokens.unlitSegment
        for index in 0..<OrbGeometry.segmentCount {
            let light = Self.light(index, lit: lit)
            if light.brightness < 1 {
                let boost = Self.sweepBoost(index, frame)
                let color = boost > 0 ? unlit.opacity(1 + boost / max(unlit.alpha, 0.01)) : unlit
                scene.add(Self.segment(index, frame, color: color), blend: .over)
            }
            guard light.brightness > 0 else { continue }
            let flow = flow(index, frame, gate: gate)
            var color = Self.segmentColor(index, frame).scaled(Self.shimmer(index, frame))
            if flow > 0 { color = color.mix(hot ?? color.scaled(1.15), 0.75 * flow) }
            if light.whiteness > 0 {
                color = color.mixOKLab(frame.tokens.leadingSegment(Double(index) / 35, overdrive: frame.overdrive), light.whiteness)
            }
            if frame.flash > 0 { color = color.mix(.white, 0.25 * frame.flash) }
            scene.add(Self.segment(index, frame, color: color.opacity(min(1, light.brightness * (1 + 0.9 * flow)))), blend: .over)
        }
    }

    private static let tickTiers: [SpeedTier] = [.cruise, .boost, .overdrive, .redline]

    func addTicks(_ scene: inout OrbScene, _ frame: OrbFrame) {
        let g = frame.geometry
        let idle = frame.dark
            ? RGBColor.white.opacity(frame.content.increaseContrast ? 0.5 : 0.26)
            : RGBColor.black.opacity(frame.content.increaseContrast ? 0.45 : 0.22)
        let shown = frame.unavailable ? 0 : frame.displayHeat
        let redline = max(frame.redline, 1)
        for tier in Self.tickTiers {
            let fraction = HeatPalette.heat(forFraction: tier.enterSpeed(redline: redline) / redline)
            let passed = shown >= fraction
            let color = passed ? frame.tokens.heat(max(fraction, 0.1)) : idle
            scene.add(.circle(center: g.point(angle: OrbGeometry.angle(forFraction: fraction), radius: g.tickRadius),
                              radius: 0.0085 * frame.s, color: color, glow: passed && frame.dark ? 1.5 * frame.unit : 0,
                              glowAlpha: 0.5), blend: .over)
        }
    }

    /// A four-pointed star on the leading segment from `h ≥ 0.5` (DESIGN 2.1, Tip flare).
    func addTipFlare(_ scene: inout OrbScene, _ frame: OrbFrame, gate: LedEffects) {
        guard gate.tipFlare, !frame.unavailable else { return }
        let amount = LedMath.flareAmount(heat: frame.heat, overdrive: frame.overdrive, lvl: gate.lvl)
        guard amount > 0.002 else { return }
        let s = frame.s
        let angle = OrbGeometry.angle(forFraction: min(frame.displayHeat, 1))
        let lengths = LedMath.flareLengths(overdrive: frame.overdrive)
        let color = frame.dark ? HeatPalette.whiteHot.opacity(0.9 * amount) : HeatPalette.color(frame.heat).inked.opacity(0.4 * amount)
        scene.add(.flare(center: frame.geometry.point(angle: angle, radius: frame.geometry.gaugeRadius),
                         rotation: (angle + 90) * .pi / 180, tangential: lengths.tangential * s, radial: lengths.radial * s,
                         radialWidth: 0.0032 * s, tangentialWidth: 0.0028 * s, color: color), blend: frame.glowBlend)
    }

    /// The comets (DESIGN 2.1): a Gaussian band just outside the gauge with a `40° + 60° h` tail and a glowing head;
    /// from `h > 0.55` a second one half a turn behind at 70 %.
    func addComets(_ scene: inout OrbScene, _ frame: OrbFrame, gate: LedEffects) {
        let visibility = cometVisibility.value
        guard visibility > 0.01, frame.instrumentHeat > 0.01 else { return }
        let h = frame.instrumentHeat
        let s = frame.s
        let count = LedMath.cometCount(heat: h, maxComets: gate.maxComets)
        let tail = LedMath.cometTail(heat: h)
        let heat = HeatPalette.color(h)
        let radius = 0.455 * s
        for index in 0..<count {
            let head = 360 * phases.comet + 180 * Double(index)
            let opacity = visibility * (0.25 + 0.6 * h) * (index == 1 ? 0.7 : 1) * (frame.dark ? 1 : 0.6)
            let headColor = frame.dark ? HeatPalette.whiteHot : heat.inked
            let tailColor = frame.dark ? heat : heat.inked
            var band = OrbInstance.arc(center: frame.center, radius: radius, width: 0, start: head - tail, sweep: tail,
                                       color: headColor.opacity(opacity), tailColor: tailColor.opacity(opacity),
                                       glow: (0.0035 + 0.0045 * h) * s, glowAlpha: 1)
            band.extra.x = 0
            scene.add(band, blend: frame.glowBlend)
            scene.add(OrbInstance.circle(center: frame.geometry.point(angle: head, radius: radius), radius: 0,
                                         color: headColor.opacity(opacity), core: 0, glow: (0.01 + 0.006 * h) * s,
                                         glowAlpha: 0.9).exponentialGlow(), blend: frame.glowBlend)
        }
    }
}

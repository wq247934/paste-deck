import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// `minimal` — one thin progress ring (DESIGN 2a.5): the number, the ring and the title; almost nothing moves. The ring
/// fills to the redline and runs a second lap beyond it, the way an activity ring passes 100 %.
@MainActor
final class MinimalStyle: OrbStyleRenderer {
    let kind = OrbStyleKind.minimal
    let linePlacement = OrbLinePlacement.minimal
    let readoutLayout = OrbReadoutLayout(
        valueSize: 0.30, valueBaseline: 0.07, valueMaxWidth: 0.66, unitSize: nil, unitGap: 0,
        title: .belowValue(0.098), titleSize: 0.068, titleMaxWidth: 0.62, dots: nil, pillCenter: -0.25,
        rolls: false, titleCrossfades: true, valueGlow: false, valueMotion: false
    )
    let hasAura = false
    let hasWave = false
    let hasRays = false
    let signOfLifeDuration: TimeInterval = 0

    private static let goldDark = RGBColor(hex: 0xFACC15)
    private static let goldLight = RGBColor(hex: 0xC99700)

    private var breathPhase = 0.0
    private var blinkStart: TimeInterval = -.infinity

    init() {}

    // MARK: Simulation

    func step(_ frame: OrbFrame) {
        guard frame.dt > 0 else { return }
        let tau = 2 * Double.pi
        breathPhase = (breathPhase + tau * MinimalMath.breathHz * frame.dt).truncatingRemainder(dividingBy: tau)
    }

    func pulse(at time: TimeInterval, strength: Double, heat: Double) {
        blinkStart = time
    }

    private func breathes(_ frame: OrbFrame) -> Bool {
        frame.tier == .redline && !frame.unavailable && frame.effects.level >= .soft && !frame.effects.reduceMotion
    }

    private func blink(_ frame: OrbFrame) -> Double {
        guard frame.effects.level >= .soft else { return 0 }
        return MinimalMath.blink(age: frame.time - blinkStart, reduceMotion: frame.effects.reduceMotion)
    }

    private func tint(_ frame: OrbFrame) -> Double {
        guard frame.effects.celebrate else { return 0 }
        return MinimalMath.goldTint(age: frame.peakAge, reduceMotion: frame.effects.reduceMotion)
    }

    func isBusy(_ frame: OrbFrame) -> Bool {
        blink(frame) > 0 || tint(frame) > 0
    }

    /// Static at idle; in the redline tier the glow breathes at 15 fps; springs and transitions are the animator's.
    func ambientFrameClass(_ frame: OrbFrame) -> OrbFrameClass {
        breathes(frame) ? .fps15 : .none
    }

    // MARK: Layers

    func build(into scene: inout OrbScene, _ frame: OrbFrame) {
        let s = frame.s
        let dark = frame.dark
        let contrast = frame.content.increaseContrast
        let width = CGFloat(MinimalMath.width(diameter: Double(s), increaseContrast: contrast))
        let radius = CGFloat(MinimalMath.radius) * s
        let center = frame.center

        let track = frame.tokens.unlitSegment.opacity(1.15 * (contrast ? 2 : 1))
        scene.add(.ring(center: center, radius: radius, width: width, color: track), blend: .over)

        let active = !frame.isIdle && !frame.unavailable
        guard active else { return }
        let progress = MinimalMath.progress(heat: frame.heat, overdrive: frame.overdrive)
        guard progress > 0.002 else { return }
        let laps = MinimalMath.laps(progress)

        let h = frame.heat
        let gold = tint(frame)
        let goldColor = dark ? Self.goldDark : Self.goldLight
        let head = frame.labelColor(max(h, 0.04)).mix(goldColor, gold)
        let tail = frame.labelColor(max(h, 0.04)).darkened(dark ? 0.28 : 0.1).mix(goldColor, gold)
        let blink = blink(frame)
        let redline = frame.tier == .redline
        let breath = redline ? MinimalMath.breath(phase: breathPhase, reduceMotion: !breathes(frame)) : 0
        let glows = dark && frame.tier >= .boost && frame.effects.level >= .soft && !contrast && !frame.content.isThumbnail
        let glow = MinimalMath.glow(redline: redline, breath: breath, blink: blink, max: frame.effects.isMax)

        if glows {
            let sigma = CGFloat(glow.sigma) * s
            let strength = glow.alpha * Self.strokeGlow(width: width, sigma: sigma)
            scene.add(.bandArc(center: center, radius: radius, width: width, start: MinimalMath.angle(0), sweep: 360 * laps.first,
                               color: head.opacity(strength), startColor: head.opacity(strength), roundCaps: true, core: 0,
                               glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1), blend: .over)
        }
        scene.add(.bandArc(center: center, radius: radius, width: width, start: MinimalMath.angle(0), sweep: 360 * laps.first,
                           color: head, startColor: tail, roundCaps: true), blend: .over)

        if laps.second > 0.0005 {
            // The second lap runs over the first; its head casts a soft shadow onto the lap below.
            let headAngle = MinimalMath.angle(laps.second)
            let shadow = RGBColor.black.opacity(dark ? 0.55 : 0.22)
            let behind = MinimalMath.shadowBehind * 180 / .pi
            let ahead = MinimalMath.shadowAhead * 180 / .pi
            scene.add(.bandArc(center: center, radius: radius, width: width, start: headAngle - behind, sweep: behind + ahead,
                               color: shadow, startColor: shadow, core: 0.0, glow: OrbInstance.glow(sigma: 0.35 * width),
                               glowAlpha: 1), blend: .over)
            if glows {
                let sigma = CGFloat(glow.sigma) * s
                let strength = glow.alpha * Self.strokeGlow(width: width, sigma: sigma)
                scene.add(.bandArc(center: center, radius: radius, width: width, start: MinimalMath.angle(0),
                                   sweep: 360 * laps.second, color: head.opacity(strength), startColor: head.opacity(strength),
                                   roundCaps: true, core: 0, glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1),
                          blend: .over)
            }
            scene.add(.bandArc(center: center, radius: radius, width: width, start: MinimalMath.angle(0), sweep: 360 * laps.second,
                               color: head, startColor: head, roundCaps: true), blend: .over)
        }

        let dot = MinimalMath.headDot(redline: redline && frame.effects.level >= .soft, breath: breath, blink: blink)
        if dot > 0.01 {
            let headPoint = frame.geometry.point(angle: MinimalMath.angle(MinimalMath.head(progress)), radius: radius)
            let color = dark ? head.mix(HeatPalette.whiteHot, 0.6) : head
            scene.add(.circle(center: headPoint, radius: width * 0.32, color: color.opacity(min(1, dot))), blend: .over)
        }
    }

    /// Peak strength of a canvas shadow of a stroke `width` wide relative to the analytic glow.
    private static func strokeGlow(width: CGFloat, sigma: CGFloat) -> Double {
        guard sigma > 0 else { return 1 }
        return erf(Double(width / (2 * 1.41421356 * sigma)))
    }
}

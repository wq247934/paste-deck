import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// `needle` — the analog racing tachometer (DESIGN 2a.2): a graduated dial with a red zone, a heavy needle on an
/// underdamped spring that trembles at speed and pins against the peg beyond the redline, a lit trace, shift lights that
/// flash at the redline, a wake behind a fast needle and sparks where it grinds against the peg.
@MainActor
final class NeedleStyle: OrbStyleRenderer {
    let kind = OrbStyleKind.needle
    private static let hubLayout = OrbReadoutLayout(
        valueSize: 0.205, valueBaseline: 0.035, valueMaxWidth: 0.40, unitSize: 0.062, unitGap: 0.08,
        title: .fixed(0.338), titleSize: 0.062, titleMaxWidth: 0.46, infoScale: 0.85, infoMaxWidth: 0.42,
        dots: 0.405, pillCenter: -0.175
    )
    /// While the two-line readout is on and fits, the unit leaves the hub for the dial face (DESIGN 10): the hub draws
    /// no unit, and the layout names the dial position so the unit's click target follows it.
    private static let dialUnitBaseline: CGFloat = -0.254
    private static let dialUnitSize: CGFloat = 0.046
    private static let hubWithoutUnit: OrbReadoutLayout = {
        var layout = hubLayout
        layout.unitSize = nil
        return layout
    }()
    private static let dialUnitLayout: OrbReadoutLayout = {
        var layout = hubLayout
        layout.unitSize = dialUnitSize
        layout.unitGap = dialUnitBaseline - hubLayout.valueBaseline
        return layout
    }()

    var readoutLayout: OrbReadoutLayout { unitOnDial ? Self.dialUnitLayout : Self.hubLayout }
    let linePlacement = OrbLinePlacement.needle
    /// The unit is printed on the dial face (two-line readout on and fitting at this size).
    private(set) var unitOnDial = false

    private static let redDark = RGBColor(hex: 0xF43F5E)
    private static let redLight = RGBColor(hex: 0xE11D48)
    private static let idleNeedle = RGBColor(hex: 0x9EA8BA)
    private static let lampLight = RGBColor(hex: 0xF59E0B)
    private static let hubRadius = 0.235

    private var spring = NeedleMath.Spring()
    private var initialized = false
    private var target = 0.0
    private var springy = true
    /// Angular speed of the needle in degrees per second (spring only, without the tremble).
    private(set) var angularSpeed = 0.0
    private var tremble = 0.0
    private var phases = (0.0, 0.0, 0.0)
    private var redPhase = 0.0
    private var lampPhase = 0.0
    private var sparks = NeedleSparks()
    private var flareStart: TimeInterval = -.infinity
    private var flareStrength = 0.0

    init() {}

    // MARK: Simulation

    func step(_ frame: OrbFrame) {
        let content = frame.content
        unitOnDial = content.showsReadout && !content.valueOnly && !content.isThumbnail
            && content.lines.map { OrbLineMetrics.fits(linePlacement, diameter: frame.s, format: $0.format, language: content.language) } == true
        let dt = frame.dt
        let level = frame.effects.level
        let active = !frame.isIdle && !frame.unavailable
        springy = level >= .soft && !frame.effects.reduceMotion
        target = springy
            ? NeedleMath.target(rawHeat: frame.rawHeat, rawOverdrive: frame.rawOverdrive, idle: !active)
            : (active ? NeedleMath.direct(heat: frame.heat, overdrive: frame.overdrive) : 0)
        if !initialized || frame.resumed {
            spring.reset(to: target)
            initialized = true
            sparks.removeAll()
        }
        guard dt > 0 else { return }
        let previous = spring.position
        if springy {
            spring.step(toward: target, dt: dt)
        } else {
            spring.reset(to: target)
        }
        angularSpeed = (spring.position - previous) / dt * 270

        let tau = 2 * Double.pi
        let frequencies = NeedleMath.trembleFrequencies
        phases.0 = (phases.0 + tau * frequencies.0 * dt).truncatingRemainder(dividingBy: tau)
        phases.1 = (phases.1 + tau * frequencies.1 * dt).truncatingRemainder(dividingBy: tau)
        phases.2 = (phases.2 + tau * frequencies.2 * dt).truncatingRemainder(dividingBy: tau)
        let amplitude = level >= .standard && active
            ? NeedleMath.trembleAmplitude(heat: frame.heat, overdrive: frame.overdrive, max: level == .max)
            : 0
        tremble = NeedleMath.trembleOffset(amplitude: amplitude, phases: phases)
        redPhase = (redPhase + tau * NeedleMath.redZonePulseHz(overdrive: frame.overdrive) * dt).truncatingRemainder(dividingBy: tau)
        lampPhase = (lampPhase + tau * NeedleMath.lampFlashHz * dt).truncatingRemainder(dividingBy: tau)

        let pinned = springy && active && NeedleMath.isPinned(needle: spring.position, target: target)
        let rate = level >= .standard && pinned ? NeedleMath.pegSparkRate(overdrive: frame.overdrive, max: level == .max) : 0
        if rate > 0 || !sparks.isEmpty {
            sparks.step(dt: dt, rate: rate, angle: NeedleMath.angle(NeedleMath.contact), pool: NeedleMath.pegSparkPool(max: level == .max))
        }
    }

    func pulse(at time: TimeInterval, strength: Double, heat: Double) {
        flareStart = time
        flareStrength = strength
    }

    private func flare(at time: TimeInterval) -> Double {
        let age = time - flareStart
        guard age >= 0, age < NeedleMath.tipFlareDuration else { return 0 }
        return (1 - age / NeedleMath.tipFlareDuration) * flareStrength
    }

    private func sweeping(_ frame: OrbFrame) -> Bool {
        frame.effects.celebrate && !frame.effects.reduceMotion && frame.peakAge >= 0 && frame.peakAge < NeedleMath.peakSweepDuration
    }

    func isBusy(_ frame: OrbFrame) -> Bool {
        let active = !frame.isIdle && !frame.unavailable
        let goal = NeedleMath.target(rawHeat: frame.rawHeat, rawOverdrive: frame.rawOverdrive, idle: !active)
        return (springy && !spring.isSettled(at: goal)) || !sparks.isEmpty || flare(at: frame.time) > 0 || sweeping(frame)
    }

    func ambientFrameClass(_ frame: OrbFrame) -> OrbFrameClass {
        if frame.isIdle || frame.unavailable { return .none }
        if frame.tier >= .overdrive || abs(angularSpeed) > NeedleMath.fastTurn { return .fps60 }
        return .fps30
    }

    // MARK: Layers

    /// The needle as drawn: spring plus tremble, swung to the peg and back by a new peak.
    private func displayed(_ frame: OrbFrame) -> Double {
        var n = NeedleMath.displayed(spring: spring.position, trembleDegrees: tremble)
        if sweeping(frame) { n = NeedleMath.peakSweep(n, age: frame.peakAge) }
        return min(NeedleMath.pegStop, max(NeedleMath.zeroStop, n))
    }

    func build(into scene: inout OrbScene, _ frame: OrbFrame) {
        let thumbnail = frame.content.isThumbnail || frame.content.valueOnly
        let n = displayed(frame)
        let active = !frame.isIdle && !frame.unavailable
        addDial(&scene, frame)
        addRedZone(&scene, frame, active: active, thumbnail: thumbnail)
        if unitOnDial { addDialUnit(&scene, frame) }
        addGraduations(&scene, frame, needle: n, active: active, thumbnail: thumbnail)
        if !thumbnail {
            if active { addTrace(&scene, frame, needle: n) }
            addPins(&scene, frame)
            if !frame.isSmall { addLamps(&scene, frame, needle: n, active: active) }
            if active { addWake(&scene, frame, needle: n) }
        }
        addNeedle(&scene, frame, needle: n, active: active, thumbnail: thumbnail)
        if !thumbnail { addSparks(&scene, frame) }
        addHub(&scene, frame, thumbnail: thumbnail)
    }

    /// Peak strength of a canvas shadow (the shape blurred by a Gaussian of σ) relative to the analytic glow, which
    /// is full strength at the edge whatever the size: thin strokes and small dots glow only faintly.
    static func strokeGlow(width: CGFloat, sigma: CGFloat) -> Double {
        guard sigma > 0 else { return 1 }
        return erf(Double(width / (2 * 1.41421356 * sigma)))
    }

    static func dotGlow(radius: CGFloat, sigma: CGFloat) -> Double {
        guard sigma > 0 else { return 1 }
        return 1 - exp(-Double(radius * radius / (2 * sigma * sigma)))
    }

    private func glowFactor(_ frame: OrbFrame) -> Double {
        (frame.content.increaseContrast ? 0.5 : 1) * (frame.effects.isMax ? 1.25 : 1)
    }

    private func addDial(_ scene: inout OrbScene, _ frame: OrbFrame) {
        let color = frame.dark ? RGBColor.white.opacity(0.028) : RGBColor.black.opacity(0.035)
        let start = NeedleMath.angle(-0.004)
        scene.add(.bandArc(center: frame.center, radius: 0.41 * frame.s, width: 0.075 * frame.s, start: start,
                           sweep: 270 * 1.008, color: color, startColor: color), blend: .over)
    }

    private func redColor(_ frame: OrbFrame) -> RGBColor { frame.dark ? Self.redDark : Self.redLight }

    private func addRedZone(_ scene: inout OrbScene, _ frame: OrbFrame, active: Bool, thumbnail: Bool) {
        let red = redColor(frame)
        let inRedline = active && frame.tier == .redline
        var alpha = frame.dark ? 0.62 : 0.8
        if inRedline, frame.effects.level >= .soft {
            alpha = 0.8 + 0.2 * (frame.effects.reduceMotion ? 1 : 0.5 + 0.5 * sin(redPhase))
        }
        let start = NeedleMath.angle(NeedleMath.redZoneStart)
        let sweep = 270 * (1 - NeedleMath.redZoneStart)
        let radius = 0.4655 * frame.s
        let width = 0.017 * frame.s
        if inRedline, frame.effects.level >= .standard, !thumbnail {
            let sigma = NeedleMath.redZoneGlowSigma(overdrive: frame.overdrive, max: frame.effects.isMax) * frame.s
            let glow = red.opacity(0.9 * frame.redlineAmount * (frame.content.increaseContrast ? 0.5 : 1)
                * Self.strokeGlow(width: width, sigma: sigma))
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: start, sweep: sweep, color: glow,
                               startColor: glow, core: 0, glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1), blend: frame.glowBlend)
        }
        let color = red.opacity(alpha)
        scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: start, sweep: sweep, color: color,
                           startColor: color), blend: .over)
    }

    private func addGraduations(_ scene: inout OrbScene, _ frame: OrbFrame, needle n: Double, active: Bool, thumbnail: Bool) {
        let dark = frame.dark
        let contrast = frame.content.increaseContrast
        let red = redColor(frame)
        let outer = 0.445 * frame.s
        let glowSigma = 0.015 * frame.s
        let glowFactor = glowFactor(frame)
        let reduceMotion = frame.effects.reduceMotion
        for k in 0..<NeedleMath.graduationCount {
            let major = NeedleMath.isMajor(k)
            if !major && (frame.isSmall || thumbnail) { continue }
            let p = NeedleMath.graduation(k)
            let lit = active && p <= n + 1e-6
            var color: RGBColor
            var alpha: Double
            if lit {
                color = frame.labelColor(p)
                if p > n - 1.0 / 40 {
                    color = dark ? color.mix(HeatPalette.whiteHot, 0.75) : color.mix(HeatPalette.amberHot, 0.25)
                }
                if frame.flash > 0 { color = color.mix(.white, 0.25 * frame.flash) }
                alpha = 0.95
            } else if p >= NeedleMath.redZoneStart - 1e-6 {
                color = red
                alpha = major ? 0.85 : 0.6
            } else {
                color = dark ? .white : .black
                alpha = (major ? 0.5 : 0.24) * (contrast ? 1.6 : 1) * (dark ? 1 : 0.85)
            }
            if let u = frame.signOfLife {
                if reduceMotion {
                    alpha = min(1, alpha + (dark ? 0.12 : 0.08) * sin(.pi * u))
                } else {
                    let d = p - (u * 1.3 - 0.15)
                    alpha = min(1, alpha + (dark ? 0.35 : 0.25) * exp(-d * d * 90))
                }
            }
            let angle = NeedleMath.angle(p)
            let length = (major ? 0.062 : 0.03) * frame.s
            let width = (major ? 0.014 : 0.0075) * frame.s
            let glows = lit && major && dark && frame.effects.level >= .soft && !thumbnail
            scene.add(.capsule(
                from: frame.geometry.point(angle: angle, radius: outer - length),
                to: frame.geometry.point(angle: angle, radius: outer),
                width: width,
                color: color.opacity(alpha),
                glow: glows ? OrbInstance.glow(sigma: glowSigma) : 0,
                glowAlpha: glows ? 0.8 * glowFactor * Self.strokeGlow(width: width, sigma: glowSigma) : 0
            ), blend: .over)
        }
    }

    private func addTrace(_ scene: inout OrbScene, _ frame: OrbFrame, needle n: Double) {
        guard n > 0.002 else { return }
        let radius = 0.366 * frame.s
        let width = 0.011 * frame.s
        let start = NeedleMath.angle(0)
        let flash = 1 + 0.25 * frame.flash
        if frame.dark {
            scene.add(.paletteArc(center: frame.center, radius: radius, width: width, start: start, sweep: 270 * n,
                                  heatFrom: 0, heatTo: n, alpha: min(1, 0.7 * flash), startAlpha: 0.3), blend: .additive)
            return
        }
        // Light: the label color of each position, in short runs blended between their ends.
        let runs = max(2, Int((n * 16).rounded(.up)))
        for index in 0..<runs {
            let p0 = n * Double(index) / Double(runs)
            let p1 = n * Double(index + 1) / Double(runs)
            let a0 = min(1, 0.85 * (0.3 + 0.7 * p0 / n) * flash)
            let a1 = min(1, 0.85 * (0.3 + 0.7 * p1 / n) * flash)
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: NeedleMath.angle(p0),
                               sweep: 270 * (p1 - p0), color: frame.labelColor(p1).opacity(a1),
                               startColor: frame.labelColor(p0).opacity(a0)), blend: .over)
        }
    }

    private func addPins(_ scene: inout OrbScene, _ frame: OrbFrame) {
        let color = frame.dark ? RGBColor.white.opacity(0.32) : RGBColor.black.opacity(0.28)
        scene.add(.circle(center: frame.point(NeedleMath.angle(NeedleMath.zeroPin), 0.405), radius: 0.011 * frame.s, color: color),
                  blend: .over)
        scene.add(.circle(center: frame.point(NeedleMath.angle(NeedleMath.pegPin), 0.405), radius: 0.011 * frame.s, color: color),
                  blend: .over)
    }

    private func addLamps(_ scene: inout OrbScene, _ frame: OrbFrame, needle n: Double, active: Bool) {
        let dark = frame.dark
        let flashing = active && frame.tier == .redline && frame.effects.level >= .soft
        let housing = dark ? RGBColor.white.opacity(0.08) : RGBColor.black.opacity(0.09)
        let flashColor = dark ? HeatPalette.color(0.97).mix(HeatPalette.whiteHot, 0.55) : Self.lampLight
        let flash = frame.effects.reduceMotion ? 1 : NeedleMath.lampFlash(phase: lampPhase)
        let glowFactor = glowFactor(frame)
        for index in 0..<NeedleMath.lampThresholds.count {
            let threshold = NeedleMath.lampThresholds[index]
            let center = frame.point(NeedleMath.lampAngles[index], 0.33)
            scene.add(.circle(center: center, radius: 0.019 * frame.s, color: housing), blend: .over)
            var brightness = active && NeedleMath.lampLit(index, needle: n) ? 1.0 : 0
            var color = dark ? HeatPalette.color(threshold) : HeatPalette.color(threshold).darkened(0.15)
            if flashing {
                color = flashColor
                brightness = flash
            }
            guard brightness > 0.001 else { continue }
            let radius = 0.019 * 0.86 * frame.s
            let sigma = 0.02 * frame.s
            scene.add(.circle(center: center, radius: radius, color: color.opacity(brightness),
                              glow: dark ? OrbInstance.glow(sigma: sigma) : 0,
                              glowAlpha: dark ? 0.9 * glowFactor * Self.dotGlow(radius: radius, sigma: sigma) : 0),
                      blend: .over)
        }
    }

    private func addWake(_ scene: inout OrbScene, _ frame: OrbFrame, needle n: Double) {
        guard frame.effects.level >= .soft, !frame.effects.reduceMotion else { return }
        let length = NeedleMath.wakeLength(angularSpeed: angularSpeed)
        guard length > 0 else { return }
        let h = frame.instrumentHeat
        let color = frame.labelColor(h)
        let bright = color.opacity(0.32)
        let clear = color.opacity(0)
        let head = NeedleMath.angle(n)
        let radius = (0.235 + 0.43) / 2 * frame.s
        let width = (0.43 - 0.235) * frame.s
        if angularSpeed > 0 {
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: head - length, sweep: length,
                               color: bright, startColor: clear), blend: frame.glowBlend)
        } else {
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: head, sweep: length,
                               color: clear, startColor: bright), blend: frame.glowBlend)
        }
    }

    private func addNeedle(_ scene: inout OrbScene, _ frame: OrbFrame, needle n: Double, active: Bool, thumbnail: Bool) {
        let s = frame.s
        let dark = frame.dark
        let h = frame.instrumentHeat
        let angle = NeedleMath.angle(n)
        let flare = active && !thumbnail ? flare(at: frame.time) : 0
        let tip = 0.44 * s
        let tail = 0.09 * s
        let pivotHalf = 0.031 * s
        let tipHalf = 0.006 * s
        let tailHalf = 0.9 * pivotHalf
        let fill: RGBColor
        if !active {
            fill = Self.idleNeedle.opacity(0.75)
        } else if dark {
            fill = HeatPalette.color(max(h, 0.04)).mix(HeatPalette.whiteHot, 0.05 + 0.45 * frame.overdrive)
        } else {
            fill = frame.labelColor(max(h, 0.05))
        }
        func blade(_ color: RGBColor, offset: CGPoint = .zero, grow: CGFloat = 0, core: Double = 1, glow: CGFloat = 0,
                   glowAlpha: Double = 0) -> OrbInstance {
            .blade(pivot: CGPoint(x: frame.center.x + offset.x, y: frame.center.y + offset.y), angle: angle,
                   tipLength: tip + grow, tailLength: tail + grow, pivotHalfWidth: pivotHalf + grow, tipHalfWidth: tipHalf + grow,
                   tailHalfWidth: tailHalf + grow, color: color, core: core, glow: glow, glowAlpha: glowAlpha)
        }
        if dark {
            let sigma = (0.0275 + 0.0175 * flare) * s * (frame.effects.isMax ? 1.25 : 1)
            let alpha = min(1, 0.45 + 0.35 * h + 0.6 * flare) * (frame.content.increaseContrast ? 0.5 : 1)
                * Self.strokeGlow(width: pivotHalf + tipHalf, sigma: sigma)
            scene.add(blade(HeatPalette.color(max(0.1, h)).opacity(alpha), core: 0, glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1),
                      blend: .additive)
        } else {
            scene.add(blade(RGBColor.black.opacity(0.22), offset: CGPoint(x: 0.006 * s, y: 0.01 * s),
                            glow: OrbInstance.glow(sigma: 0.007 * s), glowAlpha: 1), blend: .over)
        }
        if frame.content.increaseContrast {
            scene.add(blade(dark ? RGBColor.black.opacity(0.6) : .white, grow: 1), blend: .over)
        }
        scene.add(blade(fill), blend: .over)

        let ux = cos(angle * .pi / 180)
        let uy = sin(angle * .pi / 180)
        let spineStart = CGPoint(x: frame.center.x + ux * 0.9 * Self.hubRadius * s, y: frame.center.y + uy * 0.9 * Self.hubRadius * s)
        let tipPoint = CGPoint(x: frame.center.x + ux * tip, y: frame.center.y + uy * tip)
        let spineEnd = CGPoint(x: tipPoint.x - ux * tipHalf, y: tipPoint.y - uy * tipHalf)
        let spine = dark ? HeatPalette.whiteHot.opacity(min(1, 0.75 + 0.25 * flare)) : RGBColor.white.opacity(0.55)
        scene.add(.capsule(from: spineStart, to: spineEnd, width: max(0.6, 0.0045 * s), color: spine), blend: .over)
        if flare > 0.01 {
            let hot = dark ? HeatPalette.whiteHot : HeatPalette.amberHot
            scene.add(.circle(center: tipPoint, radius: 0.06 * s, color: hot.opacity(0.7 * flare))
                .radialGradient(to: hot.opacity(0), radius: 0.06 * s), blend: frame.glowBlend)
        }
    }

    private func addSparks(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !sparks.isEmpty, frame.effects.level >= .standard else { return }
        let s = frame.s
        let dark = frame.dark
        let start = dark ? HeatPalette.whiteHot : HeatPalette.amberHot
        let end = dark ? HeatPalette.color(0.95) : frame.labelColor(0.95)
        for spark in sparks.sparks {
            let u = spark.age / spark.life
            let head = CGPoint(x: frame.center.x + spark.x * s, y: frame.center.y + spark.y * s)
            let tail = CGPoint(x: head.x - spark.vx * 0.025 * s, y: head.y - spark.vy * 0.025 * s)
            let color = start.mix(end, u).opacity((1 - u) * frame.readoutZoneFade(at: head))
            scene.add(.capsule(from: tail, to: head, width: spark.width * (1 - 0.5 * u) * frame.unit, color: color,
                               tailColor: color.opacity(0.35)), blend: frame.glowBlend)
        }
    }

    private func addHub(_ scene: inout OrbScene, _ frame: OrbFrame, thumbnail: Bool) {
        let s = frame.s
        let dark = frame.dark
        let radius = Self.hubRadius * s
        let center = frame.center
        if !thumbnail {
            let shadow = RGBColor.black.opacity(dark ? 0.55 : 0.16)
            scene.add(.circle(center: CGPoint(x: center.x, y: center.y + 0.012 * s), radius: radius * 0.96, color: shadow,
                              glow: OrbInstance.glow(sigma: 0.025 * s), glowAlpha: 1), blend: .over)
        }
        let top = dark ? RGBColor(hex: 0x262C3C, alpha: 0.95) : RGBColor(hex: 0xFFFFFF, alpha: 0.98)
        let bottom = dark ? RGBColor(hex: 0x0C0E14, alpha: 0.95) : RGBColor(hex: 0xECEFF5, alpha: 0.98)
        scene.add(.circle(center: center, radius: radius, color: top).linearGradient(to: bottom, angle: 90, halfLength: radius),
                  blend: .over)
        guard !thumbnail else { return }
        // Inner highlight just inside the bezel.
        let highlightTop = dark ? RGBColor.white.opacity(0.2) : RGBColor.white
        let highlightBottom = dark ? RGBColor.white.opacity(0.03) : RGBColor.black.opacity(0.1)
        scene.add(.ring(center: center, radius: radius - 0.004 * s, width: max(1, 0.008 * s), color: highlightTop)
            .linearGradient(to: highlightBottom, angle: 90, halfLength: radius), blend: .over)
        // Chrome bezel with a 135° gradient (three stops), drawn as four quarter arcs between the stops.
        let first = dark ? RGBColor.white.opacity(0.42) : RGBColor.white
        let middle = dark ? RGBColor.white.opacity(0.10) : RGBColor(hex: 0xA0A8B6, alpha: 0.55)
        let last = dark ? RGBColor.white.opacity(0.22) : RGBColor(hex: 0x78808E, alpha: 0.6)
        let width = max(1.2, 0.013 * s)
        func quarter(_ start: Double, _ from: RGBColor, _ to: RGBColor) {
            scene.add(.bandArc(center: center, radius: radius, width: width, start: start, sweep: 90, color: to, startColor: from),
                      blend: .over)
        }
        quarter(225, first, middle)
        quarter(315, middle, last)
        quarter(45, last, middle)
        quarter(135, middle, first)
    }

    // MARK: Readout

    func buildReadout(into scene: inout OrbScene, _ frame: OrbFrame, readout: OrbReadoutBuilder) {
        readout.add(into: &scene, frame, layout: unitOnDial ? Self.hubWithoutUnit : Self.hubLayout)
    }

    /// The readout sits in the hub below the value, away from the new-peak pill, so it stays during a celebration.
    func buildLines(into scene: inout OrbScene, _ frame: OrbFrame, lines: OrbLineReadout) {
        lines.add(into: &scene, frame, placement: linePlacement,
                    palette: .standard(dark: frame.dark, increaseContrast: frame.content.increaseContrast), yieldsToPill: false)
    }

    /// The unit as the legend of a real tachometer (DESIGN 10): on the dial face above the hub, under the graduations
    /// and the needle, in the secondary token at 75 %; it stays while the two-line readout is quiet.
    private func addDialUnit(_ scene: inout OrbScene, _ frame: OrbFrame) {
        let s = frame.s
        let tracking = 0.4 * frame.unit
        let style = OrbTextStyle(size: max(OrbReadoutBuilder.textFloor, Self.dialUnitSize * s), weight: .medium, tracking: tracking)
        guard let texture = OrbTextCache.shared.texture(frame.content.unit, style: style, language: frame.content.language,
                                                        scale: scene.backingScale) else { return }
        let secondary = frame.content.increaseContrast ? frame.tokens.secondaryText.opacity(1.35) : frame.tokens.secondaryText
        scene.add(OrbTextDraw(texture, centerX: frame.center.x + tracking / 2, baseline: frame.center.y + Self.dialUnitBaseline * s,
                              color: secondary.opacity(0.75)))
    }
}

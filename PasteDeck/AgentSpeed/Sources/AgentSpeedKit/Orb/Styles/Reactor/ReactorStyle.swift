import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// `reactor` — the reactor energy ring (DESIGN 2a.4): a dark core window carries the readout; around it three
/// counter-rotating rotors spin up with speed, lengthen until rotor A closes into a solid ring beyond the redline, and
/// throw lightning at the redline. Every completed response kicks the rotors; a new peak locks them at 12 o'clock.
@MainActor
final class ReactorStyle: OrbStyleRenderer {
    let kind = OrbStyleKind.reactor
    let linePlacement = OrbLinePlacement.reactor
    let readoutLayout = OrbReadoutLayout(
        valueSize: 0.205, valueBaseline: 0.03, valueMaxWidth: 0.46, unitSize: 0.062, unitGap: 0.08,
        title: .belowUnit(0.074), titleSize: 0.058, titleMaxWidth: 0.50, infoMaxWidth: 0.52, dots: 0.252, pillCenter: -0.172
    )

    private static let slate = HeatPalette.color(0)
    private static let gold = RGBColor(hex: 0xFACC15)
    private static let flashDuration = 0.12

    /// Rotor angles in degrees: the head of rotor A's first arc, rotor B's first coil, rotor C's first arc.
    private var angleA = 17.2
    private var angleB = 63.0
    private var angleC = 114.6
    /// Phase of rotor B's energy bands (radians) and of the corona breathing.
    private var bandPhase = 0.0
    private var breathPhase = 0.0
    private var kick = 0.0
    private var lightning = ReactorLightning()

    private var lockStart: TimeInterval = -.infinity
    private var lockReduced = false
    private var lockFrom = (0.0, 0.0, 0.0)
    private var lockTo = (0.0, 0.0, 0.0)
    private var pendingLock: TimeInterval?
    private var pendingPulse: (time: TimeInterval, strength: Double, heat: Double)?
    private var flareStart: TimeInterval = -.infinity
    private var flareHeat = 0.0
    private var lastFlash: TimeInterval = -.infinity
    private var reducedMotion = false

    init() {}

    // MARK: Simulation

    func step(_ frame: OrbFrame) {
        if frame.resumed {
            kick = 0
            lightning.removeAll()
            lockStart = -.infinity
            pendingLock = nil
            pendingPulse = nil
            flareStart = -.infinity
        }
        let dt = frame.dt
        let level = frame.effects.level
        let still = frame.effects.reduceMotion || level == .off
        reducedMotion = frame.effects.reduceMotion
        let active = !frame.isIdle && !frame.unavailable
        let h = frame.instrumentHeat * frame.activity
        let o = frame.unavailable ? 0 : frame.overdrive
        let coils = ReactorMath.coilCount(small: frame.isSmall)

        if let pulse = pendingPulse {
            pendingPulse = nil
            if !still {
                kick += ReactorMath.kickPerStrength * pulse.strength
                flareStart = pulse.time
                flareHeat = pulse.heat
            }
        }
        if let start = pendingLock {
            pendingLock = nil
            lockStart = start
            lockReduced = frame.effects.reduceMotion
            if !lockReduced {
                lockFrom = (angleA, angleB, angleC)
                lockTo = (
                    ReactorMath.lockTarget(angle: angleA, symmetry: ReactorMath.lockSymmetry(rotor: 0, coils: coils), clockwise: true),
                    ReactorMath.lockTarget(angle: angleB, symmetry: ReactorMath.lockSymmetry(rotor: 1, coils: coils), clockwise: false),
                    ReactorMath.lockTarget(angle: angleC, symmetry: ReactorMath.lockSymmetry(rotor: 2, coils: coils), clockwise: true)
                )
            }
        }
        guard dt > 0 else { return }
        kick = ReactorMath.decayedKick(kick, dt: dt)
        let tau = 2 * Double.pi
        if !still {
            breathPhase = (breathPhase + tau * ReactorMath.breathingRate(heat: h) * dt).truncatingRemainder(dividingBy: tau)
        }

        let lockAge = frame.time - lockStart
        if !lockReduced, lockAge >= 0, lockAge < ReactorMath.lockEnd {
            let p = ReactorMath.lockProgress(age: lockAge)
            angleA = lockFrom.0 + (lockTo.0 - lockFrom.0) * p
            angleB = lockFrom.1 + (lockTo.1 - lockFrom.1) * p
            angleC = lockFrom.2 + (lockTo.2 - lockFrom.2) * p
            if lockAge + dt >= ReactorMath.lockEnd {
                angleA = ReactorMath.wrap(angleA)
                angleB = ReactorMath.wrap(angleB)
                angleC = ReactorMath.wrap(angleC)
            }
        } else if !still, active {
            let speeds = ReactorMath.speeds(heat: h, overdrive: o, kick: kick)
            angleA = ReactorMath.advance(angleA, speed: speeds.a, dt: dt)
            angleB = ReactorMath.advance(angleB, speed: speeds.b, dt: dt)
            angleC = ReactorMath.advance(angleC, speed: speeds.c, dt: dt)
        }
        if !still, active {
            bandPhase = (bandPhase + tau * ReactorMath.bandRate(heat: h, overdrive: o) * dt).truncatingRemainder(dividingBy: tau)
        }

        let max = frame.effects.isMax
        let boiling = active && !still && level >= .standard && frame.tier == .redline
        let rate = boiling ? ReactorMath.boltRate(overdrive: o, max: max) : 0
        if rate > 0 || !lightning.isEmpty {
            let started = lightning.step(time: frame.time, dt: dt, rate: rate, maxBolts: ReactorMath.maxBolts(max: max),
                                         sparkPool: ReactorMath.sparkPool(max: max), overdrive: o)
            if started > 0, ReactorMath.mayFlash(at: frame.time, lastFlash: lastFlash) { lastFlash = frame.time }
        }
    }

    func pulse(at time: TimeInterval, strength: Double, heat: Double) {
        pendingPulse = (time, strength, heat)
    }

    func celebrate(at time: TimeInterval) {
        pendingLock = time
    }

    private func lockGold(_ frame: OrbFrame) -> Double {
        let age = frame.time - lockStart
        return lockReduced ? ReactorMath.reducedLockGold(age: age) : ReactorMath.lockGold(age: age)
    }

    private func boltFlash(_ frame: OrbFrame) -> Double {
        let age = frame.time - lastFlash
        guard age >= 0, age < Self.flashDuration else { return 0 }
        return 1 - age / Self.flashDuration
    }

    func isBusy(_ frame: OrbFrame) -> Bool {
        let lockAge = frame.time - lockStart
        let lockRunning = lockAge >= 0 && lockAge < (lockReduced ? ReactorMath.reducedLockDuration : ReactorMath.lockEnd)
        let flareAge = frame.time - flareStart
        return kick > 0 || lockRunning || pendingLock != nil || pendingPulse != nil || !lightning.isEmpty
            || (flareAge >= 0 && flareAge < ReactorMath.coronaFlareDuration) || boltFlash(frame) > 0
    }

    func ambientFrameClass(_ frame: OrbFrame) -> OrbFrameClass {
        if frame.isIdle || frame.unavailable { return .none }
        return frame.tier >= .overdrive ? .fps60 : .fps30
    }

    // MARK: Layers

    private struct Palette {
        var heat: RGBColor
        var hot: RGBColor
        var unlit: RGBColor
        var tailFloor: Double
        var glow: Double
    }

    func build(into scene: inout OrbScene, _ frame: OrbFrame) {
        let thumbnail = frame.content.isThumbnail || frame.content.valueOnly
        let active = !frame.isIdle && !frame.unavailable
        let h = frame.instrumentHeat * frame.activity
        let dark = frame.dark
        let palette = Palette(
            heat: frame.labelColor(max(h, dark ? 0.02 : 0.05)),
            hot: frame.hotColor(h),
            unlit: frame.tokens.unlitSegment,
            tailFloor: frame.content.increaseContrast ? 0.6 : (dark ? 0.25 : 0.5),
            glow: (frame.content.increaseContrast ? 0.5 : 1) * (frame.effects.isMax ? 1.3 : 1)
        )
        let gold = frame.effects.celebrate ? lockGold(frame) : 0
        if !thumbnail {
            addStator(&scene, frame, palette)
            addTracks(&scene, frame, palette)
            if active { addCorona(&scene, frame, palette, heat: h) }
        }
        addRotorA(&scene, frame, palette, heat: h, active: active, gold: gold)
        if !thumbnail { addRotorB(&scene, frame, palette, heat: h, active: active, gold: gold) }
        addRotorC(&scene, frame, palette, heat: h, active: active, gold: gold)
        if !thumbnail {
            addFlareRing(&scene, frame)
            addLightning(&scene, frame)
        }
        addCore(&scene, frame, palette, heat: h, active: active, gold: gold, thumbnail: thumbnail)
    }

    private func addStator(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette) {
        let s = frame.s
        let unlit = palette.unlit
        scene.add(.ring(center: frame.center, radius: ReactorMath.statorRadius * s, width: max(1, ReactorMath.statorWidth * s),
                        color: unlit.opacity(1.4)), blend: .over)
        let count = ReactorMath.notchCount(small: frame.isSmall)
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 360
            let bright = count == 4 || index % 6 == 0
            scene.add(.capsule(from: frame.point(angle, ReactorMath.notchInner), to: frame.point(angle, ReactorMath.notchOuter),
                               width: max(0.8, ReactorMath.notchWidth * s), color: unlit.opacity(bright ? 2.6 : 1.4)), blend: .over)
        }
    }

    private func addTracks(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette) {
        let s = frame.s
        let color = palette.unlit.opacity(frame.content.increaseContrast ? 2 : 1)
        scene.add(.ring(center: frame.center, radius: ReactorMath.rotorARadius * s, width: ReactorMath.rotorAWidth * s, color: color),
                  blend: .over)
        scene.add(.ring(center: frame.center, radius: ReactorMath.rotorCRadius * s, width: ReactorMath.rotorCWidth * s, color: color),
                  blend: .over)
    }

    private func addCorona(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette, heat h: Double) {
        let still = frame.effects.reduceMotion || frame.effects.level == .off
        let breath = still ? 1 : 1 + 0.15 * sin(breathPhase)
        let flare = still ? 0 : ReactorMath.coronaFlare(age: frame.time - flareStart)
        let flash = 0.2 * boltFlash(frame) + 0.25 * frame.flash
        var alpha = (ReactorMath.coronaAlpha(heat: h, dark: frame.dark, max: false) * breath + flare + flash)
            * (frame.effects.isMax ? 1.2 : 1)
        if frame.content.increaseContrast { alpha *= 0.5 }
        guard alpha > 0.004 else { return }
        let color = frame.dark ? palette.heat.mix(HeatPalette.whiteHot, 0.2 * frame.overdrive) : palette.heat
        // A soft radial falloff from the core rim; its curve concentrates light near the rim, so it reaches a bit further.
        scene.add(.radial(center: frame.center, inner: ReactorMath.coreRadius * frame.s, outer: 0.42 * frame.s, color: color,
                          alpha: min(1, alpha)), blend: frame.glowBlend)
    }

    /// Head and tail of an arc of rotor A or C.
    private func arcColors(_ frame: OrbFrame, _ palette: Palette, active: Bool, gold: Double) -> (head: RGBColor, tail: RGBColor, alpha: Double) {
        guard active else {
            return (Self.slate, Self.slate, frame.dark ? 0.38 : 0.45)
        }
        var head = palette.hot
        if gold > 0 { head = head.mix(Self.gold, gold) }
        if frame.flash > 0 { head = head.mix(.white, 0.25 * frame.flash) }
        return (head, palette.heat, 1)
    }

    private func addRotorA(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette, heat h: Double, active: Bool, gold: Double) {
        let s = frame.s
        let length = ReactorMath.arcLengthA(heat: active ? h : 0, overdrive: active ? frame.overdrive : 0)
        let width = ReactorMath.rotorAWidth * s * (active ? 1 : 0.6)
        let radius = ReactorMath.rotorARadius * s
        let colors = arcColors(frame, palette, active: active, gold: gold)
        let blend = frame.glowBlend
        let glows = active && frame.dark && !frame.content.isThumbnail && !frame.content.valueOnly
        let sigma = 0.015 * s * (frame.effects.isMax ? 1.3 : 1)
        let glowAlpha = 0.7 * palette.glow * ReactorMath.strokeGlow(width: Double(width), sigma: Double(sigma))
        for index in 0..<ReactorMath.rotorAArcs {
            let head = angleA + Double(index) * 120
            if glows {
                let glow = palette.heat.opacity(glowAlpha)
                scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: head - length, sweep: length,
                                   color: glow, startColor: glow, startAlpha: palette.tailFloor, core: 0,
                                   glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1), blend: .additive)
            }
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: head - length, sweep: length,
                               color: colors.head.opacity(colors.alpha), startColor: colors.tail.opacity(colors.alpha),
                               startAlpha: palette.tailFloor), blend: blend)
        }
    }

    private func addRotorB(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette, heat h: Double, active: Bool, gold: Double) {
        let s = frame.s
        let small = frame.isSmall
        let count = ReactorMath.coilCount(small: small)
        let length = ReactorMath.coilLength(small: small)
        let radius = ReactorMath.rotorBRadius * s
        let width = ReactorMath.rotorBWidth * s
        let sign = frame.signOfLife
        for index in 0..<count {
            let position = Double(index) / Double(count)
            var energy = active ? ReactorMath.coilEnergy(theta: position * 2 * .pi, psi: bandPhase, heat: h) : 0.25
            if let u = sign {
                energy += reducedMotion ? 0.3 * sin(.pi * u) : ReactorMath.signOfLifeBand(position: position, progress: u)
            }
            var color: RGBColor
            if gold > 0 {
                energy = max(energy, gold)
                color = (active ? palette.heat : Self.slate).mix(Self.gold, gold)
            } else if !active {
                color = Self.slate
            } else {
                color = energy > 0.75 ? palette.heat.mix(palette.hot, (energy - 0.75) * 3) : palette.heat
                if frame.flash > 0 { color = color.mix(.white, 0.2 * frame.flash) }
            }
            let center = angleB + position * 360
            let alpha = min(1, energy)
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: center - length / 2, sweep: length,
                               color: color.opacity(alpha), startColor: color.opacity(alpha)), blend: frame.glowBlend)
        }
    }

    private func addRotorC(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette, heat h: Double, active: Bool, gold: Double) {
        let s = frame.s
        let length = ReactorMath.arcLengthC(heat: active ? h : 0, overdrive: active ? frame.overdrive : 0)
        let width = ReactorMath.rotorCWidth * s
        let radius = ReactorMath.rotorCRadius * s
        let colors = arcColors(frame, palette, active: active, gold: gold)
        let alpha = colors.alpha * (active ? 0.95 : 1)
        for index in 0..<ReactorMath.rotorCArcs {
            let head = angleC + Double(index) * 180
            scene.add(.bandArc(center: frame.center, radius: radius, width: width, start: head - length, sweep: length,
                               color: colors.head.opacity(alpha), startColor: colors.tail.opacity(alpha),
                               startAlpha: palette.tailFloor), blend: frame.glowBlend)
        }
    }

    private func addFlareRing(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !frame.effects.reduceMotion, frame.effects.level >= .soft,
              let ring = ReactorMath.flareRing(age: frame.time - flareStart) else { return }
        let heat = max(0.15, flareHeat)
        let color = frame.labelColor(heat).opacity(ring.alpha)
        scene.add(.ring(center: frame.center, radius: ring.radius * frame.s, width: ring.width * frame.s + 0.5, color: color),
                  blend: frame.glowBlend)
    }

    private func addLightning(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !lightning.isEmpty else { return }
        let s = frame.s
        let c = frame.center
        let dark = frame.dark
        let glowColor = dark ? HeatPalette.color(0.92) : frame.labelColor(0.9)
        let coreColor = dark ? HeatPalette.whiteHot : HeatPalette.amberHot
        let blend = frame.glowBlend
        for bolt in lightning.bolts {
            let alpha = ReactorMath.boltAlpha(progress: (frame.time - bolt.start) / bolt.life)
            guard alpha > 0.01 else { continue }
            for stroke in 0..<3 {
                let width: CGFloat
                let color: RGBColor
                switch stroke {
                case 0:
                    width = 0.03 * s
                    color = glowColor.opacity(0.28 * alpha)
                case 1:
                    width = 0.011 * s
                    color = glowColor.opacity(0.75 * alpha)
                default:
                    width = max(0.6, 0.0045 * s)
                    color = coreColor.opacity(alpha)
                }
                var previous = ReactorLightning.point(bolt, 0, time: frame.time)
                for index in 1...ReactorMath.boltSegments {
                    let next = ReactorLightning.point(bolt, index, time: frame.time)
                    scene.add(.capsule(from: CGPoint(x: c.x + previous.x * s, y: c.y + previous.y * s),
                                       to: CGPoint(x: c.x + next.x * s, y: c.y + next.y * s), width: width, color: color),
                              blend: blend)
                    previous = next
                }
            }
        }
        guard frame.effects.level >= .standard else { return }
        for spark in lightning.sparks {
            let u = spark.age / spark.life
            let center = CGPoint(x: c.x + spark.x * s, y: c.y + spark.y * s)
            let color = dark ? HeatPalette.whiteHot.mix(HeatPalette.color(0.9), u) : HeatPalette.amberHot
            scene.add(.circle(center: center, radius: spark.size * 0.6 * frame.unit,
                              color: color.opacity((1 - u) * frame.readoutZoneFade(at: center))), blend: blend)
        }
    }

    private func addCore(_ scene: inout OrbScene, _ frame: OrbFrame, _ palette: Palette, heat h: Double, active: Bool,
                         gold: Double, thumbnail: Bool) {
        let s = frame.s
        let radius = ReactorMath.coreRadius * s
        let dark = frame.dark
        let top = dark ? RGBColor(hex: 0x181C28, alpha: 0.97) : RGBColor(hex: 0xFFFFFF, alpha: 0.99)
        let bottom = dark ? RGBColor(hex: 0x080A0F, alpha: 0.97) : RGBColor(hex: 0xEEF1F6, alpha: 0.99)
        scene.add(.circle(center: frame.center, radius: radius, color: top)
            .radialGradient(to: bottom, offset: CGPoint(x: 0, y: -0.08 * s), radius: radius + 0.08 * s), blend: .over)

        let width = max(1, ReactorMath.coreRimWidth * s)
        guard active else {
            scene.add(.ring(center: frame.center, radius: radius, width: width, color: palette.unlit.opacity(2.2)), blend: .over)
            return
        }
        var rim = gold > 0 ? palette.heat.mix(Self.gold, gold) : palette.heat.mix(palette.hot, 0.4 * frame.overdrive)
        if frame.flash > 0 { rim = rim.mix(.white, 0.25 * frame.flash) }
        if dark, !thumbnail {
            let sigma = (0.015 + 0.015 * h) * s * (frame.effects.isMax ? 1.3 : 1)
            let glow = palette.heat.opacity(0.9 * palette.glow * ReactorMath.strokeGlow(width: Double(width), sigma: Double(sigma)))
            scene.add(.ring(center: frame.center, radius: radius, width: width, color: glow, core: 0,
                            glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1), blend: .additive)
        }
        scene.add(.ring(center: frame.center, radius: radius, width: width, color: rim.opacity(0.6 + 0.4 * h)), blend: .over)
    }
}

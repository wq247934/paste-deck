import Foundation
import simd

/// Turns the stage into the draw list of one frame (DESIGN 4c): scenery, speed lines, the outgoing and current
/// vehicles (with motion ghosts), particles, the upgrade flash and the idle light band.
public final class HeroFrameBuilder {
    public let library: HeroLibrary
    let stars: [SIMD3<Double>]

    public init(library: HeroLibrary) {
        self.library = library
        var seed = 11.0
        func next() -> Double {
            seed = (seed * 16807).truncatingRemainder(dividingBy: 2_147_483_647)
            return seed / 2_147_483_647
        }
        stars = (0..<library.scenery.space.stars).map { _ in
            let x = next() * 100, y = next() * 100
            return SIMD3(x, y, 0.5 + next() * 0.7)
        }
    }

    /// Values shared by everything drawn in one frame.
    struct Frame {
        let stage: HeroStage
        let paint: HeroPaint
        let time: Double
        let heat: Double
        let overdrive: Double
        let band: Double
        let wake: Double
        let ground: Double
        let distance: Double
        let level: HeroLevel
        let animated: Bool
        let presence: Double
        /// Base stroke width with Increase Contrast applied, and without.
        let width: Double
        let plainWidth: Double
        let glowOpacity: Double
        let sigma: Double
        let base: HeroAffine
        let currentEffects: HeroStartupEffects

        var dark: Bool { paint.dark }
    }

    public func build(stage: HeroStage, paint: HeroPaint, into list: HeroDrawList) {
        list.reset()
        list.dark = paint.dark
        let mask = library.mask
        list.mask = SIMD4(Float(mask.cx), Float(mask.cy), Float(mask.solid), Float(mask.clear))
        let frame = makeFrame(stage: stage, paint: paint)

        list.section = .scenery
        drawScenery(frame, into: list)
        list.section = .speedLines
        if frame.animated { drawSpeedLines(frame, into: list) }
        if let leaving = stage.outgoing {
            drawActor(leaving, outgoing: true, frame, into: list)
        }
        drawActor(stage.current, outgoing: false, frame, into: list)
        list.section = .particles
        if frame.animated { drawParticles(frame, into: list) }
        list.section = .flash
        drawFlash(frame, into: list)
        applySweep(frame, into: list)
    }

    private func makeFrame(stage: HeroStage, paint: HeroPaint) -> Frame {
        let t = stage.time
        let level = stage.level
        let animated = stage.animated
        let dark = paint.dark
        let wake = HeroMath.clamp(stage.wake.value, 0, 1)
        let breath = animated ? 0.86 + 0.14 * sin(2 * .pi * t / 4.8) : 1
        let idleOpacity = (dark ? 0.55 : 0.5) * breath
        let effects = stage.startupEffects(for: stage.current.vehicle)

        var glow = dark ? 0.30 + 0.45 * stage.heat + 0.15 * stage.overdrive : 0.14 + 0.18 * stage.heat
        if level == .off { glow = dark ? 0.30 : 0.12 }
        glow *= wake * (1 + effects.glow) * (paint.increaseContrast ? 0.5 : 1)
        if let flash = stage.flash, t >= flash.start {
            glow *= 1 + 0.6 * (1 - HeroMath.clamp((t - flash.start) / 0.4, 0, 1))
        }

        var shake = 0.0
        if level >= .standard, stage.tier >= 4, !stage.parked {
            shake = (0.2 + 0.5 * stage.overdrive) * (level == .max ? 1.4 : 1)
        }
        if animated { shake += effects.shake }
        var base = HeroAffine.identity
        if shake > 0 {
            let p = 2 * Double.pi
            let sx = shake * (0.5 * sin(p * 23 * t) + 0.3 * sin(p * 31 * t + 1) + 0.2 * sin(p * 41 * t + 2))
            let sy = shake * (0.5 * sin(p * 19 * t + 0.5) + 0.3 * sin(p * 29 * t + 2) + 0.2 * sin(p * 37 * t + 1))
            base = base.translated(sx, sy)
        }

        let plain = library.strokeWidth
        return Frame(
            stage: stage,
            paint: paint,
            time: t,
            heat: stage.heat,
            overdrive: stage.overdrive,
            band: stage.band,
            wake: wake,
            ground: stage.ground.value,
            distance: stage.distance,
            level: level,
            animated: animated,
            presence: idleOpacity + (1 - idleOpacity) * wake,
            width: plain * (paint.increaseContrast ? 1.3 : 1),
            plainWidth: plain,
            glowOpacity: glow,
            sigma: (1.0 + 1.4 * stage.heat + 0.6 * stage.overdrive) * (level == .max ? 1.2 : 1),
            base: base,
            currentEffects: effects
        )
    }

    // MARK: Emission helpers

    /// Strokes (and fills) `vertices` through `transform` as one item.
    func emit(_ vertices: [HeroVertex], _ transform: HeroAffine, flags: HeroDrawFlags, halfWidth: Double, opacity: Double,
              color: SIMD4<Float>, fill: SIMD4<Float> = .zero, glow: Double, sigma: Double, into list: HeroDrawList) {
        guard opacity > 0.002 || glow > 0.002 || flags.contains(.fill) else { return }
        list.begin(flags: flags, halfWidth: halfWidth, opacity: min(1, opacity), color: color, fill: fill, glow: min(1, glow), sigma: sigma)
        for vertex in vertices {
            let p = transform.apply(vertex.x, vertex.y)
            if vertex.move { list.move(p.x, p.y) } else { list.line(p.x, p.y) }
        }
        list.end()
    }

    func emit(_ limb: HeroLimb, _ transform: HeroAffine, halfWidth: Double, opacity: Double, color: SIMD4<Float>,
              glow: Double, sigma: Double, into list: HeroDrawList) {
        guard limb.count > 1, opacity > 0.002 || glow > 0.002 else { return }
        list.begin(flags: .stroke, halfWidth: halfWidth, opacity: min(1, opacity), color: color, glow: min(1, glow), sigma: sigma)
        for index in 0..<limb.count {
            let p = transform.apply(limb[index])
            if index == 0 { list.move(p.x, p.y) } else { list.line(p.x, p.y) }
        }
        list.end()
    }

    /// A straight stroke from `from` to `to` that fades out toward `to` when `fading`.
    func segment(_ from: SIMD2<Double>, _ to: SIMD2<Double>, halfWidth: Double, opacity: Double, color: SIMD4<Float>,
                 fading: Bool, glow: Double = 0, sigma: Double = 0, into list: HeroDrawList) {
        guard opacity > 0.002 else { return }
        list.begin(flags: fading ? [.stroke, .fade] : .stroke, halfWidth: halfWidth, opacity: min(1, opacity), color: color,
                   glow: glow, sigma: sigma)
        list.move(from.x, from.y)
        list.line(to.x, to.y)
        if fading { list.fade(from: 0, to: simd_length(to - from)) }
        list.end()
    }

    /// An arc about `center` (radians, clockwise on screen) as a polyline.
    func arc(center: SIMD2<Double>, radius: Double, from start: Double, to end: Double, _ transform: HeroAffine,
             halfWidth: Double, opacity: Double, color: SIMD4<Float>, flags: HeroDrawFlags = .stroke, sigma: Double = 0,
             into list: HeroDrawList) {
        guard opacity > 0.002 else { return }
        let steps = max(6, Int((abs(end - start) * radius / 1.2).rounded(.up)))
        list.begin(flags: flags, halfWidth: halfWidth, opacity: min(1, opacity), color: color, glow: 0, sigma: sigma)
        for step in 0...steps {
            let angle = start + (end - start) * Double(step) / Double(steps)
            let p = transform.apply(center.x + radius * cos(angle), center.y + radius * sin(angle))
            if step == 0 { list.move(p.x, p.y) } else { list.line(p.x, p.y) }
        }
        list.end()
    }

    // MARK: Idle sweep

    private func applySweep(_ frame: Frame, into list: HeroDrawList) {
        let stage = frame.stage
        guard frame.animated, stage.parked else { return }
        let amount = 1 - frame.wake
        guard amount >= 0.05 else { return }
        var phase = (frame.time - stage.sweepEpoch).truncatingRemainder(dividingBy: HeroStage.sweepPeriod)
        if phase < 0 { phase += HeroStage.sweepPeriod }
        let u = phase / HeroStage.sweepDuration
        guard u < 1 else { return }
        let eased = 0.5 - 0.5 * cos(Double.pi * u)
        let x = -10 + 120 * eased
        list.sweep.band = SIMD4(Float(x), 9, Float(amount), 0)
        list.sweep.color = frame.paint.sweep
    }
}

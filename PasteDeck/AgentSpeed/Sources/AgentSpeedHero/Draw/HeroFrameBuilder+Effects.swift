import Foundation
import simd

extension HeroFrameBuilder {
    /// Ambient speed lines: fading head to tail, the accent color at redline (dark).
    func drawSpeedLines(_ frame: Frame, into list: HeroDrawList) {
        let stage = frame.stage
        let color = frame.dark && stage.tier >= 4 ? frame.paint.hot : frame.paint.stroke
        let extra = frame.ground / 60 * 1.5
        let halfWidth = library.strokeWidth * 0.5 / 2
        for line in stage.lines.pool where line.alive {
            let length = line.length + extra
            let head = frame.base.apply(line.x, line.y)
            let tail = frame.base.apply(line.x - line.dx * length, line.y - line.dy * length)
            let opacity = line.opacity * HeroMath.clamp(line.age / 0.12, 0, 1)
            segment(head, tail, halfWidth: halfWidth, opacity: opacity, color: color, fading: true, into: list)
        }
    }

    func drawParticles(_ frame: Frame, into list: HeroDrawList) {
        let paint = frame.paint
        let w0 = library.strokeWidth
        let glow = frame.glowOpacity
        let sigma = frame.sigma
        let hot = frame.dark ? paint.core : paint.hot
        for particle in frame.stage.particles.pool where particle.alive {
            guard let u = particle.progress else { continue }
            let center = frame.base.apply(particle.x, particle.y)
            switch particle.kind {
            case .puff, .ring:
                let radius = particle.size + particle.grow * (1 - (1 - u) * (1 - u))
                let opacity = (particle.kind == .ring ? 0.7 : 0.5) * (1 - u)
                let color = particle.kind == .ring ? HeroColor.mix(paint.hot, paint.stroke, u) : paint.stroke
                list.circle(cx: center.x, cy: center.y, radius: radius, halfWidth: w0 * 0.45 * (1 - 0.5 * u) / 2,
                            opacity: opacity, color: color, glow: glow * opacity * 0.6, sigma: sigma)
            case .spark:
                let tail = frame.base.apply(particle.x - particle.vx * 0.022, particle.y - particle.vy * 0.022)
                let opacity = 1 - u
                segment(center, tail, halfWidth: w0 * 0.45 / 2, opacity: opacity * 0.95, color: HeroColor.mix(hot, paint.stroke, u),
                        fading: false, glow: min(1, glow * opacity), sigma: sigma, into: list)
            case .arc:
                let opacity = 1 - u
                let inner = 3.2, outer = inner + particle.size
                list.begin(flags: .stroke, halfWidth: w0 * 0.4 / 2, opacity: opacity * 0.95, color: hot,
                           glow: min(1, glow * opacity), sigma: sigma)
                let start = frame.base.apply(particle.x + cos(particle.angle) * inner, particle.y + sin(particle.angle) * inner)
                list.move(start.x, start.y)
                for step in 1...3 {
                    let radius = inner + (outer - inner) * Double(step) / 3
                    let jitter = (step % 2 == 1 ? 1.0 : -1.0) * 0.35 * (0.5 + particle.seed)
                    let p = frame.base.apply(particle.x + cos(particle.angle + jitter) * radius,
                                             particle.y + sin(particle.angle + jitter) * radius)
                    list.line(p.x, p.y)
                }
                list.end()
            case .pop:
                let length = 3.4 * sin(.pi * u)
                guard length > 0.05 else { continue }
                let placed = frame.base.translated(particle.x, particle.y).rotated(particle.angle)
                let fill = HeroColor.withAlpha(paint.core, 0.95)
                list.begin(flags: .fill, halfWidth: 0, opacity: 0, color: paint.core, fill: fill, glow: min(1, glow), sigma: sigma)
                emitTeardrop(length: length, placed, into: list)
                list.end()
            }
        }
    }

    /// `M 0 −0.9 Q 0.6l −0.9 l 0 Q 0.6l 0.9 0 0.9 Z`, flattened.
    private func emitTeardrop(length: Double, _ transform: HeroAffine, into list: HeroDrawList) {
        let steps = 8
        let start = transform.apply(0, -0.9)
        list.move(start.x, start.y)
        for k in 1...steps {
            let t = Double(k) / Double(steps), u = 1 - t
            let p = transform.apply(2 * u * t * length * 0.6 + t * t * length, u * u * -0.9 + 2 * u * t * -0.9)
            list.line(p.x, p.y)
        }
        for k in 1...steps {
            let t = Double(k) / Double(steps), u = 1 - t
            let p = transform.apply(u * u * length + 2 * u * t * length * 0.6, 2 * u * t * 0.9 + t * t * 0.9)
            list.line(p.x, p.y)
        }
        list.line(start.x, start.y)
    }

    /// The upgrade flash: a radial gradient on the incoming vehicle's center, radius 8 → 36 over 0.35 s.
    func drawFlash(_ frame: Frame, into list: HeroDrawList) {
        let stage = frame.stage
        guard let flash = stage.flash, frame.time >= flash.start else { return }
        let u = HeroMath.clamp((frame.time - flash.start) / 0.35, 0, 1)
        let vehicle = library.vehicles[stage.current.vehicle]
        let center = frame.base.apply(vehicle.center)
        let radius = 8 + 28 * HeroMath.easeOutCubic(u)
        let alpha = (frame.dark ? 0.42 : 0.26) * flash.strength * (1 - u) * (1 - u) * (frame.level == .soft ? 0.6 : 1)
        guard alpha > 0.002 else { return }
        let paint = frame.paint
        let inner = HeroColor.withAlpha(frame.dark ? HeroColor.whiteHot : paint.hot, alpha)
        let mid = HeroColor.withAlpha(paint.hot, alpha * 0.45)
        list.radial(cx: center.x, cy: center.y, radius: radius, center: inner, mid: mid, flags: frame.dark ? .additive : [])
    }
}

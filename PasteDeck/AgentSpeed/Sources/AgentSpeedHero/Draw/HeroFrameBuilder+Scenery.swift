import Foundation
import simd

extension HeroFrameBuilder {
    /// Scenery belongs to its vehicle and crossfades with it; a scenery shared by both vehicles stays and glides its
    /// ground line between their heights (DESIGN 4c, Title transitions).
    func drawScenery(_ frame: Frame, into list: HeroDrawList) {
        let stage = frame.stage
        let current = library.vehicles[stage.current.vehicle]
        if let leaving = stage.outgoing {
            let previous = library.vehicles[leaving.vehicle]
            if previous.scenery == current.scenery {
                var ground = current.groundY
                if let from = previous.groundY, let to = current.groundY {
                    let u = HeroMath.clamp((frame.time - stage.current.start) / 0.45, 0, 1)
                    ground = from + (to - from) * (0.5 - 0.5 * cos(Double.pi * u))
                }
                drawScenery(current.scenery, ground: ground, vehicle: current, alpha: frame.presence, frame, into: list)
                return
            }
            let alpha = stage.placement(of: leaving, outgoing: true).alpha
            drawScenery(previous.scenery, ground: previous.groundY, vehicle: previous, alpha: alpha * frame.presence, frame, into: list)
        }
        let alpha = stage.placement(of: stage.current, outgoing: false).alpha
        drawScenery(current.scenery, ground: current.groundY, vehicle: current, alpha: alpha * frame.presence, frame, into: list)
    }

    private func drawScenery(_ kind: HeroSceneryKind, ground: Double?, vehicle: HeroVehicle, alpha: Double, _ frame: Frame,
                             into list: HeroDrawList) {
        guard alpha > 0.002 else { return }
        let scenery = library.scenery
        let w = library.strokeWidth
        let base = (frame.dark ? 0.30 : 0.34) * alpha
        let color = frame.paint.stroke
        let transform = frame.base
        let travelled = frame.distance
        let speed = frame.ground
        switch kind {
        case .road:
            guard let y = ground else { return }
            let dash = scenery.road.dash[0], gap = scenery.road.dash[1], period = dash + gap
            let smear = HeroMath.clamp(speed / 60 / period / 0.45, 0, 1)
            let length = dash + smear * gap * 0.85
            let offset = (travelled * scenery.road.parallax).truncatingRemainder(dividingBy: period)
            list.begin(flags: .stroke, halfWidth: w * 0.55 / 2, opacity: base * (1 - 0.35 * smear), color: color)
            var x = -offset - period
            while x < 104 {
                let a = transform.apply(x, y), b = transform.apply(x + length, y)
                list.move(a.x, a.y)
                list.line(b.x, b.y)
                x += period
            }
            list.end()
        case .rail:
            guard let y = ground else { return }
            let rail = scenery.rail
            line(from: SIMD2(-2, y), to: SIMD2(102, y), transform, halfWidth: w * 0.55 / 2, opacity: base * 1.3, color: color, into: list)
            let smear = HeroMath.clamp(speed / 60 / rail.sleeperSpacing / 0.4, 0, 1)
            let offset = (travelled * rail.parallax).truncatingRemainder(dividingBy: rail.sleeperSpacing)
            list.begin(flags: .stroke, halfWidth: w * 0.5 / 2, opacity: base * (1 - 0.55 * smear), color: color)
            var x = -offset
            while x < 106 {
                let a = transform.apply(x, y + 1.4), b = transform.apply(x - 1.2 + smear * 4, y + 1.4 + rail.sleeperDepth)
                list.move(a.x, a.y)
                list.line(b.x, b.y)
                x += rail.sleeperSpacing
            }
            list.end()
        case .guideway:
            guard let y = ground else { return }
            let guideway = scenery.guideway
            list.begin(flags: .stroke, halfWidth: w * 0.55 / 2, opacity: base * 1.2, color: color)
            for beam in 0..<2 {
                let height = y + (beam == 0 ? 0 : guideway.depth)
                let a = transform.apply(-2, height), b = transform.apply(102, height)
                list.move(a.x, a.y)
                list.line(b.x, b.y)
            }
            list.end()
            let offset = (travelled * guideway.parallax).truncatingRemainder(dividingBy: guideway.pylonSpacing)
            list.begin(flags: .stroke, halfWidth: w * 0.55 / 2, opacity: base, color: color)
            var x = -offset
            while x < 110 {
                let a = transform.apply(x, y + guideway.depth), b = transform.apply(x, y + guideway.depth + guideway.pylonDepth)
                list.move(a.x, a.y)
                list.line(b.x, b.y)
                x += guideway.pylonSpacing
            }
            list.end()
        case .sky:
            let spacing = 72.0
            for (index, layer) in scenery.sky.layers.enumerated() {
                let drift = travelled * layer.parallax
                let offset = (drift + Double(index) * 31).truncatingRemainder(dividingBy: spacing)
                let opacity = layer.opacity * alpha * (frame.dark ? 1 : 1.2)
                var x = 104 - offset
                while x > -30 {
                    let shape = (Int(((x + drift) / spacing).rounded()) + index) & 1
                    let placed = transform.translated(x - 8, layer.y).scaled(layer.scale, layer.scale)
                    emit(library.clouds[shape % library.clouds.count], placed, flags: .stroke, halfWidth: w * 0.5 / 2,
                         opacity: opacity, color: color, glow: 0, sigma: 0, into: list)
                    x -= spacing
                }
            }
        case .stratosphere:
            let horizon = scenery.stratosphere.horizon
            let center = SIMD2(50.0, horizon.cy)
            arc(center: center, radius: horizon.r, from: .pi * 1.15, to: .pi * 1.85, transform, halfWidth: w * 0.55 / 2,
                opacity: base, color: color, into: list)
            arc(center: SIMD2(50, horizon.cy + 1.4), radius: horizon.r, from: .pi * 1.2, to: .pi * 1.8, transform,
                halfWidth: w * 2.2 / 2, opacity: base * 0.35, color: color, flags: [.stroke, .soft], sigma: 0.95, into: list)
        case .space:
            let direction = vehicle.headingVector
            let parallax = scenery.space.parallax
            let streak = max(0.3, speed * parallax / 60 * 1.3)
            for star in stars {
                let d = (travelled * parallax * star.z).truncatingRemainder(dividingBy: 140)
                var x = star.x - direction.x * d, y = star.y - direction.y * d
                x = (x.truncatingRemainder(dividingBy: 120) + 120).truncatingRemainder(dividingBy: 120) - 10
                y = (y.truncatingRemainder(dividingBy: 120) + 120).truncatingRemainder(dividingBy: 120) - 10
                line(from: SIMD2(x, y), to: SIMD2(x + direction.x * streak * star.z, y + direction.y * streak * star.z), transform,
                     halfWidth: w * 0.4 / 2, opacity: base * star.z * 1.2, color: color, into: list)
            }
        }
    }

    private func line(from: SIMD2<Double>, to: SIMD2<Double>, _ transform: HeroAffine, halfWidth: Double, opacity: Double,
                      color: SIMD4<Float>, into list: HeroDrawList) {
        segment(transform.apply(from), transform.apply(to), halfWidth: halfWidth, opacity: opacity, color: color, fading: false,
                into: list)
    }
}

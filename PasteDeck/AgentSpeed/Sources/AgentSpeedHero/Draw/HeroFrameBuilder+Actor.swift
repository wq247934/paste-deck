import Foundation
import simd

extension HeroFrameBuilder {
    /// The ghost trail of an upgrade: delay (s) and opacity of each copy.
    private static let ghosts: [(delay: Double, opacity: Double)] = [(0.012, 0.26), (0.026, 0.13), (0.042, 0.06)]

    func drawActor(_ actor: HeroActor, outgoing: Bool, _ frame: Frame, into list: HeroDrawList) {
        let placement = frame.stage.placement(of: actor, outgoing: outgoing)
        guard placement.alpha > 0.002 else { return }
        let effects = outgoing ? HeroStartupEffects() : frame.currentEffects
        if placement.ghostSpeed > 40, frame.animated {
            for ghost in Self.ghosts {
                var copy = placement
                copy.offset -= placement.direction * (placement.ghostSpeed * ghost.delay)
                copy.alpha *= ghost.opacity
                drawVehicle(actor.vehicle, copy, effects: effects, ghost: true, frame, into: list)
            }
        }
        drawVehicle(actor.vehicle, placement, effects: effects, ghost: false, frame, into: list)
    }

    /// One vehicle: trail marks, contrails, far limbs, parts, shock diamonds, field pulse, near limbs.
    private func drawVehicle(_ index: Int, _ placement: HeroPlacement, effects fx: HeroStartupEffects, ghost: Bool,
                             _ frame: Frame, into list: HeroDrawList) {
        let vehicle = library.vehicles[index]
        let stage = frame.stage
        let t = frame.time
        let b = frame.band
        let wake = frame.wake
        let animated = frame.animated
        let alpha = placement.alpha * frame.presence
        let paint = frame.paint
        let glowBase = ghost ? 0 : frame.glowOpacity
        let sigma = frame.sigma
        let w0 = frame.width
        let accel = stage.acceleration

        var bob = 0.0, pitch = 0.0, floatY = 0.0, hover = 0.0
        let lurch = animated ? HeroMath.clamp(0.008 * accel, -1.2, 1.2) + fx.lurch : 0
        if animated {
            if vehicle.bob > 0 {
                let phase = stage.suspensionPhase
                bob = vehicle.bob * (0.6 * sin(1.7 * phase) + 0.4 * sin(3.3 * phase + 1.3)) * (0.4 + 0.6 * b) * wake
            }
            if vehicle.float > 0 {
                floatY = vehicle.float * sin(2 * .pi * 0.32 * t) * (0.3 + 0.7 * wake)
                pitch = 0.8 * (vehicle.float / 0.7) * cos(2 * .pi * 0.32 * t) * wake
            }
            if vehicle.rollsOnTires { pitch += HeroMath.clamp(-0.0035 * accel, -1, 1) + fx.pitch }
        }
        if vehicle.hover > 0 {
            hover = vehicle.hover * fx.hover * wake * (animated ? 0.75 + 0.25 * sin(2 * .pi * 0.7 * t) : 1)
        }
        let direction = vehicle.headingVector
        var ox = placement.offset.x + direction.x * lurch
        var oy = placement.offset.y + direction.y * lurch
        if vehicle.heading != nil {
            ox -= direction.x * fx.lift
            oy -= direction.y * fx.lift
            if animated, vehicle.float > 0 {
                let n = vehicle.float * sin(2 * .pi * 0.55 * t)
                ox -= direction.y * n
                oy += direction.x * n
                floatY = 0
                pitch = 0
            }
        } else {
            oy += fx.lift
        }

        let unsprung = frame.base.translated(ox, oy)
        let sprung = frame.base.translated(ox, oy + bob + floatY - hover).rotated(pitch * .pi / 180, about: vehicle.pitchPivot)

        if !ghost {
            list.section = .trails
            drawTrailMarks(vehicle, frame, ox: ox, oy: oy, floatY: floatY, alpha: alpha, into: list)
            drawContrails(vehicle, frame, ox: ox, oy: oy, alpha: alpha, contrail: fx.contrail, into: list)
        }
        list.section = ghost ? .ghost : .vehicle

        var pose: HeroRigPose?
        let travelled = animated ? frame.distance : vehicle.rest
        switch vehicle.rig {
        case .walk(let rig):
            pose = HeroRig.walk(rig, distance: travelled, ground: vehicle.groundY ?? rig.hip.y, stand: stage.stand).pose
        case .pedal(let rig):
            pose = HeroRig.pedal(rig, distance: travelled, lift: fx.hipLift).pose
        case nil:
            pose = nil
        }
        let rider = library.style(.rider)
        let crank = library.style(.crank)
        if let pose {
            let farOpacity = alpha * rider.opacity * 0.42
            let farGlow = glowBase * alpha * 0.42 * min(1, rider.glow)
            emit(pose.far0, unsprung, halfWidth: w0 * rider.weight / 2, opacity: farOpacity, color: paint.stroke, glow: farGlow, sigma: sigma, into: list)
            emit(pose.far1, unsprung, halfWidth: w0 * rider.weight / 2, opacity: farOpacity, color: paint.stroke, glow: farGlow, sigma: sigma, into: list)
        }

        for part in vehicle.parts {
            drawPart(part, vehicle, frame, sprung: sprung, unsprung: unsprung, pose: pose, effects: fx, alpha: alpha,
                     hover: hover, glowBase: glowBase, ghost: ghost, into: list)
        }

        if !ghost, frame.level >= .standard, b > 0.35, animated {
            drawShockDiamonds(vehicle, frame, sprung: sprung, flame: fx.flame, alpha: alpha, into: list)
        }
        if !ghost, vehicle.hover > 0, animated, wake > 0.05 {
            drawFieldPulse(vehicle, frame, sprung: sprung.translated(0, hover / 2), alpha: alpha * fx.hover, into: list)
        }

        if let pose {
            if let pedal = pose.nearPedal {
                emit(pedal, unsprung, halfWidth: w0 * crank.weight / 2, opacity: alpha * crank.opacity, color: paint.stroke,
                     glow: glowBase * alpha * min(1, crank.glow), sigma: sigma, into: list)
            }
            let opacity = alpha * rider.opacity
            let glow = glowBase * alpha * min(1, rider.glow)
            for limb in 0..<pose.nearCount {
                emit(pose.near(limb), unsprung, halfWidth: w0 * rider.weight / 2, opacity: opacity, color: paint.stroke,
                     glow: glow, sigma: sigma, into: list)
            }
            if let head = pose.head {
                let c = unsprung.apply(head.x, head.y)
                list.circle(cx: c.x, cy: c.y, radius: head.z, halfWidth: w0 * rider.weight / 2, opacity: min(1, opacity),
                            color: paint.stroke, glow: min(1, glow), sigma: sigma)
            }
        }
    }

    // MARK: Parts

    private func drawPart(_ part: HeroPart, _ vehicle: HeroVehicle, _ frame: Frame, sprung: HeroAffine, unsprung: HeroAffine,
                          pose: HeroRigPose?, effects fx: HeroStartupEffects, alpha: Double, hover: Double, glowBase: Double,
                          ghost: Bool, into list: HeroDrawList) {
        let style = library.style(part.role)
        let paint = frame.paint
        let t = frame.time
        let b = frame.band
        let wake = frame.wake
        let animated = frame.animated
        var op = alpha
        var transform = part.sprung ? sprung : unsprung
        if part.role == .rider, let pose { transform = transform.translated(pose.riderOffset.x, pose.riderOffset.y) }

        var spinBlur = 0.0
        if let spin = part.spin {
            let travelled = animated ? frame.distance : vehicle.rest
            if travelled != 0 { transform = transform.rotated(HeroMath.wrapAngle(travelled / spin.radius), about: spin.pivot) }
            if animated {
                let frequency = frame.ground / (2 * .pi * spin.radius) * spin.symmetry
                spinBlur = HeroMath.smooth((frequency - 14) / 12)
            }
        }
        switch part.role {
        case .spoke:
            op *= 1 - spinBlur
        case .light:
            op *= 0.7 + 0.3 * wake + 0.6 * fx.lights
        case .glow:
            op *= fx.hover * (0.5 + 0.5 * b) * wake
            transform = transform.translated(0, hover / 2)
        case .shock:
            let squeeze = 1.15 - 0.35 * b
            transform = transform.translated(part.apex.x, part.apex.y).scaled(1, squeeze).translated(-part.apex.x, -part.apex.y)
            op *= fx.shock * (0.4 + 0.6 * b) * wake * (animated ? 0.7 + 0.3 * sin(2 * .pi * 11 * t) : 1)
        case .flame, .flameCore:
            drawFlame(part, frame, transform: transform, effects: fx, alpha: op, glowBase: glowBase, into: list)
            return
        default:
            break
        }

        let roleOpacity = paint.increaseContrast && part.role.isFaint ? max(style.opacity, 0.9) : style.opacity
        let opacity = min(1, op * roleOpacity)
        let glow = glowBase * min(1, op * min(1, style.glow))
        let color = style.hot ? paint.hot : paint.stroke
        let halfWidth = frame.width * style.weight / 2
        switch part.shape {
        case .circle(let cx, let cy, let r):
            let c = transform.apply(cx, cy)
            if opacity > 0.002 || glow > 0.002 {
                list.circle(cx: c.x, cy: c.y, radius: r, halfWidth: halfWidth, opacity: opacity, color: color, glow: glow, sigma: frame.sigma)
            }
        case .path(let vertices):
            emit(vertices, transform, flags: .stroke, halfWidth: halfWidth, opacity: opacity, color: color, glow: glow,
                 sigma: frame.sigma, into: list)
        }

        if part.role == .spoke, spinBlur > 0.01, !ghost, let spin = part.spin {
            let rr = spin.radius - 2
            let turn = (t * 0.6).truncatingRemainder(dividingBy: 1) * 2 * .pi
            let arcOpacity = 0.5 * spinBlur * alpha
            let arcWidth = frame.width * 0.45 / 2
            arc(center: spin.pivot, radius: rr * 0.72, from: turn, to: turn + 2.1, unsprung, halfWidth: arcWidth,
                opacity: arcOpacity, color: paint.stroke, into: list)
            arc(center: spin.pivot, radius: rr * 0.45, from: turn + .pi, to: turn + .pi + 2.1, unsprung, halfWidth: arcWidth,
                opacity: arcOpacity, color: paint.stroke, into: list)
        }
    }

    /// Flames scale about their nozzle with band, overdrive and flicker; the outline glows in the accent.
    private func drawFlame(_ part: HeroPart, _ frame: Frame, transform: HeroAffine, effects fx: HeroStartupEffects, alpha: Double,
                           glowBase: Double, into list: HeroDrawList) {
        guard let nozzle = part.nozzle, case .path(let vertices) = part.shape else { return }
        let t = frame.time
        let animated = frame.animated
        let flicker = animated
            ? 1 + 0.1 * (sin(2 * .pi * 17 * t) + sin(2 * .pi * 23 * t + 1.1) + sin(2 * .pi * 31 * t + 2.3)) / 3
            : 1
        let length = (0.55 + 0.45 * frame.band + 0.35 * frame.overdrive) * flicker * fx.flame * frame.wake
        guard length >= 0.02 else { return }
        let width = (1 + (animated ? 0.06 * sin(2 * .pi * 13 * t) : 0)) * min(1, 0.6 + 0.4 * length)
        let angle = atan2(nozzle.dir.y, nozzle.dir.x)
        let shaped = transform.translated(nozzle.at.x, nozzle.at.y).rotated(angle).scaled(length, width)
            .rotated(-angle).translated(-nozzle.at.x, -nozzle.at.y)
        let style = library.style(part.role)
        let paint = frame.paint
        if part.role == .flameCore {
            emit(vertices, shaped, flags: .fill, halfWidth: 0, opacity: 0, color: paint.core,
                 fill: HeroColor.withAlpha(paint.core, min(1, alpha * style.fillOpacity)),
                 glow: glowBase * min(1, alpha * style.fillOpacity), sigma: frame.sigma, into: list)
        } else {
            emit(vertices, shaped, flags: [.fill, .stroke], halfWidth: frame.width * style.weight / 2,
                 opacity: alpha * style.opacity, color: paint.hot,
                 fill: HeroColor.withAlpha(paint.stroke, min(1, alpha * style.fillOpacity)),
                 glow: glowBase * min(1, alpha), sigma: frame.sigma, into: list)
        }
    }

    // MARK: Vehicle extras

    private func drawTrailMarks(_ vehicle: HeroVehicle, _ frame: Frame, ox: Double, oy: Double, floatY: Double, alpha: Double,
                                into list: HeroDrawList) {
        let stage = frame.stage
        let halfWidth = frame.width * 0.5 / 2
        if frame.animated {
            guard frame.wake > 0.05, frame.ground > 4 else { return }
            let transform = frame.base.translated(ox, oy + floatY)
            let speed = HeroMath.clamp(frame.ground / 20, 0, 1)
            for emitter in vehicle.emitters where emitter.kind == .trail {
                for (lane, offset) in emitter.lanes.enumerated() {
                    let i = Double(lane)
                    let wobble = 1 + 0.18 * sin(2 * .pi * (5.3 + 1.7 * i) * frame.time + i)
                    let length = emitter.length * (0.45 + 0.55 * frame.band + 0.25 * frame.heat) * wobble * speed
                    let x = emitter.at.x - 1.5 - Double(lane % 2) * 2.5
                    let y = emitter.at.y + offset
                    segment(transform.apply(x, y), transform.apply(x - length, y), halfWidth: halfWidth,
                            opacity: 0.55 * alpha * frame.wake, color: frame.paint.stroke, fading: true, into: list)
                }
            }
        } else {
            guard frame.wake > 0.5, !stage.parked else { return }
            let count = frame.band < 0.34 ? 1 : frame.band < 0.67 ? 2 : 3
            let transform = frame.base.translated(ox, oy)
            for emitter in vehicle.emitters where emitter.kind == .trail {
                for (lane, offset) in emitter.lanes.enumerated() where lane < count {
                    let x = emitter.at.x - 1.5 - Double(lane % 2) * 2.5
                    let y = emitter.at.y + offset
                    segment(transform.apply(x, y), transform.apply(x - emitter.length * 0.7, y), halfWidth: halfWidth,
                            opacity: 0.5 * alpha, color: frame.paint.stroke, fading: false, into: list)
                }
            }
        }
    }

    private func drawContrails(_ vehicle: HeroVehicle, _ frame: Frame, ox: Double, oy: Double, alpha: Double, contrail: Double,
                               into list: HeroDrawList) {
        guard frame.wake > 0.02 else { return }
        let transform = frame.base.translated(ox, oy)
        let t = frame.time
        for emitter in vehicle.emitters where emitter.kind == .contrail {
            let length = (emitter.weak ? 22 : 46) * contrail * (frame.animated ? 1 : 0.8)
            guard length >= 1 else { continue }
            let ax = emitter.at.x - 2, ay = emitter.at.y
            let opacity = (emitter.weak ? 0.26 : 0.55) * (0.5 + 0.5 * frame.band) * alpha * frame.wake
            guard opacity > 0.002 else { continue }
            list.begin(flags: [.stroke, .fade], halfWidth: frame.width * (emitter.weak ? 0.45 : 0.8) / 2, opacity: min(1, opacity),
                       color: frame.paint.stroke)
            var d = 0.0
            while d <= length {
                var y = ay
                if frame.animated {
                    if vehicle.float > 0 {
                        y += vehicle.float * sin(2 * .pi * 0.32 * (t - d / 90)) * (0.3 + 0.7 * frame.wake)
                    }
                    y += 0.35 * sin((ax - d + (frame.distance * 0.05).truncatingRemainder(dividingBy: 14 * .pi)) / 7) * (d / 40)
                }
                let p = transform.apply(ax - d, y)
                if d == 0 { list.move(p.x, p.y) } else { list.line(p.x, p.y) }
                d += 2
            }
            list.fade(from: 0, to: list.currentLength)
            list.end()
        }
    }

    private func drawShockDiamonds(_ vehicle: HeroVehicle, _ frame: Frame, sprung: HeroAffine, flame: Double, alpha: Double,
                                   into list: HeroDrawList) {
        let b = frame.band
        let length = (0.55 + 0.45 * b + 0.35 * frame.overdrive) * flame
        let color = frame.dark ? frame.paint.core : frame.paint.hot
        for emitter in vehicle.emitters where emitter.kind == .afterburner {
            for index in 0..<3 {
                let step = Double(index)
                let center = emitter.at + emitter.dir * ((3.0 + 2.8 * step) * length)
                let height = 1.0 - step * 0.18
                let opacity = 0.75 * (b - 0.35) / 0.65 * alpha * (0.75 + 0.25 * sin(2 * .pi * 19 * frame.time + step))
                guard opacity > 0.002 else { continue }
                list.begin(flags: .stroke, halfWidth: frame.width * 0.35 / 2, opacity: min(1, opacity), color: color)
                for corner in 0...4 {
                    let angle = Double(corner) * .pi / 2
                    let p = sprung.apply(center.x - cos(angle) * height * 0.9, center.y - sin(angle) * height)
                    if corner == 0 { list.move(p.x, p.y) } else { list.line(p.x, p.y) }
                }
                list.end()
            }
        }
    }

    /// The maglev's bright pulse travelling along the hover gap, nose to tail, at half the ground speed.
    private func drawFieldPulse(_ vehicle: HeroVehicle, _ frame: Frame, sprung: HeroAffine, alpha: Double, into list: HeroDrawList) {
        guard let gap = vehicle.parts.first(where: { $0.role == .glow }) else { return }
        let x0 = gap.span.x0, x1 = gap.span.x1, y = gap.span.y
        let span = x1 - x0
        let position = x1 - (frame.distance * 0.5).truncatingRemainder(dividingBy: span + 20)
        let head = min(x1, position), tail = max(x0, position - 14)
        guard head > tail, alpha > 0.002 else { return }
        list.begin(flags: [.stroke, .fade], halfWidth: frame.width * 0.7 / 2, opacity: min(1, 0.9 * alpha), color: frame.paint.hot)
        let a = sprung.apply(head, y), c = sprung.apply(tail, y)
        list.move(a.x, a.y)
        list.line(c.x, c.y)
        list.fade(from: head - position, to: head - position + 14)
        list.end()
    }
}

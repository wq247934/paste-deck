import AgentSpeedHero
import SwiftUI

/// Colors and context of one badge frame.
struct HeroBadgeStyle {
    var center: CGPoint
    /// Points per canvas unit (100 units on 0.72 S).
    var unit: CGFloat
    var dark: Bool
    var increaseContrast: Bool
    var language: AppLanguage
    /// The title (and the one leaving) as drawn; nil text = none.
    var text: String
    var previousText: String
    var alpha: Double
}

/// One title on screen with its transition transform (the transition table of DESIGN 4c, Hero title badge).
private struct BadgeTitleItem {
    var text: String
    var level: Int
    var alpha: Double
    var scale: Double
    var dy: Double
    var boost: Double
}

/// One or two titles, without an array (drawing never allocates).
private struct BadgeTitleItems {
    var first: BadgeTitleItem
    var second: BadgeTitleItem?

    /// The more visible one (it decides where the medallion is interrupted).
    var top: BadgeTitleItem {
        guard let second, second.alpha > first.alpha else { return first }
        return second
    }
}

extension HeroBadge {
    private static let whiteHot = HeatPalette.whiteHot
    private static let amber = HeatPalette.amberHot
    private static let slate = HeatPalette.color(0)

    /// `C`, `H` and the glow color of DESIGN 4c (Color and glow), with the idle slate mixed in by `wake`.
    private func palette(_ style: HeroBadgeStyle) -> (c: RGBColor, h: RGBColor, glow: RGBColor, wake: Double) {
        let heat = input.heat
        let w = wake.value.clamped(to: 0...1)
        let awake = HeroPalette.stroke(heat, dark: style.dark, increaseContrast: style.increaseContrast)
        let hot = style.dark
            ? awake.mixOKLab(Self.whiteHot, 0.65 + 0.35 * input.overdrive)
            : awake.mixOKLab(Self.amber, 0.45)
        let idle = HeroPalette.stroke(0, dark: style.dark, increaseContrast: style.increaseContrast)
        let glow = style.dark ? Self.slate.mixOKLab(awake, w) : Self.slate.mixOKLab(HeatPalette.color(heat), w)
        return (idle.mixOKLab(awake, w), idle.mixOKLab(hot, w), glow, w)
    }

    /// Draws the badge into `scene` (all shapes inside the soft circular mask of the vehicle layer: solid to r 42,
    /// clear at r 49); the title glyphs are text draws on top.
    func build(into scene: inout OrbScene, _ style: HeroBadgeStyle) {
        let pal = palette(style)
        let fx = self.fx
        let u = style.unit
        var shake = CGVector.zero
        if fx >= 2, !input.reduceMotion, level > 0, input.tier >= 4 {
            let a = (0.2 + 0.5 * input.overdrive) * (fx == 3 ? 1.4 : 1)
            let t = time
            let tau = 2 * Double.pi
            shake.dx = a * (0.5 * sin(tau * 23 * t) + 0.3 * sin(tau * 31 * t + 1) + 0.2 * sin(tau * 41 * t + 2))
            shake.dy = a * (0.5 * sin(tau * 19 * t + 0.5) + 0.3 * sin(tau * 29 * t + 2) + 0.2 * sin(tau * 37 * t + 1))
        }
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: style.center.x + CGFloat(x - 50 + shake.dx) * u, y: style.center.y + CGFloat(y - 50 + shake.dy) * u)
        }
        let previousAlpha = scene.alphaScale
        scene.alphaScale = previousAlpha * Float(style.alpha)
        let previousClip = (scene.clipRadius, scene.clipFeather)
        scene.clipRadius = 49 * u
        scene.clipFeather = 7 * u
        defer {
            scene.clipRadius = previousClip.0
            scene.clipFeather = previousClip.1
            scene.alphaScale = previousAlpha
        }
        let blend: OrbBlend = style.dark ? .additive : .over
        let items = titleItems(style: style, fx: fx)

        // 1. Halo
        if !style.increaseContrast, pal.wake > 0.01 {
            let breathe = moving ? 1 + 0.1 * sin(haloPhase) : 1
            let a = (style.dark ? 0.10 + 0.22 * input.heat : 0.05 + 0.08 * input.heat) * pal.wake * breathe
            scene.add(OrbInstance.circle(center: point(50, 50), radius: 34 * u, color: pal.c.opacity(a))
                .radialGradient(to: pal.c.opacity(0), radius: 34 * u), blend: blend)
        }
        // 2. Speed streaks
        let streakColor = style.dark && input.heat >= 0.84 ? pal.h : pal.c
        for streak in streaks where streak.alive {
            let fade = min(1, streak.age / 0.12)
            scene.add(.capsule(from: point(streak.x + streak.length, streak.y), to: point(streak.x, streak.y), width: 0.5 * u,
                               color: streakColor.opacity(streak.alpha * fade), tailColor: streakColor.opacity(0)), blend: blend)
        }
        // 3. Medallion, interrupted by the title like a coin legend
        let top = items.top
        let topTitle = textCache.title(top.text, language: style.language)
        let scale = top.scale
        let halfW = topTitle.inkWidth * scale / 2 + 2.5
        let halfH = topTitle.inkHeight * scale / 2 + 2.5
        let idleK = 0.6 + 0.4 * pal.wake
        let (o1, o2): (Double, Double) = style.increaseContrast ? (0.6, 0.3) : (style.dark ? (0.34, 0.16) : (0.42, 0.22))
        var sweep = 360.0
        if let transition, transition.kind == .startup, moving {
            sweep = 360 * Easing.easeOut(((time - transition.start) / 0.45).clamped(to: 0...1))
        }
        ring(&scene, radius: 33, width: 0.8, from: -90, sweep: sweep, color: pal.c.opacity(o1 * idleK), halfW: halfW, halfH: halfH,
             point: point, unit: u, blend: .over)
        ring(&scene, radius: 30.5, width: 0.5, from: -90, sweep: 360, color: pal.c.opacity(o2 * idleK), halfW: halfW, halfH: halfH,
             point: point, unit: u, blend: .over)
        if let transition, transition.kind == .up, moving {
            let p = (time - transition.start - 0.06) / 0.5
            if p > 0, p < 1 {
                let e = Easing.easeOut(p)
                ring(&scene, radius: 33 + 11 * e, width: 1.6 * (1 - p), from: -90, sweep: 360, color: pal.h.opacity(0.7 * (1 - e)),
                     halfW: halfW, halfH: halfH, point: point, unit: u, blend: .over)
            }
        }
        // 4. Rank pips
        drawPips(&scene, style: style, point: point, unit: u, fx: fx)
        // 5. Orbit motes
        if moving, pal.wake > 0.01 {
            let caps = [0.0, 4, 8, 12]
            let wanted = 2 + 6 * input.heat
            let count = min(caps[fx], fx == 3 ? wanted * 1.5 : wanted)
            let trail = 8 + 40 * input.heat
            for slot in 0..<12 {
                let visible = min(1, max(0, count - Double(slot))) * pal.wake
                guard visible > 0.01 else { continue }
                let head = (motePhase + Double(Self.moteOrder[slot]) / 12 * 2 * .pi) * 180 / .pi
                scene.add(.arc(center: point(50, 50), radius: 33 * u, width: 1.2 * u, start: head - trail, sweep: trail,
                               color: pal.c.opacity(visible), tailColor: pal.c.opacity(0)), blend: blend)
                let radians = head * .pi / 180
                scene.add(.circle(center: point(50 + 33 * cos(radians), 50 + 33 * sin(radians)), radius: 1.0 * u,
                                  color: pal.h.opacity(visible)), blend: blend)
            }
        }
        // 6. Embers
        drawParticles(&scene, style: style, pal: pal, ember: true, point: point, unit: u, blend: blend)
        // 7. Flash
        if let transition, moving, transition.kind == .up || transition.kind == .startup {
            let p = (time - transition.start - 0.06) / 0.35
            if p > 0, p < 1 {
                let strength = (style.dark ? 0.42 : 0.26) * pow(1 - p, 2) * min(1.6, 1 + 0.2 * Double(transition.climbed - 1))
                    * (fx == 1 || transition.kind == .startup ? 0.6 : 1)
                let r = (8 + 32 * Easing.easeOut(p)) * u
                let core = style.dark ? Self.whiteHot : pal.h
                scene.add(OrbInstance.circle(center: point(50, 50), radius: r, color: core.opacity(strength))
                    .radialGradient(to: pal.h.opacity(0), radius: r), blend: blend)
            }
        }
        // 8.–9. Title, glow, sheen and the idle light band
        drawTitle(&scene, item: items.first, style: style, pal: pal, fx: fx, point: point, unit: u)
        if let second = items.second { drawTitle(&scene, item: second, style: style, pal: pal, fx: fx, point: point, unit: u) }
        // 10. Level-up sparks
        drawParticles(&scene, style: style, pal: pal, ember: false, point: point, unit: u, blend: blend)
    }

    /// The titles on screen (one, or two during a transition or a rename): the outgoing one first.
    private func titleItems(style: HeroBadgeStyle, fx: Int) -> BadgeTitleItems {
        let idleAlpha = (style.dark ? 0.55 : 0.7) * (moving ? 0.86 + 0.14 * sin(breathPhase) : 1)
        func base(_ level: Int) -> Double { level == 0 ? idleAlpha : 1 }
        func item(_ text: String, _ level: Int, _ alpha: Double, scale: Double = 1, dy: Double = 0, boost: Double = 0) -> BadgeTitleItem {
            BadgeTitleItem(text: text, level: level, alpha: alpha, scale: scale, dy: dy, boost: boost)
        }
        let steady = BadgeTitleItems(first: item(style.text, level, base(level)))
        if let from = renameFrom, time - renameStart < 0.25 {
            let q = Easing.smoothstep(0, 1, (time - renameStart) / 0.25)
            return BadgeTitleItems(first: item(from, level, base(level) * (1 - q)), second: item(style.text, level, base(level) * q))
        }
        guard let transition, fx > 0 else { return steady }
        let t = time - transition.start
        guard t < 1.0 else { return steady }
        let old = style.previousText
        if old == style.text, transition.kind == .up || transition.kind == .down { return steady }
        if input.reduceMotion {
            let q = Easing.smoothstep(0, 1, t / 0.3)
            return BadgeTitleItems(first: item(old, transition.from, base(transition.from) * (1 - q)),
                                   second: item(style.text, level, base(level) * q))
        }
        switch transition.kind {
        case .up:
            let t2 = t - 0.08
            return BadgeTitleItems(
                first: item(old, transition.from, 1 - Easing.smoothstep(0, 1, t / 0.16), scale: 1 + 0.12 * Easing.easeOut(t / 0.22)),
                second: item(style.text, level, Easing.smoothstep(0, 1, t2 / 0.12), scale: Self.springTo1(t2, from: 0.72),
                             boost: t2 > 0 ? 0.8 * exp(-t2 / 0.25) : 0)
            )
        case .down:
            let t2 = t - 0.12
            return BadgeTitleItems(
                first: item(old, transition.from, 1 - Easing.smoothstep(0, 1, t / 0.3), dy: 5 * (0.5 - 0.5 * cos(.pi * min(1, t / 0.3)))),
                second: item(style.text, level, Easing.smoothstep(0, 1, t2 / 0.35), dy: -3 * (1 - Easing.easeOut(t2 / 0.35)))
            )
        case .startup:
            let q = Easing.smoothstep(0, 1, t / 0.25)
            return BadgeTitleItems(first: item(old, 0, idleAlpha * (1 - q)),
                                   second: item(style.text, level, q, scale: Self.springTo1(t, from: 0.85), boost: 0.5 * exp(-t / 0.3)))
        case .park:
            let q = Easing.smoothstep(0, 1, t / 0.4)
            return BadgeTitleItems(first: item(old, transition.from, 1 - q), second: item(style.text, 0, idleAlpha * q))
        }
    }

    /// Underdamped spring from `from` to 1 (response 0.42 s, damping 0.6), analytic.
    static func springTo1(_ t: Double, from: Double, response: Double = 0.42, damping: Double = 0.6) -> Double {
        guard t > 0 else { return from }
        let w = 2 * Double.pi / response
        let wd = w * sqrt(1 - damping * damping)
        return 1 - (1 - from) * exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    private func drawTitle(_ scene: inout OrbScene, item: BadgeTitleItem, style: HeroBadgeStyle,
                           pal: (c: RGBColor, h: RGBColor, glow: RGBColor, wake: Double), fx: Int,
                           point: (Double, Double) -> CGPoint, unit u: CGFloat) {
        guard item.alpha > 0.005 else { return }
        let title = textCache.title(item.text, language: style.language)
        let layout = title.layout
        let idle = item.level == 0
        let sizePoints = CGFloat(layout.size) * u
        let textStyle = OrbTextStyle(size: sizePoints, weight: HeroBadgeTextCache.weight,
                                     tracking: CGFloat(layout.tracking * layout.size) * u, padding: 9 * u)
        let pivot = point(50, 50 + item.dy)
        let scale = CGFloat(item.scale)

        // Glow and fill.
        var glow: RGBColor?
        var glowRadius: CGFloat = 0
        if !idle, pal.wake > 0.01 {
            var sigma = 1.0 + 1.6 * input.heat + 0.6 * input.overdrive
            var strength = style.dark ? 0.30 + 0.45 * input.heat + 0.15 * input.overdrive : 0.16 + 0.22 * input.heat
            if fx == 0 { strength = style.dark ? 0.30 : 0.20 }
            if fx == 3 { sigma *= 1.2 }
            if style.increaseContrast { strength *= 0.5 }
            strength *= (1 + item.boost) * pal.wake
            glow = pal.glow.opacity(min(1, strength))
            glowRadius = CGFloat(2 * sigma) * u * scale
        }
        let gradient = style.dark && !style.increaseContrast && !idle
        let topColor = pal.c.mixOKLab(pal.h, 0.45).mixOKLab(Self.whiteHot, 0.35 * input.overdrive)
        let bottomColor = pal.c.mixOKLab(Self.whiteHot, 0.2 * input.overdrive)
        let inkTop = pivot.y + (point(50, title.inkTop).y - point(50, 50).y) * scale
        let inkBottom = pivot.y + (point(50, title.inkBottom).y - point(50, 50).y) * scale
        let sheenOn = fx >= 2 && !input.reduceMotion && !idle && input.heat >= 0.45
        let sheenPeriod = max(1.4, 5 - 3.5 * input.heat)
        let sheenU = sheenOn ? (sheenPhase.truncatingRemainder(dividingBy: 1)) * sheenPeriod / 0.7 : 2
        let maskWidth = title.inkWidth + 28
        var band: (x: Double, color: RGBColor, slope: CGFloat, half: Double)?
        if sheenU < 1 {
            band = (50 - maskWidth / 2 + (-0.2 + 1.4 * sheenU) * maskWidth,
                    style.dark ? Self.whiteHot.opacity(0.4) : RGBColor.white.opacity(0.5), -0.45, 18)
        } else if idle, moving {
            let phase = (time - input.sweepEpoch - HeroVehicleDriver.sweepOffset).truncatingRemainder(dividingBy: 6)
            let c = phase < 0 ? phase + 6 : phase
            if c < 0.9 {
                let x = -10 + 120 * (0.5 - 0.5 * cos(.pi * c / 0.9))
                band = (x, style.dark ? Self.whiteHot.opacity(0.75) : Self.slate.opacity(0.6), 0, 9)
            }
        }
        let fill = idle ? (style.dark ? Self.slate : HeroPalette.stroke(0, dark: false, increaseContrast: style.increaseContrast)) : pal.c
        for index in layout.lines.indices {
            guard let texture = textCache.glyphs(layout.lines[index], style: textStyle, language: style.language,
                                                 scale: scene.backingScale) else { continue }
            let baseline = point(50, title.baselines[index]).y
            let x = point(50 - title.widths[index] / 2, 50).x
            var draw = OrbTextDraw(texture, x: x, baseline: baseline, color: (gradient ? topColor : fill).opacity(item.alpha),
                                   glow: glow?.opacity(item.alpha), glowRadius: glowRadius, scale: scale, pivot: pivot)
            if gradient {
                draw.instance.fill2 = bottomColor.opacity(item.alpha).simd
                draw.instance.gradient = SIMD4(Float(inkTop), Float(inkBottom), 1, 0)
            }
            scene.add(draw)
            if let band {
                let center = point(band.x, 50)
                scene.add(OrbTextDraw(texture, x: x, baseline: baseline, color: band.color.opacity(item.alpha), scale: scale,
                                      pivot: pivot, clip: .band(center: center, halfWidth: CGFloat(band.half) * u, slope: band.slope)))
            }
        }
    }

    private func drawPips(_ scene: inout OrbScene, style: HeroBadgeStyle, point: (Double, Double) -> CGPoint, unit u: CGFloat, fx: Int) {
        let redline = max(input.redline, 1)
        let unlit = (style.dark ? RGBColor.white : RGBColor.black).opacity(style.increaseContrast ? 0.3 : 0.12)
        for k in 1...13 {
            let pip = pips[k - 1]
            let angle = (216 + 9 * Double(k - 1)) * .pi / 180
            let center = point(50 + 37.5 * cos(angle), 50 + 37.5 * sin(angle))
            scene.add(.circle(center: center, radius: 1.05 * u, color: unlit), blend: .over)
            guard pip.lit > 0.01, let title = SpeedTitle(rawValue: k) else { continue }
            let heat = HeatPalette.heat(forFraction: title.enterSpeed(redline: redline) / redline)
            let color = style.dark ? HeatPalette.color(heat)
                : DashboardPalette.legible(HeatPalette.color(heat, dark: false), dark: false, minimum: 3)
            let current = k == level
            var scale = 1.0
            if pip.pop.isFinite, moving, k <= level {
                let t = time - pip.pop
                scale = t < 0 ? 0 : Self.springTo1(t, from: 0, response: 0.3, damping: 0.5)
            }
            let radius = (current ? 1.45 : 1.05) * max(scale, 0)
            guard radius > 0.01 else { continue }
            let glows = current && style.dark && !style.increaseContrast
            scene.add(.circle(center: center, radius: CGFloat(radius) * u, color: color.opacity(pip.lit),
                              glow: glows ? OrbInstance.glow(sigma: 1.3 * u) : 0, glowAlpha: glows ? 0.35 : 0), blend: .over)
        }
    }

    private func drawParticles(_ scene: inout OrbScene, style: HeroBadgeStyle, pal: (c: RGBColor, h: RGBColor, glow: RGBColor, wake: Double),
                               ember: Bool, point: (Double, Double) -> CGPoint, unit u: CGFloat, blend: OrbBlend) {
        let core = style.dark ? Self.whiteHot : Self.amber
        for particle in particles where particle.alive && particle.ember == ember && particle.age >= 0 {
            let life = particle.age / particle.life
            let color = core.mix(pal.c, life)
            scene.add(.capsule(from: point(particle.x - particle.vx * 0.022, particle.y - particle.vy * 0.022),
                               to: point(particle.x, particle.y), width: (ember ? 0.7 : 0.6) * u,
                               color: color.opacity((1 - life) * (ember ? 0.8 : 1)), tailColor: color.opacity(0)), blend: blend)
        }
    }

    /// A ring of the medallion (or the shockwave) with the arcs that would cross the title's ink box (grown by 2.5
    /// units) left out, so a wide title interrupts the ring like a coin legend.
    private func ring(_ scene: inout OrbScene, radius r: Double, width: Double, from: Double, sweep: Double, color: RGBColor,
                      halfW: Double, halfH: Double, point: (Double, Double) -> CGPoint, unit u: CGFloat, blend: OrbBlend) {
        guard sweep > 0.5, width > 0.01, color.alpha > 0.002 else { return }
        let step = 2.0
        var runStart: Double?
        var angle = from
        let end = from + sweep
        func inside(_ degrees: Double) -> Bool {
            let radians = degrees * .pi / 180
            return abs(r * cos(radians)) <= halfW && abs(r * sin(radians)) <= halfH
        }
        while angle <= end + 0.001 {
            let blocked = inside(angle)
            if !blocked, runStart == nil { runStart = angle }
            if blocked || angle + step > end + 0.001, let begin = runStart {
                let stop = blocked ? angle : min(end, angle + step)
                if stop - begin > 0.2 {
                    scene.add(.bandArc(center: point(50, 50), radius: CGFloat(r) * u, width: CGFloat(width) * u, start: begin,
                                       sweep: stop - begin, color: color, startColor: color), blend: blend)
                }
                runStart = nil
            }
            angle += step
        }
    }
}

extension HeroBadgeTextCache {
    /// A line's glyph texture (shared orb text cache: built once per text, size and language).
    func glyphs(_ text: String, style: OrbTextStyle, language: AppLanguage, scale: CGFloat) -> OrbTextTexture? {
        OrbTextCache.shared.texture(text, style: style, language: language, scale: scale)
    }
}

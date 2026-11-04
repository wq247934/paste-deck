import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// Sparks, embers, the new-peak burst and the electric arcs of `led` (DESIGN 2.1). Sparks are streaks from their position
/// back along their velocity, fading to transparent at the tail; embers are flickering glowing dots.
extension LedStyle {
    static let sparkGold = RGBColor(red: 1, green: 0.82, blue: 0.35)
    static let arcBlue = RGBColor(red: 0.75, green: 0.85, blue: 1)

    func addParticles(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !particles.isEmpty else { return }
        let s = Double(frame.s)
        let dark = frame.dark
        let center = frame.center
        for particle in particles.particles {
            let life = 1 - particle.age / particle.life
            let radius = (particle.x * particle.x + particle.y * particle.y).squareRoot() / s
            let position = CGPoint(x: center.x + particle.x, y: center.y + particle.y)
            let fade = LedMath.particleFade(radius: radius) * frame.readoutZoneFade(at: position)
            guard fade > 0.002 else { continue }
            let color: RGBColor
            if particle.kind == .gold {
                color = Self.sparkGold
            } else if dark {
                color = HeatPalette.color(particle.heat).mix(HeatPalette.whiteHot, min(1, (1 - life) * 0.3 + 0.4))
            } else {
                color = particle.heat > 0.92 ? HeatPalette.amberHot : HeatPalette.color(particle.heat).scaled(0.9)
            }
            let alpha = min(1, life * 1.4) * (particle.kind == .ember ? 0.8 : 1) * fade
            if particle.streak {
                let speed = (particle.vx * particle.vx + particle.vy * particle.vy).squareRoot()
                let fadeV = min(1, speed / (0.12 * s))
                let length = max(0.02, min(0.06, 0.06 * fadeV))
                let a = alpha * (0.25 + 0.75 * fadeV)
                let tail = CGPoint(x: position.x - particle.vx * length, y: position.y - particle.vy * length)
                scene.add(.capsule(from: tail, to: position, width: particle.size * (dark ? 0.75 : 1), color: color.opacity(a),
                                   tailColor: color.opacity(0)), blend: frame.glowBlend)
                if dark {
                    scene.add(.circle(center: position, radius: particle.size * 0.55, color: color.mix(.white, 0.6).opacity(a)),
                              blend: frame.glowBlend)
                }
            } else {
                let flicker = 0.55 + 0.45 * sin(particle.age * 18 + particle.seed)
                let r = particle.size * (dark ? 0.8 : 1) * flicker
                let tint = dark ? color.mix(.white, 0.25) : color
                scene.add(.circle(center: position, radius: 0, color: tint.opacity(alpha), core: 0, glow: 0.854 * r,
                                  glowAlpha: 1), blend: frame.glowBlend)
            }
        }
    }

    func addArcs(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !arcs.isEmpty else { return }
        let s = Double(frame.s)
        let heat = HeatPalette.color(frame.instrumentHeat)
        let dark = frame.dark
        let color = dark ? heat.mix(Self.arcBlue, 0.5) : heat.scaled(0.85)
        for index in arcs.arcs.indices {
            let fade = LedArcs.fade(arcs.arcs[index])
            guard fade > 0.002 else { continue }
            arcs.path(of: index, diameter: s, into: &pathBuffer)
            scene.addPolyline(pathBuffer.prefix(LedArcs.points), origin: frame.center, glowColor: color,
                              coreColor: dark ? .white : color,
                              outer: OrbStroke(width: 0.022 * s, alpha: 0.18 * fade),
                              mid: OrbStroke(width: 0.008 * s, alpha: 0.5 * fade),
                              core: OrbStroke(width: 0.0032 * s, alpha: 0.95 * fade), blend: frame.glowBlend)
        }
    }
}

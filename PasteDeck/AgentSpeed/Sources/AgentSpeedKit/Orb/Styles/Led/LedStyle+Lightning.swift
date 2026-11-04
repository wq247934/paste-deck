import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// Digit lightning (DESIGN 2.1): when the odometer changes a digit, a flash and bolts crackle off its cell, drawn above
/// the readout. The cells come from the readout's own layout of the value, never measured again.
extension LedStyle {
    static let boltBlue = RGBColor(red: 0.7, green: 0.82, blue: 1)
    static let boltGlowLight = RGBColor(red: 0.42, green: 0.5, blue: 1)
    static let boltCoreLight = RGBColor(red: 0.2, green: 0.24, blue: 0.85)

    func triggerLightning(_ frame: OrbFrame, gate: LedEffects, readout: OrbReadoutBuilder) {
        let odometer = readout.odometer
        let changed = odometer.changedAt != lastValueChange && odometer.changedAt.isFinite
        lastValueChange = odometer.changedAt
        let force = forceZap
        forceZap = false
        guard gate.lightning, changed || force, !frame.unavailable, readout.valueCellsText == odometer.current else { return }
        cells.removeAll(keepingCapacity: true)
        for rect in readout.valueCells {
            cells.append(LedDigitCell(x: Double(rect.midX - frame.center.x), y: Double(rect.midY - frame.center.y),
                                      width: Double(rect.width), height: Double(rect.height)))
        }
        lightning.trigger(previous: force ? "" : odometer.previous ?? "", current: odometer.current, cells: cells,
                          time: frame.time, heat: frame.heat, overdrive: frame.overdrive, redline: frame.tier == .redline,
                          value: frame.isIdle ? 0 : 1, effects: gate, diameter: Double(frame.s), force: force)
    }

    func addLightning(_ scene: inout OrbScene, _ frame: OrbFrame) {
        guard !lightning.isEmpty else { return }
        let dark = frame.dark
        let glowColor = dark ? HeatPalette.color(max(frame.heat, 0.3)).mix(Self.boltBlue, 0.45) : Self.boltGlowLight
        let coreColor = dark ? RGBColor.white : Self.boltCoreLight
        let blend = frame.glowBlend
        scene.overlay = true
        defer { scene.overlay = false }
        for zap in lightning.zaps {
            let k = max(0, 1 - zap.age / zap.life)
            let radius = CGFloat(zap.radius)
            let center = CGPoint(x: frame.center.x + zap.x, y: frame.center.y + zap.y)
            let inner = dark ? RGBColor.white : glowColor
            scene.add(.circle(center: center, radius: 0, color: inner.opacity(LedLightning.zapAlpha(zap) * (dark ? 1 : 0.5)),
                              core: 0, glow: 0.3 * radius, glowAlpha: 1), blend: blend)
            scene.add(.circle(center: center, radius: 0, color: glowColor.opacity(k * k * 0.3 * min(1, zap.power)), core: 0,
                              glow: 0.75 * radius, glowAlpha: 1), blend: blend)
        }
        let scale = dark ? 1.0 : 0.9
        for index in lightning.bolts.indices {
            let bolt = lightning.bolts[index]
            let alpha = LedLightning.boltAlpha(bolt) * (flicker.next() < 0.22 ? 0.4 : 1) * scale
            guard alpha > 0.002 else { continue }
            let w = CGFloat(bolt.width)
            func strokes(_ path: ArraySlice<SIMD2<Double>>, width: CGFloat, alpha: Double) {
                scene.addPolyline(path, origin: frame.center, glowColor: glowColor, coreColor: coreColor,
                                  outer: OrbStroke(width: width * 5, alpha: 0.16 * alpha),
                                  mid: OrbStroke(width: width * 2, alpha: 0.45 * alpha),
                                  core: OrbStroke(width: width * 0.8, alpha: 0.95 * alpha), blend: blend)
            }
            strokes(lightning.mainPath(index), width: w, alpha: alpha)
            for fork in 0..<bolt.forks {
                strokes(lightning.forkPath(index, fork), width: w * 0.6, alpha: alpha * 0.8)
            }
        }
    }
}

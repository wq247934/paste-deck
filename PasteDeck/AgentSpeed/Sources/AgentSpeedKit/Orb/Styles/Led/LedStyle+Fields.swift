import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// The per-pixel fields of DESIGN 2.1: the silk core inside the disc and the corona with the warp streaks outside it,
/// one quad each (`OrbLedShaderSource`).
extension LedStyle {
    private func fieldUniforms(_ frame: OrbFrame, gate: LedEffects) -> OrbLedFieldUniforms {
        let h = frame.instrumentHeat
        let o = frame.unavailable ? 0 : frame.overdrive
        var uniforms = OrbLedFieldUniforms()
        uniforms.frame = SIMD4(Float(frame.center.x), Float(frame.center.y), Float(frame.s), Float(frame.alpha))
        uniforms.heat = SIMD4(Float(h), Float(o), Float(LedMath.activity(heat: h)), Float(gate.lvl))
        let still = frame.effects.reduceMotion || !frame.effects.celebrate
        let peak = still || !(frame.peakAge >= 0) ? 99 : min(frame.peakAge, 99)
        uniforms.phases = SIMD4(Float(phases.silk), Float(phases.light), Float(phases.clock), Float(peak))
        uniforms.flags = SIMD4(
            frame.dark ? 1 : 0,
            Float(frame.flash),
            Float(gate.silkRipples ? LedMath.ripple(overdrive: o) : 0),
            Float(LedMath.silkBrightness(heat: h, overdrive: o, lvl: gate.lvl))
        )
        let corona = gate.corona && !frame.unavailable ? LedMath.coronaAmount(heat: h, overdrive: o, lvl: gate.lvl) : 0
        let warp = gate.warp && !frame.unavailable ? LedMath.warpAmount(heat: h, lvl: gate.lvl) : 0
        uniforms.corona = SIMD4(Float(phases.corona), Float(phases.warp), Float(corona), Float(warp))
        let mask = frame.content.showsReadout && !frame.content.valueOnly
        uniforms.text = SIMD4(Float(-frame.readoutShift / frame.s), mask ? 1 : 0, 0, 0)
        if gate.silkWaves {
            var slot = 0
            for pulse in pulses.suffix(4) {
                let age = pulseAge(pulse, at: frame.time)
                guard age >= 0, age < 1 else { continue }
                uniforms.setWave(slot, SIMD4(Float(age), Float(pulse.strength), 0, 0))
                slot += 1
            }
        }
        return uniforms
    }

    func addSilk(_ scene: inout OrbScene, _ frame: OrbFrame, gate: LedEffects) {
        guard gate.silk, frame.alpha > 0.002 else { return }
        scene.ledField = fieldUniforms(frame, gate: gate)
        scene.addLedField(mode: 0, blend: .over)
    }

    func addCorona(_ scene: inout OrbScene, _ frame: OrbFrame, gate: LedEffects) {
        let uniforms = fieldUniforms(frame, gate: gate)
        guard uniforms.corona.z > 0.001 || uniforms.corona.w > 0.001, frame.alpha > 0.002 else { return }
        if uniforms.corona.z > 0.001 { LedNoise.coronaBody(phase: phases.corona, into: &scene.ledCoronaBody) }
        scene.ledField = uniforms
        scene.addLedField(mode: 1, blend: frame.glowBlend)
    }
}

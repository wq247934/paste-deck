import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// `led` — the LED gauge (DESIGN 2 layers 1–8, 2a.1) with the v1.4 effects of DESIGN 2.1: the silk core, gauge energy
/// flow, tip flare, two comets, corona and warp streaks, streaking sparks, electric arcs, shockwaves with a wake, the
/// new-peak flash and digit lightning. Also the dashboard hero's gauge (capped at Soft, no silk).
@MainActor
final class LedStyle: OrbStyleRenderer {
    let kind = OrbStyleKind.led
    let readoutLayout: OrbReadoutLayout = {
        var layout = OrbReadoutLayout.led
        layout.silkValue = true
        return layout
    }()
    let linePlacement = OrbLinePlacement.led
    /// The style draws its own aura, waves and rays (DESIGN 2.1).
    var hasAura: Bool { false }
    var hasWave: Bool { false }
    var hasRays: Bool { false }

    struct Pulse {
        var start: TimeInterval
        var strength: Double
        var heat: Double
    }

    var phases = LedMath.Phases()
    var particles = LedParticles()
    var arcs = LedArcs()
    var lightning = LedLightning()
    var pulses = ContiguousArray<Pulse>()
    var cometVisibility = OrbEnvelope()
    private var cometTarget = 0.0
    private var pendingBurst = false
    /// Scratch buffers reused every frame.
    var pathBuffer = ContiguousArray<SIMD2<Double>>()
    var cells = ContiguousArray<LedDigitCell>()
    var flicker = OrbRandom(seed: 0x51_1C_0B_01)
    var lastValueChange: TimeInterval = -.infinity
    var forceZap = false

    init() {
        pulses.reserveCapacity(8)
        pathBuffer.reserveCapacity(LedArcs.points)
        cells.reserveCapacity(16)
    }

    /// The effects-level table of DESIGN 2.1 for this frame.
    func gate(_ frame: OrbFrame) -> LedEffects {
        LedEffects(level: Self.rank(frame.effects.level), reduceMotion: frame.effects.reduceMotion,
                   floating: frame.content.showsReadout, small: frame.isSmall, thumbnail: frame.content.isThumbnail)
    }

    static func rank(_ level: EffectsLevel) -> Int {
        switch level {
        case .off: 0
        case .soft: 1
        case .standard: 2
        case .max: 3
        }
    }

    /// Harness hook: the next frame zaps every digit of the value (the prototype's `zap=1`).
    func zapEveryDigit() {
        forceZap = true
    }

    // MARK: Events

    func pulse(at time: TimeInterval, strength: Double, heat: Double) {
        if pulses.count >= 4 { pulses.removeFirst() }
        pulses.append(Pulse(start: time, strength: strength, heat: heat))
    }

    func celebrate(at time: TimeInterval) {
        pendingBurst = true
    }

    func pulseAge(_ pulse: Pulse, at time: TimeInterval) -> Double {
        (time - pulse.start) / LedMath.pulseDuration
    }

    // MARK: Simulation

    func step(_ frame: OrbFrame) {
        let dt = frame.dt
        guard dt > 0 else { return }
        let gate = gate(frame)
        let h = frame.instrumentHeat
        let o = frame.unavailable ? 0 : frame.overdrive
        let s = Double(frame.s)
        let comets = gate.maxComets > 0 && !frame.isIdle && !frame.unavailable
        if frame.resumed {
            particles.removeAll()
            arcs.removeAll()
            lightning.removeAll()
            pulses.removeAll(keepingCapacity: true)
            pendingBurst = false
            cometTarget = comets ? 1 : 0
            cometVisibility = OrbEnvelope(cometTarget)
        }
        LedMath.advance(&phases, heat: h, overdrive: o, dt: dt, silkRate: gate.silkRate, comet: gate.maxComets > 0)
        cometTarget = comets ? 1 : 0
        cometVisibility.step(toward: cometTarget, dt: dt, timeConstant: 0.28)
        while let first = pulses.first, pulseAge(first, at: frame.time) >= 1 { pulses.removeFirst() }

        if pendingBurst {
            pendingBurst = false
            if gate.particles {
                particles.burst(diameter: s, count: Int((Double(LedParticles.burstCount) * gate.countScale).rounded()))
            }
        }
        let sparkRate = gate.particles ? LedParticles.sparkRate(heat: h, lvl: gate.lvl, countScale: gate.countScale) : 0
        let emberRate = gate.particles
            ? LedParticles.emberRate(overdrive: o, redline: frame.tier == .redline, lvl: gate.lvl, countScale: gate.countScale)
            : 0
        if sparkRate > 0 || emberRate > 0 || !particles.isEmpty {
            particles.step(dt: dt, time: frame.time, diameter: s, sparkRate: sparkRate, emberRate: emberRate,
                           lead: frame.unavailable ? 0 : frame.displayHeat, overdrive: o)
        }
        let arcing = gate.arcs && frame.tier == .redline && !frame.unavailable
        if arcing || !arcs.isEmpty {
            arcs.step(dt: dt, active: arcing, heat: h, overdrive: o, lvl: gate.lvl, diameter: s)
        }
        if !lightning.isEmpty { lightning.step(dt: dt) }
    }

    func isBusy(_ frame: OrbFrame) -> Bool {
        !particles.isEmpty || !arcs.isEmpty || !lightning.isEmpty || !pulses.isEmpty || pendingBurst
            || !cometVisibility.isSettled(at: cometTarget)
    }

    func ambientFrameClass(_ frame: OrbFrame) -> OrbFrameClass {
        if frame.isIdle || frame.unavailable { return isBusy(frame) ? .fps30 : .none }
        return frame.instrumentHeat >= 0.45 || frame.tier >= .overdrive ? .fps60 : .fps30
    }

    // MARK: Layers

    func build(into scene: inout OrbScene, _ frame: OrbFrame) {
        let gate = gate(frame)
        let valueOnly = frame.content.valueOnly
        if !valueOnly {
            OrbSharedLayers.addAura(&scene, frame, flare: frame.auraFlare, scale: 0.8, hot: 0.25)
            addCorona(&scene, frame, gate: gate)
        }
        addSilk(&scene, frame, gate: gate)
        addSegments(&scene, frame, gate: gate)
        guard !valueOnly else { return }
        addTicks(&scene, frame)
        addTipFlare(&scene, frame, gate: gate)
        addComets(&scene, frame, gate: gate)
        addPulses(&scene, frame)
        addPeak(&scene, frame)
        addParticles(&scene, frame)
        addArcs(&scene, frame)
    }

    func buildReadout(into scene: inout OrbScene, _ frame: OrbFrame, readout: OrbReadoutBuilder) {
        readout.add(into: &scene, frame, layout: readoutLayout)
        guard !frame.content.valueOnly else { return }
        let gate = gate(frame)
        triggerLightning(frame, gate: gate, readout: readout)
        addLightning(&scene, frame)
    }
}

extension RGBColor {
    /// The prototype's porcelain ink: `pow(c, 1.55)` per channel deepens a color without muddying it.
    var inked: RGBColor {
        RGBColor(red: pow(red, 1.55), green: pow(green, 1.55), blue: pow(blue, 1.55), alpha: alpha)
    }
}

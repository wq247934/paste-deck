import AgentSpeedCore
import AgentSpeedOrbModel
import SwiftUI

/// `liquid` — the liquid energy orb (DESIGN 2a.3): a glass sphere of glowing liquid whose level rises with speed, its
/// surface waving, luminous motes streaming up, boiling, splashing and steaming at the redline. The volume is one
/// fragment shader pass (`OrbLiquidShaderSource`); particles, meniscus and glass are drawn around it.
@MainActor
final class LiquidStyle: OrbStyleRenderer {
    let kind = OrbStyleKind.liquid
    let readoutLayout: OrbReadoutLayout = {
        var layout = OrbReadoutLayout.led
        layout.dotHalo = true
        return layout
    }()
    let linePlacement = OrbLinePlacement.liquid
    let signOfLifeDuration: TimeInterval = 1.2

    private static let glass = LiquidMath.glassRadius
    private static let goldColor = RGBColor(hex: 0xFACC15)

    private var level = LiquidMath.levelSpring()
    private var levelEased = LiquidMath.CriticalSpring(settle: 0.9, value: LiquidMath.idleLevel)
    private var surge = LiquidMath.surgeSpring()
    private var amplitude = LiquidMath.CriticalSpring(settle: 0.8)
    private var chop = LiquidMath.CriticalSpring(settle: 0.6)
    private var phases = SIMD4<Double>(0, 0, 0, 0)
    private var targets = Targets()

    private var motes = LiquidPool<LiquidMote>(capacity: 72)
    private var pops = LiquidPool<LiquidPop>(capacity: 16)
    private var splashes = LiquidPool<LiquidSplash>(capacity: 40)
    private var steam = LiquidPool<LiquidSteam>(capacity: 12)
    private var drops = LiquidPool<LiquidDrop>(capacity: 3)
    private var ripples = LiquidPool<LiquidRipple>(capacity: 4)
    private var moteCarry = 0.0
    private var steamCarry = 0.0
    private var random = OrbRandom(seed: 0x5EED_1A9D_0B0B_7777)

    private var pendingPeak: TimeInterval?
    private var goldStart: TimeInterval = -.infinity
    private var goldReduced = false
    private var pendingDrops = 0
    private var pendingStrength = 0.0
    private var pendingHeat = 0.0
    private var hadSignOfLife = false
    /// Effects of the last step (events arrive between frames).
    private var allowsDrops = true

    /// Spring targets of the last step, for `isBusy`.
    private struct Targets {
        var level = LiquidMath.idleLevel
        var amplitude = 0.0
        var chop = 0.0
    }

    init() {}

    // MARK: Simulation

    /// The current state without catching up (first frame after the orb could not be seen).
    private func snap(to targets: Targets) {
        level.value = targets.level
        level.velocity = 0
        levelEased.value = targets.level
        levelEased.velocity = 0
        surge.value = 0
        surge.velocity = 0
        amplitude.value = targets.amplitude
        amplitude.velocity = 0
        chop.value = targets.chop
        chop.velocity = 0
        motes.removeAll()
        pops.removeAll()
        splashes.removeAll()
        steam.removeAll()
        drops.removeAll()
        ripples.removeAll()
        pendingPeak = nil
        pendingDrops = 0
        goldStart = -.infinity
    }

    private func heatOf(_ frame: OrbFrame) -> Double { frame.instrumentHeat * frame.activity }

    private func isActive(_ frame: OrbFrame) -> Bool { !frame.isIdle && !frame.unavailable }

    private func rank(_ frame: OrbFrame) -> Int {
        switch frame.effects.level {
        case .off: 0
        case .soft: 1
        case .standard: 2
        case .max: 3
        }
    }

    /// Off and Reduce Motion: a still surface and an eased level.
    private func isStill(_ frame: OrbFrame) -> Bool {
        frame.effects.level == .off || frame.effects.reduceMotion || frame.content.valueOnly
    }

    func step(_ frame: OrbFrame) {
        let dt = frame.dt
        let s = Double(frame.s)
        let h = heatOf(frame)
        let o = frame.unavailable ? 0 : frame.overdrive
        let active = isActive(frame)
        let level = rank(frame)
        let still = isStill(frame)
        let small = frame.isSmall
        let boiling = level >= 2 && frame.tier == .redline && active && !still
        allowsDrops = level >= 1 && !still

        let levelTarget = LiquidMath.targetLevel(heat: h, overdrive: o, active: active)
        let amplitudeTarget = LiquidMath.amplitude(heat: h, overdrive: o, active: active, level: level, reduceMotion: still)
        let chopTarget = LiquidMath.chop(overdrive: o, boiling: boiling, small: small)
        targets = Targets(level: levelTarget, amplitude: amplitudeTarget, chop: chopTarget)
        if frame.resumed { snap(to: targets) }
        guard dt > 0 else { return }

        if still {
            levelEased.step(toward: levelTarget, dt: dt)
            self.level.value = levelEased.value
            self.level.velocity = 0
        } else {
            self.level.step(toward: levelTarget, dt: dt)
            levelEased.value = self.level.value
            levelEased.velocity = 0
        }
        if let peak = pendingPeak {
            pendingPeak = nil
            if frame.effects.celebrate {
                goldStart = peak
                goldReduced = frame.effects.reduceMotion
                if !still {
                    surge.velocity += LiquidMath.surgeKick
                    spawnGold(s: s)
                }
            }
        }
        surge.step(toward: 0, dt: dt)
        amplitude.step(toward: amplitudeTarget, dt: dt)
        chop.step(toward: chopTarget, dt: dt)
        if !still {
            let rates = LiquidMath.phaseRates(heat: h, overdrive: o)
            phases += 2 * Double.pi * rates * dt
            for index in 0..<4 where phases[index] > 2 * Double.pi * 100 {
                phases[index] -= 2 * Double.pi * 100
            }
        }
        let time = frame.time
        ripples.update { time - $0.start < LiquidMath.rippleLife }

        if still {
            motes.removeAll()
            pops.removeAll()
            splashes.removeAll()
            steam.removeAll()
            drops.removeAll()
            pendingDrops = 0
            moteCarry = 0
            steamCarry = 0
        } else {
            stepParticles(frame, dt: dt, s: s, h: h, o: o, level: level, boiling: boiling, small: small)
        }

        let signOfLife = frame.signOfLife != nil
        if signOfLife, !hadSignOfLife, !still {
            // One cool bubble from the bottom-left of the shallow idle pool; it rises and pops well within 1.2 s.
            let x = -0.1 * s
            let bottom = sqrt(max(0, pow(Self.glass * s, 2) - x * x))
            spawnMote(s: s, h: 0.15, o: 0, x: x, y: bottom - 0.01 * s)
        }
        hadSignOfLife = signOfLife
    }

    private func stepParticles(_ frame: OrbFrame, dt: Double, s: Double, h: Double, o: Double, level: Int, boiling: Bool, small: Bool) {
        let active = isActive(frame)
        let rate = LiquidMath.moteRate(heat: h, overdrive: o, redline: frame.tier == .redline, active: active, level: level,
                                       reduceMotion: false)
        let cap = LiquidMath.motePool(level: level, small: small)
        moteCarry += rate * dt
        while moteCarry >= 1 {
            moteCarry -= 1
            if motes.count < cap { spawnMote(s: s, h: h, o: o, x: nil, y: nil) }
        }

        let accelerate = (0.12 + 0.2 * h) * s
        let time = frame.time
        motes.update { mote in
            mote.vy -= accelerate * dt
            mote.y += mote.vy * dt
            mote.phase += 2 * Double.pi * 2.3 * dt
            let x = mote.x + sin(mote.phase) * 0.006 * s
            let surface = surfaceOffset(x, s: s, time: time)
            guard mote.y - mote.size < surface else { return true }
            pops.append(LiquidPop(x: x, y: surface, age: 0, size: mote.size))
            if boiling, !mote.gold, random.next() < 0.55 {
                spawnSplash(x: x, y: surface, count: 1 + Int(random.next() * 2), strength: 0.5, s: s)
            }
            return false
        }
        pops.update { pop in
            pop.age += dt
            return pop.age < 0.25
        }

        if boiling, !small {
            steamCarry += LiquidMath.steamRate(overdrive: o, boiling: true, level: level, reduceMotion: false) * dt
            while steamCarry >= 1 {
                steamCarry -= 1
                steam.append(LiquidSteam(
                    x: random.range(-0.25...0.25) * s, y: 0, vy: -random.range(0.06...0.12) * s, age: 0,
                    life: random.range(0.8...1.4), size: random.range(0.03...0.06) * s, phase: random.next() * 2 * .pi
                ))
            }
        } else {
            steamCarry = 0
        }
        steam.update { wisp in
            wisp.age += dt
            guard wisp.age < wisp.life else { return false }
            wisp.y += wisp.vy * dt
            wisp.x += sin(wisp.phase + wisp.age * 3) * 0.02 * s * dt
            return true
        }

        // Pulse droplets fall in; at impact a ripple, splashes and bubbles.
        while pendingDrops > 0 {
            pendingDrops -= 1
            guard drops.count < LiquidMath.maxDrops else { continue }
            let x = (random.next() - 0.5) * 0.42 * s
            let surface = surfaceOffset(x, s: s, time: time)
            drops.append(LiquidDrop(x: x, y: LiquidMath.dropStart(surface: surface, diameter: s), vy: 0,
                                    heat: pendingHeat, strength: pendingStrength))
        }
        drops.update { drop in
            drop.vy += 2.6 * s * dt
            drop.y += drop.vy * dt
            let surface = surfaceOffset(drop.x, s: s, time: time)
            guard drop.y >= surface else { return true }
            if ripples.count >= LiquidMath.maxRipples { ripples.removeFirst() }
            ripples.append(LiquidRipple(x: drop.x, start: time, amplitude: LiquidMath.rippleAmplitude(strength: drop.strength)))
            if level >= 2 { spawnSplash(x: drop.x, y: surface, count: 3 + Int((3 * drop.strength).rounded()), strength: 1, s: s) }
            for _ in 0..<(level >= 2 ? 6 : 2) {
                spawnMote(s: s, h: h, o: o, x: drop.x + random.range(-0.03...0.03) * s,
                          y: surface + random.range(0.02...0.08) * s)
            }
            return false
        }
        splashes.update { drop in
            drop.age += dt
            guard drop.age < drop.life else { return false }
            drop.vy += 2.2 * s * dt
            drop.x += drop.vx * dt
            drop.y += drop.vy * dt
            return !(drop.vy > 0 && drop.y > surfaceOffset(drop.x, s: s, time: time))
        }
    }

    private func spawnMote(s: Double, h: Double, o: Double, x: Double?, y: Double?) {
        let radius = Self.glass * s
        let px = x ?? random.range(-0.6...0.6) * radius
        let bottom = sqrt(max(0, radius * radius - px * px))
        let py = y ?? bottom - random.range(0.02...0.06) * s
        motes.append(LiquidMote(
            x: px, y: py,
            vy: -LiquidMath.moteSpeed(heat: h, overdrive: o) * s * random.range(0.7...1.3),
            size: max(0.9, LiquidMath.moteRadius(heat: h) * s * random.range(0.6...1.4)),
            phase: random.next() * 2 * .pi,
            gold: false
        ))
    }

    private func spawnGold(s: Double) {
        for _ in 0..<LiquidMath.goldMotes {
            let added = motes.append(LiquidMote(
                x: random.range(-0.3...0.3) * s,
                y: Self.glass * s * 0.85 - random.range(0...0.1) * s,
                vy: -random.range(0.5...0.9) * s,
                size: random.range(0.008...0.016) * s,
                phase: random.next() * 2 * .pi,
                gold: true
            ))
            if !added { break }
        }
    }

    private func spawnSplash(x: Double, y: Double, count: Int, strength: Double, s: Double) {
        for _ in 0..<count {
            let added = splashes.append(LiquidSplash(
                x: x, y: y - 0.004 * s,
                vx: random.range(-0.25...0.25) * s,
                vy: -random.range(0.35...0.7) * s * (0.6 + 0.6 * strength),
                age: 0, life: random.range(0.3...0.6), size: random.range(0.006...0.011) * s
            ))
            if !added { return }
        }
    }

    func pulse(at time: TimeInterval, strength: Double, heat: Double) {
        guard allowsDrops else { return }
        pendingDrops = min(LiquidMath.maxDrops, pendingDrops + 1)
        pendingStrength = strength
        pendingHeat = heat
    }

    func celebrate(at time: TimeInterval) {
        pendingPeak = time
    }

    // MARK: Surface

    private var currentLevel: Double {
        min(0.95, max(0.04, level.value + surge.value))
    }

    /// Surface height (points from the center, y down) at `x` points from the center: mirrors `orb_liquid_wave_y`.
    private func surfaceOffset(_ x: Double, s: Double, time: TimeInterval) -> Double {
        var y = LiquidMath.meanSurface(centerY: 0, diameter: s, level: currentLevel)
        y += LiquidMath.wave(x: x, diameter: s, amplitude: amplitude.value, chop: chop.value, phases: phases)
        for ripple in ripples.items {
            y += LiquidMath.ripple(distance: abs(x - ripple.x), tau: time - ripple.start, amplitude: ripple.amplitude, diameter: s)
        }
        return y
    }

    // MARK: Frame policy

    func isBusy(_ frame: OrbFrame) -> Bool {
        !motes.isEmpty || !pops.isEmpty || !splashes.isEmpty || !steam.isEmpty || !drops.isEmpty || !ripples.isEmpty
            || pendingDrops > 0 || pendingPeak != nil
            || !level.isSettled(at: targets.level) || !levelEased.isSettled(at: targets.level)
            || !surge.isSettled(at: 0)
            || !amplitude.isSettled(at: targets.amplitude, tolerance: 0.00005)
            || !chop.isSettled(at: targets.chop, tolerance: 0.00005)
            || frame.time - goldStart < 0.95
    }

    func ambientFrameClass(_ frame: OrbFrame) -> OrbFrameClass {
        guard isActive(frame) else { return .none }
        if frame.effects.level == .soft { return .fps30 }
        return frame.tier >= .overdrive ? .fps60 : .fps30
    }

    // MARK: Layers

    func build(into scene: inout OrbScene, _ frame: OrbFrame) {
        let s = Double(frame.s)
        let center = frame.center
        let h = heatOf(frame)
        let o = frame.unavailable ? 0 : frame.overdrive
        let active = isActive(frame)
        let dark = frame.dark
        let level = rank(frame)
        let still = isStill(frame)
        let contrast = frame.content.increaseContrast
        let glowScale = (level == 3 ? 1.25 : 1) * (contrast ? 0.5 : 1)
        let alpha = Float(frame.alpha)
        let radius = Self.glass * s
        let boiling = frame.tier == .redline && active
        let valueOnly = frame.content.valueOnly

        let liquidColor = dark ? HeatPalette.color(h) : HeatPalette.color(h).mix(.white, 0.12)
        let slate = dark ? HeatPalette.color(0) : HeatPalette.color(0).mix(.white, 0.12)
        let tint = active ? liquidColor : slate
        var bodyAlpha = active ? (dark ? 0.46 + 0.10 * h : 0.80) : (dark ? 0.40 : 0.55)
        if frame.content.reduceTransparency { bodyAlpha += 0.15 }
        let levelValue = currentLevel
        let meanY = Double(center.y) + LiquidMath.meanSurface(centerY: 0, diameter: s, level: levelValue)

        var uniforms = OrbLiquidUniforms()
        uniforms.frame = SIMD4(Float(center.x), Float(center.y), Float(s), Float(radius))
        uniforms.surface = SIMD4(Float(meanY), Float(valueOnly ? 0 : amplitude.value * s), Float(valueOnly ? 0 : chop.value * s),
                                 !frame.isSmall && !valueOnly ? 1 : 0)
        uniforms.phases = SIMD4(Float(phases[0]), Float(phases[1]), Float(phases[2]), Float(phases[3]))
        for index in 0..<4 {
            guard index < ripples.count, !valueOnly else {
                uniforms.setRipple(index, .zero)
                continue
            }
            let ripple = ripples.items[index]
            let tau = frame.time - ripple.start
            let amplitude = ripple.amplitude * s * exp(-tau / 0.75)
            uniforms.setRipple(index, SIMD4(Float(Double(center.x) + ripple.x), Float(0.42 * s * tau), Float(amplitude), 1))
        }
        uniforms.liquid = Self.vector(tint, Float(min(1, bodyAlpha)) * alpha)
        let deep = dark ? tint.darkened(0.62) : tint.darkened(0.14)
        uniforms.deep = Self.vector(deep, Float(min(1, bodyAlpha + 0.2)) * alpha)
        let back = dark ? tint.darkened(0.25) : tint.darkened(0.08)
        uniforms.back = Self.vector(back, Float(min(1, bodyAlpha) * 0.55) * alpha)
        if active, !valueOnly {
            uniforms.spill = Self.vector(liquidColor, Float((dark ? 0.16 : 0.10) * (0.4 + 0.6 * h)) * alpha)
        }
        // Inner glow, kept below the readout; brighter when boiling under Reduce Motion (it stands in for the motion).
        if active {
            let boilBoost = still && boiling ? 1.3 : 1
            let glowColor = dark ? liquidColor.mix(HeatPalette.whiteHot, 0.25 + 0.45 * o) : liquidColor
            let glowAlpha = (dark ? (0.26 + 0.2 * o) : 0.10) * (0.3 + 0.7 * h) * glowScale * boilBoost
            uniforms.glow = Self.vector(glowColor, Float(min(1, glowAlpha)) * alpha)
            let glowY = max(meanY + 0.08 * s, Double(center.y) + 0.38 * s)
            uniforms.glowGeom = SIMD4(Float(center.x), Float(glowY), Float(0.32 * s), dark ? 1 : 0)
        }
        uniforms.shade = dark ? SIMD4(0, 0, 0, 0.5 * alpha) : Self.vector(RGBColor(hex: 0x283042), 0.14 * alpha)
        if active, level >= 1, !still, !frame.isSmall, !valueOnly {
            let currentColor = dark ? liquidColor.mix(HeatPalette.whiteHot, 0.35 + 0.4 * o) : RGBColor.white
            uniforms.current = Self.vector(currentColor, Float((dark ? 0.10 : 0.22) * (0.4 + 0.6 * h)) * alpha)
            uniforms.currentGeom = SIMD4(0, Float(0.006 * s), Float(phases[0]), dark ? 1 : 0)
        }
        let goldAge = frame.time - goldStart
        if !valueOnly {
            if goldReduced {
                if goldAge >= 0, goldAge < 0.3 {
                    let bandY = meanY + 0.06 * s
                    uniforms.gold = SIMD4(Float(bandY), Float(0.45 * sin(.pi * goldAge / 0.3)) * alpha, Float(0.06 * s), dark ? 1 : 0)
                }
            } else if goldAge >= 0, goldAge < 0.9 {
                let bottom = Double(center.y) + radius
                let bandY = bottom - (bottom - meanY) * Easing.easeOut(goldAge / 0.9)
                uniforms.gold = SIMD4(Float(bandY), Float(0.45 * (1 - goldAge / 0.9)) * alpha, Float(0.06 * s), dark ? 1 : 0)
            }
        }
        let bodyTop = min(meanY, Double(center.y) + 0.2 * s) - 0.04 * s
        uniforms.flags = SIMD4(dark ? 1 : 0, dark && active ? 1 : 0, Float(bodyTop), Float(Double(center.y) + radius))

        // Meniscus (mode 1): flashes with a tier change and brightens when boiling under Reduce Motion.
        var meniscusColor: RGBColor
        var meniscusAlpha: Double
        if active {
            meniscusColor = dark ? liquidColor.mix(HeatPalette.whiteHot, 0.45 + 0.5 * o) : HeatPalette.color(h).darkened(0.25)
            meniscusAlpha = 0.95
        } else {
            meniscusColor = dark ? .white : slate.darkened(0.25)
            meniscusAlpha = dark ? 0.28 : 0.5
        }
        var signBoost = 0.0
        if still, let u = frame.signOfLife { signBoost = 0.25 * sin(.pi * u) }
        let flash = frame.flash + (still && boiling ? 0.3 : 0) + signBoost
        if flash > 0 {
            meniscusColor = meniscusColor.mix(.white, 0.25 * min(1, flash))
            meniscusAlpha = min(1, meniscusAlpha * (1 + 0.25 * flash))
        }
        let meniscusWidth = max(1, (0.008 + 0.004 * h) * s) * (contrast ? 1.5 : 1)
        uniforms.meniscus = Self.vector(meniscusColor, Float(meniscusAlpha) * alpha)
        if dark, active {
            let sigma = (0.015 + 0.015 * h) * s * (level == 3 ? 1.3 : 1)
            let strength = 0.9 * min(1, meniscusWidth / (sigma * 2.507)) * (contrast ? 0.5 : 1) * (still && boiling ? 1.4 : 1)
            uniforms.meniscusGlow = Self.vector(liquidColor, Float(min(1, strength * 1.6)) * alpha)
            uniforms.meniscusGeom = SIMD4(Float(meniscusWidth), Float(sigma), 1, 0)
        } else {
            uniforms.meniscusGeom = SIMD4(Float(meniscusWidth), 1, 0, 0)
        }
        scene.liquid = uniforms
        scene.addLiquid(mode: 0)

        if !still {
            scene.clipRadius = CGFloat(radius)
            addMotes(&scene, frame, h: h, liquidColor: liquidColor)
            addSurfaceParticles(&scene, frame, liquidColor: liquidColor)
            scene.clipRadius = 0
        }
        scene.addLiquid(mode: 1)
        addGlass(&scene, frame, h: h, active: active, liquidColor: liquidColor, glowScale: glowScale)
    }

    private static func vector(_ color: RGBColor, _ alpha: Float) -> SIMD4<Float> {
        SIMD4(Float(color.red), Float(color.green), Float(color.blue), alpha)
    }

    private func point(_ frame: OrbFrame, _ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: frame.center.x + CGFloat(x), y: frame.center.y + CGFloat(y))
    }

    private func addMotes(_ scene: inout OrbScene, _ frame: OrbFrame, h: Double, liquidColor: RGBColor) {
        guard !motes.isEmpty else { return }
        let s = Double(frame.s)
        let dark = frame.dark
        let heatHot = LiquidMath.hotness(heat: h)
        let hotColor = dark ? liquidColor.mix(HeatPalette.whiteHot, 0.9) : RGBColor.white
        // Glass bubbles first (normal blending), then the luminous motes (additive in dark), so a frame needs two
        // batches whatever the mix.
        for mote in motes.items {
            let hot = mote.gold ? 1 : heatHot
            guard hot < 1 else { continue }
            let center = point(frame, mote.x + sin(mote.phase) * 0.006 * s, mote.y)
            let clear = frame.readoutZoneFade(at: center)
            let size = CGFloat(mote.size)
            let ring = RGBColor.white.opacity((dark ? 0.5 : 0.85) * (1 - hot) * clear)
            scene.add(.ring(center: center, radius: size, width: max(0.6, size * 0.28), color: ring), blend: .over)
            let spot = CGPoint(x: center.x - size * 0.35, y: center.y - size * 0.35)
            scene.add(.circle(center: spot, radius: max(0.4, size * 0.28),
                              color: RGBColor.white.opacity((dark ? 0.6 : 0.95) * (1 - hot) * clear)), blend: .over)
        }
        for mote in motes.items {
            let hot = mote.gold ? 1 : heatHot
            guard hot > 0 else { continue }
            let center = point(frame, mote.x + sin(mote.phase) * 0.006 * s, mote.y)
            let clear = frame.readoutZoneFade(at: center)
            let size = CGFloat(mote.size)
            let color = mote.gold ? Self.goldColor : hotColor
            let peak = (dark ? 0.95 : 0.9) * hot * clear
            let rim = (dark ? 0.4 : 0.45) * hot * clear
            // A luminous core to 35 % of twice the radius, then a Gaussian halo to twice the radius.
            scene.add(.circle(center: center, radius: size * 0.7, color: color.opacity(peak), glow: size * 0.9, glowAlpha: 1)
                .radialGradient(to: color.opacity(rim), radius: size * 0.7), blend: frame.glowBlend)
        }
    }

    private func addSurfaceParticles(_ scene: inout OrbScene, _ frame: OrbFrame, liquidColor: RGBColor) {
        let s = Double(frame.s)
        let dark = frame.dark
        let popColor = dark ? HeatPalette.whiteHot : RGBColor.white
        for pop in pops.items {
            let u = pop.age / 0.25
            scene.add(.ring(center: point(frame, pop.x, pop.y), radius: CGFloat(pop.size * (1 + 1.5 * u)), width: 0.8,
                            color: popColor.opacity(0.6 * (1 - u))), blend: .over)
        }
        let splashColor = dark ? liquidColor.mix(HeatPalette.whiteHot, 0.5) : liquidColor.darkened(0.1)
        for drop in splashes.items {
            let u = drop.age / drop.life
            scene.add(.circle(center: point(frame, drop.x, drop.y), radius: CGFloat(drop.size),
                              color: splashColor.opacity(0.9 * (1 - u * 0.6))), blend: frame.glowBlend)
        }
        let mean = LiquidMath.meanSurface(centerY: 0, diameter: s, level: currentLevel)
        let steamColor = dark ? HeatPalette.whiteHot : RGBColor.white
        for wisp in steam.items {
            let u = wisp.age / wisp.life
            let radius = CGFloat(wisp.size * (1 + u))
            let a = sin(.pi * u) * (dark ? 0.12 : 0.18)
            scene.add(.circle(center: point(frame, wisp.x, mean + wisp.y), radius: radius, color: steamColor.opacity(a))
                .radialGradient(to: steamColor.opacity(0), radius: radius), blend: frame.glowBlend)
        }
        for drop in drops.items {
            let heat = max(0.15, drop.heat)
            let color = dark ? HeatPalette.color(heat).mix(HeatPalette.whiteHot, 0.3) : frame.labelColor(heat)
            let radius = CGFloat((0.012 + 0.006 * drop.strength) * s)
            scene.add(.blade(pivot: point(frame, drop.x, drop.y), angle: -90, tipLength: radius * 2.2, tailLength: 0,
                             pivotHalfWidth: radius, tipHalfWidth: radius * 0.12, tailHalfWidth: radius,
                             color: color.opacity(0.95)), blend: frame.glowBlend)
        }
    }

    private func addGlass(_ scene: inout OrbScene, _ frame: OrbFrame, h: Double, active: Bool, liquidColor: RGBColor, glowScale: Double) {
        let s = frame.s
        let dark = frame.dark
        let center = frame.center
        scene.add(.ring(center: center, radius: CGFloat(Self.glass) * s, width: max(1, 0.006 * s),
                        color: dark ? RGBColor.white.opacity(0.09) : RGBColor.black.opacity(0.06)), blend: .over)
        guard !frame.content.valueOnly else { return }
        if active {
            let caustic = liquidColor.opacity((dark ? 0.35 : 0.3) * (0.3 + 0.7 * h) * min(1, glowScale))
            scene.add(.bandArc(center: center, radius: 0.475 * s, width: 0.02 * s, start: 55, sweep: 70, color: caustic,
                               startColor: caustic, core: 0.55, glow: OrbInstance.glow(sigma: 0.008 * s), glowAlpha: 0.7),
                      blend: frame.glowBlend)
        }
        let highlight = dark ? RGBColor.white.opacity(0.13) : RGBColor.white.opacity(0.75)
        scene.add(.ellipse(center: CGPoint(x: center.x - 0.17 * s, y: center.y - 0.22 * s),
                           radii: CGSize(width: 0.2 * s, height: 0.12 * s), rotation: -34, color: highlight)
            .radialGradient(to: highlight.opacity(0), radius: 0.24 * s), blend: .over)
        let glint = dark ? RGBColor.white.opacity(0.22) : RGBColor.white.opacity(0.95)
        scene.add(.bandArc(center: center, radius: 0.42 * s, width: max(1, 0.012 * s), start: 200, sweep: 36, color: glint,
                           startColor: glint, roundCaps: true), blend: .over)
    }

    // MARK: Readout

    /// Split by the surface: above it in the normal tokens, below it in colors that hold on the lit liquid
    /// (DESIGN 2a.3, layer 10), so the title never sits in its own color on its own color.
    func buildReadout(into scene: inout OrbScene, _ frame: OrbFrame, readout: OrbReadoutBuilder) {
        let s = frame.s
        let rect = CGRect(x: frame.center.x - s, y: frame.center.y - s, width: 2 * s, height: 2 * s)
        readout.add(into: &scene, frame, layout: readoutLayout, clip: .liquid(below: false, rect: rect))
        var palette = OrbReadoutPalette()
        if frame.dark {
            palette.value = RGBColor.white.opacity(0.97)
            palette.unit = RGBColor.white.opacity(0.80)
            palette.title = RGBColor.white.opacity(0.94)
            palette.shadow = RGBColor.black.opacity(frame.content.increaseContrast ? 0.75 : 0.55)
            palette.shadowRadius = 0.03 * s
        } else {
            let ink = RGBColor(hex: 0x0B0D12)
            palette.value = ink.opacity(0.94)
            palette.unit = ink.opacity(0.72)
            palette.title = HeatPalette.color(max(heatOf(frame), 0.05)).darkened(0.55)
            palette.valueGlow = false
        }
        readout.add(into: &scene, frame, layout: readoutLayout, palette: palette, clip: .liquid(below: true, rect: rect), pill: false)
    }

    /// The two lines split at the surface like the readout (DESIGN 10: the 2a.3 layer 10 rule).
    func buildLines(into scene: inout OrbScene, _ frame: OrbFrame, lines: OrbLineReadout) {
        let s = frame.s
        let rect = CGRect(x: frame.center.x - s, y: frame.center.y - s, width: 2 * s, height: 2 * s)
        let contrast = frame.content.increaseContrast
        lines.add(into: &scene, frame, placement: linePlacement, palette: .standard(dark: frame.dark, increaseContrast: contrast),
                    clip: .liquid(below: false, rect: rect))
        lines.add(into: &scene, frame, placement: linePlacement,
                  palette: .underLiquid(dark: frame.dark, diameter: s, increaseContrast: contrast), clip: .liquid(below: true, rect: rect))
    }
}


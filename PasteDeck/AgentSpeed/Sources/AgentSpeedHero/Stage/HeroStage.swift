import Foundation
import simd

/// The hero vehicle's state (DESIGN 4c): which vehicle is on stage, the shared ground distance, transitions,
/// start-up, parking and the particle pools. Deterministic for a given sequence of inputs; never allocates per frame.
public final class HeroStage {
    public let library: HeroLibrary

    public private(set) var time = 0.0
    public private(set) var title: Int?
    public private(set) var current: HeroActor
    public private(set) var outgoing: HeroActor?
    public private(set) var parked = true
    /// Ground speed `G` (units/s) and its acceleration.
    public private(set) var ground = HeroCriticalSpring(settle: 0.9)
    /// 0 parked … 1 awake: recolors slate → heat and fades glow, flames, contrails and hover.
    public private(set) var wake = HeroCriticalSpring(settle: 0.5)
    /// Travelled distance `D` (units), shared by wheels, cranks, gait and scenery.
    public private(set) var distance = 0.0
    /// Walker: 1 = standing pose.
    public private(set) var stand = 1.0
    /// Band progress `b`, coasting `c`, smoothed value `v_s`, heat and overdrive of the last update.
    public private(set) var band = 0.0
    public private(set) var coast = 0.0
    public private(set) var smoothedValue = 0.0
    public private(set) var heat = 0.0
    public private(set) var overdrive = 0.0
    public private(set) var tier = 0
    public private(set) var level = HeroLevel.standard
    public private(set) var reduceMotion = false
    public private(set) var sweepEpoch = 0.0
    public private(set) var startupVehicle: Int?
    public private(set) var startupStart = 0.0
    public private(set) var flash: HeroFlash?
    /// Integrated suspension phase, so a changing band never jumps the bob's phase.
    public private(set) var suspensionPhase = 0.0
    public private(set) var particles = HeroParticles()
    public private(set) var lines = HeroSpeedLines()

    private var lastTime: Double?
    private var startupFired: UInt32 = 0
    private var random: HeroRandom

    public init(library: HeroLibrary, seed: UInt32 = 7) {
        self.library = library
        random = HeroRandom(seed: seed)
        current = HeroActor(vehicle: library.fallback, start: -.infinity, transition: .stay)
    }

    public var vehicle: HeroVehicle { library.vehicles[current.vehicle] }

    /// Continuous motion runs (not Off, not Reduce Motion).
    public var animated: Bool { level >= .soft && !reduceMotion }

    public var acceleration: Double { ground.velocity }

    // MARK: Priming

    /// Places the stage in the steady state of `input` without any transition or start-up, as when the dashboard
    /// opens: the title's vehicle cruising, or `parkedVehicle` parked while idle.
    public func prime(_ input: HeroInput, parkedVehicle: Int?) {
        lastTime = input.time
        time = input.time
        apply(input)
        title = input.title
        outgoing = nil
        startupVehicle = nil
        flash = nil
        particles.clear()
        lines.clear()
        parked = input.title == nil
        let vehicleIndex = input.title ?? parkedVehicle ?? library.fallback
        current = HeroActor(vehicle: vehicleIndex, start: -.infinity, transition: .stay)
        computeBand(input)
        ground.snap(to: groundTarget())
        wake.snap(to: parked ? 0 : 1)
        stand = parked ? 1 : 0
        distance = vehicle.rest
    }

    // MARK: Update

    public func update(_ input: HeroInput) {
        let dt = HeroMath.clamp(input.time - (lastTime ?? input.time), 0, 0.1)
        let previousTime = lastTime ?? input.time
        lastTime = input.time
        time = input.time
        apply(input)
        if input.title != title {
            let at = HeroMath.clamp(input.titleChangedAt, previousTime - 0.1, input.time)
            change(from: title, to: input.title, at: at.isFinite ? at : input.time)
            title = input.title
        }
        computeBand(input)

        let target = groundTarget()
        if animated {
            ground.step(toward: target, dt: dt)
            distance += ground.value * dt
        } else {
            ground.snap(to: target)
            distance = vehicle.rest
        }
        if level == .off {
            wake.snap(to: parked ? 0 : 1)
        } else {
            wake.step(toward: parked ? 0 : 1, dt: dt)
        }
        let standTarget = parked && ground.value < 6 ? 1.0 : 0.0
        stand = animated ? stand + (standTarget - stand) * (1 - exp(-dt / 0.18)) : standTarget
        suspensionPhase = (suspensionPhase + 2 * .pi * (1 + 0.5 * band) * dt).truncatingRemainder(dividingBy: 2 * .pi * 1000)

        if let leaving = outgoing, time - leaving.start > 0.8 { outgoing = nil }
        if startupVehicle != nil, time - startupStart > 1.4 { startupVehicle = nil }
        if let flash, time - flash.start > 0.5 { self.flash = nil }

        if animated {
            particles.step(dt: dt, ground: ground.value)
            let bounds = vehicle.bounds
            lines.step(dt: dt, cap: lineCap, heat: heat, ground: ground.value, bounds: bounds, heading: vehicle.heading,
                       random: &random)
            emitContinuous(dt: dt)
            fireStartupEvents()
        } else {
            particles.clear()
            lines.clear()
        }
    }

    private func apply(_ input: HeroInput) {
        level = input.reduceMotion ? min(input.level, .soft) : input.level
        reduceMotion = input.reduceMotion
        heat = HeroMath.clamp(input.heat, 0, 1)
        overdrive = HeroMath.clamp(input.overdrive, 0, 1)
        tier = input.tier
        sweepEpoch = input.sweepEpoch
        smoothedValue = heat < 0.999 ? input.redline * pow(heat, 1 / 0.6) : input.redline * (1 + overdrive)
    }

    private func computeBand(_ input: HeroInput) {
        guard title != nil else {
            band = 0
            coast = 0
            return
        }
        let low = max(input.threshold, 1e-9)
        if let high = input.nextThreshold, high > low {
            band = HeroMath.clamp(log(max(smoothedValue, 1e-9) / low) / log(high / low), 0, 1)
        } else {
            band = overdrive
        }
        coast = HeroMath.clamp(smoothedValue / low, 0, 1)
    }

    /// `G* = lerp(lo, hi, b) · √c`, 0 when parked.
    public func groundTarget() -> Double {
        guard !parked else { return 0 }
        let speed = vehicle.speed
        return HeroMath.lerp(speed.lo, speed.hi, band) * coast.squareRoot()
    }

    var lineCap: Int {
        guard !parked else { return 0 }
        return HeroSpeedLines.cap(level: level, heat: heat, ground: ground.value, low: vehicle.speed.lo)
    }

    // MARK: Title changes

    private func change(from old: Int?, to new: Int?, at start: Double) {
        guard let new else {
            parked = true
            return
        }
        let off = level == .off
        let fade = reduceMotion
        guard let old else {
            parked = false
            let same = new == current.vehicle
            if !same {
                outgoing = HeroActor(vehicle: current.vehicle, start: start, transition: off ? .cut : fade ? .fade : .wake)
            }
            current = HeroActor(vehicle: new, start: start, transition: same || off ? .stay : fade ? .fade : .wake)
            if !off, !fade {
                startupVehicle = new
                startupStart = start + (same ? 0.15 : 0.3)
                startupFired = 0
            }
            return
        }
        parked = false
        let transition: HeroTransition = off ? .cut : fade ? .fade : (new > old ? .upgrade : .downgrade)
        let base = placement(of: current, outgoing: false).offset
        let along = simd_dot(base, vehicle.headingVector)
        outgoing = HeroActor(vehicle: current.vehicle, start: start, transition: transition, base: along)
        current = HeroActor(vehicle: new, start: start, transition: transition, levels: abs(new - old))
        startupVehicle = nil
        if transition == .upgrade {
            flash = HeroFlash(start: start + 0.32, strength: min(1.6, 1 + 0.2 * Double(abs(new - old) - 1)))
            for _ in 0..<4 { spawnBurstLine() }
        }
    }

    private func spawnBurstLine() {
        guard animated else { return }
        lines.spawn(burst: true, heat: heat, ground: ground.value, bounds: vehicle.bounds, heading: vehicle.heading,
                    random: &random)
    }

    // MARK: Placement

    /// Offset, opacity and ghost speed of an actor at the current time (DESIGN 4c, Title transitions).
    public func placement(of actor: HeroActor, outgoing leaving: Bool) -> HeroPlacement {
        let tau = time - actor.start
        let direction = library.vehicles[actor.vehicle].headingVector
        func along(_ d: Double, _ alpha: Double, _ ghost: Double) -> HeroPlacement {
            HeroPlacement(offset: direction * d, alpha: HeroMath.clamp(alpha, 0, 1), ghostSpeed: ghost, direction: direction)
        }
        if leaving {
            switch actor.transition {
            case .upgrade:
                let u = tau / 0.34
                return along(actor.base + 90 * HeroMath.easeInCubic(u), 1 - HeroMath.smooth((tau - 0.12) / 0.18),
                             u < 1 ? 90 * 3 * u * u / 0.34 : 0)
            case .downgrade:
                return along(actor.base - 46 * HeroMath.easeInOutSine(tau / 0.55), 1 - HeroMath.smooth(tau / 0.45), 0)
            case .cut:
                return along(0, 0, 0)
            case .wake:
                return along(0, 1 - HeroMath.smooth(tau / 0.2), 0)
            case .fade, .stay:
                return along(0, 1 - HeroMath.smooth(tau / 0.3), 0)
            }
        }
        switch actor.transition {
        case .upgrade:
            let s = tau - 0.12
            guard s > 0 else { return along(-62, 0, 0) }
            let x = HeroMath.spring(at: s, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8)
            let v = HeroMath.springVelocity(at: s, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8)
            return along(x, HeroMath.smooth(s / 0.14), max(0, v))
        case .downgrade:
            let s = tau - 0.1
            return along(8 * (1 - HeroMath.easeOutCubic(s / 0.55)), HeroMath.smooth(s / 0.35), 0)
        case .fade:
            return along(0, HeroMath.smooth(tau / 0.3), 0)
        case .wake:
            return along(0, HeroMath.smooth((tau - 0.12) / 0.28), 0)
        case .stay, .cut:
            return along(0, 1, 0)
        }
    }

    // MARK: Start-up

    /// Seconds into the running start-up of `vehicleIndex`, or nil.
    public func startupTime(for vehicleIndex: Int) -> Double? {
        guard startupVehicle == vehicleIndex else { return nil }
        return time - startupStart
    }

    public func startupEffects(for vehicleIndex: Int) -> HeroStartupEffects {
        guard let tau = startupTime(for: vehicleIndex) else { return HeroStartupEffects() }
        return HeroStartup.effects(kind: library.vehicles[vehicleIndex].kind, tau: tau)
    }

    private func fireStartupEvents() {
        guard let index = startupVehicle, let tau = startupTime(for: index), tau >= 0 else { return }
        let vehicle = library.vehicles[index]
        let cap = level >= .standard ? Int.max : 6
        func once(_ bit: Int, _ at: Double, _ body: () -> Void) {
            let mask = UInt32(1) << UInt32(bit)
            guard tau >= at, startupFired & mask == 0 else { return }
            startupFired |= mask
            body()
        }
        if let dust = vehicle.emitter(.dust) {
            once(0, 0.05) { particles.burst(.puff, at: dust.at, dir: dust.dir, count: dust.count, cap: cap, random: &random) }
        }
        switch vehicle.kind {
        case .ebike:
            if let arc = vehicle.emitter(.arc) {
                once(1, 0.02) { particles.burst(.arc, at: arc.at, dir: arc.dir, count: arc.count, cap: cap, random: &random) }
            }
        case .motorcycle:
            if let exhaust = vehicle.emitter(.exhaust) {
                once(2, 0) { particles.burst(.puff, at: exhaust.at, dir: exhaust.dir, count: exhaust.count, cap: cap, random: &random) }
                once(3, 0.18) { particles.burst(.puff, at: exhaust.at, dir: exhaust.dir, count: exhaust.count, cap: cap, random: &random) }
            }
        case .car:
            if let exhaust = vehicle.emitter(.exhaust) {
                once(2, 0.1) { particles.burst(.puff, at: exhaust.at, dir: exhaust.dir, count: exhaust.count, cap: cap, random: &random) }
            }
        case .sportsCar:
            if let exhaust = vehicle.emitter(.exhaust) {
                once(2, 0.12) { particles.burst(.pop, at: exhaust.at, dir: exhaust.dir, count: 1, cap: cap, random: &random) }
            }
        case .raceCar:
            let tire = vehicle.parts.first { $0.id == "rearTire" }
            if case .circle(let cx, _, _)? = tire?.shape, let groundY = vehicle.groundY {
                once(2, 0.02) {
                    particles.burst(.puff, at: SIMD2(cx, groundY), dir: SIMD2(-1, -0.35), count: 5, cap: cap, random: &random)
                }
            }
        case .rocket:
            if let plume = vehicle.emitter(.plume) {
                once(2, 0) { particles.burst(.ring, at: plume.at, dir: plume.dir, count: 6, cap: cap, random: &random) }
            }
        default:
            break
        }
        for line in 0..<3 {
            once(8 + line, 0.1 + 0.07 * Double(line)) { spawnBurstLine() }
        }
    }

    // MARK: Particle streams

    private func emitContinuous(dt: Double) {
        guard level >= .standard, !parked else { return }
        let rate = level == .max ? 1.6 : 1
        let vehicle = vehicle
        switch vehicle.kind {
        case .rocket:
            if let sparks = vehicle.emitter(.sparks) {
                particles.emit(rate: (26 + 60 * overdrive) * rate, dt: dt, at: sparks.at, dir: sparks.dir, speed: 70, spread: 0.55,
                               gravity: 0, life: 0.32, random: &random)
            }
        case .raceCar where band > 0.55:
            if let sparks = vehicle.emitter(.sparks) {
                particles.emit(rate: 30 * (band - 0.55) / 0.45 * rate, dt: dt, at: sparks.at, dir: sparks.dir, speed: 120,
                               spread: 0.5, gravity: 260, life: 0.28, random: &random)
            }
        case .fighterJet where tier >= 3, .hypersonic where tier >= 3:
            if let burner = vehicle.emitter(.afterburner) {
                particles.emit(rate: (6 + 14 * band) * rate, dt: dt, at: burner.at, dir: burner.dir, speed: 60, spread: 0.3,
                               gravity: 0, life: 0.25, random: &random)
            }
        default:
            break
        }
    }

    // MARK: Frame demand

    /// How often frames are needed now (DESIGN 4c, Accessibility and performance).
    public func demand() -> HeroFrameDemand {
        let wakeTarget = parked ? 0.0 : 1.0
        let waking = abs(wake.value - wakeTarget) > 0.002 || abs(wake.velocity) > 0.01
        if level == .off { return .still }
        if reduceMotion { return outgoing != nil || waking ? .full : .still }
        let moving = !parked || ground.value > 0.05 || waking || outgoing != nil || startupVehicle != nil || flash != nil
            || abs(stand - (parked && ground.value < 6 ? 1 : 0)) > 0.002 || !particles.isEmpty || !lines.isEmpty
        if moving { return .full }
        var phase = (time - sweepEpoch).truncatingRemainder(dividingBy: HeroStage.sweepPeriod)
        if phase < 0 { phase += HeroStage.sweepPeriod }
        return phase > HeroStage.sweepPeriod - 0.4 || phase < HeroStage.sweepDuration + 0.05 ? .idle(fps: 30) : .idle(fps: 10)
    }

    public static let sweepPeriod = 6.0
    public static let sweepDuration = 0.9
}

extension HeroMath {
    /// d/dt of `spring(at:…)`.
    public static func springVelocity(at t: Double, from: Double, to: Double, velocity: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return velocity }
        let omega = 2 * Double.pi / response
        let zeta = damping
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let a = from - to
        let b = (velocity + zeta * omega * a) / wd
        let decay = exp(-zeta * omega * t)
        return decay * ((-zeta * omega * a + b * wd) * cos(wd * t) + (-zeta * omega * b - a * wd) * sin(wd * t))
    }
}

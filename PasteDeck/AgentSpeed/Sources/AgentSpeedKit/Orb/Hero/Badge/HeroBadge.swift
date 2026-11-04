import AgentSpeedHero
import Foundation

/// What the badge reads each frame.
struct HeroBadgeInput {
    var time: TimeInterval
    /// 0 idle, 1–13 the speed title.
    var level: Int
    var titleChangedAt: TimeInterval
    var heat: Double
    var overdrive: Double
    /// Effect tier (0 idle … 4 redline).
    var tier: Int
    var redline: Double
    var level4c: HeroLevel
    var reduceMotion: Bool
    /// Start of the gauge's 6 s idle-sweep cycle; the light band crosses 0.63 s into it.
    var sweepEpoch: TimeInterval
}

/// The dashboard hero's title badge (DESIGN 4c, Hero title badge): a medallion that ranks up with the speed title of
/// every title theme except Vehicles. All state lives in fixed pools; stepping and drawing never allocate.
@MainActor
final class HeroBadge {
    enum TransitionKind {
        case up, down, startup, park
    }

    struct Transition {
        var from: Int
        var to: Int
        var start: TimeInterval
        var kind: TransitionKind
        var climbed: Int
    }

    struct Pip {
        var lit = 0.0
        /// When the pip pops in (or starts to go dark); −∞ when none is pending.
        var pop: TimeInterval = -.infinity
    }

    struct Streak {
        var alive = false
        var x = 0.0, y = 0.0, length = 0.0, age = 0.0, speed = 0.0, alpha = 0.0
    }

    struct Particle {
        var alive = false
        var ember = false
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, age = 0.0, life = 0.0, drag = 0.0, seed = 0.0
    }

    static let streakPool = 16
    static let particlePool = 64
    static let moteOrder = [0, 6, 3, 9, 1, 7, 4, 10, 2, 8, 5, 11]

    private(set) var level = 0
    private(set) var transition: Transition?
    private(set) var time: TimeInterval = 0
    private(set) var wake = HeroCriticalSpring(settle: 0.5)
    private(set) var ground = HeroCriticalSpring(settle: 0.9)
    private(set) var omega = HeroCriticalSpring(settle: 0.6)
    private(set) var motePhase = 0.0
    private(set) var haloPhase = 0.0
    private(set) var sheenPhase = 0.0
    private(set) var breathPhase = 0.0
    private(set) var pips = [Pip](repeating: Pip(), count: 13)
    private(set) var streaks = [Streak](repeating: Streak(), count: streakPool)
    private(set) var particles = [Particle](repeating: Particle(), count: particlePool)
    private(set) var input = HeroBadgeInput(time: 0, level: 0, titleChangedAt: -.infinity, heat: 0, overdrive: 0, tier: 0,
                                            redline: 400, level4c: .standard, reduceMotion: false, sweepEpoch: 0)
    /// A rename of the shown level (theme or language change): crossfades the text in 0.25 s with no effects.
    private(set) var renameFrom: String?
    private(set) var renameStart: TimeInterval = -.infinity
    private var shownText: String?
    private var streakTimer = 0.0
    private var emberCarry = 0.0
    private var lastTime: TimeInterval?
    private var random = HeroRandom(seed: 0x6D2B_79F5)
    private var primed = false
    let textCache = HeroBadgeTextCache()

    /// CPU time of `step` and `build` per frame (benchmarks and frame clips).
    private(set) var framesBuilt = 0
    private(set) var nanoseconds: UInt64 = 0
    var collectsSamples = false
    private(set) var samples: [UInt64] = []

    func recordFrame(_ elapsed: UInt64) {
        framesBuilt += 1
        nanoseconds &+= elapsed
        if collectsSamples { samples.append(elapsed) }
    }

    /// Next frame starts from the steady state of the input (previews, a theme switched to the badge).
    func reset() {
        primed = false
    }

    /// Effects level after the Reduce Motion cap: 0 off, 1 soft, 2 standard, 3 max.
    var fx: Int { input.reduceMotion ? min(input.level4c.rawValue, 1) : input.level4c.rawValue }
    var moving: Bool { fx >= 1 && !input.reduceMotion }

    // MARK: Step

    func step(_ input: HeroBadgeInput, text: String) {
        self.input = input
        if !primed {
            prime(input, text: text)
            return
        }
        let dt = min(1.0 / 15, max(0, input.time - (lastTime ?? input.time)))
        lastTime = input.time
        time = input.time
        if input.level != level {
            begin(from: level, to: input.level, input: input)
        } else if let shown = shownText, shown != text {
            renameFrom = shown
            renameStart = input.time
        }
        shownText = text
        if let transition, input.time - transition.start > 1.0 { self.transition = nil }

        let active = level > 0 ? 1.0 : 0.0
        wake.step(toward: active, dt: dt)
        for k in 1...13 {
            var pip = pips[k - 1]
            let on = k <= level
            if pip.pop.isFinite, input.time < pip.pop {
                pips[k - 1] = pip
                continue
            }
            let rate: Double = fx == 0 ? 1e9 : (input.reduceMotion ? 1 / 0.3 : (on ? 1e9 : 1 / 0.35))
            pip.lit = min(1, max(0, pip.lit + (on ? 1 : -1) * rate * dt))
            pips[k - 1] = pip
        }
        let h = input.heat, o = input.overdrive
        ground.step(toward: active > 0 && moving ? 60 + (900 - 60) * h + 300 * o : 0, dt: dt)
        omega.step(toward: active > 0 && moving ? 2 * .pi * (0.06 + 0.9 * h + 0.5 * o) : 0, dt: dt)
        motePhase = (motePhase + omega.value * dt).truncatingRemainder(dividingBy: 2 * .pi)
        if moving {
            haloPhase = (haloPhase + 2 * .pi / (4 + (0.7 - 4) * h) * dt).truncatingRemainder(dividingBy: 2 * .pi)
            breathPhase = (breathPhase + 2 * .pi / 4.8 * dt).truncatingRemainder(dividingBy: 2 * .pi)
            sheenPhase += dt / max(1.4, 5 - 3.5 * h)
            if sheenPhase > 1000 { sheenPhase -= 1000 }
        }
        stepStreaks(dt: dt)
        stepParticles(dt: dt)
    }

    /// Starts in the steady state: the level lit, no transition, springs at rest.
    private func prime(_ input: HeroBadgeInput, text: String) {
        primed = true
        lastTime = input.time
        time = input.time
        level = input.level
        transition = nil
        renameFrom = nil
        shownText = text
        let active = level > 0 ? 1.0 : 0.0
        wake = HeroCriticalSpring(settle: 0.5, value: active)
        let h = input.heat, o = input.overdrive
        ground = HeroCriticalSpring(settle: 0.9, value: active > 0 && moving ? 60 + 840 * h + 300 * o : 0)
        omega = HeroCriticalSpring(settle: 0.6, value: active > 0 && moving ? 2 * .pi * (0.06 + 0.9 * h + 0.5 * o) : 0)
        for k in 1...13 { pips[k - 1] = Pip(lit: k <= level ? 1 : 0) }
        for index in streaks.indices { streaks[index].alive = false }
        for index in particles.indices { particles[index].alive = false }
    }

    private func begin(from: Int, to: Int, input: HeroBadgeInput) {
        let start = input.titleChangedAt.isFinite && input.titleChangedAt <= input.time && input.titleChangedAt > input.time - 0.3
            ? input.titleChangedAt : input.time
        let kind: TransitionKind = from == 0 ? .startup : (to == 0 ? .park : (to > from ? .up : .down))
        transition = Transition(from: from, to: to, start: start, kind: kind, climbed: max(1, to - from))
        renameFrom = nil
        level = to
        switch kind {
        case .up, .startup:
            let first = from + 1
            if first <= to {
                for k in first...to {
                    let stagger = kind == .startup ? 0.035 : 0.045
                    pips[k - 1].pop = start + (kind == .startup ? 0.12 : 0.1) + stagger * Double(k - first)
                }
            }
            if kind == .up, moving { burst(count: fx == 1 ? 6 : min(18, 10 + 3 * (to - from - 1)), start: start) }
        case .down, .park:
            if to + 1 <= from {
                for k in (to + 1)...from { pips[k - 1].pop = start + (kind == .park ? 0.03 * Double(from - k) : 0) }
            }
        }
    }

    // MARK: Streaks and particles

    private func stepStreaks(dt: Double) {
        let caps = [0, 5, 9, 14]
        let g = ground.value
        let h = input.heat
        let scale = fx == 3 ? 1.4 : (fx == 1 ? 0.6 : 1)
        var count = Int(((2 + 8 * h) * min(1, max(0, g / 60)) * scale).rounded())
        count = moving ? min(caps[fx], count) : 0
        var alive = 0
        for index in streaks.indices where streaks[index].alive {
            streaks[index].x -= streaks[index].speed * dt
            streaks[index].age += dt
            if streaks[index].x + streaks[index].length < -2 { streaks[index].alive = false } else { alive += 1 }
        }
        streakTimer -= dt
        guard count > 0, streakTimer <= 0, alive < Self.streakPool,
              let slot = streaks.firstIndex(where: { !$0.alive }) else { return }
        streakTimer = 0.9 / Double(count) * (0.5 + random.next())
        let upper = random.next() < 0.5
        let length = (6 + 20 * h) * (0.7 + 0.6 * random.next()) + 1.5 * g / 60
        streaks[slot] = Streak(
            alive: true,
            x: 100 + length,
            y: upper ? 16 + 17 * random.next() : 67 + 17 * random.next(),
            length: length,
            age: 0,
            speed: 1.25 * max(g, 40) * (0.85 + 0.3 * random.next()),
            alpha: (0.16 + 0.32 * h) * (0.7 + 0.6 * random.next()) * wake.value
        )
    }

    private func burst(count: Int, start: TimeInterval) {
        var made = 0
        for index in particles.indices where !particles[index].alive {
            guard made < count else { break }
            let angle = random.next() * 2 * .pi
            let speed = 40 + 50 * random.next()
            particles[index] = Particle(
                alive: true, ember: false,
                x: 50 + cos(angle) * 12, y: 50 + sin(angle) * 8,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                age: -0.08 - (input.time - start), life: 0.35 + 0.25 * random.next(), drag: 2.5, seed: 0
            )
            made += 1
        }
    }

    private func stepParticles(dt: Double) {
        let overdriveTier = level > 0 && input.tier >= 3
        if fx >= 2, !input.reduceMotion, overdriveTier {
            emberCarry += (6 + 26 * input.overdrive) * (fx == 3 ? 1.6 : 1) * dt
            while emberCarry >= 1 {
                emberCarry -= 1
                guard let slot = particles.firstIndex(where: { !$0.alive }) else { break }
                let angle = (30 + 120 * random.next()) * .pi / 180
                particles[slot] = Particle(
                    alive: true, ember: true,
                    x: 50 + cos(angle) * 33, y: 50 + sin(angle) * 33,
                    vx: 0, vy: -(18 + 16 * random.next()),
                    age: 0, life: 0.6 + 0.5 * random.next(), drag: 0, seed: random.next() * 10
                )
            }
        } else {
            emberCarry = 0
        }
        for index in particles.indices where particles[index].alive {
            var p = particles[index]
            p.age += dt
            if p.age >= p.life {
                p.alive = false
            } else if p.age >= 0 {
                if p.ember { p.vx = 6 * sin(p.seed + p.age * 7) }
                let drag = exp(-p.drag * dt)
                p.vx *= drag
                p.vy *= drag
                p.x += p.vx * dt
                p.y += p.vy * dt
            }
            particles[index] = p
        }
    }

    // MARK: Demand

    /// How often the badge needs frames (as the vehicle's demand, DESIGN 4c frame policy).
    func demand(at time: TimeInterval) -> HeroFrameDemand {
        guard primed else { return .full }
        if let transition, time - transition.start < 1.0 { return .full }
        if renameFrom != nil, time - renameStart < 0.3 { return .full }
        for particle in particles where particle.alive { return .full }
        for streak in streaks where streak.alive { return .full }
        if !wake.isSettled(at: level > 0 ? 1 : 0) { return .full }
        if level > 0 { return moving ? .full : .still }
        guard moving else { return .still }
        let phase = (time - input.sweepEpoch - HeroVehicleDriver.sweepOffset).truncatingRemainder(dividingBy: 6)
        let cycle = phase < 0 ? phase + 6 : phase
        return cycle < 0.95 ? .idle(fps: 30) : .idle(fps: 10)
    }
}

extension HeroCriticalSpring {
    func isSettled(at target: Double) -> Bool { abs(value - target) < 0.002 && abs(velocity) < 0.01 }
}

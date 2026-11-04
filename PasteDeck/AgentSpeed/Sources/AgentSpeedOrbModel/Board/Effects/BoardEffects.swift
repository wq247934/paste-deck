import Foundation

/// The board's effects layer as a simulation (DESIGN 2c Motion and effects, the prototype's `fx.js`): perimeter comets,
/// the heat ring and outside bloom, particles, row streaks, shockwaves, lightning, the new-leader celebration and the
/// neon warp. Coordinates are board points (origin at the board's top-left corner, y down); the canvas reaches
/// `margin` beyond the board on every side. Pools are allocated once, so advancing and emitting never allocate.
public struct BoardEffects {
    /// How far the effects canvas reaches beyond the board (fx.js `inset: -40px`).
    public static let margin = 40.0
    /// The bloom fades out along the board's outline to nothing this far outside it, 2 pt short of the canvas edge
    /// (DESIGN 2c Perimeter).
    public static let bloomReach = margin - 2
    public static let particleCapacity = 640
    public static let waveCapacity = 12
    public static let boltCapacity = 8
    public static let starCapacity = 135
    public static let cometCount = 4
    /// Comet dashes as fractions of the outline (fx.js 150, 46 and 16 of 1000), all ending at the head.
    public static let tailFraction = 0.15
    public static let glowFraction = 0.046
    public static let coreFraction = 0.016
    /// The comets' rect sits 0.8 pt inside the board (fx.js `inset`).
    public static let outlineInset = 0.8
    static let emberInterval = 0.12
    static let celebrationSeconds = 2.2
    static let flashSeconds = 0.38

    public private(set) var preset: BoardEffectsPreset
    public private(set) var side: Double
    public private(set) var intensity = BoardEffectsIntensity.standard
    public private(set) var reduceMotion = false
    /// `Celebrate new peaks` (DESIGN 2c): off turns a new leader into a plain overtake and drops new-peak rings.
    public var celebrations = true
    /// The warp's streaks are simulated here (frames draw them); false when the platform animates them itself from
    /// `warpRequested` and the heat, so they need no frames.
    public var simulatesWarp = true
    /// The heat and overdrive given by the last `setHeat`, and the eased values the frames show.
    public private(set) var heat = 0.0
    public private(set) var overdrive = 0.0
    public private(set) var shownHeat = 0.0
    public private(set) var shownOverdrive = 0.0
    /// Something is generating: the comets run (else they stop where they are and nothing renders).
    public private(set) var active = false
    /// Seconds of gold comets left (new leader).
    public private(set) var gold = 0.0
    /// Neon's board flash on a new leader, 1 → 0.
    public private(set) var flash = 0.0
    /// Laps travelled by the comets (fraction of the outline, wrapping).
    public private(set) var phase = 0.0
    /// 1 while the comets run, eased to 0 when nothing generates.
    public private(set) var cometSpeed = 0.0
    public private(set) var comets = ContiguousArray(repeating: BoardComet(), count: BoardEffects.cometCount)
    public private(set) var particles = ContiguousArray<BoardParticle>()
    public private(set) var waves = ContiguousArray<BoardWave>()
    public private(set) var bolts = ContiguousArray(repeating: BoardBolt(), count: BoardEffects.boltCapacity)
    /// Bolt `b`, path `k`, point `i` at `(b × maxPaths + k) × maxPoints + i`.
    public private(set) var boltPoints = ContiguousArray(
        repeating: SIMD2<Double>.zero, count: BoardEffects.boltCapacity * BoardBolt.maxPaths * BoardBolt.maxPoints)
    public private(set) var stars = ContiguousArray(repeating: BoardStar(angle: 0, distance: 0), count: BoardEffects.starCapacity)
    public private(set) var starCount = 0
    private var emberClock = 0.0
    private var random: LedRandom
    private let heatColor: @Sendable (Double) -> BoardFXColor

    public init(style: BoardStyle, side: Double, seed: UInt64 = 0xB0A2D,
                heatColor: @escaping @Sendable (Double) -> BoardFXColor) {
        preset = .of(style)
        self.side = side
        random = LedRandom(seed: seed)
        self.heatColor = heatColor
        particles.reserveCapacity(Self.particleCapacity)
        waves.reserveCapacity(Self.waveCapacity)
        updateComets()
        settleNow()
    }

    /// Ends every easing at once (a board that just appeared shows its state without fading into it).
    public mutating func settleNow() {
        shownHeat = heat
        shownOverdrive = overdrive
        cometSpeed = active && transientsAllowed ? 1 : 0
        for index in comets.indices {
            comets[index].opacity = comets[index].targetOpacity
            comets[index].offset = comets[index].targetOffset
        }
    }

    // MARK: Settings

    public mutating func setStyle(_ style: BoardStyle) {
        guard style != preset.style else { return }
        preset = .of(style)
        updateComets()
    }

    public mutating func setSide(_ side: Double) {
        self.side = side
    }

    public mutating func setIntensity(_ intensity: BoardEffectsIntensity) {
        guard intensity != self.intensity else { return }
        self.intensity = intensity
        if !particlesAllowed { particles.removeAll(keepingCapacity: true) }
        if intensity == .off { clearTransients() }
        updateComets()
    }

    public mutating func setReduceMotion(_ reduce: Bool) {
        guard reduce != reduceMotion else { return }
        reduceMotion = reduce
        if reduce { clearTransients() }
        updateComets()
    }

    // MARK: Heat

    /// The board's heat (0...1), overdrive (0...1) and whether anything generates, once per engine tick.
    public mutating func setHeat(_ heat: Double, overdrive: Double, active: Bool) {
        self.heat = heat.isFinite ? min(max(heat, 0), 1) : 0
        self.overdrive = overdrive.isFinite ? min(max(overdrive, 0), 1) : 0
        self.active = active
        if instantChanges {
            shownHeat = self.heat
            shownOverdrive = self.overdrive
        }
        updateComets()
    }

    public var tier: BoardHeatTier { BoardHeatTier(heat: heat) }

    /// Off and Reduce Motion show a new heat at once instead of easing to it.
    private var instantChanges: Bool { intensity == .off || reduceMotion }
    private var particlesAllowed: Bool { intensity.particleScale > 0 && !reduceMotion }
    private var transientsAllowed: Bool { intensity != .off && !reduceMotion }

    private mutating func updateComets() {
        var count = transientsAllowed ? preset.comets[tier.rawValue] : 0
        if intensity == .soft { count = min(count, 1) }
        let opacity = tier == .idle ? 0.35 : 1
        for index in comets.indices {
            guard index < count else {
                comets[index].targetOpacity = 0
                continue
            }
            comets[index].targetOpacity = opacity
            comets[index].targetOffset = Double(index) / Double(count)
            if comets[index].opacity < 0.01 { comets[index].offset = comets[index].targetOffset }
        }
    }

    // MARK: Frames

    /// Advances every effect by `dt` seconds (clamped to 50 ms, as fx.js).
    public mutating func advance(_ dt: Double) {
        let dt = dt.isFinite ? min(max(dt, 0), 0.05) : 0
        guard dt > 0 else { return }
        let ease = 1 - exp(-dt / 0.25)
        shownHeat = Self.approach(shownHeat, heat, ease)
        shownOverdrive = Self.approach(shownOverdrive, overdrive, ease)
        gold = max(0, gold - dt)
        flash = max(0, flash - dt / Self.flashSeconds)

        let runs = active && transientsAllowed
        cometSpeed = Self.approach(cometSpeed, runs ? 1 : 0, 1 - exp(-dt / 0.3))
        phase = (phase + dt * cometSpeed / lapSeconds).truncatingRemainder(dividingBy: 1)
        let spacing = 1 - exp(-dt / 0.35)
        for index in comets.indices {
            var comet = comets[index]
            let step = dt / 0.8
            comet.opacity += max(-step, min(step, comet.targetOpacity - comet.opacity))
            var gap = (comet.targetOffset - comet.offset).truncatingRemainder(dividingBy: 1)
            if gap > 0.5 { gap -= 1 } else if gap < -0.5 { gap += 1 }
            comet.offset = abs(gap) < 1e-4 ? comet.targetOffset : comet.offset + gap * spacing
            comets[index] = comet
        }

        if particlesAllowed, active, shownHeat > 0.78 {
            emberClock += dt
            while emberClock >= Self.emberInterval {
                emberClock -= Self.emberInterval
                emitEmbers()
            }
        } else {
            emberClock = 0
        }

        var index = particles.count - 1
        while index >= 0 {
            var p = particles[index]
            p.age += dt
            if p.age >= p.life {
                particles.swapAt(index, particles.count - 1)
                particles.removeLast()
            } else {
                p.vx -= p.vx * p.drag * dt
                p.vy -= p.vy * p.drag * dt
                p.vy += p.gravity * dt
                p.x += p.vx * dt
                p.y += p.vy * dt
                particles[index] = p
            }
            index -= 1
        }
        index = waves.count - 1
        while index >= 0 {
            waves[index].age += dt
            if waves[index].age >= waves[index].life {
                waves.swapAt(index, waves.count - 1)
                waves.removeLast()
            }
            index -= 1
        }
        for b in bolts.indices where bolts[b].alive {
            bolts[b].age += dt
            if bolts[b].age >= bolts[b].life { bolts[b].alive = false }
        }
        advanceWarp(dt)
    }

    /// Seconds per lap: 7 s idle → 1.6 s at the redline, 1.8× faster while gold.
    public var lapSeconds: Double { (7 - 5.4 * shownHeat) / (gold > 0 ? 1.8 : 1) }

    /// The frame class the effects need (DESIGN 2c Frame policy): 60 fps while a burst, wave, bolt or celebration is
    /// alive and from overdrive up, 30 fps while generating below it or while values settle, static otherwise.
    public var frameClass: OrbFrameClass {
        if !particles.isEmpty || !waves.isEmpty || liveBolts > 0 || gold > 0 || flash > 0 { return .fps60 }
        if active, transientsAllowed { return BoardHeatTier(heat: shownHeat) >= .overdrive ? .fps60 : .fps30 }
        return settled ? .none : .fps30
    }

    /// Nothing eases any more: a frame drawn now stays valid.
    public var settled: Bool {
        shownHeat == heat && shownOverdrive == overdrive && starCount == 0 && cometSpeed == (active && transientsAllowed ? 1 : 0)
            && comets.allSatisfy { $0.opacity == $0.targetOpacity && $0.offset == $0.targetOffset }
    }

    public var liveBolts: Int { bolts.reduce(0) { $0 + ($1.alive ? 1 : 0) } }

    /// What a frame of the settled effects shows: a change that keeps it equal needs no redraw.
    public var still: BoardEffectsStill {
        BoardEffectsStill(style: preset.style, side: side, intensity: intensity, reduceMotion: reduceMotion,
                          heat: shownHeat, overdrive: shownOverdrive, phase: phase, gold: gold, comets: comets)
    }

    private static func approach(_ value: Double, _ target: Double, _ ease: Double) -> Double {
        let next = value + (target - value) * ease
        return abs(target - next) < 0.001 ? target : next
    }

    private mutating func clearTransients() {
        particles.removeAll(keepingCapacity: true)
        waves.removeAll(keepingCapacity: true)
        for b in bolts.indices { bolts[b].alive = false }
        starCount = 0
        flash = 0
    }

    // MARK: Perimeter readout

    /// The outline the comets and the ring run on (inset 0.8 pt), in board points from `outlineOrigin`.
    public var outline: BoardPerimeter {
        BoardPerimeter(width: side - 2 * Self.outlineInset, height: side - 2 * Self.outlineInset,
                       radius: preset.cornerRadius - Self.outlineInset)
    }

    public var outlineOrigin: Double { Self.outlineInset }

    /// Head of comet `index` as a fraction of the outline.
    public func cometHead(_ index: Int) -> Double {
        let head = (phase + comets[index].offset + Self.tailFraction).truncatingRemainder(dividingBy: 1)
        return head < 0 ? head + 1 : head
    }

    public var cometHeadColor: BoardFXColor { gold > 0 ? .fxGoldHead : heatColor(min(1, shownHeat + 0.12)) }
    public var cometTailColor: BoardFXColor { gold > 0 ? .fxGold : heatColor(max(0.1, shownHeat - 0.15)) }
    /// White-hot above h = 0.85 and while gold.
    public var cometCoreColor: BoardFXColor { gold > 0 || shownHeat > 0.85 ? .fxWhiteHot : cometHeadColor }

    /// The full ring lights from h = 0.55.
    private var ringOn: Double { reduceMotion ? 0 : max(0, (shownHeat - 0.55) / 0.45) }
    public var ringColor: BoardFXColor { gold > 0 ? .fxGold : heatColor(shownHeat) }
    public var ringAlpha: Double { 0.12 + ringOn * 0.55 + shownOverdrive * 0.3 }
    public var ringGlowAlpha: Double { ringOn * 0.55 + shownOverdrive * 0.4 + (gold > 0 ? 0.5 : 0) }
    /// fx.js `--bloom`: 0.15 + 0.6 h + 0.4 overdrive; the bloom blurs `bloom × bloomBlur` and spreads `bloom × bloomSpread`.
    public var bloom: Double { 0.15 + shownHeat * 0.6 + shownOverdrive * 0.4 }
    /// The prototypes' `--heat-soft`: the heat color at 55 %.
    public var bloomColor: BoardFXColor { heatColor(shownHeat).opacity(0.55) }

    /// The point `fraction` along the outline in board points, with the outward direction from the board's center.
    public func outlinePoint(_ fraction: Double) -> (x: Double, y: Double, outward: Double) {
        let p = outline.point(fraction: fraction)
        let x = p.x + outlineOrigin, y = p.y + outlineOrigin
        return (x, y, atan2(y - side / 2, x - side / 2))
    }

    // MARK: Warp

    /// Neon's hyperspace streaks from h = 0.2 (Standard and Max).
    public var warpOn: Bool { simulatesWarp && preset.warp && particlesAllowed && shownHeat > 0.2 }
    /// The style, settings and the tick's heat call for the warp (a platform that animates it itself shows it).
    public var warpRequested: Bool { preset.warp && particlesAllowed && heat > 0.2 }
    public var warpCenter: SIMD2<Double> { SIMD2(side * 0.72, side * 0.28) }

    private mutating func advanceWarp(_ dt: Double) {
        guard warpOn else {
            starCount = 0
            return
        }
        let want = min(Self.starCapacity, Int(((20 + shownHeat * 70) * (intensity == .max ? 1.5 : 1)).rounded()))
        while starCount < want {
            stars[starCount] = BoardStar(angle: random.next() * .pi * 2, distance: random.next() * 40)
            starCount += 1
        }
        starCount = want
        let speed = 60 + shownHeat * 520 + shownOverdrive * 400
        let reach = hypot(side, side)
        for index in 0..<starCount {
            var star = stars[index]
            star.distance += speed * dt * (0.4 + star.distance / 140)
            if star.distance > reach {
                star.distance = random.next() * 20
                star.angle = random.next() * .pi * 2
            }
            stars[index] = star
        }
    }

    /// Streak `index`: its head, tail length, alpha, width and the heat its color takes.
    public func star(_ index: Int) -> (x: Double, y: Double, angle: Double, tail: Double, alpha: Double, width: Double, heat: Double) {
        let star = stars[index]
        let c = warpCenter
        let h = shownHeat
        return (c.x + cos(star.angle) * star.distance, c.y + sin(star.angle) * star.distance, star.angle,
                min(60, 6 + star.distance * 0.18 * (0.3 + h)), min(1, star.distance / 120) * (0.25 + h * 0.55),
                0.8 + h * 0.8, min(1, h + star.angle.truncatingRemainder(dividingBy: 0.3)))
    }

    public func heatColor(at h: Double) -> BoardFXColor { heatColor(h) }

    // MARK: Emitters

    /// Particles from `(x, y)`; scaled by the intensity (Soft and Reduce Motion: none).
    public mutating func burst(x: Double, y: Double, _ spec: BoardBurst) {
        guard particlesAllowed else { return }
        let count = Int((Double(spec.count) * intensity.particleScale).rounded())
        for index in 0..<count where particles.count < Self.particleCapacity {
            let angle = (spec.angle ?? random.next() * .pi * 2) + (random.next() - 0.5) * spec.spread
            let speed = spec.speed * (0.35 + random.next() * 0.75)
            particles.append(BoardParticle(
                x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed, age: 0, life: spec.life * (0.6 + random.next() * 0.6),
                size: spec.size * (0.6 + random.next() * 0.8), color: spec.colors[index], gravity: spec.gravity,
                drag: spec.drag, streak: spec.streak
            ))
        }
    }

    /// Streak particles flying right along a row from `x0` to `x1` at `y` (fx.js `streak`).
    public mutating func streak(from x0: Double, to x1: Double, y: Double, color: BoardFXColor) {
        guard particlesAllowed else { return }
        let count = Int((26 * intensity.particleScale).rounded())
        for index in 0..<count where particles.count < Self.particleCapacity {
            let x = x0 + random.next() * (x1 - x0)
            particles.append(BoardParticle(
                x: x, y: y + (random.next() - 0.5) * 8, vx: 220 + random.next() * 260, vy: (random.next() - 0.5) * 30,
                age: 0, life: 0.35 + random.next() * 0.35, size: 1 + random.next() * 1.2,
                color: index % 3 == 0 ? .fxWhite : color, gravity: 0, drag: 2.5, streak: true
            ))
        }
    }

    /// An expanding ring from `(x, y)` up to `maxRadius` (default the board's diagonal).
    public mutating func shockwave(x: Double, y: Double, color: BoardFXColor, maxRadius: Double? = nil, life: Double = 0.9) {
        guard transientsAllowed, waves.count < Self.waveCapacity else { return }
        waves.append(BoardWave(x: x, y: y, maxRadius: maxRadius ?? hypot(side, side), age: 0, life: life, color: color))
    }

    /// A jagged bolt from one point to another with `branches` side branches (at most 3), flickering out over `life`.
    public mutating func lightning(from start: SIMD2<Double>, to end: SIMD2<Double>, color: BoardFXColor, branches: Int = 2,
                                   life: Double = 0.32) {
        guard transientsAllowed, let slot = bolts.firstIndex(where: { !$0.alive }) else { return }
        var bolt = BoardBolt(alive: true, age: 0, life: life, color: color, pathCount: 1)
        let base = slot * BoardBolt.maxPaths * BoardBolt.maxPoints
        let mainCount = makePath(from: start, to: end, at: base)
        bolt.lengths[0] = Int32(mainCount)
        for k in 0..<min(max(branches, 0), BoardBolt.maxPaths - 1) {
            let pick = 2 + Int(random.next() * Double(mainCount - 3))
            let from = boltPoints[base + min(pick, mainCount - 1)]
            let to = from + SIMD2((random.next() - 0.3) * 60, (random.next() - 0.2) * 50)
            bolt.lengths[k + 1] = Int32(makePath(from: from, to: to, at: base + (k + 1) * BoardBolt.maxPoints))
            bolt.pathCount += 1
        }
        bolts[slot] = bolt
    }

    /// fx.js `make`: 7–10 segments jittered across the line, most in the middle; returns the point count.
    private mutating func makePath(from a: SIMD2<Double>, to b: SIMD2<Double>, at offset: Int) -> Int {
        let segments = 7 + Int(random.next() * 4)
        let delta = b - a
        let length = max(hypot(delta.x, delta.y), 0.0001)
        let normal = SIMD2(-delta.y / length, delta.x / length)
        boltPoints[offset] = a
        for i in 1..<segments {
            let t = Double(i) / Double(segments)
            let jitter = (random.next() - 0.5) * length * 0.18 * (1 - abs(t - 0.5))
            boltPoints[offset + i] = a + delta * t + normal * jitter
        }
        boltPoints[offset + segments] = b
        return segments + 1
    }

    /// Path `path` of bolt `bolt` (points in board coordinates).
    public func boltPath(_ bolt: Int, _ path: Int) -> ArraySlice<SIMD2<Double>> {
        let start = (bolt * BoardBolt.maxPaths + path) * BoardBolt.maxPoints
        return boltPoints[start..<(start + Int(bolts[bolt].lengths[path]))]
    }

    mutating func nextRandom() -> Double { random.next() }

    mutating func flashBoard() { flash = 1 }

    /// The new-leader celebration at `(x, y)`: a gold and a white shockwave, about 70 gold sparks and 2.2 s of gold
    /// comets at 1.8× speed.
    public mutating func celebrate(x: Double, y: Double) {
        guard intensity != .off else { return }
        let reach = hypot(side, side)
        shockwave(x: x, y: y, color: .fxGold, maxRadius: reach * 1.1, life: 1.1)
        shockwave(x: x, y: y, color: .fxWhiteHot, maxRadius: reach * 0.6, life: 0.7)
        burst(x: x, y: y, BoardBurst(count: 70, speed: 260, life: 1.3,
                                     colors: BoardFXPalette(.fxGold, .fxGoldPale, .fxOrange, .fxWhite), size: 2.2, gravity: 160))
        gold = Self.celebrationSeconds
    }
}

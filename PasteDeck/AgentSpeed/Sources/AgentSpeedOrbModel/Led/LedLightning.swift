import Foundation

/// The box of one readout character: center and size in points, relative to the orb center, y down.
public struct LedDigitCell: Sendable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The flash over a digit that just changed; `radius` = 1.44 × cell width.
public struct LedZap: Sendable {
    public var x, y, radius, power, age, life: Double
}

/// One bolt: its ends, length and stroke width in points, its age and life and the time to the next re-shape in seconds.
public struct LedBolt: Sendable {
    public var x0, y0, x1, y1, length, width, age, life, regen: Double
    /// 1, or 2 when power > 0.9.
    public var forks: Int
}

/// Digit lightning (DESIGN 2.1; prototype zap / makeBolt / shapeBolt / jag). Paths live in one flat point buffer
/// reserved in `init`, one block of 33 + 2 × 17 points per bolt slot; nothing allocates afterwards. Use the path slices
/// before the next mutating call: a slice held across one forces a copy of the buffer.
public struct LedLightning: Sendable {
    public static let maxBolts = 16
    /// 5 levels of midpoint displacement.
    public static let mainPoints = 33
    /// 4 levels.
    public static let forkPoints = 17
    public static let cooldown = 0.11
    public static let reshape = 0.045
    /// Flashes alive at once; a change past this many still throws its bolts.
    public static let maxZaps = 48
    /// Character positions that can zap (and keep a cooldown); later ones are ignored.
    public static let positions = 16

    static let slot = mainPoints + 2 * forkPoints

    public private(set) var bolts: ContiguousArray<LedBolt>
    public private(set) var zaps: ContiguousArray<LedZap>
    public var random: LedRandom
    private var points: ContiguousArray<SIMD2<Double>>
    private var lastZap: ContiguousArray<Double>

    public init(seed: UInt64 = 0x5EED_0B07) {
        self.init(random: LedRandom(seed: seed))
    }

    public init(random: LedRandom) {
        self.random = random
        bolts = []
        bolts.reserveCapacity(Self.maxBolts)
        zaps = []
        zaps.reserveCapacity(Self.maxZaps)
        points = ContiguousArray(repeating: .zero, count: Self.maxBolts * Self.slot)
        lastZap = ContiguousArray(repeating: -.infinity, count: Self.positions)
    }

    public var isEmpty: Bool { bolts.isEmpty && zaps.isEmpty }

    public mutating func removeAll() {
        bolts.removeAll(keepingCapacity: true)
        zaps.removeAll(keepingCapacity: true)
        for i in lastZap.indices { lastZap[i] = -.infinity }
    }

    // MARK: Trigger

    /// The odometer changed `previous` → `current`; `cells[i]` is the cell of character i of `current` (same count).
    /// Applies: per changed digit (every digit when the length changed) the 0.11 s cooldown per position and the chance
    /// min(1, 0.3 + 0.3 s + 0.4 h) unless `force`; power (0.55 + 0.22 s)(0.6 + 0.6 h + 0.6 o) lvl; a zap; then
    /// effects.boltsPerDigit(1 + [h > 0.55] + [redline, 60 %]) bolts while fewer than effects.boltCap are alive. Nothing
    /// when `value < 0.5` or `effects.lightning` is off. Bolt ends per prototype makeBolt (redline 30 %: on the LED ring
    /// 0.39 S toward the start ±0.15 S jitter of the aim; else roll < 0.6 and the neighbor is a digit: the same edge of
    /// the neighbor; else a crackle of S (0.05 + 0.07 p) at ±90° ± 0.85 rad). `time` only needs to increase; a jump
    /// backwards (a wrapped clock) lifts the cooldowns.
    public mutating func trigger(previous: String, current: String, cells: ContiguousArray<LedDigitCell>, time: Double,
                                 heat h: Double, overdrive o: Double, redline: Bool, value: Double, effects: LedEffects,
                                 diameter s: Double, force: Bool = false) {
        guard effects.lightning, value >= 0.5 else { return }
        var cur = current.utf8.makeIterator()
        var prev = previous.utf8.makeIterator()
        var count = 0
        var previousCount = 0
        var digits: UInt64 = 0
        var changed: UInt64 = 0
        while let c = Self.nextLead(&cur) {
            let p = Self.nextLead(&prev)
            if p != nil { previousCount += 1 }
            if count < 64 {
                let bit: UInt64 = 1 << UInt64(count)
                if Self.isDigit(c) { digits |= bit }
                if p != c { changed |= bit }
            }
            count += 1
        }
        while Self.nextLead(&prev) != nil { previousCount += 1 }
        let sameLength = count == previousCount
        let cap = min(effects.boltCap, Self.maxBolts)

        for i in 0..<min(count, cells.count, Self.positions) {
            let bit: UInt64 = 1 << UInt64(i)
            guard digits & bit != 0, !sameLength || changed & bit != 0 else { continue }
            let significance = (digits >> UInt64(i + 1)).nonzeroBitCount
            if !force {
                let elapsed = time - lastZap[i]
                if elapsed >= 0 && elapsed < Self.cooldown { continue }
                if random.next() > Self.chance(significance: significance, heat: h) { continue }
            }
            lastZap[i] = time
            let p = Self.power(significance: significance, heat: h, overdrive: o, lvl: effects.lvl)
            let cell = cells[i]
            if zaps.count < Self.maxZaps {
                zaps.append(LedZap(x: cell.x, y: cell.y, radius: 1.44 * cell.width, power: p, age: 0,
                                   life: Self.zapLife(power: p)))
            }
            let roll = redline ? random.next() : 1
            let n = effects.boltsPerDigit(Self.boltCount(heat: h, redline: redline, roll: roll))
            for _ in 0..<n {
                guard bolts.count < cap else { break }
                makeBolt(cells: cells, index: i, power: p, redline: redline, digits: digits, diameter: s)
            }
        }
    }

    private mutating func makeBolt(cells: ContiguousArray<LedDigitCell>, index i: Int, power p: Double, redline: Bool,
                                   digits: UInt64, diameter s: Double) {
        let cell = cells[i]
        let gh = cell.height * 0.36
        let gw = cell.width * 0.42
        let side: Double = random.next() < 0.5 ? -1 : 1
        let x0 = cell.x + (random.next() - 0.5) * gw * 1.4
        let y0 = cell.y + side * gh
        let neighbor = i + (random.next() < 0.5 ? -1 : 1)
        let roll = random.next()
        let x1: Double
        let y1: Double
        if redline && roll < 0.3 {
            let a = atan2(y0, x0 + (random.next() - 0.5) * s * 0.3)
            x1 = cos(a) * 0.39 * s
            y1 = sin(a) * 0.39 * s
        } else if neighbor >= 0, neighbor < cells.count, neighbor < 64, digits & (1 << UInt64(neighbor)) != 0,
                  roll < 0.6 {
            let nb = cells[neighbor]
            x1 = nb.x + (random.next() - 0.5) * gw
            y1 = nb.y + side * gh * (0.6 + random.next() * 0.5)
        } else {
            let a = side * .pi / 2 + (random.next() - 0.5) * 1.7
            let l = s * (0.05 + 0.07 * p)
            x1 = x0 + cos(a) * l
            y1 = y0 + sin(a) * l
        }
        let life = Self.boltLife(power: p, roll: random.next())
        bolts.append(LedBolt(x0: x0, y0: y0, x1: x1, y1: y1, length: hypot(x1 - x0, y1 - y0),
                             width: Self.boltWidth(power: p, diameter: s), age: 0, life: life, regen: Self.reshape,
                             forks: p > 0.9 ? 2 : 1))
        shape(bolts.count - 1)
    }

    private mutating func shape(_ index: Int) {
        let b = bolts[index]
        let base = index * Self.slot
        Self.jag(from: SIMD2(b.x0, b.y0), to: SIMD2(b.x1, b.y1), roughness: 0.3, depth: 5, random: &random,
                 into: &points, at: base)
        let heading = atan2(b.y1 - b.y0, b.x1 - b.x0)
        for f in 0..<b.forks {
            let start = points[base + 3 + Int(random.next() * Double(Self.mainPoints - 8))]
            let a = heading + (random.next() - 0.5) * 1.9
            let l = b.length * (0.2 + random.next() * 0.3)
            Self.jag(from: start, to: start + SIMD2(cos(a), sin(a)) * l, roughness: 0.35, depth: 4, random: &random,
                     into: &points, at: base + Self.mainPoints + f * Self.forkPoints)
        }
    }

    // MARK: Step

    /// Ages zaps and bolts, re-shapes each bolt every 45 ms, drops finished ones. `dt` is clamped to 0...`LedMath.maxStep`.
    public mutating func step(dt: Double) {
        let dt = LedMath.clampedStep(dt)
        guard dt > 0 else { return }
        var i = 0
        while i < zaps.count {
            zaps[i].age += dt
            if zaps[i].age >= zaps[i].life {
                zaps.swapAt(i, zaps.count - 1)
                zaps.removeLast()
            } else {
                i += 1
            }
        }
        i = 0
        while i < bolts.count {
            bolts[i].age += dt
            if bolts[i].age >= bolts[i].life {
                removeBolt(at: i)
                continue
            }
            bolts[i].regen -= dt
            if bolts[i].regen <= 0 {
                shape(i)
                bolts[i].regen = Self.reshape
            }
            i += 1
        }
    }

    private mutating func removeBolt(at i: Int) {
        let last = bolts.count - 1
        if i != last {
            bolts[i] = bolts[last]
            let from = last * Self.slot
            let to = i * Self.slot
            for k in 0..<Self.slot { points[to + k] = points[from + k] }
        }
        bolts.removeLast()
    }

    // MARK: Paths

    /// The bolt's main path (33 points), a slice of the flat point buffer (no copy; indices start at `startIndex`, not
    /// 0); empty for a bad index.
    public func mainPath(_ index: Int) -> ArraySlice<SIMD2<Double>> {
        guard bolts.indices.contains(index) else { return points[0..<0] }
        let base = index * Self.slot
        return points[base..<(base + Self.mainPoints)]
    }

    /// Fork `fork` (17 points) of the bolt, a slice of the flat point buffer (no copy); empty past `forks`.
    public func forkPath(_ index: Int, _ fork: Int) -> ArraySlice<SIMD2<Double>> {
        guard bolts.indices.contains(index), fork >= 0, fork < bolts[index].forks else { return points[0..<0] }
        let base = index * Self.slot + Self.mainPoints + fork * Self.forkPoints
        return points[base..<(base + Self.forkPoints)]
    }

    // MARK: Numbers

    /// Alpha min(1, 1.6 (1 − age/life)) (the 22 % flicker to 40 % is drawn by the renderer with its own random).
    public static func boltAlpha(_ bolt: LedBolt) -> Double {
        guard bolt.life > 0 else { return 0 }
        return min(1, max(0, 1.6 * (1 - bolt.age / bolt.life)))
    }

    /// Flash peak min(0.8, 0.35 p), fading (1 − t/T)², T = 0.16 + 0.06 p.
    public static func zapAlpha(_ zap: LedZap) -> Double {
        guard zap.life > 0 else { return 0 }
        let k = min(1, max(0, 1 - zap.age / zap.life))
        return min(0.8, 0.35 * zap.power) * k * k
    }

    /// min(1, 0.3 + 0.3 s + 0.4 h), `s` = the digits to the right of the changed one.
    public static func chance(significance s: Int, heat h: Double) -> Double {
        min(1, 0.3 + 0.3 * Double(s) + 0.4 * h)
    }

    /// (0.55 + 0.22 s)(0.6 + 0.6 h + 0.6 o) lvl
    public static func power(significance s: Int, heat h: Double, overdrive o: Double, lvl: Double) -> Double {
        (0.55 + 0.22 * Double(s)) * (0.6 + 0.6 * h + 0.6 * o) * lvl
    }

    /// Bolts per digit before LOD: 1 + [h > 0.55] + [redline and roll < 0.6].
    public static func boltCount(heat h: Double, redline: Bool, roll: Double) -> Int {
        1 + (h > 0.55 ? 1 : 0) + (redline && roll < 0.6 ? 1 : 0)
    }

    /// 0.0032 S (0.7 + 0.5 p)
    public static func boltWidth(power p: Double, diameter s: Double) -> Double { 0.0032 * s * (0.7 + 0.5 * p) }

    /// 0.14 + 0.1 roll + 0.05 p seconds.
    public static func boltLife(power p: Double, roll: Double) -> Double { 0.14 + 0.1 * roll + 0.05 * p }

    /// 0.16 + 0.06 p seconds.
    public static func zapLife(power p: Double) -> Double { 0.16 + 0.06 * p }

    /// Midpoint displacement (prototype `jag`): writes 2^depth + 1 points from `from` to `to` (both exact) at `offset`;
    /// each level displaces the new midpoints along their segment's normal by (rand − 0.5) · disp, disp starting at
    /// length · roughness and × 0.55 per level. Does nothing when the buffer is too short.
    public static func jag(from: SIMD2<Double>, to: SIMD2<Double>, roughness: Double, depth: Int,
                           random: inout LedRandom, into buffer: inout ContiguousArray<SIMD2<Double>>, at offset: Int) {
        let depth = min(max(depth, 0), 20)
        let n = (1 << depth) + 1
        guard offset >= 0, offset + n <= buffer.count else { return }
        let end = offset + n - 1
        buffer[offset] = from
        buffer[end] = to
        var disp = hypot(to.x - from.x, to.y - from.y) * roughness
        var step = n - 1
        while step > 1 {
            let half = step / 2
            var j = offset
            while j < end {
                let a = buffer[j]
                let b = buffer[j + step]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let measured = hypot(dx, dy)
                let len = measured > 0 ? measured : 1
                let off = (random.next() - 0.5) * disp
                buffer[j + half] = SIMD2((a.x + b.x) / 2 - dy / len * off, (a.y + b.y) / 2 + dx / len * off)
                j += step
            }
            disp *= 0.55
            step = half
        }
    }

    // MARK: Text

    private static func nextLead(_ it: inout String.UTF8View.Iterator) -> UInt8? {
        while let b = it.next() {
            if b & 0xC0 != 0x80 { return b }
        }
        return nil
    }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
}

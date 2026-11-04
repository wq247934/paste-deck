import Foundation

/// How often an orb wants frames (DESIGN 2a, Frame policy). `none` means static: the last frame stays on screen.
public enum OrbFrameClass: Int, Comparable, Sendable, CaseIterable {
    case none = 0
    case fps15
    case fps30
    case fps60

    public static func < (lhs: OrbFrameClass, rhs: OrbFrameClass) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The nominal rate the class aims for on a display.
    public var nominalRate: Double {
        switch self {
        case .none: 0
        case .fps15: 15
        case .fps30: 30
        case .fps60: 60
        }
    }

    public var demoted: OrbFrameClass { self == .fps60 ? .fps30 : self }
}

/// Pure frame-rate arithmetic shared by every orb and preview surface.
public enum OrbFramePolicy {
    /// The display refresh rate itself is never used above this.
    public static let maximumRate = 72.0
    /// From this many orbs in the 60 fps class at once, all but the focused one drop to 30 fps.
    public static let crowdLimit = 4

    /// The integer divisor of `refresh` whose rate is closest to `target` (ties to the higher rate), never above
    /// `maximumRate`: 144 Hz → 2 (72) for 60, 5 (28.8) for 30, 10 (14.4) for 15; 120 Hz → 2, 4, 8; 60 Hz → 1, 2, 4.
    public static func divisor(refresh: Double, target: Double) -> Int {
        guard refresh.isFinite, refresh > 0, target > 0 else { return 1 }
        var best = 1
        var bestDistance = Double.infinity
        let limit = max(1, Int((refresh / 1).rounded(.up)))
        for k in 1...limit {
            let rate = refresh / Double(k)
            guard rate <= maximumRate + 1e-9 else { continue }
            let distance = abs(rate - target)
            if distance < bestDistance - 1e-9 {
                best = k
                bestDistance = distance
            }
            if rate < target { break }
        }
        return best
    }

    /// The smallest divisor whose rate does not exceed `cap` (previews: "≤ 24 fps", "≤ 15 fps").
    public static func divisor(refresh: Double, atMost cap: Double) -> Int {
        guard refresh.isFinite, refresh > 0, cap > 0 else { return 1 }
        let ceiling = min(cap, maximumRate)
        return max(1, Int((refresh / ceiling - 1e-9).rounded(.up)))
    }

    public static func divisor(refresh: Double, for frameClass: OrbFrameClass) -> Int? {
        frameClass == .none ? nil : divisor(refresh: refresh, target: frameClass.nominalRate)
    }

    /// Applies the crowd rule: with `crowdLimit` or more requests at 60 fps, every one of them except `focused`
    /// (the hovered or most recently interacted orb) is demoted to 30 fps.
    public static func effective(_ requested: [OrbFrameClass], focused: Int?) -> [OrbFrameClass] {
        let crowded = requested.filter { $0 == .fps60 }.count >= crowdLimit
        guard crowded else { return requested }
        return requested.enumerated().map { index, frameClass in index == focused ? frameClass : frameClass.demoted }
    }

    /// Greatest common divisor of the active divisors, so a shared display link can run at `refresh / gcd`.
    public static func linkDivisor(_ divisors: [Int]) -> Int {
        divisors.reduce(0) { gcd($0, $1) }
    }

    /// Whether a client with `divisor` renders on the display tick `index` (counted at the refresh rate).
    public static func renders(onTick index: Int64, divisor: Int) -> Bool {
        divisor <= 1 || index % Int64(divisor) == 0
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
}

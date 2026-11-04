import Foundation

/// A ladder of speed steps entered at thresholds that scale with the redline (DESIGN section 1). The first active
/// step starts at an absolute speed; below it, after a delay, the ladder rests at `idle`.
protocol SpeedLadder: CaseIterable, Comparable, Sendable where AllCases == [Self] {
    static var idle: Self { get }
    /// The lowest active step, entered at `SpeedTier.cruiseSpeed`.
    static var firstActive: Self { get }
    /// Speed (tok/s) at which the step is entered.
    func enterSpeed(redline: Double) -> Double
    var next: Self? { get }
    var previous: Self? { get }
}

extension SpeedLadder {
    /// The step for a value without hysteresis (first snapshot, previews).
    static func step(for value: Double, redline: Double) -> Self {
        guard value >= SpeedTier.cruiseSpeed else { return idle }
        return allCases.last { $0 != idle && value >= $0.enterSpeed(redline: redline) } ?? firstActive
    }
}

/// Effect tiers: they drive sparks, embers, shimmer and the tick dots; they are not shown as text.
enum SpeedTier: Int, SpeedLadder {
    case idle, cruise, boost, overdrive, redline

    static var firstActive: SpeedTier { .cruise }

    /// Entry threshold as a fraction of the redline speed (cruise uses an absolute 0.5 tok/s).
    var threshold: Double {
        switch self {
        case .idle: 0
        case .cruise: 0
        case .boost: 0.15
        case .overdrive: 0.375
        case .redline: 0.75
        }
    }

    func enterSpeed(redline: Double) -> Double {
        self == .cruise ? SpeedTier.cruiseSpeed : threshold * redline
    }

    var titleKey: String {
        switch self {
        case .idle: "tier.idle"
        case .cruise: "tier.cruise"
        case .boost: "tier.boost"
        case .overdrive: "tier.overdrive"
        case .redline: "tier.redline"
        }
    }

    var next: SpeedTier? { SpeedTier(rawValue: rawValue + 1) }
    var previous: SpeedTier? { SpeedTier(rawValue: rawValue - 1) }

    static let cruiseSpeed = 0.5

    static func < (lhs: SpeedTier, rhs: SpeedTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

typealias TierTracker = LadderTracker<SpeedTier>

/// Step selection with hysteresis (enter at the threshold, leave at 90 %), a 3 s idle delay and a 0.8 s hold.
struct LadderTracker<Step: SpeedLadder> {
    static var holdDuration: TimeInterval { 0.8 }
    static var idleDelay: TimeInterval { 3 }
    static var exitRatio: Double { 0.9 }

    private(set) var shown: Step = .idle
    private var candidate: Step = .idle
    private var candidateSince: TimeInterval = 0
    private var belowActiveSince: TimeInterval?

    /// Feeds a raw value; returns true when the shown step changed.
    mutating func update(value: Double, redline: Double, now: TimeInterval) -> Bool {
        let next = rawStep(value: value, redline: redline, now: now)
        if next != candidate {
            candidate = next
            candidateSince = now
        }
        guard candidate != shown, now - candidateSince >= Self.holdDuration else { return false }
        shown = candidate
        return true
    }

    /// Next moment a re-evaluation could change the shown step without new data.
    func nextDecisionTime(after now: TimeInterval) -> TimeInterval? {
        var times: [TimeInterval] = []
        if candidate != shown { times.append(candidateSince + Self.holdDuration) }
        if let since = belowActiveSince, candidate != .idle { times.append(since + Self.idleDelay) }
        return times.filter { $0 > now }.min()
    }

    mutating func reset(to step: Step = .idle) {
        shown = step
        candidate = step
        belowActiveSince = nil
    }

    private mutating func rawStep(value: Double, redline: Double, now: TimeInterval) -> Step {
        if value < SpeedTier.cruiseSpeed {
            if belowActiveSince == nil { belowActiveSince = now }
        } else {
            belowActiveSince = nil
        }
        if let since = belowActiveSince, now - since >= Self.idleDelay { return .idle }

        var step = candidate == .idle ? (value >= SpeedTier.cruiseSpeed ? Step.firstActive : .idle) : candidate
        guard step != .idle else { return .idle }
        while let up = step.next, value >= up.enterSpeed(redline: redline) { step = up }
        while step > Step.firstActive, value < step.enterSpeed(redline: redline) * Self.exitRatio, let down = step.previous {
            step = down
        }
        return step
    }
}

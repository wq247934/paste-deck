import AgentSpeedCore
import Foundation
import Observation

/// The live speed reduced to what every surface draws: smoothed heat, overdrive and value, the effect tier and the
/// speed title shown as the label.
@MainActor
@Observable
public final class LiveGauge {
    private(set) var tier: SpeedTier = .idle
    private(set) var previousTier: SpeedTier = .idle
    /// The visible label (DESIGN section 1, "Speed titles"); changes independently of the effect tier.
    public private(set) var title: SpeedTitle = .idle
    private(set) var previousTitle: SpeedTitle = .idle
    /// Value shown in text readouts, refreshed at most 4 times per second.
    private(set) var readoutValue: Double = 0
    /// Bumps on every ingest so paused renderers redraw.
    private(set) var revision = 0

    @ObservationIgnored private(set) var tierChangedAt: TimeInterval = -.infinity
    @ObservationIgnored private(set) var titleChangedAt: TimeInterval = -.infinity
    @ObservationIgnored private(set) var rawValue: Double = 0
    @ObservationIgnored private(set) var lastActiveAt: TimeInterval = -.infinity
    @ObservationIgnored private var heatSpring = SpringValue()
    @ObservationIgnored private var overdriveSpring = SpringValue()
    @ObservationIgnored private var valueSpring = SpringValue(omega: 9)
    @ObservationIgnored private var tracker = TierTracker()
    @ObservationIgnored private var titleTracker = TitleTracker()
    @ObservationIgnored private var readoutUpdatedAt: TimeInterval = -.infinity
    @ObservationIgnored private var pendingReadout: Timer?
    @ObservationIgnored private var decisionTimer: Timer?

    @ObservationIgnored var redline: Double = 400 {
        didSet { if redline != oldValue { ingest(rawValue, now: Clock.now) } }
    }

    static let readoutInterval: TimeInterval = 0.25

    init() {}

    func ingest(_ value: Double, now: TimeInterval) {
        let value = value.isFinite ? max(0, value) : 0
        rawValue = value
        if value >= SpeedTier.cruiseSpeed { lastActiveAt = now }
        heatSpring.retarget(HeatPalette.heat(value: value, redline: redline), at: now)
        overdriveSpring.retarget(HeatPalette.overdrive(value: value, redline: redline), at: now)
        valueSpring.retarget(value, at: now)
        evaluateTier(now: now)
        scheduleReadout(now: now)
        revision &+= 1
    }

    /// Jumps straight to a value without animation (previews, first snapshot).
    func snap(to value: Double, tier: SpeedTier? = nil, title: SpeedTitle? = nil, now: TimeInterval) {
        rawValue = value
        heatSpring.snap(to: HeatPalette.heat(value: value, redline: redline), at: now)
        overdriveSpring.snap(to: HeatPalette.overdrive(value: value, redline: redline), at: now)
        valueSpring.snap(to: value, at: now)
        let resolved = tier ?? Self.tier(for: value, redline: redline)
        tracker.reset(to: resolved)
        previousTier = resolved
        self.tier = resolved
        tierChangedAt = -.infinity
        let resolvedTitle = title ?? SpeedTitle.step(for: value, redline: redline)
        titleTracker.reset(to: resolvedTitle)
        previousTitle = resolvedTitle
        self.title = resolvedTitle
        titleChangedAt = -.infinity
        readoutValue = value
        if value >= SpeedTier.cruiseSpeed { lastActiveAt = now }
        revision &+= 1
    }

    /// Shows `title` at once with its real transition, the springs easing to `value` (Settings previews, which step
    /// through the levels as the focus moves instead of waiting for the hold).
    func show(_ title: SpeedTitle, value: Double, now: TimeInterval) {
        rawValue = value
        if value >= SpeedTier.cruiseSpeed { lastActiveAt = now }
        heatSpring.retarget(HeatPalette.heat(value: value, redline: redline), at: now)
        overdriveSpring.retarget(HeatPalette.overdrive(value: value, redline: redline), at: now)
        valueSpring.retarget(value, at: now)
        let tier = title == .idle ? SpeedTier.idle : Self.tier(for: value, redline: redline)
        tracker.reset(to: tier)
        if tier != self.tier {
            previousTier = self.tier
            self.tier = tier
            tierChangedAt = now
        }
        titleTracker.reset(to: title)
        if title != self.title {
            previousTitle = self.title
            self.title = title
            titleChangedAt = now
        }
        readoutValue = value
        revision &+= 1
    }

    func heat(at time: TimeInterval) -> Double { heatSpring.value(at: time).clamped(to: 0...1) }
    func overdrive(at time: TimeInterval) -> Double { overdriveSpring.value(at: time).clamped(to: 0...1) }
    func smoothedValue(at time: TimeInterval) -> Double { max(0, valueSpring.value(at: time)) }
    var targetHeat: Double { heatSpring.target }

    func isSettled(at time: TimeInterval) -> Bool {
        heatSpring.isSettled(at: time) && overdriveSpring.isSettled(at: time)
    }

    /// Seconds since the speed last reached the cruise threshold.
    func idleDuration(at time: TimeInterval) -> TimeInterval { time - lastActiveAt }

    static func tier(for value: Double, redline: Double) -> SpeedTier {
        SpeedTier.step(for: value, redline: redline)
    }

    private func evaluateTier(now: TimeInterval) {
        if tracker.update(value: rawValue, redline: redline, now: now) {
            previousTier = tier
            tier = tracker.shown
            tierChangedAt = now
        }
        if titleTracker.update(value: rawValue, redline: redline, now: now) {
            previousTitle = title
            title = titleTracker.shown
            titleChangedAt = now
        }
        decisionTimer?.invalidate()
        decisionTimer = nil
        let decisions = [tracker.nextDecisionTime(after: now), titleTracker.nextDecisionTime(after: now)].compactMap { $0 }
        guard let next = decisions.min() else { return }
        let timer = Timer(timeInterval: max(0.02, next - now + 0.01), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluateTier(now: Clock.now)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        decisionTimer = timer
    }

    private func scheduleReadout(now: TimeInterval) {
        let elapsed = now - readoutUpdatedAt
        if elapsed >= Self.readoutInterval {
            pendingReadout?.invalidate()
            pendingReadout = nil
            publishReadout(now: now)
            return
        }
        guard pendingReadout == nil else { return }
        let timer = Timer(timeInterval: Self.readoutInterval - elapsed, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingReadout = nil
                self.publishReadout(now: Clock.now)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingReadout = timer
    }

    private func publishReadout(now: TimeInterval) {
        readoutUpdatedAt = now
        if readoutValue != rawValue { readoutValue = rawValue }
    }
}

import AgentSpeedCore
import AgentSpeedHero
import AgentSpeedOrbModel
import Observation
import SwiftUI

/// Where an orb is shown: floating on the desktop, embedded in the dashboard (capped at Soft, opaque body, the hero
/// vehicle instead of the readout), or a Settings thumbnail / style card (capped at Soft).
enum OrbSurface: Sendable {
    case floating
    case embedded
    case preview
}

/// Per-orb animation state: frame demand, live events, the shared envelopes and the style renderers.
///
/// An orb draws only while something moves and not at all otherwise (or while hidden), so a quiet orb costs no CPU
/// (DESIGN 2a, Frame policy). Springs and trackers live in the orb's gauge, so a style change never makes the value
/// jump; the outgoing and incoming styles crossfade for 0.25 s.
@MainActor
@Observable
final class OrbAnimator {
    /// Scheduling of the dashboard's embedded `MTKView`.
    enum FrameMode: Equatable {
        case paused
        case active
        /// A slow ambient rate (frames per second).
        case ambient(Int)
    }

    struct Pulse {
        var start: TimeInterval
        var strength: Double
        var heat: Double
    }

    /// Debug, harness and preview overrides.
    struct Overrides {
        var level: EffectsLevel?
        var reduceMotion: Bool?
    }

    #if DEBUG
    /// `AGENT_SPEED_NO_HERO=1` (debug builds): the dashboard orb without its vehicle, for measurements.
    private static let disablesHero = ProcessInfo.processInfo.environment["AGENT_SPEED_NO_HERO"] == "1"
    #else
    private static let disablesHero = false
    #endif

    static let pulseDuration: TimeInterval = 0.7
    static let peakDuration: TimeInterval = 1.8
    /// The global sign-of-life cycle of idle orbs (DESIGN 2a, Shared foundation).
    static let signOfLifePeriod: TimeInterval = 6
    /// The dashboard's Core Animation idle sweep (DESIGN 4c resolved detail 10).
    static let sweepPeriod: TimeInterval = 6
    static let sweepDuration: TimeInterval = 2.2
    static let styleCrossfade: TimeInterval = 0.25

    private(set) var frameMode: FrameMode = .active
    /// What a floating orb or preview asks of the shared frame clock.
    private(set) var frameClass: OrbFrameClass = .fps30
    /// Bumps on every celebrated new peak.
    private(set) var peakCount = 0

    @ObservationIgnored let surface: OrbSurface
    @ObservationIgnored var overrides = Overrides()
    @ObservationIgnored private(set) var renderer: OrbStyleRenderer
    @ObservationIgnored private(set) var outgoing: OrbStyleRenderer?
    @ObservationIgnored private(set) var styleChangedAt: TimeInterval = -.infinity
    @ObservationIgnored private var renderers: [OrbStyleKind: OrbStyleRenderer] = [:]
    @ObservationIgnored private(set) var pulses = ContiguousArray<Pulse>()
    @ObservationIgnored private(set) var peakStart: TimeInterval = -.infinity
    @ObservationIgnored private(set) var breathPhase = 0.0
    @ObservationIgnored private(set) var flare = OrbEnvelope()
    @ObservationIgnored private(set) var redline = OrbEnvelope()
    @ObservationIgnored private(set) var hover = OrbEnvelope()
    @ObservationIgnored private(set) var activity = OrbEnvelope()
    @ObservationIgnored private(set) var valueGlow = OrbEnvelope()
    @ObservationIgnored private(set) var skew = OrbEnvelope()
    @ObservationIgnored let readout = OrbReadoutBuilder()
    @ObservationIgnored let lines = OrbLineReadout()
    /// The hero vehicle of the embedded (dashboard) orb, DESIGN 4c.
    @ObservationIgnored let hero: HeroVehicleDriver?
    /// The hero title badge that replaces the vehicle for every title theme except Vehicles (DESIGN 4c).
    @ObservationIgnored let badge: HeroBadge?
    @ObservationIgnored var heroArt = HeroArtState()
    @ObservationIgnored private var cachedGeometry: OrbGeometry?

    @ObservationIgnored private weak var model: AgentSpeedModel?
    @ObservationIgnored private(set) weak var feed: OrbFeed?
    @ObservationIgnored private weak var interaction: OrbInteraction?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var loop: ObservationLoop?
    @ObservationIgnored private var wakeTimer: Timer?
    @ObservationIgnored private var wakeAt: TimeInterval = .infinity
    @ObservationIgnored private(set) var lastStep: TimeInterval?
    @ObservationIgnored private var hoverChangedAt: TimeInterval = -.infinity
    @ObservationIgnored private var createdAt = Clock.now
    @ObservationIgnored private var envelopeTargets = EnvelopeTargets()
    /// Set while the orb could not be seen; the next frame shows the current state without catching up.
    @ObservationIgnored private var pendingResume = false
    /// True during the first frame after the orb was hidden, occluded or on another Space (DESIGN 2a, Frame policy:
    /// "never a catch-up animation"): springs, envelopes and particles jump to the current state.
    @ObservationIgnored private(set) var isResuming = false

    private struct EnvelopeTargets: Equatable {
        var redline = 0.0
        var hover = 0.0
        var activity = 0.0
        var glow = 0.0
        var skew = 0.0
    }

    init(surface: OrbSurface, style: OrbStyleKind = .led) {
        self.surface = surface
        let renderer = OrbStyles.make(style)
        self.renderer = renderer
        renderers[style] = renderer
        pulses.reserveCapacity(8)
        hero = surface == .embedded && !Self.disablesHero ? HeroVehicleDriver() : nil
        badge = hero == nil ? nil : HeroBadge()
    }

    var isAttached: Bool { model != nil }
    var style: OrbStyleKind { renderer.kind }

    /// Whether the pointer is over the floating orb's disc.
    var hoverTarget: Bool { surface == .floating && (interaction?.isHovered ?? false) }

    // MARK: Lifecycle

    func attach(model: AgentSpeedModel, feed: OrbFeed, interaction: OrbInteraction?) {
        guard self.model == nil else { return }
        self.model = model
        self.feed = feed
        self.interaction = interaction
        follow(feed, model: model)
        let value = feed.gauge.readoutValue
        readout.reset(text: SpeedFormat.speed(value), value: value)
        prime(tier: feed.gauge.tier, effects: effects(for: model))
        listener = feed.addListener { [weak self] event in
            self?.handle(event)
        }
        var lastHover = interaction?.isHovered ?? false
        loop = ObservationLoop { [weak self] in
            guard let self, let model = self.model, let feed = self.feed else { return }
            let gauge = feed.gauge
            _ = (gauge.revision, gauge.tier, gauge.title, gauge.readoutValue, model.settings.effects, model.accessibility.reduceMotion)
            _ = model.titles.document
            _ = (feed.generating, feed.unavailableTitleKey, feed.bezel)
            let hovered = self.interaction?.isHovered ?? false
            if hovered != lastHover {
                lastHover = hovered
                self.hoverChangedAt = Clock.now
            }
            if self.interaction?.isVisibleOnScreen == false { self.pendingResume = true }
            self.reevaluate()
        }
    }

    /// The hero vehicle follows `feed`'s gauge when it is not the app's all-sources feed (Settings previews).
    func follow(_ feed: OrbFeed, model: AgentSpeedModel) {
        if feed !== model.mainFeed { hero?.gauge = feed.gauge }
    }

    func detach() {
        if let listener { feed?.removeListener(listener) }
        listener = nil
        loop?.cancel()
        loop = nil
        wakeTimer?.invalidate()
        wakeTimer = nil
        model = nil
        feed = nil
        interaction = nil
    }

    // MARK: Style

    /// Switches the instrument; the old one fades out over 0.25 s (cut with Reduce Motion).
    func setStyle(_ kind: OrbStyleKind, at time: TimeInterval = Clock.now) {
        guard kind != renderer.kind else { return }
        let next = renderers[kind] ?? OrbStyles.make(kind)
        renderers[kind] = next
        let reduceMotion = model.map { effects(for: $0).reduceMotion } ?? false
        outgoing = reduceMotion ? nil : renderer
        renderer = next
        styleChangedAt = reduceMotion ? -.infinity : time
        reevaluate()
    }

    /// Crossfade progress of the incoming style (1 when done).
    func styleMix(at time: TimeInterval) -> Double {
        guard outgoing != nil else { return 1 }
        return ((time - styleChangedAt) / Self.styleCrossfade).clamped(to: 0...1)
    }

    func finishCrossfadeIfDone(at time: TimeInterval) {
        if outgoing != nil, styleMix(at: time) >= 1 { outgoing = nil }
    }

    // MARK: Events

    func effects(for model: AgentSpeedModel) -> OrbEffects {
        let reduceMotion = overrides.reduceMotion ?? model.accessibility.reduceMotion
        return OrbEffects(level: overrides.level ?? model.settings.effects, reduceMotion: reduceMotion, surface: surface)
    }

    private func handle(_ event: OrbFeedEvent) {
        guard let model, let feed else { return }
        let now = Clock.now
        let effects = self.effects(for: model)
        switch event {
        case .response(let output, let speed):
            guard model.settings.responsePulses, effects.pulses else { return }
            let strength = (log10(max(1, Double(output))) / 3.4).clamped(to: 0.3...1)
            let speed = speed ?? feed.gauge.smoothedValue(at: now)
            let heat = HeatPalette.heat(value: speed, redline: feed.redlineOutput)
            addPulse(at: now, strength: strength, heat: max(heat, 0.08))
        case .newPeak:
            guard model.settings.celebratePeaks, effects.celebrate else { return }
            celebrate(at: now)
        }
        reevaluate()
    }

    /// Coalesces pulses to at most one every 150 ms.
    func addPulse(at time: TimeInterval, strength: Double, heat: Double) {
        if let last = pulses.indices.last, time - pulses[last].start < 0.15 {
            pulses[last].strength = max(pulses[last].strength, strength)
            pulses[last].heat = max(pulses[last].heat, heat)
            return
        }
        if pulses.count >= 6 { pulses.removeFirst() }
        pulses.append(Pulse(start: time, strength: strength, heat: heat))
        flare.step(toward: max(flare.value, strength), dt: 1, timeConstant: 0)
        renderer.pulse(at: time, strength: strength, heat: heat)
    }

    func celebrate(at time: TimeInterval) {
        peakStart = time
        peakCount &+= 1
        renderer.celebrate(at: time)
    }

    // MARK: Simulation

    struct StepInput {
        var heat: Double
        var overdrive: Double
        var tier: SpeedTier
        var effects: OrbEffects
        var dark: Bool
        var hovered: Bool
        var unavailable = false
    }

    /// Advances the shared envelopes to `time`; returns the step. Called once per rendered frame.
    @discardableResult
    func stepShared(to time: TimeInterval, input: StepInput) -> Double {
        let resuming = pendingResume && interaction?.isVisibleOnScreen != false
        if resuming { pendingResume = false }
        isResuming = resuming
        let dt = resuming ? 1.0 / 60 : (time - (lastStep ?? time)).clamped(to: 0...(1.0 / 15))
        lastStep = time
        guard dt > 0 else { return 0 }
        let h = input.unavailable ? 0 : input.heat
        let effects = input.effects
        if effects.breathing { breathPhase = (breathPhase + Self.lerp(0.25, 1 / 0.7, h) * dt).truncatingRemainder(dividingBy: 1) }
        let active = input.tier != .idle && !input.unavailable
        let targets = EnvelopeTargets(
            redline: input.tier == .redline && active ? 1 : 0,
            hover: input.hovered ? 1 : 0,
            activity: active ? 1 : 0,
            glow: input.tier >= .boost && active ? 1 : 0,
            skew: input.tier >= .overdrive && effects.skew && active ? 1 : 0
        )
        envelopeTargets = targets
        if resuming {
            redline = OrbEnvelope(targets.redline)
            hover = OrbEnvelope(targets.hover)
            activity = OrbEnvelope(targets.activity)
            valueGlow = OrbEnvelope(targets.glow)
            skew = OrbEnvelope(targets.skew)
            flare = OrbEnvelope()
            pulses.removeAll(keepingCapacity: true)
            peakStart = -.infinity
            return dt
        }
        redline.step(toward: targets.redline, dt: dt, timeConstant: 0.2)
        hover.step(toward: targets.hover, dt: dt, timeConstant: effects.reduceMotion ? 0.06 : 0.09)
        flare.step(toward: 0, dt: dt, timeConstant: 0.28)
        activity.step(toward: targets.activity, dt: dt, timeConstant: 0.18)
        valueGlow.step(toward: targets.glow, dt: dt, timeConstant: 0.22)
        skew.step(toward: targets.skew, dt: dt, timeConstant: 0.3)
        while let first = pulses.first, time - first.start > Self.pulseDuration { pulses.removeFirst() }
        return dt
    }

    func geometry(diameter: CGFloat, side: CGFloat) -> OrbGeometry {
        if let cachedGeometry, cachedGeometry.diameter == diameter, cachedGeometry.center.x == side / 2 {
            return cachedGeometry
        }
        let geometry = OrbGeometry(diameter: diameter, canvasSide: side)
        cachedGeometry = geometry
        return geometry
    }

    /// Prepares an unattached animator to draw a still frame of the current state.
    func primeForStill(model: AgentSpeedModel, gauge: LiveGauge) {
        hero?.reset()
        let value = gauge.readoutValue
        readout.reset(text: SpeedFormat.speed(value), value: value)
        prime(tier: gauge.tier, effects: effects(for: model))
    }

    /// Starts the envelopes at their resting values so a freshly shown orb doesn't fade in its glow.
    private func prime(tier: SpeedTier, effects: OrbEffects) {
        activity = OrbEnvelope(tier == .idle ? 0 : 1)
        valueGlow = OrbEnvelope(tier >= .boost ? 1 : 0)
        skew = OrbEnvelope(tier >= .overdrive && effects.skew ? 1 : 0)
        redline = OrbEnvelope(tier == .redline ? 1 : 0)
    }

    /// `led`: gauge sweep progress after a new peak (0 → 1 over 0.5 s), or 1 when none.
    func peakSweep(at time: TimeInterval) -> Double {
        let t = time - peakStart
        guard t >= 0, t < 0.5 else { return 1 }
        return Easing.easeOut(t / 0.5)
    }

    /// When the dashboard's idle sweep cycle starts: a few seconds after the orb settled into idle.
    func idleEpoch(for gauge: LiveGauge) -> TimeInterval {
        let since = gauge.tierChangedAt.isFinite ? gauge.tierChangedAt : createdAt
        return since + 2.5
    }

    /// Progress of the idle sign of life at `time` on the global clock (every 6 s, skipping a cycle that would start
    /// less than 2 s after entering idle), or nil.
    func signOfLife(at time: TimeInterval, gauge: LiveGauge, effects: OrbEffects, unavailable: Bool) -> Double? {
        let duration = renderer.signOfLifeDuration
        guard surface != .embedded, duration > 0, gauge.tier == .idle, !unavailable, effects.idleSweep else { return nil }
        let cycleStart = (time / Self.signOfLifePeriod).rounded(.down) * Self.signOfLifePeriod
        let idleSince = gauge.tierChangedAt.isFinite ? gauge.tierChangedAt : -.infinity
        guard cycleStart >= idleSince + 2 else { return nil }
        let u = (time - cycleStart) / duration
        return u >= 0 && u <= 1 ? u : nil
    }

    // MARK: Scheduling

    /// Re-evaluates the frame demand now (after a rendered frame or a change).
    func reevaluate() {
        guard let model, let feed else { return }
        let now = Clock.now
        if surface == .embedded {
            let mode = desiredMode(model: model, feed: feed, at: now)
            if frameMode != mode { frameMode = mode }
            scheduleWake(mode == .paused ? .infinity : now + 0.25)
            return
        }
        let (frameClass, wake) = desiredClass(model: model, feed: feed, at: now)
        if self.frameClass != frameClass { self.frameClass = frameClass }
        // While frames run, every frame re-evaluates; a timer is only needed to wake a static orb.
        scheduleWake(frameClass == .none ? wake : .infinity)
    }

    private func scheduleWake(_ time: TimeInterval) {
        // A pending wake that comes first (or nearly with it) already covers this one: it re-evaluates and re-arms, so
        // rendered frames don't replace the timer every time.
        if wakeTimer != nil, wakeAt <= time + 0.05 { return }
        guard time != wakeAt else { return }
        wakeAt = time
        wakeTimer?.invalidate()
        wakeTimer = nil
        guard time.isFinite else { return }
        let timer = Timer(timeInterval: max(0.01, time - Clock.now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wakeAt = .infinity
                self.wakeTimer = nil
                self.reevaluate()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        wakeTimer = timer
    }

    /// Frame class of a floating orb or preview and when to look again without new data (DESIGN 2a, Frame policy).
    private func desiredClass(model: AgentSpeedModel, feed: OrbFeed, at now: TimeInterval) -> (OrbFrameClass, TimeInterval) {
        if let interaction, !interaction.isVisibleOnScreen { return (.none, .infinity) }
        let gauge = feed.gauge
        let effects = self.effects(for: model)
        let unavailable = feed.unavailableTitleKey != nil
        let minimal = renderer.kind == .minimal
        let transitionClass: OrbFrameClass = minimal ? .fps30 : .fps60
        if inTransition(gauge: gauge, at: now) { return (transitionClass, now + 0.1) }

        let springs = !gauge.isSettled(at: now) || !envelopesSettled || inMotion(at: now)
        let lines = lineDemand(feed: feed, reduceMotion: effects.reduceMotion, at: now)
        if effects.level == .off || effects.reduceMotion {
            guard !springs, !renderer.isBusy(frameFor(now)), !lines.frames else { return (.fps30, now + 0.1) }
            return (.none, min(lines.wake, nextSignOfLife(after: now, gauge: gauge, effects: effects, unavailable: unavailable)))
        }
        let frame = frameFor(now)
        var frameClass = unavailable ? .none : renderer.ambientFrameClass(frame)
        if springs || renderer.isBusy(frame) || lines.frames { frameClass = max(frameClass, .fps30) }
        if signOfLife(at: now, gauge: gauge, effects: effects, unavailable: unavailable) != nil { frameClass = max(frameClass, .fps30) }
        guard frameClass == .none else { return (frameClass, now + 0.25) }
        return (.none, min(lines.wake, nextSignOfLife(after: now, gauge: gauge, effects: effects, unavailable: unavailable)))
    }

    /// The two-line readout's fades and the thinking line's glide draw at 30 fps (a Reduce Motion change still gets its
    /// frame); a static orb wakes when the quiet fade or the end of the thinking hold is due (DESIGN 10, Frame policy).
    /// New numbers render one frame through the content refresh.
    private func lineDemand(feed: OrbFeed, reduceMotion: Bool, at now: TimeInterval) -> (frames: Bool, wake: TimeInterval) {
        feed.lines?.reading?.motion(at: now, reduceMotion: reduceMotion) ?? (false, .infinity)
    }

    /// Transitions that run at 60 fps for their duration (DESIGN 2a, Frame policy): new peak, tier flash, title, hover
    /// and style change.
    private func inTransition(gauge: LiveGauge, at now: TimeInterval) -> Bool {
        now - peakStart < Self.peakDuration + 0.2
            || now - gauge.tierChangedAt < 0.5
            || now - gauge.titleChangedAt < OrbReadoutBuilder.titleSlide + 0.1
            || now - hoverChangedAt < 0.45
            || now - styleChangedAt < Self.styleCrossfade + 0.05
            || readout.isRenaming(at: now)
    }

    /// Short motion that runs at the orb's resting rate (at least 30 fps): response waves, the odometer and the aura
    /// flare. Responses arrive every second or two while agents work, so drawing them at 60 fps would keep a cruising
    /// orb at 60 fps and break the cruise budget.
    private func inMotion(at now: TimeInterval) -> Bool {
        !pulses.isEmpty || !readout.isSettled(at: now) || flare.value > 0.02
    }

    private var envelopesSettled: Bool {
        redline.isSettled(at: envelopeTargets.redline)
            && hover.isSettled(at: envelopeTargets.hover)
            && activity.isSettled(at: envelopeTargets.activity)
            && valueGlow.isSettled(at: envelopeTargets.glow)
            && skew.isSettled(at: envelopeTargets.skew)
    }

    /// The next sign-of-life start of an idle orb (a single timer, not polling).
    private func nextSignOfLife(after now: TimeInterval, gauge: LiveGauge, effects: OrbEffects, unavailable: Bool) -> TimeInterval {
        guard surface != .embedded, renderer.signOfLifeDuration > 0, gauge.tier == .idle, !unavailable, effects.idleSweep else {
            return .infinity
        }
        var start = ((now / Self.signOfLifePeriod).rounded(.down) + 1) * Self.signOfLifePeriod
        let idleSince = gauge.tierChangedAt.isFinite ? gauge.tierChangedAt : -.infinity
        while start < idleSince + 2 { start += Self.signOfLifePeriod }
        return start
    }

    /// A minimal frame for scheduling questions (no content needed).
    private func frameFor(_ time: TimeInterval) -> OrbFrame {
        let gauge = feed?.gauge
        let effects = model.map { self.effects(for: $0) } ?? OrbEffects(level: .standard, reduceMotion: false, surface: surface)
        return OrbFrame.scheduling(time: time, gauge: gauge, effects: effects, unavailable: feed?.unavailableTitleKey != nil,
                                   geometry: cachedGeometry)
    }

    private func desiredMode(model: AgentSpeedModel, feed: OrbFeed, at now: TimeInterval) -> FrameMode {
        let gauge = feed.gauge
        let effects = self.effects(for: model)
        let busy = !gauge.isSettled(at: now)
            || (gauge.tier != .idle && (effects.ambient || effects.shimmer))
            || renderer.isBusy(frameFor(now))
            || inTransition(gauge: gauge, at: now)
            || inMotion(at: now)
            || now - gauge.tierChangedAt < 0.9
            || !envelopesSettled
        guard !busy else { return .active }
        switch HeroCenter.demand(animator: self, model: model, at: now) {
        case .full?: return .active
        case .idle(let fps)?: return .ambient(fps)
        case .still?, nil: return .paused
        }
    }

    /// Runs the simulation forward without rendering (previews).
    func prewarm(from start: TimeInterval, to end: TimeInterval, step: (TimeInterval) -> Void) {
        lastStep = start
        var time = start
        while time < end {
            time = min(end, time + 1.0 / 60)
            step(time)
        }
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t.clamped(to: 0...1)
    }
}

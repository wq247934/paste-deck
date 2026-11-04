import Foundation

/// The stream scheduler of METRICS 11.9 on a monotonic millisecond clock: one long-lived connection, reports built
/// when the data changes, written at once and acknowledged one by one. The owner performs the actions and reports the
/// connection's events back (`opened`, `ready`, `ack`, `error`, `closed`, `rejected`), only those of the current
/// connection. One value is one transport session.
public struct ReportStreamScheduler: Sendable {
    public static let connectMs: Int64 = 10_000
    public static let closingMs: Int64 = 1000
    public static let staleMs: Int64 = 1000
    public static let stableMs: Int64 = 60_000
    /// The reconnect delay of the 1st, 2nd … failure; the last one repeats.
    public static let backoffMs: [Int64] = [500, 1000, 2000, 4000, 8000, 16_000, 30_000]

    private struct Awaited: Sendable {
        let seq: Int
        let observed: Int64?
        let written: Int64
    }

    private struct Strikes: Sendable {
        var reject = 0
        var nonce = 0
        var signature = 0
        var runConflicts = 0
        var oversize = 0
    }

    /// The document's settings; the next connection's `ready` must match them.
    public private(set) var settings: ReportStreamSettings
    /// The settings that govern the current connection (its `ready`).
    public private(set) var limits: ReportStreamSettings
    /// `H` (`heartbeatSeconds`, METRICS 11.5).
    public var heartbeatMs: Int64
    /// The document has the capability.
    public private(set) var available: Bool
    public private(set) var paused: Bool
    public private(set) var networkOff: Bool
    /// Reporting was turned off or the app quits (`Event.stop`).
    public private(set) var ended = false
    public private(set) var mode: ReportScheduler.Mode = .quiet
    public private(set) var connection: Connection = .closed
    public private(set) var seq = 0
    public private(set) var failures = 0
    public private(set) var reconnectAt: Int64 = .min
    public private(set) var rateLimitedUntil: Int64 = .min
    public private(set) var stop: Stop?
    /// The time of the last delivered report.
    public private(set) var lastDelivered: Int64?
    /// The pending wake-up; a tick at or after it consumes it.
    public private(set) var wakeAt: Int64?
    /// The `rank` of the last delivery that carried one.
    public private(set) var rank: Int?
    public private(set) var counters = Counters()
    public private(set) var latency = ReportLatency()
    /// The deadline of `connecting`, `opening` or `closing`.
    public private(set) var deadline: Int64?
    private var readyAt: Int64?
    private var awaiting: [Awaited] = []
    private var lastActive: Int64?
    private var previousTick: Int64?
    /// The start of the open window (the preview's `windowMs`).
    public private(set) var windowStart: Int64?
    private var observed: Int64?
    private var dirty = false
    private var lastBuild: Int64?
    private var lastActivity: ReportScheduler.Activity?
    private var mismatched = false
    private var waitingSettings = false
    private var strikes = Strikes()
    /// The random reconnect factor in [0.8, 1.2]; the fixtures use 1.
    private let jitter: @Sendable () -> Double

    /// `settings` is nil while the transport is unavailable.
    public init(
        settings: ReportStreamSettings?,
        heartbeatSeconds: Int,
        paused: Bool = false,
        networkOff: Bool = false,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }
    ) {
        self.settings = settings ?? .standard
        limits = self.settings
        available = settings != nil
        heartbeatMs = Int64(heartbeatSeconds) * 1000
        self.paused = paused
        self.networkOff = networkOff
        self.jitter = jitter
    }

    public var awaitingCount: Int { awaiting.count }

    /// The open window's earliest observation (the preview's `realtime`).
    public var windowObserved: Int64? { observed }

    /// True while waiting for the refreshed settings after a `ready` with other limits.
    public var awaitsSettings: Bool { waitingSettings }

    /// Forgets the pending wake-up (one that a tick of the same time replaced).
    public mutating func clearWake() { wakeAt = nil }

    /// One tick at `t`: an engine tick, a snapshot after a read, or a wake-up. `changed` is the changed rule of
    /// METRICS 11.9 and `observed` the tick's observation; `blocked` covers the readiness the scheduler does not track
    /// (reporting on, confirmed, registered, no error that needs the user).
    public mutating func tick(
        at t: Int64, active: Bool, changed: Bool = false, observed tickObserved: Int64? = nil, blocked: Bool = false,
        events: [ReportScheduler.Event] = []
    ) -> [Action] {
        var actions: [Action] = []
        if let wakeAt, t >= wakeAt { self.wakeAt = nil }
        var userLeave = false
        for event in events {
            switch event {
            case .pause:
                userLeave = userLeave || !paused
                paused = true
            case .resume:
                paused = false
            case .networkOff:
                networkOff = true
                if connection != .closed { end(.abort, &actions) }
            case .networkOn:
                networkOff = false
            case .stop:
                userLeave = userLeave || !ended
                ended = true
            }
        }
        if let previousTick, t - previousTick > ReportScheduler.gapMs {
            discard(at: t, beforeIncrements: true, &actions)
            if connection != .closed { end(.abort, &actions) }
        }
        previousTick = t
        if windowStart == nil { windowStart = t }
        let previous = mode
        if active { lastActive = t }
        let since = lastActive.map { t - $0 }
        mode = if let since, since < ReportScheduler.holdMs { .active }
            else if let since, since < ReportScheduler.quietMs { .idle } else { .quiet }
        if changed || mode.rawValue != lastActivity?.rawValue { dirty = true }
        if changed, let tickObserved { observed = min(observed ?? tickObserved, tickObserved) }
        if connection == .closing, let deadline, t >= deadline { end(.abort, &actions) }
        if userLeave, connection == .open, previous != .quiet, t >= rateLimitedUntil { leave(at: t, &actions) }

        if ended || networkOff || paused || stop != nil || !available || blocked {
            if connection == .open {
                if awaiting.isEmpty {
                    end(.close, &actions)
                } else {
                    connection = .closing
                    deadline = t + Self.closingMs
                }
            } else if connection == .connecting || connection == .opening {
                end(.abort, &actions)
            }
            discard(at: t, &actions)
            return actions
        }

        if mode == .quiet {
            if previous != .quiet, connection == .open {
                leave(at: t, &actions)
            } else if connection == .connecting || connection == .opening {
                end(.abort, &actions)
            }
            discard(at: t, &actions)
            return actions
        }

        switch connection {
        case .closed:
            if t >= reconnectAt, t >= rateLimitedUntil, !waitingSettings {
                connection = .connecting
                deadline = t + Self.connectMs
                actions.append(.connect)
            }
            discard(at: t, &actions)
            return actions
        case .connecting, .opening:
            if let deadline, t >= deadline {
                end(.abort, &actions)
                failure(at: t, &actions)
            }
            discard(at: t, &actions)
            return actions
        case .closing:
            discard(at: t, &actions)
            return actions
        case .open:
            break
        }

        if awaiting.contains(where: { t > $0.written + Int64(limits.ackTimeoutMs) }) {
            end(.abort, &actions)
            failure(at: t, &actions)
            discard(at: t, &actions)
            return actions
        }

        let minInterval = Int64(limits.minIntervalMs)
        var due = dirty && (lastBuild.map { t - $0 >= minInterval } ?? true)
        due = due || t - (lastBuild ?? readyAt ?? t) >= heartbeatMs
        if due {
            if awaiting.count < limits.maxInFlight {
                build(at: t, mode == .active ? .active : .idle, &actions)
            } else {
                discard(at: t, &actions)
                dirty = false
                counters.saturated += 1
                actions.append(.saturated)
            }
        } else if dirty, let lastBuild {
            let at = lastBuild + minInterval
            if wakeAt != at {
                wakeAt = at
                actions.append(.wake(at: at))
            }
        }
        return actions
    }

    // MARK: - The connection's events

    /// The `101` with the subprotocol: `connecting` → `opening`, 10 s to a valid `ready`.
    public mutating func opened(at t: Int64) -> [Action] {
        if connection == .connecting {
            connection = .opening
            deadline = t + Self.connectMs
        }
        return []
    }

    /// A valid `ready`: limits equal to the document's open the connection; others close it and refresh the document
    /// once.
    public mutating func ready(at t: Int64, limits given: ReportStreamSettings) -> [Action] {
        guard connection == .opening else { return [] }
        var actions: [Action] = []
        if given == settings {
            connection = .open
            deadline = nil
            readyAt = t
            mismatched = false
            limits = given
            discard(at: t, &actions)
            dirty = true
            lastBuild = nil
            return actions
        }
        end(.close, &actions)
        if mismatched {
            halt(.mismatch, &actions)
        } else {
            mismatched = true
            waitingSettings = true
            actions.append(.react(.refreshDiscovery))
        }
        return actions
    }

    /// A refreshed document: its stream settings, or nil when it lacks the capability.
    public mutating func settingsChanged(at t: Int64, _ given: ReportStreamSettings?) -> [Action] {
        var actions: [Action] = []
        if let given {
            settings = given
            available = true
            waitingSettings = false
        } else if waitingSettings {
            waitingSettings = false
            halt(.mismatch, &actions)
        } else {
            available = false
        }
        return actions
    }

    /// The forced refresh after a differing `ready` failed.
    public mutating func refreshFailed(at t: Int64) -> [Action] {
        guard waitingSettings else { return [] }
        var actions: [Action] = []
        waitingSettings = false
        halt(.mismatch, &actions)
        return actions
    }

    /// *Try Again*: clears a stop, the strikes, the mismatch flags and the failures; connects at the next tick.
    public mutating func retry(at t: Int64) -> [Action] {
        stop = nil
        mismatched = false
        waitingSettings = false
        strikes = Strikes()
        failures = 0
        reconnectAt = t
        return []
    }

    /// An `ack`; `matches` is false when its run id or body hash is not the awaited report's.
    public mutating func ack(at t: Int64, seq: Int, status: AckStatus, matches: Bool = true, rank: Int? = nil) -> [Action] {
        guard connection == .open || connection == .closing else { return [] }
        guard matches, let index = awaiting.firstIndex(where: { $0.seq == seq }) else {
            counters.unmatched += 1
            return []
        }
        var actions: [Action] = []
        let report = awaiting.remove(at: index)
        switch status {
        case .accepted: counters.accepted += 1
        case .duplicate: counters.duplicate += 1
        }
        lastDelivered = t
        if let rank { self.rank = rank }
        let sample = report.observed.map { t - $0 }
        if let sample { latency.add(sample) }
        actions.append(.delivered(seq: seq, status: status, latencyMs: sample))
        strikes = Strikes()
        if let readyAt, t - readyAt >= Self.stableMs { failures = 0 }
        closeWhenAnswered(&actions)
        return actions
    }

    /// A written report whose message does not fit `maxMessageBytes` even without models and sources: dropped as
    /// stale.
    public mutating func unwritable(seq: Int) -> [Action] {
        guard let index = awaiting.firstIndex(where: { $0.seq == seq }) else { return [] }
        var actions: [Action] = []
        awaiting.remove(at: index)
        counters.stale += 1
        actions.append(.dropped(seq: seq, .stale))
        closeWhenAnswered(&actions)
        return actions
    }

    /// An `error`; `seq` is nil for `"run": null` or another run's id.
    public mutating func error(
        at t: Int64, seq: Int?, code: String, httpStatus: Int, retryAfterSeconds: Int? = nil, fatal: Bool = false
    ) -> [Action] {
        guard connection == .open || connection == .closing else { return [] }
        var actions: [Action] = []
        if let seq, let index = awaiting.firstIndex(where: { $0.seq == seq }) {
            awaiting.remove(at: index)
            counters.rejected += 1
            actions.append(.dropped(seq: seq, .rejected))
        }
        react(to: code, status: httpStatus, retryAfter: retryAfterSeconds, at: t, &actions)
        if fatal, connection != .closed {
            end(.abort, &actions)
            failure(at: t, &actions)
        } else {
            closeWhenAnswered(&actions)
        }
        return actions
    }

    /// A refused handshake; `code` from its v1 error body, else classified by the status.
    public mutating func rejected(at t: Int64, status: Int, code: String? = nil, retryAfterSeconds: Int? = nil) -> [Action] {
        guard connection == .connecting else { return [] }
        var actions: [Action] = []
        end(nil, &actions)
        let code = code ?? ReportStreamRejection.classify(status: status, body: nil,
                                                          retryAfter: retryAfterSeconds.map(String.init)).code
        if !react(to: code, status: status, retryAfter: retryAfterSeconds, at: t, &actions) {
            failure(at: t, &actions)
        }
        return actions
    }

    /// The connection ended with `code` (sent by the service, or 1006 for the network).
    public mutating func closed(at t: Int64, code: Int) -> [Action] {
        guard connection != .closed else { return [] }
        var actions: [Action] = []
        let was = connection
        end(nil, &actions)
        guard was != .closing else { return actions }
        switch code {
        case 4001: halt(.apiKey, &actions)
        case 4003: halt(.forbidden, &actions)
        case 4004:
            actions.append(.react(.reRegister))
            failure(at: t, &actions)
        case 4009: halt(.replaced, &actions)
        case 4410: halt(.gone, &actions)
        case 4429, 4503: wait(at: t, seconds: nil, &actions)
        case 1002, 1003, 1007: halt(.incompatible, &actions)
        case 1009:
            actions.append(.react(.refreshDiscovery))
            strikes.oversize += 1
            if strikes.oversize >= 3 { halt(.incompatible, &actions) } else { failure(at: t, &actions) }
        default:
            failure(at: t, &actions)
        }
        return actions
    }

    // MARK: - Steps

    /// The reaction table; true when it ended the attempt (a failure, a wait, a stop or a fresh start).
    @discardableResult
    private mutating func react(to code: String?, status: Int?, retryAfter: Int?, at t: Int64, _ actions: inout [Action]) -> Bool {
        switch code {
        case "timestamp_out_of_window":
            actions.append(.react(.correctClock))
            return false
        case "nonce_replayed":
            strikes.nonce += 1
            guard strikes.nonce >= 3 else { return false }
            halt(.nonce, &actions)
            return true
        case "signature_invalid":
            actions.append(.react(.recheckRegistration))
            strikes.signature += 1
            if strikes.signature >= 3 {
                halt(.keyMismatch, &actions)
                return true
            }
            if connection != .closed { end(.close, &actions) }
            failure(at: t, &actions)
            return true
        case "api_key_required", "api_key_invalid":
            halt(.apiKey, &actions)
            return true
        case "forbidden":
            halt(.forbidden, &actions)
            return true
        case "unknown_device":
            actions.append(.react(.reRegister))
            if connection != .closed { end(.abort, &actions) }
            failure(at: t, &actions)
            return true
        case "username_mismatch":
            actions.append(.react(.rename))
            return false
        case "seq_conflict":
            if connection != .closed { end(.abort, &actions) }
            actions.append(.react(.newRun))
            newRun(at: t)
            reconnectAt = t
            return true
        case "run_conflict":
            if connection != .closed { end(.close, &actions) }
            strikes.runConflicts += 1
            if strikes.runConflicts >= 2 { halt(.clientState, &actions) } else { reconnectAt = t }
            return true
        case "version_unsupported":
            actions.append(.react(.refreshDiscovery))
            halt(.upgrade, &actions)
            return true
        case "payload_too_large":
            actions.append(.react(.refreshDiscovery))
            strikes.oversize += 1
            guard strikes.oversize >= 3 else { return false }
            halt(.incompatible, &actions)
            return true
        case "report_stale":
            return false
        default:
            break
        }
        if code == "rate_limited" || (status == 503 && retryAfter != nil) {
            if connection != .closed { end(.abort, &actions) }
            wait(at: t, seconds: retryAfter, &actions)
            return true
        }
        if code == "gone" {
            halt(.gone, &actions)
            return true
        }
        if let status, (400..<500).contains(status) {
            strikes.reject += 1
            guard strikes.reject >= 3 else { return false }
            halt(.rejected, &actions)
            return true
        }
        if connection != .closed { end(.abort, &actions) }
        failure(at: t, &actions)
        return true
    }

    private mutating func newRun(at t: Int64) {
        seq = 0
        windowStart = t
        observed = nil
        dirty = false
        lastBuild = nil
        lastActivity = nil
    }

    private mutating func discard(at t: Int64, beforeIncrements: Bool = false, _ actions: inout [Action]) {
        windowStart = t
        observed = nil
        actions.append(.discard(beforeIncrements: beforeIncrements))
    }

    /// The connection ends: every awaited report is dropped as unknown (never resent).
    private mutating func end(_ action: Action?, _ actions: inout [Action]) {
        if let action { actions.append(action) }
        for report in awaiting {
            actions.append(.dropped(seq: report.seq, .unknown))
            counters.unknown += 1
        }
        awaiting.removeAll()
        connection = .closed
        deadline = nil
        readyAt = nil
    }

    private mutating func closeWhenAnswered(_ actions: inout [Action]) {
        if connection == .closing, awaiting.isEmpty { end(.close, &actions) }
    }

    private mutating func failure(at t: Int64, _ actions: inout [Action]) {
        failures += 1
        let delay = Self.backoffMs[min(failures, Self.backoffMs.count) - 1]
        reconnectAt = t + Int64((Double(delay) * jitter()).rounded())
        actions.append(.backoff(reconnectAt: reconnectAt))
    }

    private mutating func wait(at t: Int64, seconds: Int?, _ actions: inout [Action]) {
        let wait = seconds.map { min(max($0, 5), 3600) } ?? 60
        rateLimitedUntil = max(rateLimitedUntil, t + Int64(wait) * 1000)
        actions.append(.wait(until: rateLimitedUntil))
    }

    private mutating func halt(_ reason: Stop, _ actions: inout [Action]) {
        stop = reason
        actions.append(.stop(reason))
        if connection != .closed { end(.abort, &actions) }
    }

    /// Builds `leaving` when a slot is free, writes it and closes within a second.
    private mutating func leave(at t: Int64, _ actions: inout [Action]) {
        if awaiting.count < limits.maxInFlight { build(at: t, .leaving, &actions) }
        connection = .closing
        deadline = t + Self.closingMs
        if awaiting.isEmpty { end(.close, &actions) }
    }

    private mutating func build(at t: Int64, _ activity: ReportScheduler.Activity, _ actions: inout [Action]) {
        seq += 1
        let ticket = Ticket(seq: seq, activity: activity, builtAt: t, windowMs: t - (windowStart ?? t), observed: observed)
        actions.append(.build(ticket))
        counters.built += 1
        windowStart = t
        observed = nil
        dirty = false
        lastBuild = t
        lastActivity = activity
        if let age = ticket.observationAgeMs, age > Self.staleMs {
            actions.append(.dropped(seq: ticket.seq, .stale))
            counters.stale += 1
            return
        }
        awaiting.append(Awaited(seq: ticket.seq, observed: ticket.observed, written: t))
        actions.append(.write(seq: ticket.seq))
    }
}

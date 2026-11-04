import Foundation

/// What a stream session asks of its owner (the app's report controller, or a test).
@MainActor
public protocol ReportStreamSessionDelegate: AnyObject {
    /// Empty the open window; `beforeIncrements` for the gap rule (METRICS 11.1).
    func streamSession(_ session: ReportStreamSession, discardBeforeIncrements: Bool)
    /// The body of `ticket` with `realtime`, taking the window; nil when it cannot be built.
    func streamSession(_ session: ReportStreamSession, bodyFor ticket: ReportStreamScheduler.Ticket) -> Data?
    /// What signs the upgrade and the reports now; nil without a usable key.
    func streamSessionCredentials(_ session: ReportStreamSession) -> ReportStreamCredentials?
    /// A reaction of REPORTING 8.3; `serverTime` comes with `correctClock` when the error carried one.
    func streamSession(_ session: ReportStreamSession, react reaction: ReportStreamScheduler.Reaction, serverTime: Int64?)
    /// The key could not sign the upgrade or a report.
    func streamSessionSigningFailed(_ session: ReportStreamSession)
    /// The connection, the counters, a delivery, a stop or a wait changed (the status line).
    func streamSessionDidChange(_ session: ReportStreamSession)
    /// The scheduler asked for a tick (the end of the minimum interval): tick with the latest values.
    func streamSessionWake(_ session: ReportStreamSession)
}

/// One transport session of the WebSocket transport (METRICS 11.9): the stream scheduler, the current connection and
/// the run's id. It performs the scheduler's actions — connecting, writing signed reports, closing — and hands the
/// connection's events back to it, only those of the current connection.
@MainActor
public final class ReportStreamSession {
    public weak var delegate: (any ReportStreamSessionDelegate)?
    public private(set) var scheduler: ReportStreamScheduler
    public private(set) var runId = ReportCanonical.newUUID()
    /// The wall-clock time of the last acknowledged report.
    public private(set) var lastDeliveredAt: Date?
    private let transport: any ReportStreamTransport
    private let clock: @MainActor () -> Int64
    private var link: (any ReportStreamLink)?
    private var generation = 0
    private var bodies: [Int: Data] = [:]
    private var digests: [Int: String] = [:]
    private var serverTime: Int64?
    private var wakeTimer: DispatchWorkItem?
    private var wakeTimerAt: Int64?

    public init(
        scheduler: ReportStreamScheduler, transport: any ReportStreamTransport = URLSessionReportStream(),
        clock: @escaping @MainActor () -> Int64
    ) {
        self.scheduler = scheduler
        self.transport = transport
        self.clock = clock
    }

    public var isConnected: Bool { link != nil }

    public func tick(
        at t: Int64, active: Bool, changed: Bool, observed: Int64?, blocked: Bool, events: [ReportScheduler.Event] = []
    ) {
        perform(scheduler.tick(at: t, active: active, changed: changed, observed: observed, blocked: blocked,
                               events: events), at: t)
    }

    /// A refreshed document: its stream settings, or nil without the capability.
    public func settingsChanged(_ settings: ReportStreamSettings?) {
        let t = clock()
        perform(scheduler.settingsChanged(at: t, settings), at: t)
    }

    /// The forced refresh after a `ready` with other limits failed.
    public func refreshFailed() {
        let t = clock()
        perform(scheduler.refreshFailed(at: t), at: t)
    }

    /// *Try Again*.
    public func retry() {
        let t = clock()
        perform(scheduler.retry(at: t), at: t)
    }

    public func update(heartbeatSeconds: Int) {
        scheduler.heartbeatMs = Int64(heartbeatSeconds) * 1000
    }

    /// The session ends without `leaving` (another transport or service, or reporting gone): its connection is closed
    /// and nothing it awaits is answered any more.
    public func shutdown() {
        generation += 1
        link?.close()
        link = nil
        wakeTimer?.cancel()
        wakeTimer = nil
        wakeTimerAt = nil
    }

    // MARK: - Connection events

    private func handle(_ event: ReportStreamEvent, generation: Int) {
        guard generation == self.generation, link != nil else { return }
        let t = clock()
        switch event {
        case .opened:
            perform(scheduler.opened(at: t), at: t)
        case .message(.ready(let limits)):
            perform(scheduler.ready(at: t, limits: limits), at: t)
        case .message(.ack(let ack)):
            let matches = ack.runId == runId && digests[ack.seq] == ack.bodySha256
            perform(scheduler.ack(at: t, seq: ack.seq, status: ack.status == "duplicate" ? .duplicate : .accepted,
                                  matches: matches, rank: ack.rank), at: t)
        case .message(.error(let failure)):
            let fatal = failure.fatal ? " fatal" : ""
            ReportLog.network.info(
                "websocket error \(failure.httpStatus, privacy: .public) \(failure.code, privacy: .public)\(fatal, privacy: .public)")
            serverTime = failure.serverTime
            defer { serverTime = nil }
            perform(scheduler.error(at: t, seq: failure.runId == runId ? failure.seq : nil, code: failure.code,
                                    httpStatus: failure.httpStatus, retryAfterSeconds: failure.retryAfterSeconds,
                                    fatal: failure.fatal), at: t)
        case .message(.other):
            break
        case .rejected(let status, let retryAfter):
            ReportLog.network.info("websocket upgrade refused \(status, privacy: .public)")
            ended()
            let rejection = ReportStreamRejection.classify(status: status, body: nil, retryAfter: retryAfter)
            perform(scheduler.rejected(at: t, status: status, code: rejection.code,
                                       retryAfterSeconds: rejection.retryAfterSeconds), at: t)
        case .closed(let code):
            ReportLog.network.info("websocket closed \(code, privacy: .public)")
            ended()
            perform(scheduler.closed(at: t, code: code), at: t)
        }
    }

    /// The connection ended on its own: it reports nothing more.
    private func ended() {
        generation += 1
        link = nil
    }

    // MARK: - Actions

    private func perform(_ actions: [ReportStreamScheduler.Action], at t: Int64) {
        for action in actions {
            switch action {
            case .discard(let beforeIncrements):
                delegate?.streamSession(self, discardBeforeIncrements: beforeIncrements)
            case .connect:
                connect()
            case .abort:
                generation += 1
                link?.abort()
                link = nil
            case .close:
                generation += 1
                link?.close()
                link = nil
            case .build(let ticket):
                bodies[ticket.seq] = delegate?.streamSession(self, bodyFor: ticket)
            case .write(let seq):
                write(seq, at: t)
            case .delivered(let seq, _, _):
                digests[seq] = nil
                lastDeliveredAt = Date()
            case .dropped(let seq, _):
                digests[seq] = nil
                bodies[seq] = nil
            case .react(let reaction):
                if reaction == .newRun {
                    runId = ReportCanonical.newUUID()
                    bodies.removeAll()
                    digests.removeAll()
                }
                delegate?.streamSession(self, react: reaction, serverTime: serverTime)
            case .stop(let reason):
                ReportLog.network.info("websocket stopped: \(reason.rawValue, privacy: .public)")
            case .saturated, .backoff, .wait, .wake:
                break
            }
        }
        armWake(now: t)
        delegate?.streamSessionDidChange(self)
    }

    private func connect() {
        generation += 1
        let generation = self.generation
        guard let credentials = delegate?.streamSessionCredentials(self) else {
            delegate?.streamSessionSigningFailed(self)
            return
        }
        let link = transport.link(
            settings: scheduler.settings, queue: .main,
            onEvent: { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event, generation: generation) }
            },
            onSigningFailure: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, generation == self.generation else { return }
                    self.delegate?.streamSessionSigningFailed(self)
                }
            })
        self.link = link
        link.start { try credentials.handshake() }
    }

    /// Writes a built report, or drops it as stale when its message would not fit (or it could not be built).
    private func write(_ seq: Int, at t: Int64) {
        guard let body = bodies.removeValue(forKey: seq),
              ReportStreamMessage.messageBytes(body: body) <= scheduler.limits.maxMessageBytes else {
            perform(scheduler.unwritable(seq: seq), at: t)
            return
        }
        guard let link, let credentials = delegate?.streamSessionCredentials(self) else {
            delegate?.streamSessionSigningFailed(self)
            return
        }
        digests[seq] = ReportStreamMessage.bodySha256(body)
        link.send { try credentials.message(body: body) }
    }

    /// One timer for the scheduler's pending wake-up; a wake that fires early is armed again by its tick.
    private func armWake(now: Int64) {
        guard let at = scheduler.wakeAt else {
            wakeTimer?.cancel()
            wakeTimer = nil
            wakeTimerAt = nil
            return
        }
        guard wakeTimerAt != at else { return }
        wakeTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wakeTimer = nil
                self.wakeTimerAt = nil
                self.delegate?.streamSessionWake(self)
            }
        }
        wakeTimer = item
        wakeTimerAt = at
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(max(0, at - now)) + 1), execute: item)
    }
}

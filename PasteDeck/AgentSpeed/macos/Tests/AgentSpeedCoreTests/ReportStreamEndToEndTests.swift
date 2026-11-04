import Foundation
import Testing
@testable import AgentSpeedCore

/// The WebSocket transport against `spec/tools/report_server.py --websocket` on loopback (METRICS 11.9): the real
/// URLSession connection, the signed upgrade and reports, the service's answers, and the stream session driving its
/// scheduler. Never reaches beyond 127.0.0.1.
@Suite(.serialized, .enabled(if: ReferencePython.available))
struct ReportStreamEndToEndTests {
    typealias Device = ReportEndToEndTests.Device

    /// Collects one link's events.
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ReportStreamEvent] = []
        private var signingFailures = 0

        func append(_ event: ReportStreamEvent) { lock.withLock { items.append(event) } }
        func signingFailed() { lock.withLock { signingFailures += 1 } }
        var all: [ReportStreamEvent] { lock.withLock { items } }

        /// Waits until `count` events arrived (at most `timeout` seconds).
        func wait(for count: Int, timeout: TimeInterval = 5) async throws -> [ReportStreamEvent] {
            let deadline = Date().addingTimeInterval(timeout)
            while all.count < count, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            return all
        }
    }

    static let queue = DispatchQueue(label: "report-stream-tests")

    static func registered(on server: ReferenceServer, _ name: String) async throws -> Device {
        let device = try await ReportEndToEndTests.device(on: server)
        #expect(try await device.register(name).result == "created")
        return device
    }

    static func credentials(_ device: Device, signer: (any ReportSigner)? = nil) -> ReportStreamCredentials {
        ReportStreamCredentials(
            api: device.document.api,
            builder: ReportRequestBuilder(userAgent: ReportEndToEndTests.userAgent, deviceId: device.deviceId,
                                          apiKey: device.apiKey),
            signer: signer ?? device.signer, clockCorrection: 0)
    }

    static func connect(_ device: Device, signer: (any ReportSigner)? = nil) -> (any ReportStreamLink, Events) {
        let events = Events()
        let settings = device.document.websocket ?? .standard
        let link = URLSessionReportStream().link(settings: settings, queue: queue, onEvent: { events.append($0) },
                                                 onSigningFailure: { events.signingFailed() })
        let credentials = credentials(device, signer: signer)
        link.start { try credentials.handshake() }
        return (link, events)
    }

    static func body(_ device: Device, username: String, runId: String, seq: Int, activity: ReportScheduler.Activity = .active,
                     observationAgeMs: Int64? = 12) -> Data {
        let sample = ReportSample(live: Rate(output: 42.5, total: 900))
        let envelope = ReportEnvelope(client: ReportEndToEndTests.client, deviceId: device.deviceId, username: username,
                                      runId: runId, seq: seq, sentAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                                      windowMs: 50, activity: activity, titleLevel: 1,
                                      realtime: ReportRealtime(observationAgeMs: observationAgeMs))
        let options = ReportOptions(sections: device.document.sections, messageLimit: device.document.websocket?.maxMessageBytes)
        return ReportBody.fitted(envelope, ReportWindow(sample).content(sample), sample, options).data
    }

    @Test func readyThenAcknowledgedReportsAndADuplicate() async throws {
        let server = try ReferenceServer(arguments: ["--websocket", "--api-path", "/agent-speed"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-mac")
        let settings = try #require(device.document.websocket)
        #expect(device.document.api.streamURL.absoluteString.hasPrefix("ws://127.0.0.1:"))
        #expect(device.document.api.streamURL.path == "/agent-speed/v1/reports/ws")

        let (link, events) = Self.connect(device)
        defer { link.close() }
        let opened = try await events.wait(for: 2)
        try #require(opened.count == 2, "\(opened)")
        #expect(opened[0] == .opened)
        #expect(opened[1] == .message(.ready(limits: settings)))

        let runId = ReportCanonical.newUUID()
        let body = Self.body(device, username: "stream-mac", runId: runId, seq: 1)
        let credentials = Self.credentials(device)
        link.send { try credentials.message(body: body) }
        link.send { try credentials.message(body: body) }
        let answered = try await events.wait(for: 4)
        try #require(answered.count == 4, "\(answered)")
        for (index, status) in [(2, "accepted"), (3, "duplicate")] {
            guard case .message(.ack(let ack)) = answered[index] else {
                Issue.record("not an ack: \(answered[index])")
                continue
            }
            #expect(ack.runId == runId && ack.seq == 1 && ack.status == status)
            #expect(ack.bodySha256 == ReportStreamMessage.bodySha256(body))
        }
        #expect(server.log.contains("stream-mac"))
    }

    @Test func aRefusedUpgradeIsClassifiedByItsStatus() async throws {
        let server = try ReferenceServer(arguments: ["--websocket"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-refused")
        let (link, events) = Self.connect(device, signer: SoftwareReportSigner())
        defer { link.abort() }
        let got = try await events.wait(for: 1)
        #expect(got == [.rejected(status: 401, retryAfter: nil)])
        #expect(ReportStreamRejection.classify(status: 401, body: nil, retryAfter: nil).code == "signature_invalid")
    }

    /// The session reacts to the refused upgrade: the registration is checked again and the attempt is a failure.
    @MainActor
    @Test func aSessionRechecksTheRegistrationWhenTheUpgradeIsRefused() async throws {
        let server = try ReferenceServer(arguments: ["--websocket"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-recheck")
        let owner = Owner(device: device, username: "stream-recheck", signer: SoftwareReportSigner())
        let session = owner.session
        session.tick(at: Owner.now, active: true, changed: true, observed: nil, blocked: false)
        let deadline = Date().addingTimeInterval(3)
        while owner.reactions.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(owner.reactions == [.recheckRegistration])
        #expect(session.scheduler.connection == .closed)
        #expect(session.scheduler.failures == 1)
        #expect(session.scheduler.stop == nil)
        session.shutdown()
    }

    /// A newer connection of the same device takes over: the session that held the older one stops as replaced.
    @MainActor
    @Test func aSessionStopsWhenAnotherConnectionTakesOver() async throws {
        let server = try ReferenceServer(arguments: ["--websocket"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-replaced")
        let owner = Owner(device: device, username: "stream-replaced")
        let session = owner.session
        var deadline = Date().addingTimeInterval(3)
        while session.scheduler.connection != .open, Date() < deadline {
            session.tick(at: Owner.now, active: true, changed: false, observed: nil, blocked: false)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.scheduler.connection == .open)
        let (other, events) = Self.connect(device)
        defer { other.close() }
        deadline = Date().addingTimeInterval(3)
        while session.scheduler.stop == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.scheduler.stop == .replaced)
        #expect(session.scheduler.connection == .closed)
        #expect(try await events.wait(for: 2).first == .opened)
    }

    @Test func aNewerConnectionReplacesTheOlderOne() async throws {
        let server = try ReferenceServer(arguments: ["--websocket"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-twice")
        let (first, firstEvents) = Self.connect(device)
        defer { first.abort() }
        _ = try await firstEvents.wait(for: 2)
        let (second, secondEvents) = Self.connect(device)
        defer { second.close() }
        let replaced = try await firstEvents.wait(for: 3)
        #expect(replaced.last == .closed(code: 4009), "\(replaced)")
        #expect(try await secondEvents.wait(for: 2).first == .opened)
    }

    /// The session drives its scheduler end to end: connect, ready, reports built on change and acknowledged, and
    /// `leaving` when reporting is turned off, answered before the connection closes with 1000.
    @MainActor
    @Test func aSessionStreamsChangesAndLeaves() async throws {
        let server = try ReferenceServer(arguments: ["--websocket", "--ws-min-interval", "20"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-session")
        let owner = Owner(device: device, username: "stream-session")
        let session = owner.session
        for _ in 0..<40 {
            let now = Owner.now
            session.tick(at: now, active: true, changed: true, observed: now - 5, blocked: false)
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.scheduler.connection == .open)
        #expect(session.scheduler.counters.accepted >= 5, "\(session.scheduler.counters)")
        #expect(session.scheduler.counters.unmatched == 0)
        #expect(session.lastDeliveredAt != nil)
        #expect(!session.scheduler.latency.samples.isEmpty)
        #expect(session.scheduler.latency.samples.allSatisfy { $0 >= 5 && $0 < 1000 })
        #expect(owner.signingFailures == 0)

        session.tick(at: Owner.now, active: true, changed: false, observed: nil, blocked: false, events: [.stop])
        #expect(session.scheduler.connection == .closing)
        let deadline = Date().addingTimeInterval(3)
        while session.scheduler.connection != .closed, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.scheduler.connection == .closed)
        #expect(session.scheduler.counters.unknown == 0)
        #expect(server.log.contains("leaving"))
    }

    /// An unanswered report: the connection is dropped after `ackTimeoutMs`, its outcome stays unknown, the next
    /// connection carries on.
    @MainActor
    @Test func anUnansweredReportEndsTheConnection() async throws {
        let server = try ReferenceServer(arguments: ["--websocket", "--ws-drop-answers", "2", "--ws-ack-timeout", "500",
                                                     "--ws-min-interval", "200"])
        defer { server.stop() }
        let device = try await Self.registered(on: server, "stream-drop")
        let owner = Owner(device: device, username: "stream-drop")
        let session = owner.session
        let started = Date()
        while session.scheduler.counters.unknown == 0, Date().timeIntervalSince(started) < 6 {
            let now = Owner.now
            session.tick(at: now, active: true, changed: true, observed: now, blocked: false)
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(session.scheduler.counters.unknown >= 1, "\(session.scheduler.counters)")
        #expect(session.scheduler.failures >= 1)
        session.shutdown()
    }
}

/// A stand-in for the report controller: bodies with `realtime`, the device's credentials.
@MainActor
final class Owner: ReportStreamSessionDelegate {
    static var now: Int64 { Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }

    let device: ReportEndToEndTests.Device
    let username: String
    let session: ReportStreamSession
    var signingFailures = 0
    var reactions: [ReportStreamScheduler.Reaction] = []

    let signer: (any ReportSigner)?

    init(device: ReportEndToEndTests.Device, username: String, signer: (any ReportSigner)? = nil) {
        self.device = device
        self.username = username
        self.signer = signer
        let scheduler = ReportStreamScheduler(settings: device.document.websocket,
                                              heartbeatSeconds: device.document.limits.heartbeatSeconds)
        session = ReportStreamSession(scheduler: scheduler, clock: { Owner.now })
        session.delegate = self
    }

    func streamSession(_ session: ReportStreamSession, discardBeforeIncrements: Bool) {}

    func streamSession(_ session: ReportStreamSession, bodyFor ticket: ReportStreamScheduler.Ticket) -> Data? {
        ReportStreamEndToEndTests.body(device, username: username, runId: session.runId, seq: ticket.seq,
                                       activity: ticket.activity, observationAgeMs: ticket.observationAgeMs)
    }

    func streamSessionCredentials(_ session: ReportStreamSession) -> ReportStreamCredentials? {
        ReportStreamEndToEndTests.credentials(device, signer: signer)
    }

    func streamSession(_ session: ReportStreamSession, react reaction: ReportStreamScheduler.Reaction, serverTime: Int64?) {
        reactions.append(reaction)
    }

    func streamSessionSigningFailed(_ session: ReportStreamSession) { signingFailures += 1 }

    func streamSessionDidChange(_ session: ReportStreamSession) {}

    func streamSessionWake(_ session: ReportStreamSession) {
        let now = Self.now
        session.tick(at: now, active: true, changed: false, observed: nil, blocked: false)
    }
}

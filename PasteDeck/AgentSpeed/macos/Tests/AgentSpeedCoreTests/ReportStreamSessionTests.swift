import Foundation
import Testing
@testable import AgentSpeedCore

/// The stream session over a scripted transport: only the current connection's events reach the scheduler, written
/// reports carry the body's digest, a message that would not fit is dropped as stale, and `shutdown` silences all.
@MainActor
@Suite struct ReportStreamSessionTests {
    final class Link: ReportStreamLink, @unchecked Sendable {
        let onEvent: @Sendable (ReportStreamEvent) -> Void
        var started = false
        var sent: [String] = []
        var ended: String?

        init(onEvent: @escaping @Sendable (ReportStreamEvent) -> Void) { self.onEvent = onEvent }

        func start(_ makeRequest: @escaping @Sendable () throws -> ReportRequest) {
            started = (try? makeRequest()) != nil
        }

        func send(_ makeText: @escaping @Sendable () throws -> String) {
            if let text = try? makeText() { sent.append(text) }
        }

        func close() { ended = "close" }
        func abort() { ended = "abort" }
    }

    final class Transport: ReportStreamTransport, @unchecked Sendable {
        var links: [Link] = []

        func link(
            settings: ReportStreamSettings, queue: DispatchQueue, onEvent: @escaping @Sendable (ReportStreamEvent) -> Void,
            onSigningFailure: @escaping @Sendable () -> Void
        ) -> any ReportStreamLink {
            let link = Link(onEvent: onEvent)
            links.append(link)
            return link
        }
    }

    final class Owner: ReportStreamSessionDelegate {
        var body = Data(#"{"seq":1}"#.utf8)
        var reactions: [ReportStreamScheduler.Reaction] = []
        let signer = SoftwareReportSigner()

        func streamSession(_ session: ReportStreamSession, discardBeforeIncrements: Bool) {}
        func streamSession(_ session: ReportStreamSession, bodyFor ticket: ReportStreamScheduler.Ticket) -> Data? { body }
        func streamSessionCredentials(_ session: ReportStreamSession) -> ReportStreamCredentials? {
            ReportStreamCredentials(
                api: try! ReportServiceURL.parse("https://example.com").get(),
                builder: ReportRequestBuilder(userAgent: "test", deviceId: ReportCanonical.newUUID(), apiKey: nil),
                signer: signer, clockCorrection: 0)
        }
        func streamSession(_ session: ReportStreamSession, react reaction: ReportStreamScheduler.Reaction,
                           serverTime: Int64?) { reactions.append(reaction) }
        func streamSessionSigningFailed(_ session: ReportStreamSession) {}
        func streamSessionDidChange(_ session: ReportStreamSession) {}
        func streamSessionWake(_ session: ReportStreamSession) {}
    }

    let transport = Transport()
    let owner = Owner()
    var now: Int64 = 1_000_000

    func session(_ settings: ReportStreamSettings = .standard) -> ReportStreamSession {
        let scheduler = ReportStreamScheduler(settings: settings, heartbeatSeconds: 30, jitter: { 1 })
        let time = now
        let session = ReportStreamSession(scheduler: scheduler, transport: transport, clock: { time })
        session.delegate = owner
        return session
    }

    /// Delivers `event` as the link's queue would (the main queue) and lets it run.
    func deliver(_ event: ReportStreamEvent, on link: Link) async {
        link.onEvent(event)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }

    func opened(_ session: ReportStreamSession, settings: ReportStreamSettings = .standard) async throws -> Link {
        session.tick(at: now, active: true, changed: true, observed: now, blocked: false)
        let link = try #require(transport.links.last)
        #expect(link.started)
        await deliver(.opened, on: link)
        await deliver(.message(.ready(limits: settings)), on: link)
        #expect(session.scheduler.connection == .open)
        return link
    }

    @Test func writesTheBuiltReportSignedAndCountsItsAcknowledgement() async throws {
        let session = session()
        let link = try await opened(session)
        session.tick(at: now, active: true, changed: true, observed: now, blocked: false)
        let text = try #require(link.sent.first)
        #expect(text.hasPrefix(#"{"type":"report","headers":{"#))
        #expect(text.hasSuffix(#","body":"{\"seq\":1}"}"#))
        let ack = ReportServiceMessage.Ack(runId: session.runId, seq: 1, status: "accepted",
                                           bodySha256: ReportStreamMessage.bodySha256(owner.body), rank: 3)
        await deliver(.message(.ack(ack)), on: link)
        #expect(session.scheduler.counters.accepted == 1)
        #expect(session.scheduler.rank == 3)
        #expect(session.lastDeliveredAt != nil)
    }

    @Test func anAcknowledgementOfAnotherBodyIsUnmatched() async throws {
        let session = session()
        let link = try await opened(session)
        session.tick(at: now, active: true, changed: true, observed: now, blocked: false)
        let ack = ReportServiceMessage.Ack(runId: session.runId, seq: 1, status: "accepted",
                                           bodySha256: String(repeating: "0", count: 64), rank: nil)
        await deliver(.message(.ack(ack)), on: link)
        #expect(session.scheduler.counters.unmatched == 1)
        #expect(session.scheduler.counters.accepted == 0)
    }

    @Test func aMessageThatWouldNotFitIsDroppedAsStale() async throws {
        let settings = ReportStreamSettings(maxMessageBytes: 32_768)
        let session = session(settings)
        let link = try await opened(session, settings: settings)
        owner.body = Data(("{\"x\":\"" + String(repeating: "a", count: 33_000) + "\"}").utf8)
        session.tick(at: now, active: true, changed: true, observed: now, blocked: false)
        #expect(link.sent.isEmpty)
        #expect(session.scheduler.counters.stale == 1)
        #expect(session.scheduler.awaitingCount == 0)
    }

    @Test func eventsOfAnEndedConnectionAreIgnored() async throws {
        let session = session()
        let first = try await opened(session)
        await deliver(.closed(code: 1006), on: first)
        #expect(session.scheduler.connection == .closed)
        #expect(session.scheduler.failures == 1)
        await deliver(.closed(code: 4009), on: first)
        #expect(session.scheduler.stop == nil)
        #expect(transport.links.count == 1)
    }

    @Test func shutdownClosesTheConnectionAndSilencesIt() async throws {
        let session = session()
        let link = try await opened(session)
        session.shutdown()
        #expect(link.ended == "close")
        #expect(!session.isConnected)
        await deliver(.closed(code: 4009), on: link)
        #expect(session.scheduler.stop == nil)
    }

    @Test func aReplacedConnectionStops() async throws {
        let session = session()
        let link = try await opened(session)
        await deliver(.closed(code: 4009), on: link)
        #expect(session.scheduler.stop == .replaced)
        #expect(!session.isConnected)
    }
}

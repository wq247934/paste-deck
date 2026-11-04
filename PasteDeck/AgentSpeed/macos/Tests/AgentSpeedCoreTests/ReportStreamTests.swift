import CryptoKit
import Foundation
import Testing
@testable import AgentSpeedCore

/// METRICS 11.9 against report-vectors.json `websocket`: availability, the URL, the signed upgrade and report, the
/// message text, `realtime`, the service's messages, refused upgrades and latency percentiles.
@Suite struct ReportStreamTests {
    static var vectors: [String: Any] {
        ((try? Fixtures.json("report-vectors.json"))?["websocket"] as? [String: Any]) ?? [:]
    }

    static let service = try! ReportServiceURL.parse("https://example.com").get()

    static func settings(_ value: Any?) -> ReportStreamSettings? {
        guard let given = value as? [String: Int] else { return nil }
        return ReportStreamSettings(
            minIntervalMs: given["minIntervalMs"]!, maxInFlight: given["maxInFlight"]!, ackTimeoutMs: given["ackTimeoutMs"]!,
            maxMessageBytes: given["maxMessageBytes"]!, pingIntervalSeconds: given["pingIntervalSeconds"]!,
            pongTimeoutSeconds: given["pongTimeoutSeconds"]!)
    }

    static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    }

    @Test func discoveryOffersTheTransportOnlyWithAValidObject() throws {
        let cases = try #require(Self.vectors["discovery"] as? [[String: Any]])
        #expect(cases.count == 25)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let document = try Self.json(try #require(item["document"]))
            let expected = Self.settings(item["expect"])
            let parsed = ReportDiscovery.parse(document, service: Self.service)
            guard case .success(let discovery) = parsed else {
                Issue.record("\(name): the HTTP document stays valid, got \(parsed)")
                continue
            }
            #expect(discovery.websocket == expected, "\(name)")
        }
    }

    @Test func storedIdentitiesOfEarlierBuildsDecodeWithoutTheTransport() throws {
        let document = try Self.json(try #require((Self.vectors["discovery"] as? [[String: Any]])?.first?["document"]))
        let discovery = try ReportDiscovery.parse(document, service: Self.service).get()
        #expect(discovery.websocket == .standard)
        let stored = try JSONEncoder().encode(discovery)
        #expect(try JSONDecoder().decode(ReportDiscovery.self, from: stored) == discovery)
        var old = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        old["websocket"] = nil
        var extensions = old["extensions"] as? [String: Any] ?? [:]
        extensions["reportWebSocket"] = nil
        old["extensions"] = extensions
        let earlier = try JSONDecoder().decode(ReportDiscovery.self, from: try Self.json(old))
        #expect(earlier.websocket == nil)
        #expect(earlier.extensions?.reportWebSocket == false)
    }

    @Test func connectionURLs() throws {
        let cases = try #require(Self.vectors["url"] as? [[String: String]])
        #expect(cases.count == 4)
        for item in cases {
            let api = try #require(ReportServiceURL.parseAPI(item["api"]!, discoveryIsLoopbackHTTP: true))
            #expect(api.streamURL.absoluteString == item["expect"], "\(item["api"]!)")
        }
    }

    @Test func handshakeIsSignedOverGetAndTheWebSocketPath() throws {
        let vector = try #require(Self.vectors["handshake"] as? [String: Any])
        let headers = try #require(vector["headers"] as? [String: String])
        let (signer, _) = try ReportSigningTests.key("device")
        let api = try #require(ReportServiceURL.parseAPI("https://api.example.com/agent-speed", discoveryIsLoopbackHTTP: false))
        let builder = ReportRequestBuilder(userAgent: "AgentSpeed/0.0.0-test (macOS)",
                                           deviceId: headers[ReportCanonical.deviceHeader]!, apiKey: nil)
        let request = try builder.handshake(api: api, signer: signer, timestamp: 1_792_872_000,
                                            nonce: headers[ReportCanonical.nonceHeader]!)
        #expect(request.method == vector["method"] as? String)
        #expect(request.url.absoluteString == vector["url"] as? String)
        #expect(request.body.isEmpty)
        #expect(request.header("Sec-WebSocket-Protocol") == headers["Sec-WebSocket-Protocol"])
        #expect(request.header("Authorization") == nil)
        for name in [ReportCanonical.deviceHeader, ReportCanonical.timestampHeader, ReportCanonical.nonceHeader] {
            #expect(request.header(name) == headers[name], "\(name)")
        }
        let canonical = try #require(vector["canonical"] as? String)
        let ours = ReportCanonical.string(
            method: "GET", authority: try #require(vector["authority"] as? String),
            path: try #require(vector["path"] as? String), timestamp: "1792872000",
            nonce: headers[ReportCanonical.nonceHeader]!, deviceId: headers[ReportCanonical.deviceHeader]!, body: Data())
        #expect(ours == canonical)
        let signature = try #require(Base64URL.decode(request.header(ReportCanonical.signatureHeader) ?? ""))
        #expect(signer.publicKey.isValidSignature(signature, for: Data(canonical.utf8)))
        let given = try #require(Base64URL.decode(headers[ReportCanonical.signatureHeader]!))
        #expect(signer.publicKey.isValidSignature(given, for: Data(canonical.utf8)))

        let keyed = ReportRequestBuilder(userAgent: "AgentSpeed/0.0.0-test (macOS)",
                                         deviceId: headers[ReportCanonical.deviceHeader]!, apiKey: "secret-12345")
        let withKey = try keyed.handshake(api: api, signer: signer, timestamp: 1_792_872_000)
        #expect(withKey.header("Authorization") == "Bearer secret-12345")
    }

    @Test func reportIsSignedLikeAPostAndCarriedAsAString() throws {
        let vector = try #require(Self.vectors["report"] as? [String: Any])
        let headers = try #require(vector["headers"] as? [String: String])
        let body = Data(try #require(vector["body"] as? String).utf8)
        #expect(ReportStreamMessage.bodySha256(body) == vector["bodySha256"] as? String)
        #expect(ReportStreamMessage.report(headers: headers, body: body) == vector["message"] as? String)

        let (signer, _) = try ReportSigningTests.key("device")
        let api = try #require(ReportServiceURL.parseAPI("https://api.example.com/agent-speed", discoveryIsLoopbackHTTP: false))
        let builder = ReportRequestBuilder(userAgent: "AgentSpeed/0.0.0-test (macOS)",
                                           deviceId: headers[ReportCanonical.deviceHeader]!, apiKey: "secret-12345")
        let text = try builder.reportMessage(api: api, body: body, signer: signer, timestamp: 1_792_872_000,
                                             nonce: headers[ReportCanonical.nonceHeader]!)
        let message = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(message["body"] as? String == vector["body"] as? String)
        let sent = try #require(message["headers"] as? [String: String])
        #expect(Set(sent.keys) == Set(ReportStreamMessage.signatureHeaders), "no API key or other header in the message")
        let canonical = try #require(vector["canonical"] as? String)
        let signature = try #require(Base64URL.decode(sent[ReportCanonical.signatureHeader]!))
        #expect(signer.publicKey.isValidSignature(signature, for: Data(canonical.utf8)))
        let tampered = canonical.replacingOccurrences(
            of: ReportStreamMessage.bodySha256(body),
            with: ReportStreamMessage.bodySha256(Data(String(decoding: body, as: UTF8.self)
                .replacingOccurrences(of: "\"output\":5", with: "\"output\":6").utf8)))
        #expect(!signer.publicKey.isValidSignature(signature, for: Data(tampered.utf8)))
    }

    @Test func messageTextEscapesOnlyWhatJSONRequires() throws {
        let cases = try #require(Self.vectors["encoding"] as? [[String: Any]])
        #expect(cases.count == 4)
        for item in cases {
            let body = Data(try #require(item["body"] as? String).utf8)
            let headers = try #require(item["headers"] as? [String: String])
            let message = ReportStreamMessage.report(headers: headers, body: body)
            #expect(message == item["message"] as? String, "\(item["body"] ?? "")")
            #expect(ReportStreamMessage.messageBytes(body: body) == message?.utf8.count)
        }
        #expect(ReportStreamMessage.report(headers: [:], body: Data()) == nil)
    }

    @Test func realtimeObject() throws {
        let cases = try #require(Self.vectors["realtime"] as? [[String: Any]])
        #expect(cases.count == 3)
        for item in cases {
            let age = item["observationAgeMs"] as? Int
            let realtime = ReportRealtime(observationAgeMs: age.map(Int64.init))
            let json = realtime.json(mixed: item["sourceMode"] as? String == "mixed", sentAtMs: item.int64("sentAtMs")!)
            let got = try JSONSerialization.jsonObject(with: json.compactData) as? NSDictionary
            #expect(got == item["expect"] as? NSDictionary, "\(item)")
        }
    }

    /// `realtime` is the last member of WebSocket bodies and absent from HTTP bodies.
    @Test func realtimeIsTheLastMemberOfWebSocketBodiesOnly() throws {
        let window = ReportWindow(ReportSample())
        let sample = ReportSample(live: Rate(output: 50, total: 60), traffic: ReportTrafficSample(status: .ok, rate: .zero))
        var envelope = ReportEnvelope(client: ReportClientInfo(version: "1.3.0", osMajor: 27),
                                      deviceId: ReportCanonical.newUUID(), username: "demo", runId: ReportCanonical.newUUID(),
                                      seq: 1, sentAtMs: 1_792_872_000_000, windowMs: 50, activity: .active, titleLevel: 0)
        let http = ReportBody.json(envelope, window.content(sample), sample, ReportOptions(sections: [.traffic]))
        #expect(http["realtime"] == nil)
        envelope.realtime = ReportRealtime(observationAgeMs: 12)
        guard case .object(let members) = ReportBody.json(envelope, window.content(sample), sample,
                                                          ReportOptions(sections: [.traffic])) else {
            Issue.record("not an object")
            return
        }
        #expect(members.last?.key == "realtime")
        #expect(members.last?.value["sourceMode"] == .string("mixed"))
        #expect(members.last?.value["observedAt"] == .string("2026-10-24T19:59:59.988Z"))
        let log = ReportBody.json(envelope, window.content(sample), sample, ReportOptions(sections: [.cost]))
        #expect(log["realtime"]?["sourceMode"] == .string("log"))
        #expect(log["realtime"]?["sourceResolutionMs"] == .int(1000))
    }

    /// The message limit drops `models`, then `sources`, like the body limit (METRICS 11.7, 11.9).
    @Test func bodiesFitTheMessageLimit() throws {
        var counters = ReportCounters()
        for index in 0..<16 {
            counters.add(ReportUsage(requests: 1, output: Int64(100 + index)), to: ReportModelKey(modelId: "model-\(index)", source: .codex))
        }
        let sample = ReportSample(live: Rate(output: 1, total: 1), facts: ReportLiveFacts(counters: counters))
        let content = ReportWindow(ReportSample()).content(sample)
        let envelope = ReportEnvelope(client: ReportClientInfo(version: "1.3.0", osMajor: 27),
                                      deviceId: ReportCanonical.newUUID(), username: "demo", runId: ReportCanonical.newUUID(),
                                      seq: 1, sentAtMs: 1_792_872_000_000, windowMs: 50, activity: .active, titleLevel: 0,
                                      realtime: ReportRealtime(observationAgeMs: nil))
        let all = ReportOptions(sections: Set(ReportSection.allCases))
        let full = ReportBody.fitted(envelope, content, sample, all)
        #expect(full.json["models"] != nil)
        var limited = all
        limited.messageLimit = ReportStreamMessage.messageBytes(body: full.data) - 1
        let fitted = ReportBody.fitted(envelope, content, sample, limited)
        #expect(fitted.json["models"] == nil)
        #expect(fitted.json["realtime"] != nil)
        #expect(ReportStreamMessage.messageBytes(body: fitted.data) <= limited.messageLimit!)
    }

    static func expected(_ message: ReportServiceMessage?) -> Any {
        switch message {
        case nil: return "invalid"
        case .other: return ["type": "other"]
        case .ready(let limits):
            return ["type": "ready", "limits": [
                "minIntervalMs": limits.minIntervalMs, "maxInFlight": limits.maxInFlight, "ackTimeoutMs": limits.ackTimeoutMs,
                "maxMessageBytes": limits.maxMessageBytes, "pingIntervalSeconds": limits.pingIntervalSeconds,
                "pongTimeoutSeconds": limits.pongTimeoutSeconds,
            ]]
        case .ack(let ack):
            return ["type": "ack", "runId": ack.runId, "seq": ack.seq, "status": ack.status, "bodySha256": ack.bodySha256,
                    "rank": ack.rank.map { $0 as Any } ?? NSNull()]
        case .error(let error):
            return ["type": "error", "runId": error.runId.map { $0 as Any } ?? NSNull(),
                    "seq": error.seq.map { $0 as Any } ?? NSNull(), "httpStatus": error.httpStatus, "code": error.code,
                    "retryAfterSeconds": error.retryAfterSeconds.map { $0 as Any } ?? NSNull(),
                    "serverTime": error.serverTime.map { $0 as Any } ?? NSNull(), "fatal": error.fatal]
        }
    }

    @Test func serviceMessagesAreParsedStrictly() throws {
        let cases = try #require(Self.vectors["messages"] as? [[String: Any]])
        #expect(cases.count == 30)
        // JSONSerialization drops a leading U+FEFF from strings; the texts are read with the app's own parser.
        let file = try Data(contentsOf: Fixtures.root.appendingPathComponent("report-vectors.json"))
        let texts = try #require(try JSONParser.parse(file)["websocket"]?["messages"]?.array).compactMap { $0["text"]?.string }
        #expect(texts.count == cases.count)
        for (item, text) in zip(cases, texts) {
            let parsed = ReportServiceMessage.parse(Data(text.utf8), maxBytes: item["maxMessageBytes"] as? Int ?? 65_536)
            let got = Self.expected(parsed)
            if let wanted = item["expect"] as? String {
                #expect(got as? String == wanted, "\(item["name"] ?? "")")
            } else {
                #expect((got as? NSDictionary) == (item["expect"] as? NSDictionary), "\(item["name"] ?? ""): \(got)")
            }
        }
        #expect(ReportServiceMessage.parse(Data([0x7B, 0xFF, 0x7D]), maxBytes: 65_536) == nil, "invalid UTF-8")
    }

    @Test func refusedUpgradesAreClassifiedByBodyThenStatus() throws {
        let cases = try #require(Self.vectors["rejections"] as? [[String: Any]])
        #expect(cases.count == 18)
        for item in cases {
            let body = (item["body"] as? String).map { Data($0.utf8) }
            let got = ReportStreamRejection.classify(status: item.int("status"), body: body,
                                                     retryAfter: item["retryAfter"] as? String)
            let expect = try #require(item["expect"] as? [String: Any])
            #expect(got.code == expect["code"] as? String, "\(item)")
            #expect(got.retryAfterSeconds == expect["retryAfterSeconds"] as? Int, "\(item)")
        }
    }

    @Test func latencyPercentilesUseTheNearestRank() throws {
        let cases = try #require(Self.vectors["latency"] as? [[String: Any]])
        #expect(cases.count == 6)
        for item in cases {
            let samples = (item["samples"] as? [Int] ?? []).map(Int64.init)
            #expect(ReportLatency.percentile(samples, 50) == item.int64("p50"), "\(samples.prefix(5))")
            #expect(ReportLatency.percentile(samples, 95) == item.int64("p95"), "\(samples.prefix(5))")
        }
    }
}

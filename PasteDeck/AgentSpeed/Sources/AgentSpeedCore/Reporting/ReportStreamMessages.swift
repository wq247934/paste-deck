import Foundation

/// What the client writes over the WebSocket transport (METRICS 11.9, Connection and Messages): the signed upgrade
/// and one `report` message per body.
public enum ReportStreamMessage {
    /// The four v1 signature headers, in the order of the message.
    public static let signatureHeaders = [
        ReportCanonical.deviceHeader, ReportCanonical.timestampHeader, ReportCanonical.nonceHeader,
        ReportCanonical.signatureHeader,
    ]

    /// `{"type":"report","headers":{…},"body":"…"}` with the body as a JSON string written exactly as the protocol's
    /// examples: `"` and `\` escaped, control characters as `\b \f \n \r \t` or `\u00xx`, everything else (`/` and
    /// non-ASCII included) as is. Nil when a signature header is missing.
    public static func report(headers: [String: String], body: Data) -> String? {
        let lower = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $1 })
        var fields: [String] = []
        for name in signatureHeaders {
            guard let value = lower[name.lowercased()] else { return nil }
            fields.append(ReportJSON.quoted(name) + ":" + ReportJSON.quoted(value))
        }
        let text = String(decoding: body, as: UTF8.self)
        return "{\"type\":\"report\",\"headers\":{" + fields.joined(separator: ",") + "},\"body\":"
            + ReportJSON.quoted(text) + "}"
    }

    /// The message of a signed `POST {api}/v1/reports` request.
    public static func report(_ request: ReportRequest) -> String? {
        report(headers: Dictionary(request.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 }),
               body: request.body)
    }

    /// The size of a report message around its body string: the outer object and four headers of fixed lengths.
    public static let overheadBytes: Int = {
        let headers = [
            ReportCanonical.deviceHeader: String(repeating: "0", count: 36),
            ReportCanonical.timestampHeader: String(repeating: "0", count: 10),
            ReportCanonical.nonceHeader: String(repeating: "0", count: 22),
            ReportCanonical.signatureHeader: String(repeating: "0", count: 86),
        ]
        return report(headers: headers, body: Data())!.utf8.count - 2
    }()

    /// The bytes a body takes inside a report message.
    public static func messageBytes(body: Data) -> Int {
        overheadBytes + ReportJSON.quoted(String(decoding: body, as: UTF8.self)).utf8.count
    }

    /// `bodySha256` of an `ack` (64 lower-case hexadecimal digits).
    public static func bodySha256(_ body: Data) -> String {
        ReportHash.sha256Hex(body)
    }
}

extension ReportRequestBuilder {
    /// The upgrade request (METRICS 11.9, Connection): signed over `GET`, the WebSocket path under `api` and an empty
    /// body, with the subprotocol header; the URL is the `wss` connection URL.
    public func handshake(api: ReportServiceURL, signer: any ReportSigner, timestamp: Int64,
                          nonce: String = ReportCanonical.newNonce()) throws -> ReportRequest {
        var request = try make(method: "GET", url: api.appending(endpoint: ReportStreamSettings.path), body: Data(),
                               signer: signer, timestamp: timestamp, nonce: nonce)
        request.url = api.streamURL
        request.headers.append(.init(name: "Sec-WebSocket-Protocol", value: ReportStreamSettings.subprotocol))
        return request
    }

    /// One report signed like `POST {api}/v1/reports` (a fresh nonce each time), as its message text.
    public func reportMessage(api: ReportServiceURL, body: Data, signer: any ReportSigner, timestamp: Int64,
                              nonce: String = ReportCanonical.newNonce()) throws -> String {
        let request = try make(method: "POST", url: api.appending(endpoint: ReportEndpoint.reports), body: body,
                               signer: signer, timestamp: timestamp, nonce: nonce)
        guard let message = ReportStreamMessage.report(request) else { throw ReportStreamMessageError.headers }
        return message
    }
}

enum ReportStreamMessageError: Error { case headers }

/// `realtime` (METRICS 11.9): only in bodies carried by the WebSocket transport, always their last member.
public struct ReportRealtime: Equatable, Sendable {
    public static let logResolutionMs: Int64 = 1000
    public static let maxAgeMs: Int64 = 900_000

    /// `builtAt − observed` of the window's earliest observation; nil when the window had no new data.
    public var observationAgeMs: Int64?

    public init(observationAgeMs: Int64?) {
        self.observationAgeMs = observationAgeMs.map { min(max($0, 0), Self.maxAgeMs) }
    }

    /// `mixed` when the body carries traffic with status `ok` (sampled), else `log`; `sentAtMs` on the corrected
    /// clock of `sentAt`.
    public func json(mixed: Bool, sentAtMs: Int64) -> ReportJSON {
        .object([
            "sourceMode": .string(mixed ? "mixed" : "log"),
            "observedAt": observationAgeMs.map { .string(ReportInstant.format(unixMs: sentAtMs - $0)) } ?? .null,
            "observationAgeMs": .optionalInt(observationAgeMs),
            "sourceResolutionMs": mixed ? .null : .int(Self.logResolutionMs),
        ])
    }
}

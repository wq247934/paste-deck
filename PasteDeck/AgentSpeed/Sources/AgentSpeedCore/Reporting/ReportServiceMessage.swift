import Foundation

/// A message of the service over the WebSocket transport, parsed strictly (METRICS 11.9, Messages): UTF-8 text, one
/// JSON object without repeated member names or lone surrogates, at most 32 levels deep and `maxMessageBytes` long.
/// `parse` returns nil for an invalid message, which the connection treats as `close 1002`.
public enum ReportServiceMessage: Equatable, Sendable {
    case ready(limits: ReportStreamSettings)
    case ack(Ack)
    case error(Failure)
    /// Another `type`: ignored.
    case other

    public struct Ack: Equatable, Sendable {
        public var runId: String
        public var seq: Int
        /// `accepted` or `duplicate`.
        public var status: String
        public var bodySha256: String
        public var rank: Int?
    }

    public struct Failure: Equatable, Sendable {
        /// Nil for an error of the connection (`run: null`).
        public var runId: String?
        public var seq: Int?
        public var httpStatus: Int
        public var code: String
        public var retryAfterSeconds: Int?
        public var serverTime: Int64?
        public var fatal: Bool
    }

    public static let maxDepth = 32
    static let maxSeq: Int64 = 9_007_199_254_740_991

    public static func parse(_ data: Data, maxBytes: Int) -> ReportServiceMessage? {
        guard let members = object(data, maxBytes: maxBytes), let type = members["type"]?.string else { return nil }
        switch type {
        case "ready":
            guard members["protocol"]?.string == ReportDiscovery.protocolName,
                  members["version"]?.int64 == 1, members["transportVersion"]?.int64 == 1,
                  isInstant(members["serverTime"]) else { return nil }
            var limits = ReportStreamSettings()
            for field in ReportStreamSettings.fields {
                guard let literal = members[field.name]?.literal, literal.isInteger else { return nil }
                limits[keyPath: field.key] = ReportClamp.integer(literal)
            }
            return .ready(limits: limits)
        case "ack":
            guard let (runId, seq) = run(members["run"]),
                  let status = members["status"]?.string, status == "accepted" || status == "duplicate",
                  let digest = members["bodySha256"]?.string, isDigest(digest),
                  isInstant(members["receivedAt"]), isInstant(members["acceptedAt"]),
                  integer(members["processingMs"], 0...900_000) != nil else { return nil }
            var rank: Int?
            if let value = members["rank"], !value.isNull {
                guard let given = integer(value, 1...100_000_000) else { return nil }
                rank = Int(given)
            }
            return .ack(Ack(runId: runId, seq: seq, status: status, bodySha256: digest, rank: rank))
        case "error":
            guard let runValue = members["run"] else { return nil }
            var reportRun: (String, Int)?
            if !runValue.isNull {
                guard let parsed = run(runValue) else { return nil }
                reportRun = parsed
            }
            guard let status = integer(members["httpStatus"], 400...599), let error = members["error"]?.object,
                  let code = error["code"]?.string, ReportReply.isCode(code),
                  let fatal = members["fatal"]?.bool else { return nil }
            var retryAfter: Int64?
            if let value = error["retryAfterSeconds"], !value.isNull {
                guard let given = integer(value, 1...86_400) else { return nil }
                retryAfter = given
            }
            var serverTime: Int64?
            if let value = error["serverTime"], !value.isNull {
                guard let given = integer(value, 0...Int64.max) else { return nil }
                serverTime = given
            }
            return .error(Failure(runId: reportRun?.0, seq: reportRun?.1, httpStatus: Int(status), code: code,
                                  retryAfterSeconds: retryAfter.map { Int($0) }, serverTime: serverTime, fatal: fatal))
        default:
            return .other
        }
    }

    /// One JSON object of at most `maxBytes`, or nil.
    static func object(_ data: Data, maxBytes: Int) -> [String: JSONValue]? {
        guard data.count <= maxBytes,
              let value = try? JSONParser.parse(data, maxDepth: maxDepth, exact: true) else { return nil }
        return value.object
    }

    /// `run` of an `ack` or `error`: `id` of 1–64 characters and `seq` ≥ 1.
    private static func run(_ value: JSONValue?) -> (String, Int)? {
        guard let members = value?.object, let id = members["id"]?.string, (1...64).contains(id.unicodeScalars.count),
              let seq = integer(members["seq"], 1...maxSeq) else { return nil }
        return (id, Int(seq))
    }

    /// An integer (never a fraction or a boolean) within `range`; values beyond 64 bits are out of range.
    private static func integer(_ value: JSONValue?, _ range: ClosedRange<Int64>) -> Int64? {
        guard let literal = value?.literal, literal.isInteger, let number = literal.int64, range.contains(number) else {
            return nil
        }
        return number
    }

    /// `YYYY-MM-DDTHH:MM:SS.sssZ`.
    private static func isInstant(_ value: JSONValue?) -> Bool {
        guard let bytes = value?.string.map({ Array($0.utf8) }), bytes.count == 24 else { return false }
        let pattern = Array("0000-00-00T00:00:00.000Z".utf8)
        for (byte, expected) in zip(bytes, pattern) {
            if expected == UInt8(ascii: "0") {
                guard (48...57).contains(byte) else { return false }
            } else if byte != expected {
                return false
            }
        }
        return true
    }

    private static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// A refused upgrade (METRICS 11.9): the code of its v1 error body, else one implied by its status, and the wait.
public enum ReportStreamRejection {
    public struct Result: Equatable, Sendable {
        /// Nil for a plain failure (`5xx` without `Retry-After`, a `3xx` …).
        public var code: String?
        public var retryAfterSeconds: Int?
    }

    /// `body` is nil when the transport cannot read it (URLSession does not expose it); `retryAfter` is the header.
    public static func classify(status: Int, body: Data?, retryAfter: String?) -> Result {
        let header = retryAfterHeader(retryAfter)
        var code: String?
        var wait: Int?
        if let body, !body.isEmpty, let error = ReportServiceMessage.object(body, maxBytes: 65_536)?["error"]?.object,
           let given = error["code"]?.string, ReportReply.isCode(given) {
            code = given
            if let literal = error["retryAfterSeconds"]?.literal, literal.isInteger, let seconds = literal.int64, seconds >= 1 {
                wait = Int(clamping: seconds)
            }
        }
        if code == nil {
            switch status {
            case 401: code = "signature_invalid"
            case 403: code = "forbidden"
            case 404: code = "unknown_device"
            case 410: code = "gone"
            case 413: code = "payload_too_large"
            case 429: code = "rate_limited"
            case 503 where header != nil: code = "rate_limited"
            case 400..<500: code = "bad_request"
            default: break
            }
        }
        return Result(code: code, retryAfterSeconds: wait ?? header)
    }

    /// Delay seconds only; an HTTP date counts as absent.
    static func retryAfterHeader(_ value: String?) -> Int? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), (1...9).contains(text.utf8.count),
              text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }
}

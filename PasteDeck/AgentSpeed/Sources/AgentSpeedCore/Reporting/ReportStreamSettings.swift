import Foundation

/// The `websocket` object of a discovery document (METRICS 11.9, Availability): the limits of the WebSocket
/// transport. Unlike `limits`, a field of another type or outside its range makes the whole object invalid.
public struct ReportStreamSettings: Equatable, Hashable, Codable, Sendable {
    public static let path = "/v1/reports/ws"
    public static let subprotocol = "agent-speed-report.v1"

    public var minIntervalMs: Int
    public var maxInFlight: Int
    public var ackTimeoutMs: Int
    public var maxMessageBytes: Int
    public var pingIntervalSeconds: Int
    public var pongTimeoutSeconds: Int

    public static let standard = ReportStreamSettings()

    /// The values as given; ranges are checked only when a document is parsed (a `ready` may announce others).
    public init(
        minIntervalMs: Int = 50, maxInFlight: Int = 8, ackTimeoutMs: Int = 2000, maxMessageBytes: Int = 65_536,
        pingIntervalSeconds: Int = 20, pongTimeoutSeconds: Int = 10
    ) {
        self.minIntervalMs = minIntervalMs
        self.maxInFlight = maxInFlight
        self.ackTimeoutMs = ackTimeoutMs
        self.maxMessageBytes = maxMessageBytes
        self.pingIntervalSeconds = pingIntervalSeconds
        self.pongTimeoutSeconds = pongTimeoutSeconds
    }

    /// The six limits in the order of the protocol, with their ranges.
    static var fields: [(name: String, key: WritableKeyPath<ReportStreamSettings, Int>, range: ClosedRange<Int>)] {[
        ("minIntervalMs", \.minIntervalMs, 10...1000),
        ("maxInFlight", \.maxInFlight, 1...64),
        ("ackTimeoutMs", \.ackTimeoutMs, 500...10_000),
        ("maxMessageBytes", \.maxMessageBytes, 32_768...65_536),
        ("pingIntervalSeconds", \.pingIntervalSeconds, 10...60),
        ("pongTimeoutSeconds", \.pongTimeoutSeconds, 5...30),
    ]}

    /// A valid `websocket` object, or nil: the fixed path and subprotocol, optional integers in their ranges, and
    /// `pongTimeoutSeconds` below `pingIntervalSeconds`. Unknown fields are ignored.
    init?(document value: JSONValue?) {
        guard let members = value?.object, members["path"]?.string == Self.path,
              members["subprotocol"]?.string == Self.subprotocol else { return nil }
        var settings = ReportStreamSettings()
        for field in Self.fields {
            guard let given = members[field.name] else { continue }
            guard let literal = given.literal, literal.isInteger, let number = literal.int64,
                  field.range.contains(Int(clamping: number)) else { return nil }
            settings[keyPath: field.key] = Int(number)
        }
        guard settings.pongTimeoutSeconds < settings.pingIntervalSeconds else { return nil }
        self = settings
    }
}

extension ReportServiceURL {
    /// The connection URL of the WebSocket transport (METRICS 11.9): `https` → `wss` (`http` → `ws` only for the
    /// loopback test service), authority and base path kept, plus the WebSocket path.
    public var streamURL: URL {
        URL(string: (isLoopbackHTTP ? "ws" : "wss") + "://" + authority + path + ReportStreamSettings.path)!
    }
}

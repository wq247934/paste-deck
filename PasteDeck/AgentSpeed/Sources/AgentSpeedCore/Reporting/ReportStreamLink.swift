import Foundation

/// What one WebSocket connection tells its owner, in order and only until it ends (METRICS 11.9).
public enum ReportStreamEvent: Equatable, Sendable {
    /// The `101` selected the subprotocol and no extension.
    case opened
    /// A valid message of the service (another `type` is not passed on).
    case message(ReportServiceMessage)
    /// The upgrade was answered without `101`; `retryAfter` is the header as received (the body cannot be read).
    case rejected(status: Int, retryAfter: String?)
    /// The connection ended: the service's close code, `1002` for a protocol violation (no subprotocol, an
    /// extension, a binary, invalid or oversized message), `1006` for the network or a missing Pong.
    case closed(code: Int)
}

/// One connection. After `close` or `abort` it reports nothing more.
public protocol ReportStreamLink: AnyObject, Sendable {
    /// Signs the upgrade off the caller's thread and opens the connection; a failed signature ends the connection
    /// and calls `onSigningFailure` instead of reporting an event.
    func start(_ makeRequest: @escaping @Sendable () throws -> ReportRequest)
    /// Signs and writes one text message after the ones before it; a failed write ends the connection, a failed
    /// signature calls `onSigningFailure`.
    func send(_ makeText: @escaping @Sendable () throws -> String)
    /// `close 1000`.
    func close()
    /// Drops the connection without waiting.
    func abort()
}

/// The network seam of the WebSocket transport; tests use the reference server.
public protocol ReportStreamTransport: Sendable {
    /// A connection whose events (and signing failures) arrive on `queue`; nothing happens before `start`.
    func link(
        settings: ReportStreamSettings, queue: DispatchQueue,
        onEvent: @escaping @Sendable (ReportStreamEvent) -> Void,
        onSigningFailure: @escaping @Sendable () -> Void
    ) -> any ReportStreamLink
}

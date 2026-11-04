import Foundation

/// What signs the upgrade and each report of a stream (METRICS 11.9), captured on the main actor and used off it:
/// the API base, the device's headers and API key, the key, and the session's clock correction (METRICS 11.6).
public struct ReportStreamCredentials: Sendable {
    public var api: ReportServiceURL
    public var builder: ReportRequestBuilder
    public var signer: any ReportSigner
    /// Seconds added to the local clock.
    public var clockCorrection: Int64

    public init(api: ReportServiceURL, builder: ReportRequestBuilder, signer: any ReportSigner, clockCorrection: Int64) {
        self.api = api
        self.builder = builder
        self.signer = signer
        self.clockCorrection = clockCorrection
    }

    /// The signed upgrade, with a fresh timestamp and nonce.
    public func handshake() throws -> ReportRequest {
        try builder.handshake(api: api, signer: signer, timestamp: timestamp)
    }

    /// One `report` message, with a fresh timestamp and nonce.
    public func message(body: Data) throws -> String {
        try builder.reportMessage(api: api, body: body, signer: signer, timestamp: timestamp)
    }

    private var timestamp: Int64 { Int64(Date().timeIntervalSince1970) + clockCorrection }
}

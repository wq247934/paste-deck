import Foundation

/// Answer latencies of delivered reports (METRICS 11.9, Latency): `answer time − observed` of the last 512 deliveries
/// that carried an observation, with their nearest-rank percentiles.
public struct ReportLatency: Equatable, Sendable {
    public static let capacity = 512

    public private(set) var samples: [Int64] = []

    public init() {}

    public mutating func add(_ sample: Int64) {
        samples.append(sample)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public var p50: Int64? { Self.percentile(samples, 50) }
    public var p95: Int64? { Self.percentile(samples, 95) }

    /// Nearest rank: the smallest sample with at least `p` % of the samples at or below it.
    public static func percentile(_ samples: [Int64], _ p: Int) -> Int64? {
        guard !samples.isEmpty else { return nil }
        let ordered = samples.sorted()
        let rank = max(1, (p * ordered.count + 99) / 100)
        return ordered[rank - 1]
    }
}

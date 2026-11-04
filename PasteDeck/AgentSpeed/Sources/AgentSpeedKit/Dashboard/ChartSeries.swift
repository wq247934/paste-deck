import AgentSpeedCore
import Foundation

/// Visible span of the live chart.
enum ChartRange: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    static let storageKey = "dashboard.chartRange"

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// Seconds averaged into one plotted sample; the five-minute view halves the density to stay calm.
    var bucketSeconds: Int { self == .fiveMinutes ? 2 : 1 }

    var titleKey: String {
        switch self {
        case .oneMinute: "mac.dashboard.range.1m"
        case .twoMinutes: "mac.dashboard.range.2m"
        case .fiveMinutes: "mac.dashboard.range.5m"
        }
    }
}

struct ChartSample: Equatable, Sendable {
    /// Unix seconds at the sample's center.
    var time: TimeInterval
    var measured: Double
    var estimated: Double
    var isLive: Bool

    var total: Double { measured + estimated }
}

/// The history buckets of one snapshot, reduced to what the chart plots.
struct ChartSeries: Equatable, Sendable {
    var samples: [ChartSample]
    var start: TimeInterval
    var end: TimeInterval
    /// Highest total among visible samples.
    var maxTotal: Double
    /// Index runs whose in-flight estimate is noticeable; drawn translucent with a dashed top line.
    var estimatedRuns: [ClosedRange<Int>]

    var hasEstimate: Bool { !estimatedRuns.isEmpty }
    var live: ChartSample? { samples.last }

    init(snapshot: SpeedSnapshot, range: ChartRange, metric: SpeedMetric) {
        let now = snapshot.timestamp.timeIntervalSince1970
        let span = range.seconds
        let group = range.bucketSeconds
        let groupSpan = TimeInterval(group)
        start = now - span
        end = now

        var samples: [ChartSample] = []
        samples.reserveCapacity(snapshot.history.count / group + 2)
        var key: Int?
        var measured = 0.0, estimated = 0.0, count = 0

        func flush() {
            guard let key, count > 0 else { return }
            samples.append(ChartSample(
                time: TimeInterval(key * group) + groupSpan / 2,
                measured: measured / Double(count),
                estimated: estimated / Double(count),
                isLive: false
            ))
        }

        for point in snapshot.history {
            let second = point.time.timeIntervalSince1970
            // The current second is still filling up; the live rate stands in for it at the right edge.
            guard second + 1 <= now + 0.001, second + groupSpan >= start - groupSpan else { continue }
            let pointKey = Int((second / groupSpan).rounded(.down))
            if pointKey != key {
                flush()
                key = pointKey
                measured = 0
                estimated = 0
                count = 0
            }
            measured += Self.sanitized(point.measured.value(for: metric))
            estimated += Self.sanitized(point.estimated.value(for: metric))
            count += 1
        }
        flush()

        if !snapshot.history.isEmpty || snapshot.live != .zero {
            let live = Self.sanitized(snapshot.live.value(for: metric))
            let share = snapshot.liveEstimatedShare.isFinite ? snapshot.liveEstimatedShare.clamped(to: 0...1) : 0
            samples.append(ChartSample(time: now, measured: live * (1 - share), estimated: live * share, isLive: true))
        }

        let visible = samples.lazy.filter { $0.time >= now - span }
        let maxTotal = visible.map(\.total).max() ?? 0
        self.maxTotal = maxTotal
        self.samples = samples
        estimatedRuns = Self.runs(in: samples, threshold: max(0.05, maxTotal * 0.004))
    }

    /// Nearest sample to a time, restricted to the visible window.
    func nearestIndex(to time: TimeInterval) -> Int? {
        var best: Int?
        var bestDistance = TimeInterval.infinity
        for (index, sample) in samples.enumerated() where sample.time >= start - 0.5 {
            let distance = abs(sample.time - time)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func sanitized(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func runs(in samples: [ChartSample], threshold: Double) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for (index, sample) in samples.enumerated() {
            if sample.estimated > threshold {
                if runStart == nil { runStart = index }
            } else if let first = runStart {
                runs.append(first...(index - 1))
                runStart = nil
            }
        }
        if let first = runStart { runs.append(first...(samples.count - 1)) }
        return runs
    }
}

/// The y-axis top: a "nice" ceiling with hysteresis so the scale settles instead of breathing with every bucket.
enum ChartDomain {
    static let minimum = 10.0
    /// A peak this far above the data still pulls the scale up so its line can be shown.
    static let peakReach = 1.6

    static func target(maxTotal: Double, peak: Double) -> Double {
        var top = nice(max(maxTotal * 1.12, minimum))
        if peak > top, peak <= top * peakReach {
            top = nice(peak * 1.1)
        }
        return top
    }

    /// Grows immediately, shrinks only once the data clearly fits a smaller scale.
    static func settle(current: Double?, target: Double) -> Double {
        guard let current, current > 0 else { return target }
        if target > current || target <= current * 0.62 { return target }
        return current
    }

    static func nice(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return minimum }
        let magnitude = pow(10, (log10(value)).rounded(.down))
        let fraction = value / magnitude
        let steps: [Double] = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        let step = steps.first { fraction <= $0 + 1e-9 } ?? 10
        return step * magnitude
    }
}

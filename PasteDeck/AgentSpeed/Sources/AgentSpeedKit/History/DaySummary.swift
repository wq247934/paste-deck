import AgentSpeedCore
import Foundation

/// One source's output and cost on one day, for stacking the chart.
struct SourceOutput: Equatable, Sendable {
    let source: SourceKind
    let output: Int
    var requests = 0
    /// The source's cost as counted: an excluded subscription source adds nothing (METRICS 9.4).
    var cost = HistoryCost.none
}

/// A model's cost on a day over the counted sources (METRICS 9.7): nil without cost data.
struct ModelCost: Equatable, Sendable {
    var cost: CostTally?
    /// Requests of the model from counted sources; 0 when only subscription sources used it.
    var requests = 0
}

/// One calendar day for the selected source, or summed over every source (METRICS 8). Speeds are always
/// Σ measured output ÷ Σ measured time, never an average of averages.
struct DaySummary: Identifiable, Equatable, Sendable {
    var id: DayKey { day }
    let day: DayKey
    let requests: Int
    let input: Int
    let cachedInput: Int
    let cacheWriteInput: Int
    let output: Int
    let reasoning: Int
    let measuredOutput: Int
    let measuredMs: Int64
    let unfinalized: Int
    let agents: Int
    /// The day's overall live peak; only days observed live have one, and only the all-sources view shows it.
    let peak: Double?
    /// Every model of the day, most output first.
    let models: [ModelUsage]
    /// Output per source (non-zero output or requests only), in `SourceKind` order.
    let sources: [SourceOutput]
    /// The day's cost over the counted sources (DESIGN 9: subscriptions left out unless included).
    var cost = HistoryCost.none
    /// Every source's cost, for the CSV (subscription exclusion does not apply there); nil without cost data.
    var totalCost: CostTally?
    /// The price table version bound to the day (METRICS 9.7).
    var priceVersion: Int?
    /// Per model over the counted sources.
    var modelCosts: [String: ModelCost] = [:]
    /// The day's network traffic (METRICS 10.9); nil before measuring began.
    var traffic: DayTraffic?

    /// A day with agent traffic but no token usage (DESIGN 10): listed, every token figure 0.
    static func trafficOnly(_ day: DayKey) -> DaySummary {
        DaySummary(day: day, requests: 0, input: 0, cachedInput: 0, cacheWriteInput: 0, output: 0, reasoning: 0, measuredOutput: 0,
                   measuredMs: 0, unfinalized: 0, agents: 0, peak: nil, models: [], sources: [])
    }

    /// The day has token usage (as `HistoryAggregator.hasUsage` for a stored record); a traffic-only day has none.
    var hasUsage: Bool { requests > 0 || output > 0 || input > 0 }

    /// Output tok/s over the day's measured responses.
    var averageSpeed: Double? {
        measuredMs > 0 && measuredOutput > 0 ? Double(measuredOutput) / (Double(measuredMs) / 1000) : nil
    }

    /// Share of input served from the cache (cachedInput ÷ input).
    var cacheHitRatio: Double? {
        input > 0 ? (Double(cachedInput) / Double(input)).clamped(to: 0...1) : nil
    }

    func output(of source: SourceKind) -> Int {
        sources.first { $0.source == source }?.output ?? 0
    }

    /// The counted, known cost of `source` (0 when excluded or unpriced).
    func costMicroUsd(of source: SourceKind) -> Int64 {
        sources.first { $0.source == source }?.cost.microUsd ?? 0
    }

    /// The day's value of a chart metric: output tokens, or known micro-USD.
    func value(_ metric: HistoryChartMetric) -> Double {
        switch metric {
        case .output: Double(output)
        case .cost: Double(cost.microUsd)
        case .traffic: Double(traffic?.shown.sum ?? 0)
        }
    }
}

/// Totals over a run of days.
struct HistoryTotals: Equatable, Sendable {
    var requests = 0
    var input = 0
    var cachedInput = 0
    var output = 0
    var measuredOutput = 0
    var measuredMs: Int64 = 0
    var activeDays = 0
    /// The day with the most output (the newest of equals).
    var busiestDay: DaySummary?
    /// Σ of the days' costs (METRICS 9.8: a range total is the sum of its days).
    var cost = HistoryCost.none
    /// Days that have cost data (`history.summary.costPerDay` divides by them).
    var costDays = 0

    static let empty = HistoryTotals()

    /// Σ measured output ÷ Σ measured time over the whole range.
    var averageSpeed: Double? {
        measuredMs > 0 && measuredOutput > 0 ? Double(measuredOutput) / (Double(measuredMs) / 1000) : nil
    }

    var hasData: Bool { activeDays > 0 }
}

import AgentSpeedCore
import Foundation

/// One bar of a single day's breakdown: a source with all sources, else one model of the selected source.
struct BreakdownItem: Identifiable, Equatable, Sendable {
    enum Subject: Hashable, Sendable {
        case source(SourceKind)
        case model(String)
        /// Output the day's records do not attribute to a named model.
        case otherModels
    }

    var id: Subject { subject }
    let subject: Subject
    let output: Int
    let requests: Int
    /// Share of the day's output (or cost, for the cost metric); the items' shares add up to 1.
    let share: Double
    /// The metric relative to the largest item (the bar length, 0…1).
    let scale: Double
    /// Σ measured output ÷ Σ measured time (per source, or per model, METRICS 8); nil when nothing was measured.
    let averageSpeed: Double?
    /// The item's cost as counted (an excluded subscription source adds nothing, METRICS 9.4).
    var cost = HistoryCost.none
    /// The source's traffic of the day as displayed (DESIGN 10); nil for models and before measuring began.
    var traffic: TrafficBytes?
}

/// A single day split by source (all sources) or by model (one source), most output first (DESIGN 4b, item 1).
struct DayBreakdown: Equatable, Sendable {
    enum Kind: Sendable { case bySource, byModel }

    let day: DayKey
    let kind: Kind
    let items: [BreakdownItem]
    /// The measure that sorts and sizes the bars (DESIGN 9).
    var metric: HistoryChartMetric = .output

    var output: Int { items.reduce(0) { $0 + $1.output } }
    var isEmpty: Bool { items.isEmpty }

    var titleKey: String {
        switch kind {
        case .bySource: "history.chart.bySource"
        case .byModel: "history.chart.byModel"
        }
    }
}

enum HistoryBreakdown {
    /// `day` split by source when `source` is nil, else by the models of `source`, sorted and sized by `metric`.
    static func build(
        _ usage: [DailyUsage], day: DayKey, source: SourceKind?, metric: HistoryChartMetric = .output, excluded: Set<SourceKind> = [],
        traffic: DayTraffic? = nil
    ) -> DayBreakdown {
        let records = usage.filter { record in
            (source == nil || record.source == source) && HistoryAggregator.hasUsage(record) && DayKey(record.day) == day
        }
        if source == nil {
            return DayBreakdown(day: day, kind: .bySource,
                                items: bySource(records, excluded: excluded, metric: metric, traffic: traffic?.bySource ?? [:]),
                                metric: metric)
        }
        // A day of one source with traffic but no token usage has no models: it shows the source's one bar (DESIGN 10).
        if let source, metric == .traffic, records.isEmpty, let bytes = traffic?.bySource[source] {
            return DayBreakdown(day: day, kind: .bySource, items: bySource([], excluded: excluded, metric: metric, traffic: [source: bytes]),
                                metric: metric)
        }
        return DayBreakdown(day: day, kind: .byModel, items: byModel(records, metric: metric), metric: metric)
    }

    private struct Tally {
        var output = 0
        var requests = 0
        var measuredOutput = 0
        var measuredMs: Int64 = 0
        var cost = HistoryCost.none
        var traffic: TrafficBytes?

        mutating func add(_ other: Tally) {
            output += other.output
            requests += other.requests
            measuredOutput += other.measuredOutput
            measuredMs += other.measuredMs
            cost = cost.adding(other.cost)
        }
    }

    private static func bySource(_ records: [DailyUsage], excluded: Set<SourceKind>, metric: HistoryChartMetric,
                                 traffic: [SourceKind: TrafficBytes]) -> [BreakdownItem] {
        var tallies: [BreakdownItem.Subject: Tally] = [:]
        for (kind, bytes) in traffic { tallies[.source(kind), default: Tally()].traffic = bytes }
        for record in records {
            var tally = tallies[.source(record.source)] ?? Tally()
            tally.output += max(0, record.totals.output)
            tally.requests += max(0, record.totals.requests)
            tally.measuredOutput += max(0, record.measuredOutput)
            tally.measuredMs += max(0, record.measuredMs)
            tally.cost = tally.cost.adding(HistoryAggregator.cost(of: record, excluded: excluded))
            tallies[.source(record.source)] = tally
        }
        return items(tallies, metric: metric)
    }

    /// Each model with its own measured output and time; what no named model accounts for (responses without a
    /// model, rows stored before per-model time existed) is gathered under `otherModels`.
    /// A model of one source (one source is selected directly, so nothing is excluded).
    private static func byModel(_ records: [DailyUsage], metric: HistoryChartMetric) -> [BreakdownItem] {
        var tallies: [BreakdownItem.Subject: Tally] = [:]
        for record in records {
            var named = Tally()
            var namedCost = HistoryCost.none
            for model in record.models {
                let name = model.model.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, model.output > 0 || model.requests > 0 else { continue }
                // A contribution stored before costs existed has no model costs: they stay unavailable.
                let cost = HistoryCost(tally: model.cost, requests: max(0, model.requests), excluded: [])
                let part = Tally(output: max(0, model.output), requests: max(0, model.requests),
                                 measuredOutput: max(0, model.measuredOutput), measuredMs: max(0, model.measuredMs), cost: cost)
                tallies[.model(name), default: Tally()].add(part)
                named.add(part)
                namedCost = namedCost.adding(cost)
            }
            let restRequests = max(0, record.totals.requests - named.requests)
            let restCost: CostTally? = record.cost.map { tally in
                CostTally(costMicroUsd: max(0, tally.costMicroUsd - (namedCost.tally?.costMicroUsd ?? 0)),
                          unpricedRequests: max(0, tally.unpricedRequests - (namedCost.tally?.unpricedRequests ?? 0)))
            }
            let rest = Tally(
                output: max(0, record.totals.output - named.output),
                requests: restRequests,
                measuredOutput: max(0, record.measuredOutput - named.measuredOutput),
                measuredMs: max(0, record.measuredMs - named.measuredMs),
                cost: HistoryCost(tally: restCost, requests: restRequests, excluded: [])
            )
            if rest.output > 0 || (metric == .cost && rest.cost.microUsd > 0) { tallies[.otherModels, default: Tally()].add(rest) }
        }
        return items(tallies, metric: metric)
    }

    private static func items(_ tallies: [BreakdownItem.Subject: Tally], metric: HistoryChartMetric) -> [BreakdownItem] {
        // Models have no traffic of their own: a by-model breakdown keeps sizing by output.
        let byTraffic = metric == .traffic && tallies.keys.contains { if case .source = $0 { true } else { false } }
        func value(_ tally: Tally) -> Double {
            switch metric {
            case .output: Double(tally.output)
            case .cost: Double(tally.cost.microUsd)
            case .traffic: byTraffic ? Double(tally.traffic?.sum ?? 0) : Double(tally.output)
            }
        }
        let total = tallies.values.reduce(0) { $0 + value($1) }
        let largest = tallies.values.map(value).max() ?? 0
        return tallies
            .map { subject, tally in
                let speed = HistoryAggregator.speed(measuredOutput: tally.measuredOutput, measuredMs: tally.measuredMs)
                return BreakdownItem(
                    subject: subject,
                    output: tally.output,
                    requests: tally.requests,
                    share: total > 0 ? value(tally) / total : 0,
                    scale: largest > 0 ? value(tally) / largest : 0,
                    averageSpeed: speed,
                    cost: tally.cost,
                    traffic: tally.traffic
                )
            }
            .sorted { precedes($0, $1, metric: metric) }
    }

    /// Most of the metric first, then most output, most requests, then source order or model name; other models
    /// always last.
    private static func precedes(_ lhs: BreakdownItem, _ rhs: BreakdownItem, metric: HistoryChartMetric) -> Bool {
        if (lhs.subject == .otherModels) != (rhs.subject == .otherModels) { return rhs.subject == .otherModels }
        if metric == .cost, lhs.cost.microUsd != rhs.cost.microUsd { return lhs.cost.microUsd > rhs.cost.microUsd }
        if metric == .traffic, let a = lhs.traffic?.sum, let b = rhs.traffic?.sum, a != b { return a > b }
        if metric == .traffic, (lhs.traffic == nil) != (rhs.traffic == nil) { return lhs.traffic != nil }
        if lhs.output != rhs.output { return lhs.output > rhs.output }
        if lhs.requests != rhs.requests { return lhs.requests > rhs.requests }
        switch (lhs.subject, rhs.subject) {
        case let (.source(a), .source(b)):
            return (SourceKind.allCases.firstIndex(of: a) ?? 0) < (SourceKind.allCases.firstIndex(of: b) ?? 0)
        case let (.model(a), .model(b)):
            return a.localizedStandardCompare(b) == .orderedAscending
        default:
            return false
        }
    }
}

import AgentSpeedCore
import Foundation

/// Evenly spaced axis values from 0 to `max`.
struct AxisTicks: Equatable, Sendable {
    let step: Double
    let intervals: Int

    var max: Double { step * Double(intervals) }
    var values: [Double] { (0...intervals).map { step * Double($0) } }
}

/// Month rules and labels plus day labels of the daily chart, as day indices into the range.
struct ChartAxisMarks: Equatable, Sendable {
    enum Kind: Sendable { case month, year }

    struct MonthLabel: Equatable, Sendable {
        let index: Int
        let day: DayKey
        let kind: Kind
    }

    /// First day of each month after the range start (a faint vertical rule).
    let rules: [Int]
    let months: [MonthLabel]
    let days: [Int]
}

/// Scales, ticks and layout of the Usage History chart (DESIGN 4b, item 3).
enum HistoryChartMath {
    private static let niceSteps: [Double] = [1, 2, 2.5, 5, 10]
    private static let dayLabelSteps = [1, 2, 7, 14]
    private static let monthLabelSteps = [1, 2, 3, 6, 12]

    /// Smallest 1/2/2.5/5 × 10ⁿ step that is at least `value`.
    static func niceStep(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        for nice in niceSteps where nice * magnitude >= value * (1 - 1e-9) {
            return nice * magnitude
        }
        return 10 * magnitude
    }

    /// Ticks for 0…`dataMax` with at most `maxIntervals` intervals.
    static func ticks(_ dataMax: Double, maxIntervals: Int = 4) -> AxisTicks {
        let maxIntervals = Swift.max(1, maxIntervals)
        guard dataMax.isFinite, dataMax > 0 else { return AxisTicks(step: 1, intervals: maxIntervals) }
        let step = niceStep(dataMax / Double(maxIntervals))
        let intervals = Int(ceil(dataMax / step - 1e-9)).clamped(to: 1...maxIntervals)
        return AxisTicks(step: step, intervals: intervals)
    }

    /// Ticks for a secondary axis that share the primary axis' grid lines: exactly `intervals` intervals with the
    /// smallest nice step that fits `dataMax`.
    static func alignedTicks(_ dataMax: Double, intervals: Int) -> AxisTicks {
        let intervals = Swift.max(1, intervals)
        guard dataMax.isFinite, dataMax > 0 else { return AxisTicks(step: 1, intervals: intervals) }
        return AxisTicks(step: niceStep(dataMax / Double(intervals)), intervals: intervals)
    }

    /// Stacking order: the source with the most output (or cost) in the range first (drawn at the bottom).
    static func stackOrder(_ days: [DaySummary], metric: HistoryChartMetric = .output) -> [SourceKind] {
        var totals: [SourceKind: Int64] = [:]
        for day in days {
            for entry in day.sources {
                totals[entry.source, default: 0] += metric == .output ? Int64(entry.output) : entry.cost.microUsd
            }
        }
        return totals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return SourceKind.allCases.firstIndex(of: lhs.key) ?? 0 < SourceKind.allCases.firstIndex(of: rhs.key) ?? 0
            }
            .map(\.key)
    }

    /// Runs of consecutive days that have a value; the speed line breaks between runs.
    static func runs(_ values: [Double?]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for index in 0...values.count {
            let present = index < values.count && (values[index].map(\.isFinite) ?? false)
            if present, start == nil {
                start = index
            } else if !present, let first = start {
                runs.append(first..<index)
                start = nil
            }
        }
        return runs
    }

    /// Month rules and labels plus day labels for a range drawn with `slot` points per day. Labels are thinned so
    /// neighbours stay at least `minSpacing` apart. Daily or every-other-day labels end on the last day; weekly ones
    /// sit on the first day of each week (`weekStart`, 1 = Sunday, as the locale starts weeks).
    static func marks(_ range: DayRange, slot: Double, weekStart: Int = 1, minSpacing: Double = 44) -> ChartAxisMarks {
        let count = range.count
        guard count > 0, slot.isFinite, slot > 0 else { return ChartAxisMarks(rules: [], months: [], days: []) }
        let boundaries = (1..<Swift.max(count, 1)).filter { range.day(at: $0).day == 1 }
        let monthStep = monthLabelSteps.first { 30.4 * Double($0) * slot >= minSpacing } ?? 12
        let labelled = boundaries.filter { (range.day(at: $0).month - 1) % monthStep == 0 }
        var months = labelled.map { index in
            let day = range.day(at: index)
            return ChartAxisMarks.MonthLabel(index: index, day: day, kind: day.month == 1 ? .year : .month)
        }
        if months.first.map({ Double($0.index) * slot >= minSpacing * 1.25 }) ?? true {
            months.insert(ChartAxisMarks.MonthLabel(index: 0, day: range.start, kind: .month), at: 0)
        }
        let rules = monthStep == 1 || 30.4 * slot >= 6 ? boundaries : labelled

        var days: [Int] = []
        if let dayStep = dayLabelSteps.first(where: { Double($0) * slot >= minSpacing * 0.75 }) {
            if dayStep >= 7, let first = (0..<Swift.min(7, count)).first(where: { range.day(at: $0).weekday == weekStart }) {
                days = Array(stride(from: first, to: count, by: dayStep))
            } else {
                days = Array(stride(from: count - 1, through: 0, by: -dayStep).reversed())
            }
        }
        return ChartAxisMarks(rules: rules, months: months, days: days)
    }
}

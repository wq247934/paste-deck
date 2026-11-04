import Foundation

/// One row of the history's effort or speed section (DESIGN 4b, 3b): a value summed over models, providers and
/// evidence.
public struct ModeHistoryRow: Equatable, Sendable, Identifiable {
    public struct ModelOutput: Equatable, Sendable {
        public var model: String
        public var output: Int
    }

    public var mode: String
    public var requests = 0
    public var output = 0
    public var measuredOutput = 0
    public var measuredMs: Int64 = 0
    /// Output per model, largest first.
    public var models: [ModelOutput] = []

    public var id: String { mode }
    public var isUnknown: Bool { mode == "unknown" }
    public var averageSpeed: Double? { measuredMs > 0 ? Double(measuredOutput) / (Double(measuredMs) / 1000) : nil }

    public init(mode: String) {
        self.mode = mode
    }
}

public enum ModeHistoryBreakdown {
    /// The rows of `kind` over `days` in display order, unknown last; they add up to the days' totals. With no known
    /// value only the unknown row remains (empty when there are no days).
    public static func rows(_ days: [DailyUsage], kind: ExecutionModeKind) -> [ModeHistoryRow] {
        var rows: [String: ModeHistoryRow] = [:]
        var models: [String: [String: Int]] = [:]
        for day in days {
            for usage in day.modeBreakdown where usage.attribution.kind == kind {
                let mode = usage.attribution.mode
                var row = rows[mode] ?? ModeHistoryRow(mode: mode)
                row.requests = row.requests.saturatingAdd(usage.requests)
                row.output = row.output.saturatingAdd(usage.output)
                row.measuredOutput = row.measuredOutput.saturatingAdd(usage.measuredOutput)
                let sum = row.measuredMs.addingReportingOverflow(usage.measuredMs)
                row.measuredMs = sum.overflow ? .max : sum.partialValue
                rows[mode] = row
                if usage.output > 0 {
                    models[mode, default: [:]][usage.model] = (models[mode]?[usage.model] ?? 0).saturatingAdd(usage.output)
                }
            }
        }
        rows = rows.filter { $0.value.isUnknown || $0.value.requests > 0 || $0.value.output > 0 }
        if rows.isEmpty { rows["unknown"] = ModeHistoryRow(mode: "unknown") }
        if let unknown = rows["unknown"], unknown.requests == 0, unknown.output == 0, rows.count > 1 {
            rows["unknown"] = nil
        }
        return ModeDisplay.ordered(Array(rows.keys), kind: kind).compactMap { mode in
            guard var row = rows[mode] else { return nil }
            row.models = (models[mode] ?? [:])
                .map { ModeHistoryRow.ModelOutput(model: $0.key, output: $0.value) }
                .sorted { $0.output == $1.output ? $0.model < $1.model : $0.output > $1.output }
            return row
        }
    }
}

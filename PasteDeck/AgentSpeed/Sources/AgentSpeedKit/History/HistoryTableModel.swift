import AgentSpeedCore
import Foundation

enum HistoryColumn: String, CaseIterable, Identifiable, Sendable {
    case date, requests, output, input, cost, traffic, cacheHit, speed, peak, agents, models

    var id: String { rawValue }

    var headerKey: String {
        switch self {
        case .date: "history.table.date"
        case .requests: "history.table.requests"
        case .output: "history.table.output"
        case .input: "history.table.input"
        case .cost: "history.table.cost"
        case .traffic: "history.table.traffic"
        case .cacheHit: "history.table.cacheHit"
        case .speed: "history.table.speed"
        case .peak: "history.table.peak"
        case .agents: "history.table.agents"
        case .models: "history.table.models"
        }
    }

    /// Numbers are right-aligned; the date and the model names are not.
    var isNumeric: Bool { self != .date && self != .models }

    /// The first click on a header sorts largest (or newest) first; model names sort A→Z.
    var defaultDescending: Bool { self != .models }

    /// Columns of the table; the peak only exists for all sources (METRICS 8); traffic while it is measured or stored.
    static func visible(allSources: Bool, traffic: Bool = false) -> [HistoryColumn] {
        allCases.filter { (allSources || $0 != .peak) && (traffic || $0 != .traffic) }
    }
}

struct HistorySort: Equatable, Sendable {
    var column: HistoryColumn = .date
    var descending = true

    /// Clicking `column`: flips the order of the current column, else starts the new one in its default order.
    func toggled(_ column: HistoryColumn) -> HistorySort {
        column == self.column
            ? HistorySort(column: column, descending: !descending)
            : HistorySort(column: column, descending: column.defaultDescending)
    }
}

/// Sorting, cell text and copied text of the daily table (DESIGN 4b, item 4).
@MainActor
enum HistoryTable {
    /// Stable sort. Days without a value in the column (no measured speed, no peak, no models) always come last;
    /// ties keep the newest day first.
    static func sort(_ rows: [DaySummary], by sort: HistorySort) -> [DaySummary] {
        let newestFirst: (DaySummary, DaySummary) -> Bool = { $0.day > $1.day }
        if sort.column == .models {
            let present = rows.filter { !$0.models.isEmpty }.sorted { lhs, rhs in
                let order = lhs.models[0].model.localizedCaseInsensitiveCompare(rhs.models[0].model)
                if order == .orderedSame { return newestFirst(lhs, rhs) }
                return sort.descending ? order == .orderedDescending : order == .orderedAscending
            }
            return present + rows.filter(\.models.isEmpty).sorted(by: newestFirst)
        }
        let keyed = rows.map { ($0, key($0, sort.column)) }
        let present = keyed.compactMap { row, key in key.map { (row, $0) } }.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return newestFirst(lhs.0, rhs.0) }
            return sort.descending ? lhs.1 > rhs.1 : lhs.1 < rhs.1
        }
        let missing = keyed.filter { $0.1 == nil }.map(\.0).sorted(by: newestFirst)
        return present.map(\.0) + missing
    }

    static func cell(_ row: DaySummary, _ column: HistoryColumn, today: DayKey, money: HistoryMoney, _ l10n: Localizer) -> String {
        switch column {
        case .date: HistoryText.tableDate(row.day, today: today, l10n)
        case .requests: HistoryText.fullNumber(row.requests, l10n)
        case .output: SpeedFormat.tokens(row.output)
        case .input: SpeedFormat.tokens(row.input)
        case .cost: money.display(row.cost, subscriptionTag: l10n("cost.subscription.tag"))
        case .traffic: row.traffic.map { TrafficText(l10n: l10n, bits: false).pair($0.shown) } ?? "–"
        case .cacheHit: HistoryText.percent(row.cacheHitRatio)
        case .speed: row.averageSpeed.map(SpeedFormat.speed) ?? l10n("history.noSpeed")
        case .peak: row.peak.map(SpeedFormat.speed) ?? "–"
        case .agents: HistoryText.fullNumber(row.agents, l10n)
        case .models: HistoryText.topModels(row.models, l10n)
        }
    }

    /// The exact value behind a compact cell, for its tooltip; nil when the cell already is exact.
    static func fullCell(_ row: DaySummary, _ column: HistoryColumn, money: HistoryMoney, _ l10n: Localizer) -> String? {
        switch column {
        case .date: HistoryText.longDate(row.day, l10n)
        case .output: HistoryText.fullNumber(row.output, l10n)
        case .input: HistoryText.fullNumber(row.input, l10n)
        case .cost: costTooltip(row.cost, money: money, l10n)
        case .traffic: trafficTooltip(row.traffic, l10n)
        case .speed: row.averageSpeed.map { HistoryText.fullSpeed($0, l10n) }
        case .peak: row.peak.map { HistoryText.fullSpeed($0, l10n) }
        case .models: row.models.isEmpty ? nil : row.models.map { HistoryText.modelWithSpeed($0, l10n) }.joined(separator: "\n")
        case .requests, .cacheHit, .agents: nil
        }
    }

    /// The traffic cell's tooltip: not recorded before measuring began; else the tools' part and the recorded time of a
    /// partial day; nil when there is nothing to add (as on Windows).
    static func trafficTooltip(_ traffic: DayTraffic?, _ l10n: Localizer) -> String? {
        guard let traffic else { return l10n("history.traffic.notRecorded") }
        let lines = HistoryText.trafficNotes(traffic, machine: false, l10n)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The cost cell's tooltip: the amount with US dollars beside another currency, and why a value is partial or
    /// missing (`history.unpricedDay`, `history.costUnavailable`, the excluded subscriptions).
    static func costTooltip(_ cost: HistoryCost, money: HistoryMoney, _ l10n: Localizer) -> String? {
        var lines: [String] = []
        if case .priced(let micro, let partial) = cost.kind { lines.append((partial ? "≥" : "") + money.amountWithUSD(micro)) }
        if let note = HistoryText.costNote(cost, l10n) { lines.append(note) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Rows as tab-separated text with a header line (pastes into a spreadsheet as a table). Counts are exact.
    static func copyText(_ rows: [DaySummary], columns: [HistoryColumn], today: DayKey, money: HistoryMoney, _ l10n: Localizer) -> String {
        let header = columns.map { l10n($0.headerKey) }.joined(separator: "\t")
        let lines = rows.map { row in
            columns.map { column -> String in
                switch column {
                case .output: HistoryText.fullNumber(row.output, l10n)
                case .input: HistoryText.fullNumber(row.input, l10n)
                case .models: row.models.map(\.model).joined(separator: ", ")
                default: cell(row, column, today: today, money: money, l10n)
                }
            }.joined(separator: "\t")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    private static func key(_ row: DaySummary, _ column: HistoryColumn) -> Double? {
        switch column {
        case .date: Double(row.day.ordinal)
        case .requests: Double(row.requests)
        case .output: Double(row.output)
        case .input: Double(row.input)
        case .cost: row.cost.sortValue
        case .traffic: row.traffic.map { Double($0.shown.sum) }
        case .cacheHit: row.cacheHitRatio
        case .speed: row.averageSpeed
        case .peak: row.peak
        case .agents: Double(row.agents)
        case .models: nil
        }
    }
}

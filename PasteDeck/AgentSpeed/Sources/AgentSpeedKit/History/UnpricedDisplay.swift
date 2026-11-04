import AgentSpeedCore
import Foundation

/// The words of the unknown-prices popover and of Settings → Cost (DESIGN 9 *Unknown prices*), kept apart from the
/// views so logic checks can read them.
@MainActor
enum UnpricedDisplay {
    /// Rows shown per source group; the rest is counted by `history.unpricedModels.more`.
    static let rowsPerGroup = 20
    static let separator = " · "

    static func reasonLabel(_ reason: UnpricedReason, _ l10n: Localizer) -> String {
        l10n("cost.reason.\(reason.rawValue)")
    }

    /// The chip's tooltip: the reason's hint, followed for `unpriceable` by the table's rule text (English, as published).
    static func reasonHelp(_ diagnosis: UnpricedDiagnosis, _ l10n: Localizer) -> String {
        let hint = l10n("cost.reason.\(diagnosis.reason.rawValue).hint")
        guard diagnosis.reason == .unpriceable, let rule = diagnosis.rule, !rule.isEmpty else { return hint }
        return hint + "\n" + rule
    }

    /// The model as shown: `cost.noModelName` for a fact without one.
    static func model(_ row: UnpricedRow, _ l10n: Localizer) -> String {
        row.key.model.isEmpty ? l10n("cost.noModelName") : row.key.model
    }

    /// What follows the chip, in order: `經由 provider`, Fast, `查詢名稱 key` when the key differs from the model.
    struct Details: Equatable {
        var provider: String?
        var fast: Bool
        var lookup: String?
    }

    static func details(_ row: UnpricedRow, _ l10n: Localizer) -> Details {
        let canonical = row.diagnosis.canonical
        return Details(
            provider: row.key.provider.map { l10n("history.unpricedModels.via", $0) },
            fast: row.key.fast,
            lookup: canonical.flatMap { $0 != row.key.model ? l10n("history.unpricedModels.lookup", $0) : nil }
        )
    }

    /// The detail parts as plain text (the bolt is drawn, never written).
    static func detailParts(_ row: UnpricedRow, _ l10n: Localizer) -> [String] {
        let details = details(row, l10n)
        return [details.provider, details.fast ? l10n("speed.value.fast") : nil, details.lookup].compactMap { $0 }
    }

    /// `出現日期：2026/06/24 – 2026/07/03`, one date when the first and last day are the same.
    static func seen(_ row: UnpricedRow, _ l10n: Localizer) -> String {
        guard let first = DayKey(row.first), let last = DayKey(row.last) else { return l10n("history.unpricedModels.seen", row.first) }
        let dates = first == last ? HistoryText.date(first, l10n) : HistoryText.date(first, l10n) + " – " + HistoryText.date(last, l10n)
        return l10n("history.unpricedModels.seen", dates)
    }

    /// The detail line's tooltip: the whole line, then the days seen.
    static func lineHelp(_ row: UnpricedRow, _ l10n: Localizer) -> String {
        ([reasonLabel(row.diagnosis.reason, l10n)] + detailParts(row, l10n)).joined(separator: separator) + "\n" + seen(row, l10n)
    }

    /// The row's accessibility value: reason, provider, Fast, lookup key, requests and the days seen.
    static func accessibilityValue(_ row: UnpricedRow, _ l10n: Localizer) -> String {
        HistoryText.join([reasonLabel(row.diagnosis.reason, l10n)] + detailParts(row, l10n) + [
            HistoryText.labelled(l10n("history.table.requests"), HistoryText.fullNumber(row.requests, l10n), l10n),
            seen(row, l10n),
        ], l10n)
    }

    /// `另有 3 項 · 41 筆請求` for the rows past the first 20 of a group; nil when every row shows.
    static func more(_ group: UnpricedGroup, _ l10n: Localizer) -> String? {
        let rest = group.rows.dropFirst(rowsPerGroup)
        guard !rest.isEmpty else { return nil }
        return l10n("history.unpricedModels.more", rest.count, rest.reduce(0) { $0 + $1.requests })
    }

    /// A group heading as read aloud: the source and its count.
    static func groupLabel(_ group: UnpricedGroup, _ l10n: Localizer) -> String {
        HistoryText.join([l10n(group.source.titleKey), l10n("history.unpricedDay", group.rowRequests)], l10n)
    }

    // MARK: - Settings → Cost

    /// Today's live view over the enabled sources (METRICS 9.10 *Live*).
    static func today(_ sources: [SourceStatus], day: String, table: PriceTable) -> UnpricedView {
        let enabled = sources.filter(\.enabled)
        let parts = UnpricedPart.live(
            day: day,
            requests: Dictionary(uniqueKeysWithValues: enabled.map { ($0.kind, $0.today.requests) }),
            facts: Dictionary(uniqueKeysWithValues: enabled.map { ($0.kind, $0.unpricedFacts) }))
        return UnpricedView(parts: parts, table: table, range: UnpricedRange(view: "live", first: day, last: day))
    }

    struct TodayItem: Equatable {
        var model: String
        var reason: UnpricedReason
        var requests: Int
    }

    /// One item per distinct model and reason, most requests first, then the model's UTF-8 bytes.
    static func todayItems(_ view: UnpricedView) -> [TodayItem] {
        var items: [String: TodayItem] = [:]
        var order: [String] = []
        for row in view.groups.flatMap(\.rows) {
            let key = row.diagnosis.reason.rawValue + "\u{0}" + row.key.model
            if items[key] == nil { order.append(key) }
            items[key, default: TodayItem(model: row.key.model, reason: row.diagnosis.reason, requests: 0)].requests += row.requests
        }
        return order.compactMap { items[$0] }.sorted { lhs, rhs in
            if lhs.requests != rhs.requests { return lhs.requests > rhs.requests }
            if lhs.model != rhs.model { return lhs.model.utf8.lexicographicallyPrecedes(rhs.model.utf8) }
            return (UnpricedReason.allCases.firstIndex(of: lhs.reason) ?? 0) < (UnpricedReason.allCases.firstIndex(of: rhs.reason) ?? 0)
        }
    }

    /// `prices.unknownToday` with its items, or nil when today has no unpriced request.
    static func todayLine(_ items: [TodayItem], _ l10n: Localizer) -> String? {
        guard !items.isEmpty else { return nil }
        let list = items.map { item in
            l10n("prices.unknownToday.item", item.model.isEmpty ? l10n("cost.noModelName") : item.model, reasonLabel(item.reason, l10n))
        }
        return l10n("prices.unknownToday", list.joined(separator: l10n("list.separator")))
    }

    /// The line's tooltip: each reason's hint once, in the order the reasons first appear.
    static func todayHelp(_ items: [TodayItem], _ l10n: Localizer) -> String {
        var seen: Set<UnpricedReason> = []
        return items.compactMap { item in
            seen.insert(item.reason).inserted
                ? HistoryText.labelled(reasonLabel(item.reason, l10n), l10n("cost.reason.\(item.reason.rawValue).hint"), l10n) : nil
        }
        .joined(separator: "\n")
    }
}

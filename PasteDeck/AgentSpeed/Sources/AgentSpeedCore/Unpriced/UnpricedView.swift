import Foundation

/// The unpriced facts of one (day, source) with its requests, the requests stored without cost data and the derived
/// ones (METRICS 9.10 *Rows*).
public struct UnpricedPart: Equatable, Sendable {
    /// `YYYY-MM-DD`.
    public var day: String
    public var source: SourceKind
    public var requests: Int
    public var noCostData: Int
    public var derived: Int
    public var facts: [UnpricedFact]

    public init(day: String, source: SourceKind, requests: Int, noCostData: Int = 0, derived: Int = 0, facts: [UnpricedFact] = []) {
        self.day = day
        self.source = source
        self.requests = requests
        self.noCostData = noCostData
        self.derived = derived
        self.facts = facts
    }

    /// Sums parts of the same (day, source): facts by key, the counters by addition; sorted by day, then source.
    public static func merged(_ parts: [UnpricedPart]) -> [UnpricedPart] {
        var merged: [UsageKey: (part: UnpricedPart, tally: [UnpricedFactKey: Int])] = [:]
        for part in parts {
            let key = UsageKey(day: part.day, source: part.source)
            var entry = merged[key] ?? (UnpricedPart(day: part.day, source: part.source, requests: 0), [:])
            entry.part.requests += part.requests
            entry.part.noCostData += part.noCostData
            entry.part.derived += part.derived
            for fact in part.facts { entry.tally[fact.key, default: 0] += fact.requests }
            merged[key] = entry
        }
        return merged.values
            .map { entry in
                var part = entry.part
                part.facts = UnpricedFact.list(entry.tally)
                return part
            }
            .sorted { $0.day != $1.day ? $0.day < $1.day : $0.source.ordinal < $1.source.ordinal }
    }

    /// The live view of today (METRICS 9.10 *Live*): one part per source with today's requests.
    public static func live(day: String, requests: [SourceKind: Int], facts: [SourceKind: [UnpricedFact]]) -> [UnpricedPart] {
        SourceKind.allCases.compactMap { source in
            guard let count = requests[source], count > 0 else { return nil }
            return UnpricedPart(day: day, source: source, requests: count, facts: facts[source] ?? [])
        }
    }
}

/// One row of the diagnostics: the facts of one (source, model, provider, fast, noDate) that have a reason.
public struct UnpricedRow: Equatable, Sendable, Identifiable {
    public var source: SourceKind
    public var key: UnpricedFactKey
    public var diagnosis: UnpricedDiagnosis
    public var requests: Int
    /// The earliest and latest day of its facts.
    public var first: String
    public var last: String

    public init(source: SourceKind, key: UnpricedFactKey, diagnosis: UnpricedDiagnosis, requests: Int, first: String, last: String) {
        self.source = source
        self.key = key
        self.diagnosis = diagnosis
        self.requests = requests
        self.first = first
        self.last = last
    }

    public var id: String {
        [source.rawValue, key.model, key.provider.map { "1" + $0 } ?? "0", key.fast ? "1" : "0", key.noDate ? "1" : "0"]
            .joined(separator: "\u{0}")
    }
}

/// A source of the view with its totals and rows.
public struct UnpricedGroup: Equatable, Sendable, Identifiable {
    public var source: SourceKind
    public var requests = 0
    public var unpriced = 0
    /// Facts the current table prices (free included).
    public var pricedNow = 0
    public var noCostData = 0
    public var derived = 0
    public var rows: [UnpricedRow] = []

    public init(source: SourceKind) {
        self.source = source
    }

    public var id: SourceKind { source }
    /// Σ requests of its rows.
    public var rowRequests: Int { rows.reduce(0) { $0 + $1.requests } }
}

/// The range a diagnostics view covers (METRICS 9.10 *Text* `range`).
public struct UnpricedRange: Equatable, Sendable {
    /// `today`, `yesterday`, `7d`, `30d`, `90d`, `year`, `all`, `custom` or `live`.
    public var view: String
    public var first: String
    public var last: String
    public var source: SourceKind?
    public var excluded: Set<SourceKind>

    public init(view: String, first: String, last: String, source: SourceKind? = nil, excluded: Set<SourceKind> = []) {
        self.view = view
        self.first = first
        self.last = last
        self.source = source
        self.excluded = excluded
    }
}

extension UnpricedRange {
    /// `YYYY-MM-DD` of a real calendar date.
    public static func isDate(_ text: String) -> Bool {
        text.utf8.count == 10 && UTCDay.instantMs(text) != nil
    }

    /// The range of `--dump-unpriced`: `live` for today's engine data; `first`/`last` a custom range; else the last
    /// `days` local days with today (default 30), named `today`, `7d`, `30d` or `90d` for 1, 7, 30 and 90.
    public static func probe(days: Int?, first: String?, last: String?, live: Bool, source: SourceKind?,
                             now: Date = Date(), timeZone: TimeZone = .current) -> UnpricedRange {
        let today = DayLabeler(timeZone: timeZone).label(for: now)
        if live { return UnpricedRange(view: "live", first: today, last: today, source: source) }
        if let first, let last { return UnpricedRange(view: "custom", first: first, last: last, source: source) }
        let count = max(1, days ?? 30)
        let view = [1: "today", 7: "7d", 30: "30d", 90: "90d"][count] ?? "custom"
        let start = (UTCDay.instantMs(today) ?? 0) - Int64(count - 1) * UTCDay.msPerDay
        return UnpricedRange(view: view, first: UTCDay(ms: start).label, last: today, source: source)
    }
}

/// Source groups and rows of a view (METRICS 9.10 *Rows*), reasons computed with the current table.
public struct UnpricedView: Equatable, Sendable {
    public var range: UnpricedRange
    public var groups: [UnpricedGroup]
    /// The current table the reasons were computed with (the text's `prices` line).
    public var tableVersion: Int
    public var tableUpdated: String

    public static let empty = UnpricedView(
        range: UnpricedRange(view: "custom", first: "", last: ""), groups: [], tableVersion: 0, tableUpdated: "")

    public init(range: UnpricedRange, groups: [UnpricedGroup], tableVersion: Int, tableUpdated: String) {
        self.range = range
        self.groups = groups
        self.tableVersion = tableVersion
        self.tableUpdated = tableUpdated
    }

    public init(parts: [UnpricedPart], table: PriceTable, range: UnpricedRange) {
        self.range = range
        tableVersion = table.version
        tableUpdated = table.updated
        var groups: [SourceKind: UnpricedGroup] = [:]
        var rows: [SourceKind: [UnpricedFactKey: UnpricedRow]] = [:]
        var diagnoses: [UnpricedFactKey: UnpricedDiagnosis?] = [:]
        for part in parts {
            let source = part.source
            guard range.first <= part.day, part.day <= range.last, !range.excluded.contains(source),
                  range.source.map({ $0 == source }) ?? true else { continue }
            var group = groups[source] ?? UnpricedGroup(source: source)
            group.requests += part.requests
            group.noCostData += part.noCostData
            group.derived += part.derived
            for fact in part.facts {
                group.unpriced += fact.requests
                let diagnosis: UnpricedDiagnosis?
                if fact.noDate {
                    diagnosis = UnpricedDiagnosis(reason: .noDate)
                } else if let known = diagnoses[fact.key] {
                    diagnosis = known
                } else {
                    diagnosis = table.resolver.diagnose(model: fact.model, provider: fact.provider, fast: fact.fast)
                    diagnoses[fact.key] = diagnosis
                }
                guard let diagnosis else {
                    group.pricedNow += fact.requests
                    continue
                }
                var row = rows[source]?[fact.key]
                    ?? UnpricedRow(source: source, key: fact.key, diagnosis: diagnosis, requests: 0, first: part.day, last: part.day)
                row.requests += fact.requests
                row.first = min(row.first, part.day)
                row.last = max(row.last, part.day)
                rows[source, default: [:]][fact.key] = row
            }
            groups[source] = group
        }
        self.groups = groups.values
            .map { group in
                var group = group
                group.rows = (rows[group.source] ?? [:]).values.sorted { lhs, rhs in
                    lhs.requests != rhs.requests ? lhs.requests > rhs.requests : UnpricedFactKey.precedes(lhs.key, rhs.key)
                }
                return group
            }
            .sorted { $0.unpriced != $1.unpriced ? $0.unpriced > $1.unpriced : $0.source.ordinal < $1.source.ordinal }
    }

    public var unpriced: Int { groups.reduce(0) { $0 + $1.unpriced } }
    public var pricedNow: Int { groups.reduce(0) { $0 + $1.pricedNow } }
    public var rowCount: Int { groups.reduce(0) { $0 + $1.rows.count } }
}

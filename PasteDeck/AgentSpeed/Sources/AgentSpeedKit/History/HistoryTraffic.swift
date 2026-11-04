import AgentSpeedCore
import Foundation

/// One day's traffic for the selected source, or over every source with this computer's total (METRICS 10.9). Days
/// before measuring began have none (shown as not recorded, never 0).
struct DayTraffic: Equatable, Sendable {
    /// The agents' own processes and their tools.
    var own: TrafficBytes
    var tools: TrafficBytes
    /// Per source, own + tools as displayed (tools per the setting), for stacking.
    var bySource: [SourceKind: TrafficBytes]
    /// This computer (all sources view only).
    var machine: TrafficBytes?
    /// How long the day was recorded, and whether that is less than the day's elapsed time.
    var recordedMs: Int64
    var partial: Bool
    let includeTools: Bool

    /// The displayed bytes: tools per the setting.
    var shown: TrafficBytes { includeTools ? own + tools : own }
}

/// The stored traffic days and how they count in the window (METRICS 10.9, DESIGN 10 Usage history).
struct HistoryTraffic: Equatable, Sendable {
    /// Day → key (`machine` or a source) → row.
    var rows: [DayKey: [String: TrafficDay]] = [:]
    /// The first day with a stored sample.
    var since: DayKey?
    var includeTools = true
    var bits = false

    static let none = HistoryTraffic()

    init() {}

    init(days: [TrafficDay], since: String?, includeTools: Bool, bits: Bool) {
        for row in days {
            guard let day = DayKey(row.day) else { continue }
            rows[day, default: [:]][row.key] = row
        }
        self.since = since.flatMap(DayKey.init) ?? rows.keys.min()
        self.includeTools = includeTools
        self.bits = bits
    }

    var hasData: Bool { !rows.isEmpty }

    /// Whether `day` falls before measuring began.
    func notRecorded(_ day: DayKey) -> Bool {
        guard let since else { return true }
        return day < since
    }

    /// The day's traffic for `source` (every source when nil); nil before measuring began. `now` decides how much of
    /// today has elapsed, for the partial mark.
    func day(_ day: DayKey, source: SourceKind?, today: DayKey, now: Date, calendar: Calendar) -> DayTraffic? {
        guard !notRecorded(day) else { return nil }
        let keyed = rows[day] ?? [:]
        var own = TrafficBytes.zero
        var tools = TrafficBytes.zero
        var bySource: [SourceKind: TrafficBytes] = [:]
        var sampled: Int64 = 0
        for kind in SourceKind.allCases where source == nil || source == kind {
            guard let row = keyed[kind.rawValue] else { continue }
            own += TrafficBytes(rx: row.rx, tx: row.tx)
            tools += TrafficBytes(rx: row.rxTools, tx: row.txTools)
            let shown = row.total(includeTools: includeTools)
            if !shown.isZero { bySource[kind] = shown }
            sampled = max(sampled, row.sampledMs)
        }
        let machineRow = keyed[TrafficDay.machineKey]
        let recorded = machineRow?.sampledMs ?? sampled
        let start = day.date(in: calendar)
        let elapsed = day == today ? now.timeIntervalSince(start) : (day.adding(days: 1).date(in: calendar).timeIntervalSince(start))
        // A minute of slack: sampling starts a moment after launch and the last write lags by up to 60 s.
        let partial = Double(recorded) / 1000 < elapsed - 120
        return DayTraffic(own: own, tools: tools, bySource: bySource,
                          machine: source == nil ? machineRow.map { TrafficBytes(rx: $0.rx, tx: $0.tx) } ?? .zero : nil,
                          recordedMs: recorded, partial: partial, includeTools: includeTools)
    }

    /// Every day of `range` that has a row, for the chart and the CSV.
    func days(in range: DayRange) -> [DayKey] {
        rows.keys.filter(range.contains).sorted()
    }

    /// Days with agent traffic of `source` (every source when nil) as displayed, tools per the setting, oldest first.
    /// This computer's own total does not count (DESIGN 10, Traffic without token usage).
    func agentDays(source: SourceKind?) -> [DayKey] {
        rows.compactMap { day, keyed in
            keyed.contains { key, row in
                guard let kind = SourceKind(rawValue: key), source == nil || source == kind else { return false }
                return !row.total(includeTools: includeTools).isZero
            } ? day : nil
        }.sorted()
    }

    /// Sources with agent traffic on any stored day, in `SourceKind` order.
    var sourcesWithTraffic: [SourceKind] {
        var found = Set<SourceKind>()
        for keyed in rows.values {
            for (key, row) in keyed {
                if let kind = SourceKind(rawValue: key), !row.total(includeTools: includeTools).isZero { found.insert(kind) }
            }
        }
        return SourceKind.allCases.filter(found.contains)
    }
}

import Foundation

/// A local calendar day as the history store writes it (`YYYY-MM-DD`, METRICS 8), with day arithmetic that never
/// goes through a time zone.
struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int
    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    let ordinal: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
        ordinal = Self.ordinal(year: year, month: month, day: day)
    }

    init(ordinal: Int) {
        // Howard Hinnant's civil_from_days.
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        month = m
        day = d
        self.ordinal = ordinal
    }

    /// Parses `YYYY-MM-DD`; anything else is nil.
    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self = DayKey(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
            ?? DayKey(ordinal: 0)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// 1 = Sunday … 7 = Saturday, as `Calendar` numbers weekdays.
    var weekday: Int { ((ordinal % 7 + 7 + 4) % 7) + 1 }

    func adding(days: Int) -> DayKey { DayKey(ordinal: ordinal + days) }

    /// Midnight of the day in `calendar`'s time zone.
    func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.ordinal < rhs.ordinal }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    // Howard Hinnant's days_from_civil.
    private static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/// An inclusive run of calendar days.
struct DayRange: Hashable, Sendable {
    let start: DayKey
    let end: DayKey

    init(_ start: DayKey, _ end: DayKey) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    static func single(_ day: DayKey) -> DayRange { DayRange(day, day) }

    var count: Int { end.ordinal - start.ordinal + 1 }

    /// 今天, 昨天 or a one-day custom range: compared with the day before and broken down instead of charted.
    var isSingleDay: Bool { start == end }

    func contains(_ day: DayKey) -> Bool { day >= start && day <= end }

    /// Position of `day` in the range (0 = `start`).
    func index(of day: DayKey) -> Int { day.ordinal - start.ordinal }

    func day(at index: Int) -> DayKey { start.adding(days: index) }

    var days: [DayKey] { (0..<count).map(day(at:)) }
}

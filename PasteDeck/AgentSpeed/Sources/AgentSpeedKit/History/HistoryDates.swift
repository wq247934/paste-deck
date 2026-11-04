import Foundation

/// Locale-aware date text for the history window, in the app language. Formats are templates resolved by the locale,
/// so each language gets its own native order and separators.
@MainActor
enum HistoryDates {
    enum Style: Hashable {
        /// `2026/10/21`, `Oct 21, 2026`
        case date
        /// `10/21`, `Oct 21`
        case monthDay
        /// `10月`, `Oct`
        case month
        /// `2026年10月`, `Oct 2026`
        case yearMonth
        /// `21`
        case dayOfMonth
        /// `週三`, `Wed`, `水`
        case weekday
        /// `14:05`, `2:05 PM`
        case time
    }

    private struct Key: Hashable {
        let style: Style
        let language: AppLanguage
    }

    private static var formatters: [Key: DateFormatter] = [:]

    /// The Gregorian calendar in the current time zone; history days are local Gregorian dates.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // Weeks start where the user's own region starts them.
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    static func string(_ day: DayKey, _ style: Style, language: AppLanguage) -> String {
        string(day.date(in: calendar), style, language: language)
    }

    static func string(_ date: Date, _ style: Style, language: AppLanguage) -> String {
        formatter(style, language).string(from: date)
    }

    private static func formatter(_ style: Style, _ language: AppLanguage) -> DateFormatter {
        let key = Key(style: style, language: language)
        if let formatter = formatters[key] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        let spelled = language == .en
        let template = switch style {
        case .date: spelled ? "yMMMd" : "yMd"
        case .monthDay: spelled ? "MMMd" : "Md"
        case .month: "MMM"
        case .yearMonth: "yMMM"
        case .dayOfMonth: "d"
        case .weekday: "EEE"
        case .time: "jmm"
        }
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}

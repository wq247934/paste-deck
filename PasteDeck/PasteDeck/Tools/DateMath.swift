//
//  DateMath.swift
//  PasteDeck
//
//  时间日期计算工具的纯逻辑：日期解析/格式化、日期差、日期推算、
//  英文日期格式转换，以及基于内置法定节假日表（2024–2025）的工作日计算。
//  全部基于 Foundation Calendar/DateComponents，不做任何 IO。
//

import Foundation

enum DateMath {

    /// 日期计算统一使用 UTC 的格里高利历，避免本地时区夏令时影响"自然日"口径。
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return calendar
    }

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimestampMath.utcTimeZone
        formatter.isLenient = false
        return formatter
    }

    // MARK: - 解析与格式化

    /// 解析 "yyyy-MM-dd"；位数不齐或日期不存在（如 02-30）返回 nil。
    /// DateFormatter 的 ICU 解析对残缺输入（"2026-10"）过宽，先用正则锁定形状。
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = utcFormatter("yyyy-MM-dd").date(from: trimmed) else {
            return nil
        }
        return normalizedDateOnly(date)
    }

    /// 解析 "yyyy-MM-dd HH:mm" 或 "yyyy-MM-dd HH:mm:ss"；时间部分缺省为 00:00:00。
    static func parseDateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}(:\d{2})?)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        let composed = trimmed.count == 10
            ? trimmed + " 00:00:00"
            : (trimmed.count == 16 ? trimmed + ":00" : trimmed)
        return utcFormatter("yyyy-MM-dd HH:mm:ss").date(from: composed)
    }

    /// 去掉时间部分，返回当天 00:00:00 UTC。
    static func normalizedDateOnly(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    static func formatDate(_ date: Date) -> String {
        utcFormatter("yyyy-MM-dd").string(from: date)
    }

    static func formatDateTime(_ date: Date) -> String {
        utcFormatter("yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    static func weekdayText(_ date: Date) -> String {
        let symbols = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let index = utcCalendar.component(.weekday, from: date) - 1
        return symbols[(index + 7) % 7]
    }

    /// 今天（用户本地时区的"今天"，按本地日历取年月日后再按 UTC 归一）。
    static func today() -> Date {
        let local = Calendar.current
        var components = local.dateComponents([.year, .month, .day], from: Date())
        components.timeZone = TimestampMath.utcTimeZone
        return utcCalendar.date(from: components) ?? normalizedDateOnly(Date())
    }

    // MARK: - 日期差

    /// 两个日期之间相差的整天数（同日为 0，先后为正）。
    static func days(from: Date, to: Date) -> Int {
        utcCalendar.dateComponents([.day], from: normalizedDateOnly(from), to: normalizedDateOnly(to)).day ?? 0
    }

    /// 精确到时分秒的时长文本；符号只体现在"天"上，其余部分取绝对值。
    static func durationText(from: Date, to: Date) -> String? {
        let totalSeconds = Int(to.timeIntervalSince(from))
        let sign = totalSeconds < 0 ? "-" : ""
        var remaining = abs(totalSeconds)

        let day = remaining / 86_400
        remaining %= 86_400
        let hour = remaining / 3_600
        remaining %= 3_600
        let minute = remaining / 60
        let second = remaining % 60

        return "相差 \(sign)\(day) 天 \(hour) 小时 \(minute) 分 \(second) 秒"
    }

    // MARK: - 日期推算

    enum Unit: String, CaseIterable {
        case day = "天"
        case week = "周"
        case month = "月"
        case year = "年"

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }
    }

    /// 日期按单位推算；amount 为负时回退（direction 由调用方换算）。
    static func add(_ amount: Int, of unit: Unit, to date: Date) -> Date? {
        utcCalendar.date(byAdding: unit.component, value: amount, to: date)
    }

    // MARK: - 英文日期格式

    struct EnglishDateFormats: Equatable {
        let american: String
        let british: String
        let weekday: String
    }

    /// 美式 "Month d, yyyy"、英式 "d Month, yyyy"。
    static func englishDateFormats(_ raw: String) -> EnglishDateFormats? {
        guard let date = parseDate(raw) else { return nil }
        let monthDay = utcFormatter("MMMM d, yyyy").string(from: date)
        let dayMonth = utcFormatter("d MMMM, yyyy").string(from: date)
        return EnglishDateFormats(american: monthDay, british: dayMonth, weekday: weekdayText(date))
    }
}

// MARK: - 工作日历（中国法定节假日）

/// 内置 2024–2025 年国务院办公厅公布的法定节假日与调休补班安排。
/// 数据之外的年份自动退化为"仅剔除周末"并在 UI 提示。
enum WorkdayCalendar {

    /// 法定休假日（yyyy-MM-dd）。
    static let holidays: Set<String> = [
        // 2024
        "2024-01-01",
        "2024-02-10", "2024-02-11", "2024-02-12", "2024-02-13",
        "2024-02-14", "2024-02-15", "2024-02-16", "2024-02-17",
        "2024-04-04", "2024-04-05", "2024-04-06",
        "2024-05-01", "2024-05-02", "2024-05-03", "2024-05-04", "2024-05-05",
        "2024-06-10",
        "2024-09-15", "2024-09-16", "2024-09-17",
        "2024-10-01", "2024-10-02", "2024-10-03", "2024-10-04",
        "2024-10-05", "2024-10-06", "2024-10-07",
        // 2025
        "2025-01-01",
        "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31",
        "2025-02-01", "2025-02-02", "2025-02-03", "2025-02-04",
        "2025-04-04", "2025-04-05", "2025-04-06",
        "2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05",
        "2025-05-31", "2025-06-01", "2025-06-02",
        "2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04",
        "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08"
    ]

    /// 调休补班日（周末但需要上班）。
    static let makeupWorkdays: Set<String> = [
        "2024-02-04", "2024-02-18",
        "2024-04-28", "2024-05-11",
        "2024-09-14", "2024-09-29", "2024-10-12",
        "2025-01-26", "2025-02-08",
        "2025-04-27",
        "2025-09-28", "2025-10-11"
    ]

    static let supportedYears = 2024...2025
    static let supportedYearsNotice = "法定节假日与调休数据目前收录 2024–2025 年；其他年份按\"仅剔除周末\"估算。"

    static func isWorkday(_ date: Date) -> Bool {
        let key = DateMath.formatDate(date)
        if makeupWorkdays.contains(key) { return true }
        if holidays.contains(key) { return false }
        // 数据未覆盖的年份退化为纯周末判断。
        let weekday = DateMath.utcCalendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    static func isSupported(_ date: Date) -> Bool {
        supportedYears.contains(DateMath.utcCalendar.component(.year, from: date))
    }

    /// 从某天起按工作日推算 n 天（n 可为负表示往前）。
    /// 返回推算后的日期；second 参数表示起止是否完全落在收录的数据范围内。
    static func addWorkdays(from date: Date, count: Int) -> (Date, Bool) {
        let calendar = DateMath.utcCalendar
        var current = DateMath.normalizedDateOnly(date)
        let step = count >= 0 ? 1 : -1
        var remaining = abs(count)
        var fullySupported = isSupported(current)

        guard remaining > 0 else { return (current, fullySupported) }

        while remaining > 0 {
            current = calendar.date(byAdding: .day, value: step, to: current) ?? current
            fullySupported = fullySupported && isSupported(current)
            if isWorkday(current) {
                remaining -= 1
            }
        }
        return (current, fullySupported)
    }

    /// 统计区间内（含两端）的工作日数量。
    static func workdays(from start: Date, to end: Date) -> (count: Int, totalDays: Int, fullySupported: Bool) {
        let calendar = DateMath.utcCalendar
        var cursor = DateMath.normalizedDateOnly(start)
        let last = DateMath.normalizedDateOnly(end)
        guard cursor <= last else {
            let reversed = workdays(from: last, to: cursor)
            return reversed
        }

        var count = 0
        var total = 0
        var fullySupported = isSupported(cursor) && isSupported(last)
        while cursor <= last {
            total += 1
            if isWorkday(cursor) {
                count += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return (count, total, fullySupported)
    }
}

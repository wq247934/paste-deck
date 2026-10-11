//
//  TimestampMath.swift
//  PasteDeck
//
//  Unix 时间戳的纯计算逻辑：严格解析、时区格式化与双向换算。
//  全部基于 Foundation 的 Date / Calendar / TimeZone，不手写时区偏移。
//

import Foundation

enum TimestampMath {

    enum Unit: Equatable {
        case seconds
        case milliseconds

        var secondsPerUnit: TimeInterval {
            switch self {
            case .seconds: return 1
            case .milliseconds: return 0.001
            }
        }

        var displayName: String {
            switch self {
            case .seconds: return "秒"
            case .milliseconds: return "毫秒"
            }
        }
    }

    struct ParsedTimestamp: Equatable {
        /// 用户输入的原始整数值（秒或毫秒）。
        let rawValue: Int64
        let unit: Unit

        var timeIntervalSince1970: TimeInterval {
            TimeInterval(rawValue) * unit.secondsPerUnit
        }
    }

    /// 秒级接受 9–10 位（约 1973-03 ~ 2286-11），避免把 11 位手机号、
    /// 订单号等普通数字强行判定为时间戳。
    private static let secondsDigitCountRange = 9...10
    /// 毫秒级接受 12–13 位（约 1973 ~ 2286）；11 位数字不参与判定。
    private static let millisecondsDigitCountRange = 12...13

    /// Unix 时间戳可表示的合理范围：1970-01-01 ~ 9999-12-31。
    static let validUnixSecondsRange = 0.0...253_402_300_799.0

    /// 复用的 UTC 时区常量。
    static let utcTimeZone = TimeZone(identifier: "UTC") ?? TimeZone.current

    // MARK: - 解析

    /// 严格解析纯数字字符串。非纯数字、位数不符或换算后越界一律返回 nil。
    static func parse(_ raw: String?) -> ParsedTimestamp? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else {
            return nil
        }

        let digitCount = trimmed.count
        if secondsDigitCountRange.contains(digitCount) {
            guard let value = Int64(trimmed),
                  isValidUnixSeconds(TimeInterval(value)) else {
                return nil
            }
            return ParsedTimestamp(rawValue: value, unit: .seconds)
        }

        if millisecondsDigitCountRange.contains(digitCount) {
            guard let value = Int64(trimmed),
                  isValidUnixSeconds(TimeInterval(value) * Unit.milliseconds.secondsPerUnit) else {
                return nil
            }
            return ParsedTimestamp(rawValue: value, unit: .milliseconds)
        }

        return nil
    }

    static func isValidUnixSeconds(_ seconds: TimeInterval) -> Bool {
        validUnixSecondsRange.contains(seconds)
    }

    // MARK: - 时间戳 -> 日期

    static func date(from timestamp: ParsedTimestamp) -> Date {
        Date(timeIntervalSince1970: timestamp.timeIntervalSince1970)
    }

    // MARK: - 日期 -> 时间戳

    static func unixSeconds(of date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    static func unixMilliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - 格式化

    /// 按 "yyyy-MM-dd HH:mm:ss" 输出指定时区的可读时间。
    static func formattedText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = cachedFormatter(timeZone: timeZone)
        return formatter.string(from: date)
    }

    /// ISO 8601（含时区偏移）输出，例如 2026-10-11T01:35:11+08:00。
    static func iso8601Text(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }

    private static func cachedFormatter(timeZone: TimeZone) -> DateFormatter {
        // DateFormatter 创建昂贵；按(identifier, locale)缓存复用。
        let key = timeZone.identifier
        if let cached = formatterCache.object(forKey: key as NSString) {
            return cached
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatterCache.setObject(formatter, forKey: key as NSString)
        return formatter
    }

    private static let formatterCache = NSCache<NSString, DateFormatter>()
}

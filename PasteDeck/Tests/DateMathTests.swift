//
//  DateMathTests.swift
//  PasteDeck
//
//  验证时间日期计算工具的纯逻辑：解析、日期差、推算、英文格式与工作日历。
//

import Foundation
import XCTest
@testable import PasteDeck

final class DateMathTests: XCTestCase {

    private func date(_ raw: String) throws -> Date {
        try XCTUnwrap(DateMath.parseDate(raw))
    }

    // MARK: - 解析

    func testParseDate() throws {
        XCTAssertNotNil(try? date("2026-10-11"))
        XCTAssertNil(DateMath.parseDate("2026-10"))
        XCTAssertNil(DateMath.parseDate("2026/10/11"))
        XCTAssertNil(DateMath.parseDate("not a date"))
        XCTAssertNil(DateMath.parseDate(""))
        // 位数不齐拒绝（lenient=false）。
        XCTAssertNil(DateMath.parseDate("2026-1-1"))
    }

    func testParseDateTime() throws {
        XCTAssertNotNil(DateMath.parseDateTime("2026-10-11 09:35:11"))
        XCTAssertNotNil(DateMath.parseDateTime("2026-10-11 09:35"))
        XCTAssertNil(DateMath.parseDateTime("2026-10-11 9:35:11"))
        XCTAssertNil(DateMath.parseDateTime("abc"))
    }

    // MARK: - 日期差

    func testDays() throws {
        let start = try date("2026-10-11")
        let end = try date("2027-01-01")
        XCTAssertEqual(DateMath.days(from: start, to: end), 82)
        XCTAssertEqual(DateMath.days(from: end, to: start), -82)
        XCTAssertEqual(DateMath.days(from: start, to: start), 0)
    }

    func testDurationText() throws {
        let start = try XCTUnwrap(DateMath.parseDateTime("2026-10-11 09:35:11"))
        let end = try XCTUnwrap(DateMath.parseDateTime("2026-10-12 10:36:12"))
        XCTAssertEqual(DateMath.durationText(from: start, to: end), "相差 1 天 1 小时 1 分 1 秒")
        XCTAssertEqual(DateMath.durationText(from: end, to: start), "相差 -1 天 1 小时 1 分 1 秒")
    }

    // MARK: - 推算

    func testAdd() throws {
        let base = try date("2026-10-11")
        XCTAssertEqual(DateMath.formatDate(try XCTUnwrap(DateMath.add(100, of: .day, to: base))), "2027-01-19")
        XCTAssertEqual(DateMath.formatDate(try XCTUnwrap(DateMath.add(-1, of: .day, to: base))), "2026-10-10")
        XCTAssertEqual(DateMath.formatDate(try XCTUnwrap(DateMath.add(1, of: .month, to: base))), "2026-11-11")
        XCTAssertEqual(DateMath.formatDate(try XCTUnwrap(DateMath.add(1, of: .year, to: base))), "2027-10-11")
        XCTAssertEqual(DateMath.formatDate(try XCTUnwrap(DateMath.add(1, of: .week, to: base))), "2026-10-18")
    }

    func testWeekdayText() throws {
        // 2026-10-11 是星期日。
        XCTAssertEqual(DateMath.weekdayText(try date("2026-10-11")), "星期日")
        XCTAssertEqual(DateMath.weekdayText(try date("2026-10-12")), "星期一")
    }

    // MARK: - 英文格式

    func testEnglishDateFormats() throws {
        let formats = try XCTUnwrap(DateMath.englishDateFormats("2026-10-11"))
        XCTAssertEqual(formats.american, "October 11, 2026")
        XCTAssertEqual(formats.british, "11 October, 2026")
        XCTAssertEqual(formats.weekday, "星期日")
        XCTAssertNil(DateMath.englishDateFormats("bad"))
    }

    // MARK: - 工作日历

    func testWorkdayBasics() throws {
        // 周一至周五是工作日（数据范围内）。
        XCTAssertTrue(WorkdayCalendar.isWorkday(try date("2025-03-10"))) // 周一
        XCTAssertFalse(WorkdayCalendar.isWorkday(try date("2025-03-08"))) // 周六
    }

    func testLegalHolidaysAndMakeupDays() throws {
        // 2025 国庆中秋连休（含周末前后），均为假日。
        XCTAssertFalse(WorkdayCalendar.isWorkday(try date("2025-10-01")))
        XCTAssertFalse(WorkdayCalendar.isWorkday(try date("2025-10-08")))
        // 调休补班的周末算工作日。
        XCTAssertTrue(WorkdayCalendar.isWorkday(try date("2025-09-28"))) // 周日补班
        XCTAssertTrue(WorkdayCalendar.isWorkday(try date("2025-10-11"))) // 周六补班
        // 2025 春节 1/28-2/4 休息。
        XCTAssertFalse(WorkdayCalendar.isWorkday(try date("2025-01-29")))
        XCTAssertTrue(WorkdayCalendar.isWorkday(try date("2025-02-05")))
        // 数据范围外的周末退化判断。
        XCTAssertTrue(WorkdayCalendar.isWorkday(try date("2030-03-11"))) // 周一
        XCTAssertFalse(WorkdayCalendar.isWorkday(try date("2030-03-10"))) // 周日
    }

    func testAddWorkdays() throws {
        // 2025-03-10（周一）往后 1 个工作日 = 3-11（周二）。
        let (next, supported) = WorkdayCalendar.addWorkdays(from: try date("2025-03-10"), count: 1)
        XCTAssertTrue(supported)
        XCTAssertEqual(DateMath.formatDate(next), "2025-03-11")

        // 跨国庆假期：2025-09-30（周二）往后 1 个工作日 = 10-09（周四，10-01~10-08 全休）。
        let (afterHoliday, _) = WorkdayCalendar.addWorkdays(from: try date("2025-09-30"), count: 1)
        XCTAssertEqual(DateMath.formatDate(afterHoliday), "2025-10-09")

        // 往前推算。
        let (before, _) = WorkdayCalendar.addWorkdays(from: try date("2025-03-11"), count: -1)
        XCTAssertEqual(DateMath.formatDate(before), "2025-03-10")

        // 0 个工作日原样返回。
        let (same, _) = WorkdayCalendar.addWorkdays(from: try date("2025-03-10"), count: 0)
        XCTAssertEqual(DateMath.formatDate(same), "2025-03-10")
    }

    func testWorkdaysRange() throws {
        // 2025-03-10（周一）~ 2025-03-16（周日）：5 个工作日。
        let outcome = WorkdayCalendar.workdays(from: try date("2025-03-10"), to: try date("2025-03-16"))
        XCTAssertTrue(outcome.fullySupported)
        XCTAssertEqual(outcome.count, 5)
        XCTAssertEqual(outcome.totalDays, 7)

        // 反向区间等价。
        let reversed = WorkdayCalendar.workdays(from: try date("2025-03-16"), to: try date("2025-03-10"))
        XCTAssertEqual(reversed.count, 5)

        // 2025 年 10 月：10-01~10-08 全休，10-11 补班。
        let october = WorkdayCalendar.workdays(from: try date("2025-09-28"), to: try date("2025-10-12"))
        // 自然日 15 天；其中 10/1-10/8 假日、9/28 与 10/11 补班上班。
        XCTAssertEqual(october.totalDays, 15)
        XCTAssertEqual(october.count, 6) // 9/28 补班 + 9/29、9/30 + 10/9、10/10 + 10/11 补班
    }

    // MARK: - 今天

    func testTodayIsNormalizedToUTCMidnight() {
        let today = DateMath.today()
        let components = DateMath.utcCalendar.dateComponents([.hour, .minute, .second], from: today)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
        // 今天必然是合法的 yyyy-MM-dd。
        XCTAssertNotNil(DateMath.parseDate(DateMath.formatDate(today)))
    }
}

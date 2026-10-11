//
//  TimestampMathTests.swift
//  PasteDeck
//
//  验证 Unix 时间戳的严格解析、范围判断与时区格式化。
//

import Foundation
import XCTest
@testable import PasteDeck

final class TimestampMathTests: XCTestCase {

    // MARK: - 解析

    func testParseSecondsTimestamp() {
        let parsed = TimestampMath.parse("1791682511")
        XCTAssertEqual(parsed, TimestampMath.ParsedTimestamp(rawValue: 1_791_682_511, unit: .seconds))
    }

    func testParseMillisecondsTimestamp() {
        let parsed = TimestampMath.parse("1791682511000")
        XCTAssertEqual(parsed, TimestampMath.ParsedTimestamp(rawValue: 1_791_682_511_000, unit: .milliseconds))
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, 1_791_682_511, accuracy: 0.001)
    }

    func testParseTrimsWhitespace() {
        XCTAssertEqual(TimestampMath.parse("  1791682511\n"), TimestampMath.ParsedTimestamp(rawValue: 1_791_682_511, unit: .seconds))
    }

    func testRejectsPhoneNumberLength() {
        // 11 位手机号既不属于 9–10 位秒级，也不属于 12–13 位毫秒级。
        XCTAssertNil(TimestampMath.parse("13812345678"))
    }

    func testRejectsShortOrLongDigits() {
        XCTAssertNil(TimestampMath.parse("12345678"))
        XCTAssertNil(TimestampMath.parse("1"))
        XCTAssertNil(TimestampMath.parse("17916825110000")) // 14 位
        XCTAssertNil(TimestampMath.parse("99999999999999999999")) // 20 位溢出
    }

    func testRejectsNonDigits() {
        XCTAssertNil(TimestampMath.parse(""))
        XCTAssertNil(TimestampMath.parse("   "))
        XCTAssertNil(TimestampMath.parse("12a4"))
        XCTAssertNil(TimestampMath.parse("17 916"))
        XCTAssertNil(TimestampMath.parse("-1791682511"))
        XCTAssertNil(TimestampMath.parse("17916825.11"))
        // 阿拉伯-印度数字等非 ASCII “数字”不接受。
        XCTAssertNil(TimestampMath.parse("١٧٩١٦٨٢٥١١"))
    }

    // MARK: - 范围

    func testValidRangeBoundaries() {
        XCTAssertTrue(TimestampMath.isValidUnixSeconds(0))
        XCTAssertTrue(TimestampMath.isValidUnixSeconds(1_791_682_511))
        XCTAssertTrue(TimestampMath.isValidUnixSeconds(253_402_300_799))
        XCTAssertFalse(TimestampMath.isValidUnixSeconds(253_402_300_800))
        XCTAssertFalse(TimestampMath.isValidUnixSeconds(-1))
    }

    // MARK: - 格式化

    func testFormatWithExplicitTimeZone() throws {
        // 1000000000 = 2001-09-09T01:46:40Z。
        let date = try XCTUnwrap(TimestampMath.parse("1000000000")).letDate()
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertEqual(TimestampMath.formattedText(date, timeZone: shanghai), "2001-09-09 09:46:40")

        let utc = TimeZone(identifier: "UTC") ?? TimeZone.current
        XCTAssertEqual(TimestampMath.formattedText(date, timeZone: utc), "2001-09-09 01:46:40")
    }

    func testISO8601Output() throws {
        let date = try XCTUnwrap(TimestampMath.parse("1791682511")).letDate()
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(TimestampMath.iso8601Text(date, timeZone: utc), "2026-10-11T01:35:11Z")
    }

    func testSecondsAndMillisecondsProduceSameDate() throws {
        let seconds = try XCTUnwrap(TimestampMath.parse("1791682511")).letDate()
        let milliseconds = try XCTUnwrap(TimestampMath.parse("1791682511000")).letDate()
        XCTAssertEqual(seconds, milliseconds)
    }

    // MARK: - 反向换算

    func testReverseConversion() {
        let date = Date(timeIntervalSince1970: 1_791_682_511.25)
        XCTAssertEqual(TimestampMath.unixSeconds(of: date), 1_791_682_511)
        XCTAssertEqual(TimestampMath.unixMilliseconds(of: date), 1_791_682_511_250)
    }

    func testRoundTrip() throws {
        let original = try XCTUnwrap(TimestampMath.parse("1791682511")).letDate()
        let backSeconds = TimestampMath.unixSeconds(of: original)
        XCTAssertEqual(try XCTUnwrap(TimestampMath.parse(String(backSeconds))).letDate(), original)
    }
}

private extension TimestampMath.ParsedTimestamp {
    func letDate() -> Date {
        TimestampMath.date(from: self)
    }
}

//
//  ContentRecognizerTests.swift
//  PasteDeck
//
//  验证剪贴板内容的纯内存识别：时间戳、IPv4/CIDR 与误判防护。
//

import Foundation
import XCTest
@testable import PasteDeck

final class ContentRecognizerTests: XCTestCase {

    // MARK: - 纯文本识别

    func testRecognizeSecondsTimestamp() {
        XCTAssertEqual(
            ContentRecognizer.recognizeText("1791682511"),
            .unixTimestamp(TimestampMath.ParsedTimestamp(rawValue: 1_791_682_511, unit: .seconds))
        )
    }

    func testRecognizeMillisecondsTimestamp() {
        XCTAssertEqual(
            ContentRecognizer.recognizeText("1791682511000"),
            .unixTimestamp(TimestampMath.ParsedTimestamp(rawValue: 1_791_682_511_000, unit: .milliseconds))
        )
    }

    func testRecognizeIPv4() {
        XCTAssertEqual(
            ContentRecognizer.recognizeText(" 220.173.103.110 "),
            .ipv4Address(IPv4Math.Address.parse("220.173.103.110")!)
        )
    }

    func testRecognizeCIDR() {
        guard case let .ipv4CIDR(address, prefix) = ContentRecognizer.recognizeText("192.168.1.0/24") else {
            return XCTFail("应识别为 CIDR")
        }
        XCTAssertEqual(address.dottedString, "192.168.1.0")
        XCTAssertEqual(prefix, 24)
    }

    func testDoesNotMisjudgeCommonText() {
        XCTAssertEqual(ContentRecognizer.recognizeText("13812345678"), .unrecognized)
        XCTAssertEqual(ContentRecognizer.recognizeText("hello world"), .unrecognized)
        XCTAssertEqual(ContentRecognizer.recognizeText("订单号 20261011000123"), .unrecognized)
        XCTAssertEqual(ContentRecognizer.recognizeText(""), .unrecognized)
        XCTAssertEqual(ContentRecognizer.recognizeText(nil), .unrecognized)
    }

    func testLongTextNotRecognized() {
        XCTAssertEqual(ContentRecognizer.recognizeText(String(repeating: "1", count: 200)), .unrecognized)
    }

    // MARK: - 卡片识别

    func testRecognizeTimestampCard() throws {
        let snapshot = makeSnapshot(contentType: .text, text: "1791682511")
        let matches = ContentRecognizer.recognize(snapshot)
        XCTAssertEqual(matches, [ContentRecognizer.Match(tool: .timestampConversion, prefilledText: "1791682511")])
    }

    func testRecognizeIPCard() throws {
        let snapshot = makeSnapshot(contentType: .text, text: "10.0.0.137")
        let matches = ContentRecognizer.recognize(snapshot)
        XCTAssertEqual(matches, [ContentRecognizer.Match(tool: .ipv4Subnet, prefilledText: "10.0.0.137")])
    }

    func testPlainTextCardHasNoMatch() {
        let snapshot = makeSnapshot(contentType: .text, text: "PasteDeck 让复制更有价值。")
        XCTAssertTrue(ContentRecognizer.recognize(snapshot).isEmpty)
    }

    func testNonTextCardsHaveNoMatch() {
        XCTAssertTrue(ContentRecognizer.recognize(makeSnapshot(contentType: .image, text: nil)).isEmpty)
        XCTAssertTrue(ContentRecognizer.recognize(makeSnapshot(contentType: .file, text: nil)).isEmpty)
        XCTAssertTrue(ContentRecognizer.recognize(makeSnapshot(contentType: .color, text: nil)).isEmpty)
        XCTAssertTrue(ContentRecognizer.recognize(makeSnapshot(contentType: .link, text: "https://example.com")).isEmpty)
    }

    func testJSONCardHasNoMatchUntilJSONToolExists() {
        // 首批没有 JSON 工具；识别不应为 JSON 内容推荐时间戳或 IP 工具。
        XCTAssertTrue(ContentRecognizer.recognize(makeSnapshot(contentType: .json, text: "{\"a\":1}")).isEmpty)
    }

    // MARK: - Helpers

    private func makeSnapshot(contentType: ClipboardContentType, text: String?) -> ClipboardItemSnapshot {
        let item = ClipboardItem(contentType: contentType, textContent: text)
        return ClipboardItemSnapshot(item: item)
    }
}

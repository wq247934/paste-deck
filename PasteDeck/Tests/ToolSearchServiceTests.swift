//
//  ToolSearchServiceTests.swift
//  PasteDeck
//
//  验证统一搜索中工具侧的关键词匹配、内容建议与排序。
//

import Foundation
import XCTest
@testable import PasteDeck

final class ToolSearchServiceTests: XCTestCase {

    private func toolIDs(_ results: [ToolSearchService.Result]) -> [String] {
        results.map(\.tool.id)
    }

    func testEmptyQueryReturnsNoTools() {
        XCTAssertTrue(ToolSearchService.search("").isEmpty)
        XCTAssertTrue(ToolSearchService.search("   ").isEmpty)
    }

    func testSearchByChineseKeyword() {
        XCTAssertTrue(toolIDs(ToolSearchService.search("时间")).contains(BuiltinTool.timestampConversion.id))
        XCTAssertTrue(toolIDs(ToolSearchService.search("时间戳")).contains(BuiltinTool.timestampConversion.id))
    }

    func testSearchByEnglishAlias() {
        XCTAssertTrue(toolIDs(ToolSearchService.search("timestamp")).contains(BuiltinTool.timestampConversion.id))
        XCTAssertTrue(toolIDs(ToolSearchService.search("ts")).contains(BuiltinTool.timestampConversion.id))
    }

    func testSearchIPCaseInsensitive() {
        let results = ToolSearchService.search("IP")
        XCTAssertTrue(toolIDs(results).contains(BuiltinTool.ipv4Subnet.id))
        XCTAssertTrue(toolIDs(ToolSearchService.search("子网")).contains(BuiltinTool.ipv4Subnet.id))
        XCTAssertTrue(toolIDs(ToolSearchService.search("cidr")).contains(BuiltinTool.ipv4Subnet.id))
    }

    func testSearchQuotaKeywords() {
        for query in ["额度", "codex", "workbuddy", "余额", "quota"] {
            XCTAssertTrue(
                toolIDs(ToolSearchService.search(query)).contains(BuiltinTool.quotaOverview.id),
                "搜索 \(query) 应命中额度工具"
            )
        }
    }

    func testContentSuggestionForTimestampQuery() {
        let results = ToolSearchService.search("1791682511")
        let timestampResult = results.first { $0.tool == .timestampConversion }
        XCTAssertEqual(timestampResult?.reason, .contentSuggestion)
        XCTAssertEqual(timestampResult?.prefilledText, "1791682511")
    }

    func testContentSuggestionForIPQuery() {
        let results = ToolSearchService.search("192.168.1.1")
        let ipResult = results.first { $0.tool == .ipv4Subnet }
        XCTAssertEqual(ipResult?.reason, .contentSuggestion)
        XCTAssertEqual(ipResult?.prefilledText, "192.168.1.1")
    }

    func testKeywordMatchDoesNotPrefill() {
        // 搜索 “时间” 命中关键词，但不应把查询词预填进工具输入框。
        let results = ToolSearchService.search("时间")
        let timestampResult = results.first { $0.tool == .timestampConversion }
        XCTAssertNotNil(timestampResult)
        XCTAssertNotEqual(timestampResult?.reason, .contentSuggestion)
        XCTAssertNil(timestampResult?.prefilledText)
    }

    func testPhoneQueryDoesNotSuggestTimestampTool() {
        let results = ToolSearchService.search("13812345678")
        XCTAssertTrue(results.isEmpty, "手机号不应触发任何工具建议")
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(ToolSearchService.search("zzz完全不匹配").isEmpty)
    }

    func testResultsSortedByScoreDescending() {
        let results = ToolSearchService.search("时间")
        XCTAssertTrue(results.count > 1 || results.count == 1)
        for index in 1..<max(1, results.count) {
            XCTAssertGreaterThanOrEqual(results[index - 1].score, results[index].score)
        }
    }

    func testEveryRegisteredToolIsDiscoverableByAtLeastOneKeyword() {
        // 保证注册的工具都能通过搜索找到，避免注册后被遗忘。
        for tool in BuiltinTool.allCases {
            let direct = ToolSearchService.search(tool.descriptor.name)
            XCTAssertTrue(toolIDs(direct).contains(tool.id), "工具 \(tool.id) 应能按名称搜到")
        }
    }
}

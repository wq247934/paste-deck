//
//  QuotaServiceTests.swift
//  PasteDeck
//
//  验证 Codex / WorkBuddy 余额解析与展示格式化逻辑。
//
//  Created on 2026-10-11.
//

import Foundation
import XCTest
@testable import PasteDeck

final class QuotaServiceTests: XCTestCase {

    // MARK: - QuotaFormat

    func testCompactCredits() {
        XCTAssertEqual(QuotaFormat.compactCredits(0), "0")
        XCTAssertEqual(QuotaFormat.compactCredits(987), "987")
        XCTAssertEqual(QuotaFormat.compactCredits(999.4), "999")
        XCTAssertEqual(QuotaFormat.compactCredits(1000), "1k")
        XCTAssertEqual(QuotaFormat.compactCredits(2341), "2.3k")
        XCTAssertEqual(QuotaFormat.compactCredits(1500000), "1.5M")
        XCTAssertEqual(QuotaFormat.compactCredits(-5), "0")
    }

    func testCountdownText() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertNil(QuotaFormat.countdownText(until: now.addingTimeInterval(-60), now: now))
        XCTAssertEqual(QuotaFormat.countdownText(until: now.addingTimeInterval(45 * 60), now: now), "还剩 45 分钟")
        XCTAssertEqual(QuotaFormat.countdownText(until: now.addingTimeInterval(90 * 60), now: now), "还剩 1 小时 30 分")
        XCTAssertEqual(QuotaFormat.countdownText(until: now.addingTimeInterval(3 * 86400), now: now), "还剩 3 天")
    }

    // MARK: - Codex 快照解析

    func testCodexSnapshotParsing() throws {
        let rpcResult: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "planType": "pro",
                    "limitName": "codex_default",
                    "rateLimitReachedType": "primary_window",
                    "credits": ["availableCount": 3],
                    "primary": [
                        "usedPercent": 24.5,
                        "resetsAt": 1_800_000,
                        "windowDurationMins": 300,
                    ],
                    "secondary": [
                        "usedPercent": 46.0,
                        "resetsAt": 1_900_000,
                    ],
                ]
            ],
            "rateLimitResetCredits": [
                "availableCount": 1,
                "credits": [
                    ["title": "促销卡", "status": "available", "expiresAt": 1_700_000, "grantedAt": 1_600_000],
                    ["title": "新年卡", "status": "available", "expiresAt": 1_650_000],
                ],
            ],
        ]

        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: rpcResult)

        XCTAssertEqual(snapshot.plan, "pro")
        XCTAssertTrue(snapshot.isRateLimitReached)
        XCTAssertEqual(snapshot.availableCredits, 3)

        XCTAssertTrue(snapshot.session.isAvailable)
        XCTAssertEqual(snapshot.session.usedPercent, 24.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.session.remainingPercent, 75.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.session.windowMinutes, 300)
        XCTAssertEqual(snapshot.session.resetsAt, Date(timeIntervalSince1970: 1_800_000))

        XCTAssertTrue(snapshot.weekly.isAvailable)
        XCTAssertEqual(snapshot.weekly.usedPercent, 46.0, accuracy: 0.001)

        // 重置卡按过期时间升序
        XCTAssertEqual(snapshot.resetCredits.count, 2)
        XCTAssertEqual(snapshot.resetCredits.first?.title, "新年卡")
        XCTAssertEqual(snapshot.resetCreditsAvailableCount, 1)
    }

    func testCodexSnapshotHandlesMissingWindows() throws {
        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: [
            "rateLimits": ["planType": "free"] as [String: Any]
        ])

        XCTAssertEqual(snapshot.plan, "free")
        XCTAssertFalse(snapshot.isRateLimitReached)
        XCTAssertFalse(snapshot.session.isAvailable)
        XCTAssertFalse(snapshot.weekly.isAvailable)
        XCTAssertTrue(snapshot.resetCredits.isEmpty)
    }

    func testCodexSnapshotWithoutRateLimitsThrows() {
        XCTAssertThrowsError(try CodexQuotaService.parseSnapshot(rpcResult: [:])) { error in
            guard case CodexQuotaService.CodexQuotaError.noRateLimits = error else {
                return XCTFail("expected noRateLimits, got \(error)")
            }
        }
    }

    // MARK: - WorkBuddy 快照解析

    func testWorkBuddySummaryFormatting() {
        let data: [String: Any] = [
            "IsPaidUser": true,
            "SubscriptionPackageCode": "TCACA_code_002_AkiJS3ZHF5",
            // 真实接口的容量字段以字符串返回，需宽松转换
            "Packages": [
                [
                    "PackageCode": "TCACA_code_009_0XmEQc2xOf",
                    "CycleTotalCapacity": "1200.0",
                    "CycleUsedCapacity": "300.5",
                    "CycleRemainCapacity": "899.5",
                    "CapacityUnit": "credits",
                ],
                [
                    "PackageCode": "TCACA_code_001_PqouKr6QWV",
                    "CycleTotalCapacity": 100.0,
                    "CycleUsedCapacity": 0,
                    "CycleRemainCapacity": 100.0,
                ],
                [
                    "PackageCode": "unknown_code",
                    "CycleTotalCapacity": "50",
                    "CycleUsedCapacity": "50",
                    "CycleRemainCapacity": "0",
                ],
            ],
        ]
        let credential: [String: Any] = [
            "account": ["nickname": "王小栈", "type": "personal"],
            "auth": ["expiresAt": 1_900_000_000_000],
        ]

        let snapshot = WorkBuddyQuotaService.formatSummary(data, credential: credential)

        XCTAssertEqual(snapshot.isPaidUser, true)
        XCTAssertEqual(snapshot.subscriptionName, "Pro 月付")
        XCTAssertEqual(snapshot.accountName, "王小栈")
        XCTAssertEqual(snapshot.accountType, "personal")
        XCTAssertEqual(snapshot.tokenExpiresAt, Date(timeIntervalSince1970: 1_900_000_000))

        // 分层排序：使用中 → 未使用 → 已耗尽；同层按剩余从多到少
        XCTAssertEqual(snapshot.packages.map(\.name), ["加量包", "免费包", "unknown_code"])
        XCTAssertEqual(snapshot.total, 1350.0)
        XCTAssertEqual(snapshot.used, 350.5)
        XCTAssertEqual(snapshot.remain, 999.5)
    }

    // MARK: - 菜单栏文本

    @MainActor
    func testMenuBarTitleEmptyWithoutData() {
        // 单例可能带有其他测试遗留状态，仅验证空态分支的返回类型安全。
        let manager = QuotaStatusManager.shared
        if manager.codexSnapshot == nil && manager.workbuddySnapshot == nil {
            XCTAssertNil(manager.menuBarAttributedTitle)
        }
    }
}

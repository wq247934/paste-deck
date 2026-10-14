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
                    "rateLimitReachedType": "rate_limit_reached",
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
        XCTAssertEqual(snapshot.rateLimitReachedType, "rate_limit_reached")
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

    /// 回归：rateLimitReachedType 是与 primary / secondary 平级的全局标志，
    /// 只描述账户层面的限流原因。5 小时窗口用尽时，每周窗口的余量不能被一并抹成 0。
    func testCodexWeeklyQuotaNotZeroedByGlobalRateLimitFlag() throws {
        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: [
            "rateLimitsByLimitId": [
                "codex": [
                    "planType": "plus",
                    "rateLimitReachedType": "rate_limit_reached",
                    "primary": [
                        "usedPercent": 100,
                        "windowDurationMins": 300,
                        "resetsAt": 1_791_788_133,
                    ],
                    "secondary": [
                        "usedPercent": 63,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_792_296_146,
                    ],
                ]
            ]
        ])

        // 全局限流标志为真
        XCTAssertTrue(snapshot.isRateLimitReached)

        // 5 小时窗口确实用尽
        XCTAssertTrue(snapshot.session.isLimitReached)
        XCTAssertEqual(snapshot.session.displayRemainingPercent, 0, accuracy: 0.001)

        // 每周窗口仍有 37% 余量，不受全局标志影响
        XCTAssertFalse(snapshot.weekly.isLimitReached)
        XCTAssertEqual(snapshot.weekly.displayRemainingPercent, 37, accuracy: 0.001)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 37, accuracy: 0.001)
        XCTAssertEqual(snapshot.weekly.windowMinutes, 10_080)
    }

    /// 反向场景：只有周额度触顶时，5 小时窗口同样不受影响。
    func testCodexSessionQuotaNotZeroedWhenOnlyWeeklyExhausted() throws {
        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: [
            "rateLimitsByLimitId": [
                "codex": [
                    "rateLimitReachedType": "rate_limit_reached",
                    "primary": ["usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1_791_788_133],
                    "secondary": ["usedPercent": 100, "windowDurationMins": 10_080, "resetsAt": 1_792_296_146],
                ]
            ]
        ])

        XCTAssertFalse(snapshot.session.isLimitReached)
        XCTAssertEqual(snapshot.session.displayRemainingPercent, 88, accuracy: 0.001)
        XCTAssertTrue(snapshot.weekly.isLimitReached)
        XCTAssertEqual(snapshot.weekly.displayRemainingPercent, 0, accuracy: 0.001)
    }

    /// 无 rateLimitReachedType 时视为未限流，各窗口仍按自身 usedPercent 计算。
    func testCodexSnapshotWithoutRateLimitTypeLeavesWindowsIntact() throws {
        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: [
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["usedPercent": 100, "windowDurationMins": 300, "resetsAt": 1_800_000],
                    "secondary": ["usedPercent": 63, "windowDurationMins": 10_080, "resetsAt": 1_900_000],
                ]
            ]
        ])

        XCTAssertFalse(snapshot.isRateLimitReached)
        XCTAssertNil(snapshot.rateLimitReachedType)
        XCTAssertTrue(snapshot.session.isLimitReached)
        XCTAssertEqual(snapshot.weekly.displayRemainingPercent, 37, accuracy: 0.001)
    }

    func testCodexSnapshotHandlesMissingWindows() throws {
        let snapshot = try CodexQuotaService.parseSnapshot(rpcResult: [
            "rateLimits": ["planType": "free"] as [String: Any]
        ])

        XCTAssertEqual(snapshot.plan, "free")
        XCTAssertFalse(snapshot.isRateLimitReached)
        XCTAssertNil(snapshot.rateLimitReachedType)
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

    // MARK: - Gemini 快照解析

    func testGeminiSnapshotParsing() throws {
        let json: [String: Any] = [
            "accounts": [
                [
                    "id": "ce8e736c-45ac-4cf4-b50e-3aae7cc02bfc",
                    "email": "wq247934918@gmail.com",
                    "name": "qian king",
                    "priority": 50,
                    "is_current": true,
                    "disabled": false,
                    "quota": [
                        "subscription_tier": "PRO",
                        "is_forbidden": false,
                        "last_updated": 1_791_896_896,
                        "models": [
                            [
                                "name": "gemini-3.8-flash-high",
                                "percentage": 49,
                                "reset_time": "2026-10-18T09:27:24Z",
                            ],
                            [
                                "name": "gemini-2.5-pro",
                                "percentage": 49,
                                "reset_time": "2026-10-18T09:27:24Z",
                            ],
                        ],
                        "quota_groups": [
                            [
                                "display_name": "Gemini Models",
                                "description": "Models within this group: Gemini Flash, Gemini Pro",
                                "buckets": [
                                    [
                                        "bucket_id": "gemini-weekly",
                                        "window": "weekly",
                                        "remaining_fraction": 0.49074173,
                                        "reset_time": "2026-10-18T09:27:24Z",
                                        "cycle_tokens": 554_417_446,
                                        "display_name": "Weekly Limit Remaining",
                                    ],
                                    [
                                        "bucket_id": "gemini-5h",
                                        "window": "5h",
                                        "remaining_fraction": 0.6272899,
                                        "reset_time": "2026-10-13T16:02:58Z",
                                        "display_name": "Five Hour Limit Remaining",
                                    ],
                                ],
                            ],
                            [
                                "display_name": "Claude and GPT models",
                                "buckets": [
                                    [
                                        "bucket_id": "3p-weekly",
                                        "window": "weekly",
                                        "remaining_fraction": 0.0,
                                        "reset_time": "2026-10-14T02:12:11Z",
                                        "display_name": "Weekly Limit Remaining",
                                    ],
                                    [
                                        "bucket_id": "3p-5h",
                                        "window": "5h",
                                        "remaining_fraction": 1.0,
                                        "reset_time": "2026-10-13T18:08:17Z",
                                        "display_name": "Five Hour Limit Remaining",
                                    ],
                                ],
                            ],
                        ],
                    ],
                ]
            ],
            "current_account_id": "ce8e736c-45ac-4cf4-b50e-3aae7cc02bfc",
        ]

        let snapshot = try GeminiQuotaService.parseSnapshot(json: json)

        XCTAssertEqual(snapshot.accountId, "ce8e736c-45ac-4cf4-b50e-3aae7cc02bfc")
        XCTAssertEqual(snapshot.accountEmail, "wq247934918@gmail.com")
        XCTAssertEqual(snapshot.accountName, "qian king")
        XCTAssertEqual(snapshot.subscriptionTier, "PRO")
        XCTAssertFalse(snapshot.isForbidden)

        // 5 小时窗口
        XCTAssertTrue(snapshot.session.isAvailable)
        XCTAssertEqual(snapshot.session.remainingPercent, 62.72899, accuracy: 0.001)
        XCTAssertEqual(snapshot.session.displayRemainingPercent, 62.72899, accuracy: 0.001)
        XCTAssertFalse(snapshot.session.isLimitReached)
        XCTAssertNotNil(snapshot.session.resetsAt)

        // 每周窗口
        XCTAssertTrue(snapshot.weekly.isAvailable)
        XCTAssertEqual(snapshot.weekly.remainingPercent, 49.074173, accuracy: 0.001)
        XCTAssertFalse(snapshot.weekly.isLimitReached)
        XCTAssertNotNil(snapshot.weekly.resetsAt)

        // 模型明细
        XCTAssertEqual(snapshot.models.count, 2)
        XCTAssertEqual(snapshot.models.first?.name, "gemini-3.8-flash-high")
        XCTAssertEqual(snapshot.models.first?.percentage, 49.0)

        // 第三方 3p 组
        XCTAssertNotNil(snapshot.thirdPartySession)
        XCTAssertEqual(snapshot.thirdPartySession?.remainingPercent, 100.0)
        XCTAssertNotNil(snapshot.thirdPartyWeekly)
        XCTAssertTrue(snapshot.thirdPartyWeekly?.isLimitReached == true)
        XCTAssertEqual(snapshot.thirdPartyWeekly?.displayRemainingPercent, 0.0)
    }

    func testGeminiSnapshotFallbackToModels() throws {
        let json: [String: Any] = [
            "accounts": [
                [
                    "email": "test@example.com",
                    "quota": [
                        "models": [
                            [
                                "name": "gemini-3.5-flash",
                                "percentage": 78,
                                "reset_time": "2026-10-14T00:00:00Z",
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let snapshot = try GeminiQuotaService.parseSnapshot(json: json)
        XCTAssertTrue(snapshot.session.isAvailable)
        XCTAssertEqual(snapshot.session.remainingPercent, 78.0)
        XCTAssertEqual(snapshot.session.displayRemainingPercent, 78.0)
        XCTAssertFalse(snapshot.weekly.isAvailable)
    }

    func testGeminiSnapshotWithoutAccountsThrows() {
        XCTAssertThrowsError(try GeminiQuotaService.parseSnapshot(json: [:])) { error in
            guard case GeminiQuotaService.GeminiQuotaError.noAccountData = error else {
                return XCTFail("expected noAccountData, got \(error)")
            }
        }
    }

    // MARK: - Gemini Token 统计解析测试

    func testGeminiTokenStatsParsing() {
        let summaryJson: [String: Any] = [
            "total_tokens": 989_200_000.0,
            "total_input_tokens": 988_500_000.0,
            "total_output_tokens": 706_700.0,
            "total_cached_tokens": 938_000_000.0,
            "total_requests": 3206,
            "unique_accounts": 1,
        ]

        let modelsJson: [[String: Any]] = [
            [
                "model": "gemini-3.8-flash",
                "request_count": 3196,
                "total_input_tokens": 987_600_000.0,
                "total_output_tokens": 693_100.0,
                "total_cached_tokens": 937_900_000.0,
                "total_tokens": 988_293_100.0,
            ],
            [
                "model": "claude-sonnet-4-6",
                "request_count": 7,
                "total_input_tokens": 778_800.0,
                "total_output_tokens": 8_400.0,
                "total_cached_tokens": 57_400.0,
                "total_tokens": 787_200.0,
            ]
        ]

        let accountsJson: [[String: Any]] = [
            [
                "account_email": "wq247934918@gmail.com",
                "request_count": 3206,
                "total_tokens": 989_200_000.0,
            ]
        ]

        let summary = GeminiQuotaService.parseTokenStatsSummary(json: summaryJson, modelsCount: modelsJson.count)
        XCTAssertEqual(summary.totalTokens, 989_200_000.0)
        XCTAssertEqual(summary.totalInputTokens, 988_500_000.0)
        XCTAssertEqual(summary.totalOutputTokens, 706_700.0)
        XCTAssertEqual(summary.totalCachedTokens, 938_000_000.0)
        XCTAssertEqual(summary.totalRequests, 3206)
        XCTAssertEqual(summary.uniqueAccounts, 1)
        XCTAssertEqual(summary.modelsCount, 2)

        let models = GeminiQuotaService.parseModelTokenStats(jsonArray: modelsJson, totalTokens: summary.totalTokens)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].model, "gemini-3.8-flash")
        XCTAssertEqual(models[0].requestCount, 3196)
        XCTAssertEqual(models[0].percentage, 99.9083, accuracy: 0.01)

        let accounts = GeminiQuotaService.parseAccountTokenStats(jsonArray: accountsJson, totalTokens: summary.totalTokens)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].accountEmail, "wq247934918@gmail.com")
        XCTAssertEqual(accounts[0].percentage, 100.0, accuracy: 0.01)
    }

    // MARK: - WorkBuddy2API 网关解析与格式化测试

    func testWorkBuddyGatewayOverviewParsing() {
        let json: [String: Any] = [
            "service": "workbuddy2api",
            "version": "1.11.11-panel",
            "healthy": 1,
            "total": 1,
            "cooling": 0,
            "disabled": 0,
            "sticky_sessions": 0,
            "uptime_sec": 560934,
            "redis_mode": "noop",
            "accounts": [
                [
                    "uid": "ae2c16ea-bb2d-4664-9508-769dad4a1e0d",
                    "nickname": "King乾",
                    "credits": 1066.0,
                    "credits_total": 12689.0,
                    "realm": "cn",
                    "disabled": false,
                    "cooling": false,
                    "success_count": 8526,
                    "err_total": 0,
                    "in_flight": 0,
                    "consecutive_fails": 0,
                ]
            ]
        ]

        let overview = WorkBuddyGatewayService.parseOverview(json)
        XCTAssertEqual(overview.service, "workbuddy2api")
        XCTAssertEqual(overview.version, "1.11.11-panel")
        XCTAssertEqual(overview.healthy, 1)
        XCTAssertEqual(overview.total, 1)
        XCTAssertEqual(overview.healthPercentage, 100)
        XCTAssertEqual(overview.uptimeSec, 560934)
        XCTAssertEqual(overview.accounts.count, 1)

        let acc = overview.accounts[0]
        XCTAssertEqual(acc.displayName, "King乾")
        XCTAssertEqual(acc.avatarInitial, "K")
        XCTAssertEqual(acc.credits, 1066.0)
        XCTAssertEqual(acc.creditsTotal, 12689.0)
        XCTAssertEqual(acc.successRateText, "100%")

        let (statusText, pill) = WorkBuddyGatewayService.accountStatus(acc)
        XCTAssertEqual(statusText, "正常")
        XCTAssertEqual(pill, "ok")

        // 格式化函数验证（与 codex-quota-utools 丝毫不差）
        XCTAssertEqual(WorkBuddyGatewayService.fmtUptime(560934), "6 天 11 小时")
        XCTAssertEqual(WorkBuddyGatewayService.fmtCredits(1066.0), "1066")
        XCTAssertEqual(WorkBuddyGatewayService.fmtBig(951_835_021), "951.8M")
        XCTAssertEqual(WorkBuddyGatewayService.fmtBig(2562), "2562")
    }

    func testWorkBuddyGatewayPackagesSorting() {
        let json: [String: Any] = [
            "accounts": [
                [
                    "uid": "test-uid",
                    "nickname": "测试账号",
                    "remain": 534.0,
                    "packages": [
                        [
                            "package_code": "pkg_unused",
                            "name": "未动包",
                            "size": 500.0,
                            "remain": 500.0,
                            "used": 0.0,
                        ],
                        [
                            "package_code": "pkg_exhausted",
                            "name": "耗尽包",
                            "size": 100.0,
                            "remain": 0.0,
                            "used": 100.0,
                        ],
                        [
                            "package_code": "pkg_in_use",
                            "name": "使用中包",
                            "size": 100.0,
                            "remain": 34.0,
                            "used": 66.0,
                        ]
                    ]
                ]
            ]
        ]

        let accounts = WorkBuddyGatewayService.parsePackages(json)
        XCTAssertEqual(accounts.count, 1)
        let pkgs = accounts[0].packages
        XCTAssertEqual(pkgs.count, 3)

        // 分层排序：使用中 (Tier 0) -> 未动 (Tier 1) -> 已耗尽 (Tier 2)
        XCTAssertEqual(pkgs[0].name, "使用中包")
        XCTAssertEqual(pkgs[0].tier, 0)
        XCTAssertEqual(pkgs[1].name, "未动包")
        XCTAssertEqual(pkgs[1].tier, 1)
        XCTAssertEqual(pkgs[2].name, "耗尽包")
        XCTAssertEqual(pkgs[2].tier, 2)
    }

    func testWorkBuddyGatewayUsageParsing() {
        let json: [String: Any] = [
            "generated": "2026-10-13T10:00:00+08:00",
            "totals": [
                "requests": 2562,
                "errors": 42,
                "total_tokens": 444_311_322.0,
                "prompt_tokens": 443_007_605.0,
                "completion_tokens": 1_303_717.0,
            ],
            "by_model": [
                [
                    "key": "space-bunny",
                    "requests": 1102,
                    "total_tokens": 205_800_000.0,
                    "avg_latency_ms": 16120.0,
                ]
            ],
            "by_account": [
                [
                    "key": "King乾",
                    "requests": 2562,
                    "total_tokens": 444_311_322.0,
                ]
            ]
        ]

        let usage = WorkBuddyGatewayService.parseUsage(json, hours: 72)
        XCTAssertEqual(usage.hours, 72)
        XCTAssertEqual(usage.totals.requests, 2562)
        XCTAssertEqual(usage.totals.errors, 42)
        XCTAssertEqual(usage.totals.successRateText, "98%")
        XCTAssertEqual(usage.byModel.count, 1)
        XCTAssertEqual(usage.byModel[0].key, "space-bunny")
        XCTAssertEqual(usage.byModel[0].latencyText, "16120ms")
        XCTAssertEqual(usage.byAccount.count, 1)
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

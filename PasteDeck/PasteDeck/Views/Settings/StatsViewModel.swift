//
//  StatsViewModel.swift
//  PasteDeck
//
//  Created on 2026-07-07.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class StatsViewModel: ObservableObject {

    @Published var overview: OverviewStats?
    @Published var trend: [DailyTrendPoint] = []
    @Published var typeDistribution: [TypeDistributionItem] = []
    @Published var topSourceApps: [SourceAppStat] = []
    @Published var extremes: ExtremeStats?
    @Published var translationUsage: [TranslationUsageStat] = []
    @Published var isLoading = false
    @Published var trendDays: Int = 7
    @Published var translationUsageDays: Int = 7
    @Published var translationUsageFilter: TranslationUsageFilter = .all

    private var hasLoaded = false
    private var reloadTask: Task<Void, Never>?

    /// 当前筛选范围内的翻译明细；切换范围只做内存聚合，不重复读取 SwiftData。
    var filteredTranslationUsage: [TranslationUsageStat] {
        StatsService.filterTranslationUsage(translationUsage, by: translationUsageFilter)
    }

    /// 当前筛选范围内的请求、成功率、字符与 Token 用量摘要。
    var translationUsageSummary: TranslationUsageSummary {
        StatsService.makeTranslationUsageSummary(from: filteredTranslationUsage)
    }

    /// 当前时间范围内常规 API 的字符用量摘要；“全部”视图用它避免把大模型字符数混入 API 指标。
    var translationAPIUsageSummary: TranslationUsageSummary {
        StatsService.makeTranslationUsageSummary(
            from: StatsService.filterTranslationUsage(translationUsage, by: .api)
        )
    }

    /// 当前时间范围内大模型的 Token 用量摘要；“全部”视图用它与 API 字符数分开呈现。
    var translationLLMUsageSummary: TranslationUsageSummary {
        StatsService.makeTranslationUsageSummary(
            from: StatsService.filterTranslationUsage(translationUsage, by: .llm)
        )
    }

    /// 当前筛选范围内按日期与调用类别聚合的趋势图数据。
    var translationUsageDailyPoints: [TranslationUsageDailyPoint] {
        StatsService.makeTranslationUsageDailyPoints(
            from: filteredTranslationUsage,
            days: translationUsageDays
        )
    }

    /// 当前筛选范围内调用次数最多的服务排行。
    var translationUsageServicePoints: [TranslationUsageServicePoint] {
        StatsService.makeTranslationUsageServicePoints(from: filteredTranslationUsage)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        loadAll()
    }

    func loadAll() {
        isLoading = true
        hasLoaded = true

        let days = trendDays
        let usageDays = translationUsageDays

        Task { [weak self] in
            // 串行执行所有查询，避免多个 ModelContext 并发访问同一 container 导致崩溃
            let result = await Task.detached(priority: .userInitiated) {
                let overview = StatsService.fetchOverview()
                let trend = StatsService.fetchTrend(days: days)
                let distribution = StatsService.fetchTypeDistribution()
                let apps = StatsService.fetchTopSourceApps()
                let extremes = StatsService.fetchExtremes()
                let translationUsage = StatsService.fetchTranslationUsage(days: usageDays)

                return (overview, trend, distribution, apps, extremes, translationUsage)
            }.value

            guard let self else { return }

            self.overview = result.0
            self.trend = result.1
            self.typeDistribution = result.2
            self.topSourceApps = result.3
            self.extremes = result.4
            self.translationUsage = result.5
            self.isLoading = false
        }
    }

    func reloadTrend() {
        let days = trendDays
        Task { [weak self] in
            let trend = await Task.detached(priority: .userInitiated) { StatsService.fetchTrend(days: days) }.value
            guard let self else { return }
            self.trend = trend
        }
    }

    /// 单独刷新翻译调用聚合，避免切换统计时间范围时重复读取剪贴板历史。
    func reloadTranslationUsage() {
        let days = translationUsageDays
        Task { [weak self] in
            let usage = await Task.detached(priority: .userInitiated) {
                StatsService.fetchTranslationUsage(days: days)
            }.value
            guard let self else { return }
            self.translationUsage = usage
        }
    }

    /// 收到剪贴板变更通知时调用，debounce 后重载全部数据。
    func handleClipboardChanged() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.loadAll()
        }
    }

    /// 收到翻译调用完成通知时只刷新翻译统计，避免无关数据查询。
    func handleTranslationUsageChanged() {
        reloadTranslationUsage()
    }
}

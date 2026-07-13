//
//  StatsService.swift
//  PasteDeck
//
//  Provides aggregated statistics data for the stats panel.
//  All queries run on background threads with isolated ModelContext.
//
//  Created on 2026-07-07.
//

import Foundation
import SwiftData

// MARK: - Data Structures

struct OverviewStats: Equatable, Sendable {
    let todayCount: Int
    let totalItems: Int
    let cacheBytes: Int
}

struct DailyTrendPoint: Identifiable, Equatable, Sendable {
    let id: Date
    let date: Date
    let count: Int
}

struct TypeDistributionItem: Identifiable, Equatable, Sendable {
    let id: String
    let type: ClipboardContentType
    let count: Int
    let percentage: Double
}

struct SourceAppStat: Identifiable, Equatable, Sendable {
    let id: String
    let appName: String
    let count: Int
}

struct ExtremeStats: Equatable, Sendable {
    let longestTextChars: Int?
    let largestImageSize: String?
    let largestFileDisplay: String?
    let earliestRecordDate: Date?
    let totalFavorites: Int
    let totalPinned: Int
}

/// 翻译调用统计行，直接对应一个“日期 + 服务类型 + 密钥 + 模型”的聚合快照。
struct TranslationUsageStat: Identifiable, Equatable, Sendable {
    /// 聚合快照的稳定标识，用于 SwiftUI 列表渲染。
    let id: UUID
    /// 该行所属日期的零点。
    let date: Date
    /// 调用种类；候选值为 api、llm。
    let usageKind: String
    /// 服务商种类；常规 API 为 baidu、tencent、youdao、alibaba，LLM 为 llm。
    let providerKind: String
    /// 用户设置的服务或密钥名称。
    let providerName: String
    /// 不可逆密钥指纹，支持区分同一服务的不同密钥。
    let credentialFingerprint: String
    /// 大模型标识；常规 API 为空字符串。
    let modelName: String
    /// 翻译请求总数，包含失败请求。
    let requestCount: Int
    /// 成功请求数。
    let successCount: Int
    /// 失败请求数。
    let failedCount: Int
    /// 原文字符总数。
    let sourceCharacterCount: Int
    /// 译文字符总数。
    let translatedCharacterCount: Int
    /// 大模型输入 token 总数；服务未返回 usage 时为零。
    let promptTokenCount: Int
    /// 大模型输出 token 总数；服务未返回 usage 时为零。
    let completionTokenCount: Int
}

/// 翻译统计的查看范围；候选值为 all、api、llm。
enum TranslationUsageFilter: String, CaseIterable, Identifiable, Sendable {
    /// 同时查看常规 API 与大模型调用。
    case all
    /// 只查看常规机器翻译 API。
    case api
    /// 只查看 OpenAI-compatible 大模型。
    case llm

    /// SwiftUI Picker 使用的稳定标识。
    var id: String { rawValue }

    /// 统计页筛选器展示名称。
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .api: return "API"
        case .llm: return "大模型"
        }
    }
}

/// 当前筛选范围内的翻译统计摘要。
struct TranslationUsageSummary: Equatable, Sendable {
    /// 总请求数，包含失败请求。
    let requestCount: Int
    /// 成功请求数。
    let successCount: Int
    /// 失败请求数。
    let failedCount: Int
    /// 原文字符总数；常规 API 统计页以字符作为输入用量单位。
    let sourceCharacterCount: Int
    /// 译文字符总数；常规 API 统计页以字符作为输出用量单位。
    let translatedCharacterCount: Int
    /// 大模型输入 token 总数。
    let promptTokenCount: Int
    /// 大模型输出 token 总数。
    let completionTokenCount: Int

    /// 成功率；没有请求时为零。
    var successRate: Double {
        requestCount > 0 ? Double(successCount) / Double(requestCount) : 0
    }
}

/// 翻译调用趋势图中的单日、单类别数据点。
struct TranslationUsageDailyPoint: Identifiable, Equatable, Sendable {
    /// 日期与调用类别组成的稳定图表标识。
    let id: String
    /// 数据点所属日期零点。
    let date: Date
    /// 调用种类；候选值为 api、llm。
    let usageKind: String
    /// 当日该类别的请求数。
    let requestCount: Int
    /// 当日该类别的成功请求数，用于悬停详情。
    let successCount: Int
    /// 当日该类别的失败请求数，用于悬停详情。
    let failedCount: Int
    /// 当日原文字符总数；常规 API 的悬停详情以此表示输入用量。
    let sourceCharacterCount: Int
    /// 当日译文字符总数；常规 API 的悬停详情以此表示输出用量。
    let translatedCharacterCount: Int
    /// 当日大模型输入 token 总数；服务未返回 usage 时为零。
    let promptTokenCount: Int
    /// 当日大模型输出 token 总数；服务未返回 usage 时为零。
    let completionTokenCount: Int
}

/// 服务调用排行图中的聚合数据点。
struct TranslationUsageServicePoint: Identifiable, Equatable, Sendable {
    /// 调用类别、服务名称和模型组成的稳定图表标识。
    let id: String
    /// 图表展示名称；大模型会包含模型标识。
    let displayName: String
    /// 调用种类；候选值为 api、llm。
    let usageKind: String
    /// 所选时段内的请求总数。
    let requestCount: Int
    /// 所选时段内的成功请求数，用于悬停详情。
    let successCount: Int
    /// 所选时段内的失败请求数，用于悬停详情。
    let failedCount: Int
    /// 所选时段内的原文字符总数；常规 API 的悬停详情以此表示输入用量。
    let sourceCharacterCount: Int
    /// 所选时段内的译文字符总数；常规 API 的悬停详情以此表示输出用量。
    let translatedCharacterCount: Int
    /// 所选时段内的大模型输入 token 总数；服务未返回 usage 时为零。
    let promptTokenCount: Int
    /// 所选时段内的大模型输出 token 总数；服务未返回 usage 时为零。
    let completionTokenCount: Int
}

// MARK: - StatsService

enum StatsService {

    // MARK: - Overview

    nonisolated static func fetchOverview() -> OverviewStats {
        let context = ModelContext(AppModelContainer.container)

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayDescriptor = FetchDescriptor<DailyStatsSnapshot>(
            predicate: #Predicate { $0.date == todayStart }
        )
        let todayCount = ((try? context.fetch(todayDescriptor).first)?.totalCount) ?? 0

        let totalItems = (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0

        let cacheBytes = CacheManager().getTotalCacheSize()

        return OverviewStats(
            todayCount: todayCount,
            totalItems: totalItems,
            cacheBytes: cacheBytes
        )
    }

    // MARK: - Trend

    nonisolated static func fetchTrend(days: Int) -> [DailyTrendPoint] {
        let context = ModelContext(AppModelContainer.container)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) else {
            return []
        }

        let descriptor = FetchDescriptor<DailyStatsSnapshot>(
            predicate: #Predicate { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []

        // 构建日期 -> count 映射，补齐空缺日期
        var countByDate: [Date: Int] = [:]
        for snapshot in snapshots {
            countByDate[snapshot.date] = snapshot.totalCount
        }

        var points: [DailyTrendPoint] = []
        for offset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: offset, to: startDate) {
                points.append(DailyTrendPoint(
                    id: date,
                    date: date,
                    count: countByDate[date] ?? 0
                ))
            }
        }

        return points
    }

    // MARK: - Type Distribution

    nonisolated static func fetchTypeDistribution() -> [TypeDistributionItem] {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<DailyStatsSnapshot>()
        let snapshots = (try? context.fetch(descriptor)) ?? []

        var totalCounts: [String: Int] = [:]
        var grandTotal = 0

        for snapshot in snapshots {
            for (typeKey, count) in snapshot.typeCounts {
                totalCounts[typeKey, default: 0] += count
                grandTotal += count
            }
        }

        let allTypes = ClipboardContentType.allCases
        let items = allTypes.compactMap { type -> TypeDistributionItem? in
            let count = totalCounts[type.rawValue] ?? 0
            guard count > 0 else { return nil }
            let percentage = grandTotal > 0 ? Double(count) / Double(grandTotal) * 100 : 0
            return TypeDistributionItem(
                id: type.rawValue,
                type: type,
                count: count,
                percentage: percentage
            )
        }

        return items.sorted { $0.count > $1.count }
    }

    // MARK: - Top Source Apps

    nonisolated static func fetchTopSourceApps(limit: Int = 5) -> [SourceAppStat] {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<DailyStatsSnapshot>()
        let snapshots = (try? context.fetch(descriptor)) ?? []

        var appCounts: [String: Int] = [:]
        for snapshot in snapshots {
            for (appName, count) in snapshot.sourceAppCounts {
                appCounts[appName, default: 0] += count
            }
        }

        return appCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { SourceAppStat(id: $0.key, appName: $0.key, count: $0.value) }
    }

    // MARK: - Extremes

    nonisolated static func fetchExtremes() -> ExtremeStats {
        let context = ModelContext(AppModelContainer.container)

        // 全量读取，内存中按类型过滤
        let allItems = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []

        // 最长文本
        var longestTextChars: Int? = nil
        let maxText = allItems
            .filter { $0.contentType == .text }
            .map { $0.textContent?.count ?? 0 }
            .max()
        if let maxText, maxText > 0 { longestTextChars = maxText }

        // 最大图片
        var largestImageSize: String? = nil
        if let largest = allItems.filter({ $0.contentType == .image }).max(by: { $0.fileSize < $1.fileSize }) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            largestImageSize = "\(formatter.string(fromByteCount: Int64(largest.fileSize))) · \(largest.imageWidth)×\(largest.imageHeight)"
        }

        // 最大文件引用
        var largestFileDisplay: String? = nil
        if let largest = allItems.filter({ $0.contentType == .file }).max(by: { $0.fileSize < $1.fileSize }) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let name = largest.fileName ?? "未知文件"
            largestFileDisplay = "\(name) · \(formatter.string(fromByteCount: Int64(largest.fileSize)))"
        }

        // 最早记录
        let earliestDate = allItems.map(\.createdAt).min()

        // 收藏数与置顶数
        let totalFavorites = allItems.filter { ($0.collections ?? []).contains(where: { $0.isDefault }) }.count
        let totalPinned = allItems.filter(\.isPinned).count

        return ExtremeStats(
            longestTextChars: longestTextChars,
            largestImageSize: largestImageSize,
            largestFileDisplay: largestFileDisplay,
            earliestRecordDate: earliestDate,
            totalFavorites: totalFavorites,
            totalPinned: totalPinned
        )
    }

    // MARK: - Translation Usage

    /// 读取最近指定天数内按日、服务类型、密钥与模型聚合的翻译用量。
    nonisolated static func fetchTranslationUsage(days: Int) -> [TranslationUsageStat] {
        let context = ModelContext(AppModelContainer.container)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: todayStart) else {
            return []
        }
        let descriptor = FetchDescriptor<TranslationUsageSnapshot>(
            predicate: #Predicate { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []
        return snapshots
            .map { snapshot in
                TranslationUsageStat(
                    id: snapshot.id,
                    date: snapshot.date,
                    usageKind: snapshot.usageKindRawValue,
                    providerKind: snapshot.providerKindRawValue,
                    providerName: snapshot.providerName,
                    credentialFingerprint: snapshot.credentialFingerprint,
                    modelName: snapshot.modelName,
                    requestCount: snapshot.requestCount,
                    successCount: snapshot.successCount,
                    failedCount: snapshot.failedCount,
                    sourceCharacterCount: snapshot.sourceCharacterCount,
                    translatedCharacterCount: snapshot.translatedCharacterCount,
                    promptTokenCount: snapshot.promptTokenCount,
                    completionTokenCount: snapshot.completionTokenCount
                )
            }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                if $0.usageKind != $1.usageKind { return $0.usageKind < $1.usageKind }
                return $0.providerName < $1.providerName
            }
    }

    /// 按“全部、常规 API、大模型”筛选本地聚合结果，不触发新的 SwiftData 查询。
    nonisolated static func filterTranslationUsage(
        _ usage: [TranslationUsageStat],
        by filter: TranslationUsageFilter
    ) -> [TranslationUsageStat] {
        switch filter {
        case .all:
            return usage
        case .api:
            return usage.filter { $0.usageKind == TranslationUsageKind.api.rawValue }
        case .llm:
            return usage.filter { $0.usageKind == TranslationUsageKind.llm.rawValue }
        }
    }

    /// 汇总当前筛选范围内的请求、成功率、字符与 Token 用量。
    nonisolated static func makeTranslationUsageSummary(
        from usage: [TranslationUsageStat]
    ) -> TranslationUsageSummary {
        TranslationUsageSummary(
            requestCount: usage.reduce(0) { $0 + $1.requestCount },
            successCount: usage.reduce(0) { $0 + $1.successCount },
            failedCount: usage.reduce(0) { $0 + $1.failedCount },
            sourceCharacterCount: usage.reduce(0) { $0 + $1.sourceCharacterCount },
            translatedCharacterCount: usage.reduce(0) { $0 + $1.translatedCharacterCount },
            promptTokenCount: usage.reduce(0) { $0 + $1.promptTokenCount },
            completionTokenCount: usage.reduce(0) { $0 + $1.completionTokenCount }
        )
    }

    /// 将明细聚合为“日期 + API/大模型”的趋势数据点。
    nonisolated static func makeTranslationUsageDailyPoints(
        from usage: [TranslationUsageStat],
        days: Int,
        endingAt endDate: Date = Date()
    ) -> [TranslationUsageDailyPoint] {
        let calendar = Calendar.current
        let normalizedDayCount = max(1, days)
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(
            byAdding: .day,
            value: -(normalizedDayCount - 1),
            to: endDay
        ) else {
            return []
        }
        let usageKinds = Set(usage.map(\.usageKind)).sorted()
        guard !usageKinds.isEmpty else { return [] }
        let usageByDate = Dictionary(grouping: usage) { calendar.startOfDay(for: $0.date) }
        var points: [TranslationUsageDailyPoint] = []

        for dayOffset in 0..<normalizedDayCount {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            let usageByKind = Dictionary(grouping: usageByDate[date] ?? [], by: \.usageKind)
            for usageKind in usageKinds {
                let dailyUsage = usageByKind[usageKind] ?? []
                points.append(TranslationUsageDailyPoint(
                    id: "\(date.timeIntervalSince1970):\(usageKind)",
                    date: date,
                    usageKind: usageKind,
                    requestCount: dailyUsage.reduce(0) { $0 + $1.requestCount },
                    successCount: dailyUsage.reduce(0) { $0 + $1.successCount },
                    failedCount: dailyUsage.reduce(0) { $0 + $1.failedCount },
                    sourceCharacterCount: dailyUsage.reduce(0) { $0 + $1.sourceCharacterCount },
                    translatedCharacterCount: dailyUsage.reduce(0) { $0 + $1.translatedCharacterCount },
                    promptTokenCount: dailyUsage.reduce(0) { $0 + $1.promptTokenCount },
                    completionTokenCount: dailyUsage.reduce(0) { $0 + $1.completionTokenCount }
                ))
            }
        }

        return points
    }

    /// 聚合服务调用排行；大模型按“配置名称 + 模型”区分，避免不同模型被合并。
    nonisolated static func makeTranslationUsageServicePoints(
        from usage: [TranslationUsageStat],
        limit: Int = 6
    ) -> [TranslationUsageServicePoint] {
        let usageByService = Dictionary(grouping: usage) { item in
            "\(item.usageKind)|\(item.providerName)|\(item.modelName)"
        }
        return usageByService.compactMap { identifier, serviceUsage -> TranslationUsageServicePoint? in
            guard let firstUsage = serviceUsage.first else { return nil }
            let displayName: String
            if firstUsage.usageKind == TranslationUsageKind.llm.rawValue,
               !firstUsage.modelName.isEmpty {
                displayName = "\(firstUsage.providerName) · \(firstUsage.modelName)"
            } else {
                displayName = firstUsage.providerName
            }
            return TranslationUsageServicePoint(
                id: identifier,
                displayName: displayName,
                usageKind: firstUsage.usageKind,
                requestCount: serviceUsage.reduce(0) { $0 + $1.requestCount },
                successCount: serviceUsage.reduce(0) { $0 + $1.successCount },
                failedCount: serviceUsage.reduce(0) { $0 + $1.failedCount },
                sourceCharacterCount: serviceUsage.reduce(0) { $0 + $1.sourceCharacterCount },
                translatedCharacterCount: serviceUsage.reduce(0) { $0 + $1.translatedCharacterCount },
                promptTokenCount: serviceUsage.reduce(0) { $0 + $1.promptTokenCount },
                completionTokenCount: serviceUsage.reduce(0) { $0 + $1.completionTokenCount }
            )
        }
        .sorted { $0.requestCount > $1.requestCount }
        .prefix(max(1, limit))
        .map { $0 }
    }

    // MARK: - Date Formatting Helpers

    nonisolated static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    nonisolated static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    nonisolated static func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

}

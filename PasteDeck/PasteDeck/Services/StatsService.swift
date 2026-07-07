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

        // 最长文本
        var longestTextChars: Int? = nil
        let textRaw = ClipboardContentType.text.rawValue
        if let textItems = try? context.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentType.rawValue == textRaw }
        )) {
            longestTextChars = textItems.map { $0.textContent?.count ?? 0 }.max()
            if longestTextChars == 0 { longestTextChars = nil }
        }

        // 最大图片
        var largestImageSize: String? = nil
        let imageRaw = ClipboardContentType.image.rawValue
        if let imageItems = try? context.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentType.rawValue == imageRaw },
            sortBy: [SortDescriptor(\.fileSize, order: .reverse)]
        )) {
            if let largest = imageItems.first {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                largestImageSize = "\(formatter.string(fromByteCount: Int64(largest.fileSize))) · \(largest.imageWidth)×\(largest.imageHeight)"
            }
        }

        // 最大文件引用
        var largestFileDisplay: String? = nil
        let fileRaw = ClipboardContentType.file.rawValue
        if let fileItems = try? context.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentType.rawValue == fileRaw },
            sortBy: [SortDescriptor(\.fileSize, order: .reverse)]
        )) {
            if let largest = fileItems.first {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let name = largest.fileName ?? "未知文件"
                largestFileDisplay = "\(name) · \(formatter.string(fromByteCount: Int64(largest.fileSize)))"
            }
        }

        // 最早记录
        var earliestDate: Date? = nil
        var earliestDescriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        earliestDescriptor.fetchLimit = 1
        earliestDate = (try? context.fetch(earliestDescriptor).first)?.createdAt

        // 收藏数 — 查 collections 关联含 isDefault 的记录
        let favoriteDescriptor = FetchDescriptor<ClipboardItem>()
        let allItems = (try? context.fetch(favoriteDescriptor)) ?? []
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

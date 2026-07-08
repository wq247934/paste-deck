//
//  DailyStatsUpdater.swift
//  PasteDeck
//
//  Handles incremental upsert and one-time backfill of DailyStatsSnapshot.
//
//  Created on 2026-07-07.
//

import Foundation
import SwiftData

enum DailyStatsUpdater {

    // MARK: - Incremental Upsert

    /// 在新 ClipboardItem 写入后调用，更新当天的聚合快照。
    /// 与 saveItem 同上下文调用，使用传入的 ModelContext。
    static func upsert(for item: ClipboardItem, context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: item.createdAt)
        let typeKey = item.contentType.rawValue
        let appName = ClipboardItem.normalizedSourceAppName(item.sourceApp) ?? "未知"

        let snapshot = fetchOrCreate(date: dayStart, context: context)

        snapshot.totalCount += 1
        snapshot.typeCounts[typeKey, default: 0] += 1
        snapshot.sourceAppCounts[appName, default: 0] += 1
        if item.isPinned { snapshot.pinnedAddedCount += 1 }
        snapshot.updatedAt = Date()

        try? context.save()
    }

    /// 置顶状态变更时调用，修正当天的 pinnedAddedCount。
    static func adjustPinned(by delta: Int, date: Date, context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: date)
        let snapshot = fetchOrCreate(date: dayStart, context: context)
        snapshot.pinnedAddedCount = max(0, snapshot.pinnedAddedCount + delta)
        snapshot.updatedAt = Date()
        try? context.save()
    }

    /// 收藏状态变更时调用，修正当天的 favoriteAddedCount。
    static func adjustFavorite(by delta: Int, date: Date, context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: date)
        let snapshot = fetchOrCreate(date: dayStart, context: context)
        snapshot.favoriteAddedCount = max(0, snapshot.favoriteAddedCount + delta)
        snapshot.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Backfill

    /// 首次启用时执行一次性回填，将现有 ClipboardItem 历史数据按天聚合并写入 DailyStatsSnapshot。
    /// 使用 AppSettings.statsBackfilledAt 标记判断是否已回填，避免增量写入导致误判跳过。
    /// 回填是幂等的：对已存在的 snapshot 会对字段做累加合并，不会重复计数。
    nonisolated static func backfillIfNeeded() {
        let context = ModelContext(AppModelContainer.container)

        // 检查是否已回填过
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(settingsDescriptor).first else { return }
        if settings.statsBackfilledAt != nil { return }

        // 检查是否有 ClipboardItem
        let itemCount = (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
        guard itemCount > 0 else {
            // 没有历史数据也标记为已回填
            settings.statsBackfilledAt = Date()
            try? context.save()
            return
        }

        // 全量读取 ClipboardItem，按天分组
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let items = try? context.fetch(descriptor) else { return }

        // 预加载已有的 snapshot，按 date 建立索引
        // backfill 会重建所有 snapshot，先清零已有记录，避免增量写入导致重复计数
        let existingSnapshots = (try? context.fetch(FetchDescriptor<DailyStatsSnapshot>())) ?? []
        var snapshotsByDate: [Date: DailyStatsSnapshot] = [:]
        for snapshot in existingSnapshots {
            snapshot.totalCount = 0
            snapshot.typeCounts = [:]
            snapshot.sourceAppCounts = [:]
            snapshot.pinnedAddedCount = 0
            snapshot.favoriteAddedCount = 0
            snapshotsByDate[snapshot.date] = snapshot
        }

        let calendar = Calendar.current

        for item in items {
            let dayStart = calendar.startOfDay(for: item.createdAt)

            let snapshot: DailyStatsSnapshot
            if let existing = snapshotsByDate[dayStart] {
                snapshot = existing
            } else {
                let s = DailyStatsSnapshot(date: dayStart)
                context.insert(s)
                snapshotsByDate[dayStart] = s
                snapshot = s
            }

            snapshot.totalCount += 1
            let typeKey = item.contentType.rawValue
            snapshot.typeCounts[typeKey, default: 0] += 1
            let appName = ClipboardItem.normalizedSourceAppName(item.sourceApp) ?? "未知"
            snapshot.sourceAppCounts[appName, default: 0] += 1
            if item.isPinned { snapshot.pinnedAddedCount += 1 }
            // 回填时无法准确判断收藏新增时间，跳过 favoriteAddedCount
        }

        // 设置每条 snapshot 的 updatedAt
        for snapshot in snapshotsByDate.values {
            snapshot.updatedAt = Date()
        }

        // 标记已回填
        settings.statsBackfilledAt = Date()

        try? context.save()
        NSLog("[PasteDeck] DailyStats backfill: \(snapshotsByDate.count) day snapshots processed from \(itemCount) items")
    }

    // MARK: - Private

    private static func fetchOrCreate(date: Date, context: ModelContext) -> DailyStatsSnapshot {
        let targetDate = date
        let descriptor = FetchDescriptor<DailyStatsSnapshot>(
            predicate: #Predicate { $0.date == targetDate }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let snapshot = DailyStatsSnapshot(date: date)
        context.insert(snapshot)
        return snapshot
    }
}

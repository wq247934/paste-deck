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

    /// 首次启用时，如果 DailyStatsSnapshot 表为空且 ClipboardItem 表非空，执行一次性回填。
    /// 应在后台线程调用，不阻塞主线程。
    nonisolated static func backfillIfNeeded() {
        let context = ModelContext(AppModelContainer.container)

        // 检查是否已有数据
        let existingCount = (try? context.fetchCount(FetchDescriptor<DailyStatsSnapshot>())) ?? 0
        guard existingCount == 0 else { return }

        // 检查是否有 ClipboardItem
        let itemCount = (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
        guard itemCount > 0 else { return }

        // 全量读取，按天分组
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let items = try? context.fetch(descriptor) else { return }

        var snapshotsByDay: [Date: DailyStatsSnapshot] = [:]
        let calendar = Calendar.current

        for item in items {
            let dayStart = calendar.startOfDay(for: item.createdAt)
            let snapshot = snapshotsByDay[dayStart] ?? {
                let s = DailyStatsSnapshot(date: dayStart)
                context.insert(s)
                return s
            }()
            snapshotsByDay[dayStart] = snapshot

            snapshot.totalCount += 1
            let typeKey = item.contentType.rawValue
            snapshot.typeCounts[typeKey, default: 0] += 1
            let appName = ClipboardItem.normalizedSourceAppName(item.sourceApp) ?? "未知"
            snapshot.sourceAppCounts[appName, default: 0] += 1
            if item.isPinned { snapshot.pinnedAddedCount += 1 }
            // 回填时无法准确判断收藏新增时间，跳过 favoriteAddedCount
        }

        // 设置每条 snapshot 的 updatedAt
        for snapshot in snapshotsByDay.values {
            snapshot.updatedAt = Date()
        }

        try? context.save()
        NSLog("[PasteDeck] DailyStats backfill: \(snapshotsByDay.count) day snapshots created from \(itemCount) items")
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

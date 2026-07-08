//
//  DailyStatsSnapshot.swift
//  PasteDeck
//
//  Created on 2026-07-07.
//

import Foundation
import SwiftData

/// 按日聚合的剪贴板统计快照，用于统计面板快速查询，避免全表扫描。
@Model
final class DailyStatsSnapshot {
    // MARK: - Properties

    var id: UUID
    /// 当天 0 点（Calendar.startOfDay）
    var date: Date
    /// 当天新增记录总数
    var totalCount: Int
    /// 当天各类型 count，key 为 ClipboardContentType.rawValue
    var typeCounts: [String: Int]
    /// 当天各来源 App count，key 为 normalizedSourceAppName
    var sourceAppCounts: [String: Int]
    /// 当天收藏新增数
    var favoriteAddedCount: Int
    /// 当天置顶新增数
    var pinnedAddedCount: Int
    /// 最后更新时间
    var updatedAt: Date

    // MARK: - Initialization

    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.totalCount = 0
        self.typeCounts = [:]
        self.sourceAppCounts = [:]
        self.favoriteAddedCount = 0
        self.pinnedAddedCount = 0
        self.updatedAt = Date()
    }
}

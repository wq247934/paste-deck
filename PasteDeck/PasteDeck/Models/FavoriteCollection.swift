//
//  FavoriteCollection.swift
//  PasteDeck
//
//  Created on 2026-05-28.
//

import Foundation
import SwiftData

/// 收藏夹模型，支持多对多关联 ClipboardItem
@Model
final class FavoriteCollection {
    /// 收藏夹稳定标识，用于剪贴板记录与筛选标签关联。
    var id: UUID
    /// 用户可见名称；系统收藏夹名称由产品固定管理。
    var name: String
    /// 收藏夹在主面板标签和设置列表中的显示顺序。
    var sortOrder: Int
    /// 是否为系统默认“收藏”分类；默认分类不可删除或改名。
    var isDefault: Bool
    /// 是否为系统“翻译”分类；候选值为 true（翻译历史专用）或 false（普通收藏夹）。
    var isTranslation: Bool = false
    /// 收藏夹创建时间，用于诊断与未来排序扩展。
    var createdAt: Date

    /// 与剪贴板记录的多对多关联；翻译分类中的项目是可恢复的翻译工作区。
    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.collections)
    var items: [ClipboardItem]?

    init(
        name: String,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        isTranslation: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isTranslation = isTranslation
        self.createdAt = Date()
    }
}

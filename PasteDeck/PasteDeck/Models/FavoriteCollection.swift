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
    var id: UUID
    var name: String
    var sortOrder: Int
    var isDefault: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.collections)
    var items: [ClipboardItem]?

    init(name: String, sortOrder: Int = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = Date()
    }
}

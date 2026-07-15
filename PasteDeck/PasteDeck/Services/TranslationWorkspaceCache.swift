//
//  TranslationWorkspaceCache.swift
//  PasteDeck
//
//  Persists translation workspaces in the protected translation collection.
//

import Foundation
import SwiftData

/// 翻译工作区的持久化快照；原文保存在关联 ClipboardItem.textContent，避免重复保存长文本。
struct TranslationWorkspaceSnapshot: Codable {
    /// 同一翻译窗口内按时间创建的译文卡片，保留重复选择同一模型的对比结果。
    var outputs: [TranslationOutput]
    /// 工作区当前目标语言；候选值为 automatic、simplifiedChinese、english、spanish、hindi、arabic、bengali、portuguese、russian、japanese、german、french、korean、indonesian、urdu、turkish、vietnamese、italian、thai、persian、polish；nil 兼容未保存语向的旧版历史。
    var targetLanguage: TranslationTargetLanguage? = nil
}

/// 翻译历史读写入口。每个工作区都是“翻译”系统分类中的 ClipboardItem，因而与普通历史一起搜索和展示，但能恢复为翻译窗口。
@MainActor
enum TranslationWorkspaceCache {
    /// 新建翻译工作区，并将原文加入不能删除、改名或排序的“翻译”系统分类。
    static func create(
        sourceText: String,
        targetLanguage: TranslationTargetLanguage = .automatic
    ) -> UUID? {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return nil }

        let context = ModelContext(AppModelContainer.container)
        let item = ClipboardItem(
            contentType: .text,
            textContent: trimmedSource,
            sourceApp: "PasteDeck"
        )
        item.customTitle = "翻译"
        item.translationWorkspaceData = encode(outputs: [], targetLanguage: targetLanguage)
        if let collection = translationCollection(in: context) {
            item.collections = [collection]
        }
        context.insert(item)

        guard save(context) else { return nil }
        notify(itemID: item.id, kind: .inserted)
        return item.id
    }

    /// 将当前卡片状态写回持久化快照，确保重启后仍能恢复译文与失败状态。
    static func save(
        itemID: UUID,
        outputs: [TranslationOutput],
        targetLanguage: TranslationTargetLanguage
    ) {
        let context = ModelContext(AppModelContainer.container)
        guard let item = fetchItem(id: itemID, in: context) else { return }
        item.translationWorkspaceData = encode(outputs: outputs, targetLanguage: targetLanguage)
        guard save(context) else { return }
        notify(itemID: item.id, kind: .updated)
    }

    /// 读取历史工作区的原文和已缓存卡片；损坏或旧版数据安全退化为空卡片列表。
    static func load(itemID: UUID) -> (
        sourceText: String,
        outputs: [TranslationOutput],
        targetLanguage: TranslationTargetLanguage
    )? {
        let context = ModelContext(AppModelContainer.container)
        guard let item = fetchItem(id: itemID, in: context), item.isTranslationHistory else {
            return nil
        }
        let sourceText = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sourceText.isEmpty else { return nil }
        let snapshot = decode(item.translationWorkspaceData)
        return (
            sourceText,
            snapshot?.outputs ?? [],
            snapshot?.targetLanguage ?? .automatic
        )
    }

    private static func translationCollection(in context: ModelContext) -> FavoriteCollection? {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.isTranslation == true }
        )
        if let collection = try? context.fetch(descriptor).first {
            return collection
        }

        let collections = (try? context.fetch(FetchDescriptor<FavoriteCollection>())) ?? []
        for collection in collections where collection.sortOrder > 0 {
            collection.sortOrder += 1
        }
        let collection = FavoriteCollection(
            name: "翻译",
            sortOrder: 1,
            isTranslation: true
        )
        context.insert(collection)
        return collection
    }

    private static func fetchItem(id: UUID, in context: ModelContext) -> ClipboardItem? {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    private static func encode(
        outputs: [TranslationOutput],
        targetLanguage: TranslationTargetLanguage
    ) -> Data? {
        try? JSONEncoder().encode(TranslationWorkspaceSnapshot(
            outputs: outputs,
            targetLanguage: targetLanguage
        ))
    }

    private static func decode(_ data: Data?) -> TranslationWorkspaceSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(TranslationWorkspaceSnapshot.self, from: data)
    }

    private static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }

    private static func notify(itemID: UUID, kind: ClipboardDataChangeKind) {
        NotificationCenter.default.post(
            name: .clipboardDataChanged,
            object: nil,
            userInfo: [
                ClipboardDataChangeNotification.itemIDKey: itemID,
                ClipboardDataChangeNotification.changeKindKey: kind.rawValue
            ]
        )
    }
}

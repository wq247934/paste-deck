//
//  ClipboardHistoryStore.swift
//  PasteDeck
//
//  Lightweight cached data source for the main clipboard panel.
//

import Foundation
import Combine
import SwiftData

enum ClipboardDataChangeNotification {
    static let itemIDKey = "itemID"
    static let changeKindKey = "changeKind"
}

enum ClipboardDataChangeKind: String, Sendable {
    case inserted
    case updated
}

struct ClipboardCollectionSnapshot: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let isDefault: Bool
}

struct ClipboardItemSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let contentType: ClipboardContentType
    let textContent: String?
    let imagePath: String?
    let filePath: String?
    let fileName: String?
    let fileSize: Int
    let imageWidth: Int
    let imageHeight: Int
    let ocrText: String?
    let colorHex: String?
    let sourceApp: String?
    let createdAt: Date
    let isPinned: Bool
    let customTitle: String?
    let collections: [ClipboardCollectionSnapshot]
    let searchBlob: String

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    init(item: ClipboardItem) {
        id = item.id
        contentType = item.contentType
        textContent = item.textContent
        imagePath = item.imagePath
        filePath = item.filePath
        fileName = item.fileName
        fileSize = item.fileSize
        imageWidth = item.imageWidth
        imageHeight = item.imageHeight
        ocrText = item.ocrText
        colorHex = item.colorHex
        sourceApp = item.sourceApp
        createdAt = item.createdAt
        isPinned = item.isPinned
        customTitle = item.customTitle
        collections = (item.collections ?? [])
            .map {
                ClipboardCollectionSnapshot(
                    id: $0.id,
                    name: $0.name,
                    sortOrder: $0.sortOrder,
                    isDefault: $0.isDefault
                )
            }
            .sorted { $0.sortOrder < $1.sortOrder }

        let title = ClipboardItemSnapshot.makeDisplayTitle(
            contentType: item.contentType,
            textContent: item.textContent,
            fileName: item.fileName,
            imageWidth: item.imageWidth,
            imageHeight: item.imageHeight,
            colorHex: item.colorHex,
            customTitle: item.customTitle
        )

        searchBlob = [
            title,
            item.textContent,
            item.fileName,
            item.filePath,
            item.ocrText,
            item.colorHex,
            item.sourceApp,
            collections.map(\.name).joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    var isFavorite: Bool {
        collections.contains { $0.isDefault }
    }

    var collectionIDs: Set<UUID> {
        Set(collections.map(\.id))
    }

    var displayTitle: String {
        Self.makeDisplayTitle(
            contentType: contentType,
            textContent: textContent,
            fileName: fileName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            colorHex: colorHex,
            customTitle: customTitle
        )
    }

    var displaySize: String {
        switch contentType {
        case .text, .link, .markdown, .json:
            let count = textContent?.count ?? 0
            return "\(count) 字符"
        case .image, .file:
            return Self.byteCountFormatter.string(fromByteCount: Int64(fileSize))
        case .color:
            return colorHex ?? ""
        }
    }

    var displayTime: String {
        Self.relativeDateTimeFormatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var nonDefaultCollections: [ClipboardCollectionSnapshot] {
        collections.filter { !$0.isDefault }
    }

    private static func makeDisplayTitle(
        contentType: ClipboardContentType,
        textContent: String?,
        fileName: String?,
        imageWidth: Int,
        imageHeight: Int,
        colorHex: String?,
        customTitle: String?
    ) -> String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        switch contentType {
        case .text, .markdown, .json:
            return String((textContent?.prefix(50) ?? "").replacingOccurrences(of: "\n", with: " "))
        case .link:
            return textContent ?? ""
        case .image:
            return "图片 \(imageWidth)x\(imageHeight)"
        case .file:
            return fileName ?? "文件"
        case .color:
            return colorHex ?? ""
        }
    }
}

enum ClipboardFilterOption: Equatable, Hashable, Sendable {
    case all
    case collection(UUID)

    func displayName(collections: [ClipboardCollectionSnapshot]) -> String {
        switch self {
        case .all:
            return "全部"
        case .collection(let id):
            return collections.first(where: { $0.id == id })?.name ?? "收藏夹"
        }
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let historyLimit = 5000

    @Published private(set) var allItems: [ClipboardItemSnapshot] = []
    @Published private(set) var filteredItems: [ClipboardItemSnapshot] = []
    @Published private(set) var collections: [ClipboardCollectionSnapshot] = []
    @Published private(set) var isLoading = false

    private let modelContext: ModelContext
    private var searchText = ""
    private var selectedFilter: ClipboardFilterOption = .all
    private var filterTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var hasLoaded = false

    private struct HistoryLoadResult: Sendable {
        let items: [ClipboardItemSnapshot]
        let collections: [ClipboardCollectionSnapshot]
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    deinit {
        filterTask?.cancel()
        reloadTask?.cancel()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        reloadFromDatabase()
    }

    func reloadFromDatabase() {
        reloadTask?.cancel()
        isLoading = true
        let limit = Self.historyLimit

        reloadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.fetchHistorySnapshot(limit: limit)
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            allItems = result.items
            collections = result.collections
            hasLoaded = true
            isLoading = false
            applyFilterNow()
        }
    }

    private nonisolated static func fetchHistorySnapshot(limit: Int) -> HistoryLoadResult {
        let context = ModelContext(AppModelContainer.container)

        var itemDescriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        itemDescriptor.fetchLimit = limit

        let items = ((try? context.fetch(itemDescriptor)) ?? [])
            .map(ClipboardItemSnapshot.init)

        let collectionDescriptor = FetchDescriptor<FavoriteCollection>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let collections = ((try? context.fetch(collectionDescriptor)) ?? [])
            .map {
                ClipboardCollectionSnapshot(
                    id: $0.id,
                    name: $0.name,
                    sortOrder: $0.sortOrder,
                    isDefault: $0.isDefault
                )
            }

        return HistoryLoadResult(items: items, collections: collections)
    }

    func setSearchText(_ text: String) {
        searchText = text
        scheduleFilter()
    }

    func setFilter(_ filter: ClipboardFilterOption) {
        selectedFilter = filter
        applyFilterNow()
    }

    func refreshItem(id: UUID, insertIfMissing: Bool = false) {
        guard let item = fetchItem(id: id) else {
            removeSnapshots(ids: [id])
            return
        }

        let snapshotExists = allItems.contains { $0.id == id }
        guard snapshotExists || insertIfMissing else { return }
        upsertSnapshot(ClipboardItemSnapshot(item: item))
    }

    func fetchItem(id: UUID) -> ClipboardItem? {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func copyToPasteboard(id: UUID) {
        guard let item = fetchItem(id: id) else { return }
        PasteService.shared.copyToPasteboard(item)
    }

    func preparePaste(id: UUID, plainText: Bool = false) {
        guard let item = fetchItem(id: id) else { return }
        PasteService.shared.preparePaste(item, plainText: plainText)
    }

    func batchPaste(ids: [UUID], plainText: Bool = false) {
        let items = ids.compactMap(fetchItem)
        guard !items.isEmpty else { return }
        PasteService.shared.batchPaste(items, plainText: plainText)
    }

    func togglePinned(id: UUID) {
        guard let item = fetchItem(id: id) else { return }
        item.isPinned.toggle()
        saveAndRefresh(item)
    }

    func saveTitle(id: UUID, title: String?) {
        guard let item = fetchItem(id: id) else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        item.customTitle = trimmed.isEmpty ? nil : trimmed
        saveAndRefresh(item)
    }

    func toggleDefaultFavorite(id: UUID) {
        guard let item = fetchItem(id: id),
              let defaultCollection = defaultCollection() else { return }

        if item.collections?.contains(where: { $0.id == defaultCollection.id }) == true {
            item.collections?.removeAll(where: { $0.id == defaultCollection.id })
        } else {
            if item.collections == nil {
                item.collections = []
            }
            item.collections?.append(defaultCollection)
        }

        saveAndRefresh(item)
    }

    func toggleCollection(itemID: UUID, collectionID: UUID) {
        guard let item = fetchItem(id: itemID),
              let collection = fetchCollection(id: collectionID) else { return }

        if item.collections == nil {
            item.collections = []
        }
        if let index = item.collections?.firstIndex(where: { $0.id == collection.id }) {
            item.collections?.remove(at: index)
        } else {
            item.collections?.append(collection)
        }

        saveAndRefresh(item)
    }

    func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxOrder = collections.map(\.sortOrder).max() ?? 0
        modelContext.insert(FavoriteCollection(name: trimmed, sortOrder: maxOrder + 1))
        try? modelContext.save()
        reloadCollections()
        applyFilterNow()
    }

    func deleteItem(id: UUID) {
        guard let item = fetchItem(id: id) else {
            removeSnapshots(ids: [id])
            return
        }
        modelContext.delete(item)
        try? modelContext.save()
        removeSnapshots(ids: [id])
    }

    func promotePastedItems(ids: [UUID]) {
        let baseDate = Date()
        var changedItems: [ClipboardItem] = []
        for (index, id) in ids.enumerated() {
            guard let item = fetchItem(id: id) else { continue }
            item.createdAt = baseDate.addingTimeInterval(Double(-index) * 0.001)
            changedItems.append(item)
        }

        guard !changedItems.isEmpty else { return }
        try? modelContext.save()
        for item in changedItems {
            upsertSnapshot(ClipboardItemSnapshot(item: item), applyImmediately: false)
        }
        allItems.sort { $0.createdAt > $1.createdAt }
        if allItems.count > Self.historyLimit {
            allItems = Array(allItems.prefix(Self.historyLimit))
        }
        applyFilterNow()
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        let query = searchText
        let filter = selectedFilter
        let items = allItems

        filterTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let result = Self.filter(items: items, searchText: query, filter: filter)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self?.filteredItems = result
            }
        }
    }

    private func applyFilterNow() {
        filterTask?.cancel()
        filteredItems = Self.filter(items: allItems, searchText: searchText, filter: selectedFilter)
    }

    private static func filter(
        items: [ClipboardItemSnapshot],
        searchText: String,
        filter: ClipboardFilterOption
    ) -> [ClipboardItemSnapshot] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = items

        if !normalizedQuery.isEmpty {
            result = result.filter { $0.searchBlob.contains(normalizedQuery) }
        }

        switch filter {
        case .all:
            break
        case .collection(let id):
            result = result.filter { $0.collectionIDs.contains(id) }
            result.sort {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.createdAt > $1.createdAt
            }
        }

        return result
    }

    private func saveAndRefresh(_ item: ClipboardItem) {
        try? modelContext.save()
        upsertSnapshot(ClipboardItemSnapshot(item: item))
    }

    private func upsertSnapshot(_ snapshot: ClipboardItemSnapshot, applyImmediately: Bool = true) {
        if let index = allItems.firstIndex(where: { $0.id == snapshot.id }) {
            allItems[index] = snapshot
        } else {
            allItems.insert(snapshot, at: 0)
        }
        if allItems.count > Self.historyLimit {
            allItems = Array(allItems.prefix(Self.historyLimit))
        }

        if applyImmediately {
            applyFilterNow()
        }
    }

    private func removeSnapshots(ids: Set<UUID>) {
        allItems.removeAll { ids.contains($0.id) }
        filteredItems.removeAll { ids.contains($0.id) }
    }

    private func removeSnapshots(ids: [UUID]) {
        removeSnapshots(ids: Set(ids))
    }

    private func reloadCollections() {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        collections = ((try? modelContext.fetch(descriptor)) ?? [])
            .map {
                ClipboardCollectionSnapshot(
                    id: $0.id,
                    name: $0.name,
                    sortOrder: $0.sortOrder,
                    isDefault: $0.isDefault
                )
            }
    }

    private func defaultCollection() -> FavoriteCollection? {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.isDefault == true }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchCollection(id: UUID) -> FavoriteCollection? {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

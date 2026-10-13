//
//  WorkbenchHistoryStore.swift
//  PasteDeck
//
//  Dedicated paginated history store for the PasteDeck 2.0 Workbench.
//  Unlike QuickPanelView (which maintains a 5,000-item in-memory cache for ultra-fast pasting),
//  WorkbenchHistoryStore supports browsing and searching the entire database (10k - 100k+ records)
//  with progressive pagination (100 items per page), zero main-thread freezing,
//  and instant O(1) sidebar count updates via SwiftData fetchCount.
//

import Foundation
import SwiftData
import Combine
import SQLite3

@MainActor
final class WorkbenchHistoryStore: ObservableObject {
    static let pageSize = 100

    @Published private(set) var items: [ClipboardItemSnapshot] = []
    @Published private(set) var hasMore: Bool = true
    @Published private(set) var isLoadingPage: Bool = false
    @Published private(set) var totalHistoryCount: Int = 0
    @Published private(set) var totalFavoritesCount: Int = 0
    @Published private(set) var categoryCounts: [ClipboardContentType: Int] = [:]
    @Published private(set) var collections: [ClipboardCollectionSnapshot] = []

    private let modelContext: ModelContext
    private var currentDestination: WorkbenchDestination = .history
    private var currentTypeFilter: ClipboardContentType?
    private var currentSortOrder: WorkbenchSortOrder = .newestFirst
    private var currentSearchText: String = ""

    private var activePageTask: Task<Void, Never>?
    private var activeCountTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var hasLoadedInitial = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupNotificationObservers()
    }

    deinit {
        activePageTask?.cancel()
        activeCountTask?.cancel()
        searchDebounceTask?.cancel()
    }

    // MARK: - Initial & Configuration

    func loadIfNeeded() {
        guard !hasLoadedInitial else { return }
        hasLoadedInitial = true
        reloadFirstPage()
        refreshTotalCounts()
    }

    func configure(
        destination: WorkbenchDestination,
        typeFilter: ClipboardContentType?,
        sortOrder: WorkbenchSortOrder
    ) {
        let destinationChanged = destination != currentDestination
        let filterChanged = typeFilter != currentTypeFilter
        let sortChanged = sortOrder != currentSortOrder

        guard destinationChanged || filterChanged || sortChanged else { return }

        currentDestination = destination
        currentTypeFilter = typeFilter
        currentSortOrder = sortOrder

        reloadFirstPage()
    }

    func setSearchText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentSearchText else { return }

        searchDebounceTask?.cancel()
        currentSearchText = trimmed

        searchDebounceTask = Task { [weak self] in
            // 200ms debounce for database search queries
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadFirstPage()
        }
    }

    // MARK: - Pagination

    func reloadFirstPage() {
        activePageTask?.cancel()
        isLoadingPage = true
        hasMore = true

        let destination = currentDestination
        let typeFilter = currentTypeFilter
        let sortOrder = currentSortOrder
        let query = currentSearchText
        let limit = Self.pageSize

        activePageTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.fetchPage(
                    offset: 0,
                    limit: limit,
                    destination: destination,
                    typeFilter: typeFilter,
                    sortOrder: sortOrder,
                    query: query
                )
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            self.items = result
            self.hasMore = result.count >= limit
            self.isLoadingPage = false
        }
    }

    func loadNextPage() {
        guard !isLoadingPage, hasMore else { return }
        isLoadingPage = true

        let offset = items.count
        let limit = Self.pageSize
        let destination = currentDestination
        let typeFilter = currentTypeFilter
        let sortOrder = currentSortOrder
        let query = currentSearchText

        activePageTask = Task { [weak self] in
            let nextPage = await Task.detached(priority: .userInitiated) {
                Self.fetchPage(
                    offset: offset,
                    limit: limit,
                    destination: destination,
                    typeFilter: typeFilter,
                    sortOrder: sortOrder,
                    query: query
                )
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            if nextPage.isEmpty {
                self.hasMore = false
            } else {
                self.items.append(contentsOf: nextPage)
                self.hasMore = nextPage.count >= limit
            }
            self.isLoadingPage = false
        }
    }

    // MARK: - Counts via SwiftData fetchCount (Ultra-fast SELECT COUNT(*))

    func refreshTotalCounts() {
        activeCountTask?.cancel()

        activeCountTask = Task { [weak self] in
            let counts = await Task.detached(priority: .utility) {
                Self.fetchSummaryCounts()
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            self.totalHistoryCount = counts.history
            self.totalFavoritesCount = counts.favorites
            self.categoryCounts = counts.categories
            self.collections = counts.collections
        }
    }

    // MARK: - Single Item Mutations

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

    func toggleDefaultFavorite(id: UUID) {
        guard let item = fetchItem(id: id) else { return }
        let collDescriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.isDefault == true }
        )
        guard let defaultColl = try? modelContext.fetch(collDescriptor).first else { return }

        var itemCollections = item.collections ?? []
        if let idx = itemCollections.firstIndex(where: { $0.id == defaultColl.id }) {
            itemCollections.remove(at: idx)
            totalFavoritesCount = max(0, totalFavoritesCount - 1)
        } else {
            itemCollections.append(defaultColl)
            totalFavoritesCount += 1
        }
        item.collections = itemCollections
        try? modelContext.save()

        // Update snapshot in memory
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = ClipboardItemSnapshot(item: item)
        }
    }

    func togglePinned(id: UUID) {
        guard let item = fetchItem(id: id) else { return }
        item.isPinned.toggle()
        try? modelContext.save()

        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = ClipboardItemSnapshot(item: item)
        }
    }

    func deleteItem(id: UUID) {
        guard let item = fetchItem(id: id) else { return }
        let deletedCount = ClipboardItemLifecycleService.deleteItems([item], in: modelContext)
        guard deletedCount > 0 else { return }

        items.removeAll { $0.id == id }
        totalHistoryCount = max(0, totalHistoryCount - 1)
        refreshTotalCounts()
    }

    // MARK: - Notification Handling

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .clipboardDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleClipboardChange(notification)
            }
        }
    }

    private func handleClipboardChange(_ notification: Notification) {
        guard let itemID = notification.userInfo?[ClipboardDataChangeNotification.itemIDKey] as? UUID,
              let changeKind = notification.userInfo?[ClipboardDataChangeNotification.changeKindKey] as? String else {
            // General change, refresh count and first page
            reloadFirstPage()
            refreshTotalCounts()
            return
        }

        if changeKind == ClipboardDataChangeKind.inserted.rawValue {
            if let item = fetchItem(id: itemID) {
                let snapshot = ClipboardItemSnapshot(item: item)
                // If on history tab and no search, prepend to list
                if currentDestination == .history && currentSearchText.isEmpty {
                    items.insert(snapshot, at: 0)
                }
                totalHistoryCount += 1
                categoryCounts[snapshot.contentType, default: 0] += 1
            }
        } else {
            refreshTotalCounts()
            if let item = fetchItem(id: itemID),
               let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index] = ClipboardItemSnapshot(item: item)
            }
        }
    }

    // MARK: - Background Static Fetchers

    private nonisolated static func fetchPage(
        offset: Int,
        limit: Int,
        destination: WorkbenchDestination,
        typeFilter: ClipboardContentType?,
        sortOrder: WorkbenchSortOrder,
        query: String
    ) -> [ClipboardItemSnapshot] {
        let storeURL = AppModelContainer.storeURL
        let uuids = WorkbenchSQLiteReader.fetchPageUUIDs(
            storeURL: storeURL,
            destination: destination,
            typeFilter: typeFilter,
            sortOrder: sortOrder,
            query: query,
            offset: offset,
            limit: limit
        )

        guard !uuids.isEmpty else { return [] }

        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { uuids.contains($0.id) }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return uuids.compactMap { itemMap[$0] }.map(ClipboardItemSnapshot.init)
    }

    private struct SummaryCounts: Sendable {
        let history: Int
        let favorites: Int
        let categories: [ClipboardContentType: Int]
        let collections: [ClipboardCollectionSnapshot]
    }

    private nonisolated static func fetchSummaryCounts() -> SummaryCounts {
        let storeURL = AppModelContainer.storeURL
        let summary = WorkbenchSQLiteReader.fetchCategorySummary(storeURL: storeURL)

        let context = ModelContext(AppModelContainer.container)
        let collDescriptor = FetchDescriptor<FavoriteCollection>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let collections = ((try? context.fetch(collDescriptor)) ?? [])
        let collectionSnapshots = collections.map {
            ClipboardCollectionSnapshot(
                id: $0.id,
                name: $0.name,
                sortOrder: $0.sortOrder,
                isDefault: $0.isDefault,
                isTranslation: $0.isTranslation
            )
        }

        return SummaryCounts(
            history: summary.total,
            favorites: summary.favorites,
            categories: summary.counts,
            collections: collectionSnapshots
        )
    }
}

// MARK: - Direct Fast SQLite Reader

enum WorkbenchSQLiteReader {
    struct CategorySummary {
        var total: Int = 0
        var favorites: Int = 0
        var counts: [ClipboardContentType: Int] = [:]
    }

    static func fetchCategorySummary(storeURL: URL) -> CategorySummary {
        var summary = CategorySummary()
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return summary
        }
        defer { sqlite3_close(db) }

        // 1. Total count
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT count(*) FROM ZCLIPBOARDITEM", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.total = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // 2. Favorites count (default collection)
        let favSQL = """
        SELECT count(DISTINCT Z_2ITEMS) FROM Z_2COLLECTIONS 
        JOIN ZFAVORITECOLLECTION ON Z_4COLLECTIONS = ZFAVORITECOLLECTION.Z_PK 
        WHERE ZISDEFAULT = 1
        """
        if sqlite3_prepare_v2(db, favSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                summary.favorites = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // 3. Category counts
        let catSQL = "SELECT ZCONTENTTYPE, count(*) FROM ZCLIPBOARDITEM GROUP BY ZCONTENTTYPE"
        if sqlite3_prepare_v2(db, catSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let typeCStr = sqlite3_column_text(stmt, 0) {
                    let typeStr = String(cString: typeCStr)
                    let count = Int(sqlite3_column_int64(stmt, 1))
                    if let type = ClipboardContentType(rawValue: typeStr) {
                        summary.counts[type] = count
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return summary
    }

    static func fetchPageUUIDs(
        storeURL: URL,
        destination: WorkbenchDestination,
        typeFilter: ClipboardContentType?,
        sortOrder: WorkbenchSortOrder,
        query: String,
        offset: Int,
        limit: Int
    ) -> [UUID] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var sql = "SELECT hex(ZCLIPBOARDITEM.ZID) FROM ZCLIPBOARDITEM "
        var conditions: [String] = []

        if destination == .favorites {
            sql += """
            JOIN Z_2COLLECTIONS ON ZCLIPBOARDITEM.Z_PK = Z_2COLLECTIONS.Z_2ITEMS 
            JOIN ZFAVORITECOLLECTION ON Z_2COLLECTIONS.Z_4COLLECTIONS = ZFAVORITECOLLECTION.Z_PK 
            """
            conditions.append("ZFAVORITECOLLECTION.ZISDEFAULT = 1")
        }

        if let typeFilter {
            if typeFilter == .markdown {
                conditions.append("(ZCLIPBOARDITEM.ZCONTENTTYPE = 'markdown' OR ZCLIPBOARDITEM.ZCONTENTTYPE = 'json')")
            } else {
                conditions.append("ZCLIPBOARDITEM.ZCONTENTTYPE = '\(typeFilter.rawValue)'")
            }
        }

        if !query.isEmpty {
            let escaped = query.replacingOccurrences(of: "'", with: "''")
            conditions.append("""
            (ZCLIPBOARDITEM.ZTEXTCONTENT LIKE '%\(escaped)%' OR 
             ZCLIPBOARDITEM.ZFILENAME LIKE '%\(escaped)%' OR 
             ZCLIPBOARDITEM.ZCUSTOMTITLE LIKE '%\(escaped)%' OR 
             ZCLIPBOARDITEM.ZSOURCEAPP LIKE '%\(escaped)%' OR 
             ZCLIPBOARDITEM.ZOCRTEXT LIKE '%\(escaped)%')
            """)
        }

        if !conditions.isEmpty {
            sql += "WHERE " + conditions.joined(separator: " AND ") + " "
        }

        switch sortOrder {
        case .newestFirst:
            sql += "ORDER BY ZCLIPBOARDITEM.ZCREATEDAT DESC "
        case .oldestFirst:
            sql += "ORDER BY ZCLIPBOARDITEM.ZCREATEDAT ASC "
        case .size:
            sql += "ORDER BY ZCLIPBOARDITEM.ZFILESIZE DESC "
        }

        sql += "LIMIT \(limit) OFFSET \(offset);"

        var stmt: OpaquePointer?
        var uuids: [UUID] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let hexCStr = sqlite3_column_text(stmt, 0) {
                    let hex = String(cString: hexCStr)
                    if let uuid = uuidFromHex(hex) {
                        uuids.append(uuid)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return uuids
    }

    private static func uuidFromHex(_ hex: String) -> UUID? {
        guard hex.count == 32 else { return nil }
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
        return UUID(uuidString: formatted)
    }
}

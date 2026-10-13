//
//  UnifiedSearchCoordinator.swift
//  PasteDeck
//
//  Coordinates unified search results across BuiltinTools and ClipboardItems,
//  maintaining a single consistent keyboard selection index and execution dispatch.
//

import Foundation
import Combine

enum UnifiedSearchEntry: Identifiable, Equatable {
    case tool(ToolSearchService.Result)
    case clipboard(ClipboardItemSnapshot)

    var id: String {
        switch self {
        case .tool(let result):
            return "tool:\(result.id)"
        case .clipboard(let snapshot):
            return "clip:\(snapshot.id.uuidString)"
        }
    }

    var isTool: Bool {
        if case .tool = self { return true }
        return false
    }

    var clipboardSnapshot: ClipboardItemSnapshot? {
        if case .clipboard(let snapshot) = self { return snapshot }
        return nil
    }

    var toolResult: ToolSearchService.Result? {
        if case .tool(let result) = self { return result }
        return nil
    }
}

@MainActor
final class UnifiedSearchCoordinator: ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            performSearch()
        }
    }

    @Published private(set) var toolMatches: [ToolSearchService.Result] = []
    @Published private(set) var unifiedEntries: [UnifiedSearchEntry] = []
    @Published var selectedIndex: Int = 0

    private weak var historyStore: ClipboardHistoryStore?
    private weak var workbenchStore: WorkbenchHistoryStore?
    private var cancellables = Set<AnyCancellable>()

    init(historyStore: ClipboardHistoryStore? = nil) {
        self.historyStore = historyStore
        if let historyStore = historyStore {
            bindHistoryStore(historyStore)
        }
    }

    func setHistoryStore(_ store: ClipboardHistoryStore) {
        self.historyStore = store
        self.workbenchStore = nil
        cancellables.removeAll()
        bindHistoryStore(store)
    }

    func setWorkbenchStore(_ store: WorkbenchHistoryStore) {
        self.workbenchStore = store
        self.historyStore = nil
        cancellables.removeAll()
        bindWorkbenchStore(store)
    }

    private func bindHistoryStore(_ store: ClipboardHistoryStore) {
        store.$filteredItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildEntries()
            }
            .store(in: &cancellables)
    }

    private func bindWorkbenchStore(_ store: WorkbenchHistoryStore) {
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildEntries()
            }
            .store(in: &cancellables)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedEntry: UnifiedSearchEntry? {
        guard !unifiedEntries.isEmpty,
              selectedIndex >= 0,
              selectedIndex < unifiedEntries.count else {
            return nil
        }
        return unifiedEntries[selectedIndex]
    }

    func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            toolMatches = []
        } else {
            toolMatches = ToolSearchService.search(trimmed)
        }
        historyStore?.setSearchText(trimmed)
        workbenchStore?.setSearchText(trimmed)
        rebuildEntries()
    }

    func rebuildEntries() {
        var entries: [UnifiedSearchEntry] = []

        if isSearching {
            for tool in toolMatches {
                entries.append(.tool(tool))
            }
        }

        if let historyItems = historyStore?.filteredItems {
            for item in historyItems {
                entries.append(.clipboard(item))
            }
        } else if let wbItems = workbenchStore?.items {
            for item in wbItems {
                entries.append(.clipboard(item))
            }
        }

        self.unifiedEntries = entries

        if entries.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= entries.count {
            selectedIndex = max(0, entries.count - 1)
        }
    }

    func moveUp() {
        guard !unifiedEntries.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        guard !unifiedEntries.isEmpty else { return }
        selectedIndex = min(unifiedEntries.count - 1, selectedIndex + 1)
    }

    func select(index: Int) {
        guard index >= 0, index < unifiedEntries.count else { return }
        selectedIndex = index
    }

    func select(entry: UnifiedSearchEntry) {
        if let idx = unifiedEntries.firstIndex(of: entry) {
            selectedIndex = idx
        }
    }
}

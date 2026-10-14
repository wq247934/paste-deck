//
//  UnifiedSearchCoordinator.swift
//  PasteDeck
//
//  Coordinates unified search results across BuiltinTools and ClipboardItems,
//  maintaining a single consistent keyboard selection index and execution dispatch.
//

import AppKit
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

    /// 多选集合（剪贴板条目 id）。对齐 master selectedItems 模型。
    @Published private(set) var multiSelectedIDs: Set<UUID> = []
    /// Shift 选区锚点索引。
    private var anchorIndex: Int = 0

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

    /// 是否处于多选状态（≥2 条）。
    var isMultiSelecting: Bool { multiSelectedIDs.count > 1 }

    /// 当前可见条目里参与多选的剪贴板条目，按显示顺序排列。
    var multiSelectedSnapshots: [ClipboardItemSnapshot] {
        unifiedEntries.compactMap { entry -> ClipboardItemSnapshot? in
            guard case .clipboard(let snapshot) = entry else { return nil }
            return multiSelectedIDs.contains(snapshot.id) ? snapshot : nil
        }
    }

    /// 重建 Shift 选区：把 [from, to] 之间的剪贴板条目并入多选（跳过工具条目）。
    private func rebuildExtendedSelection(from: Int, to: Int) {
        let lo = max(0, min(from, to))
        let hi = min(max(from, to), unifiedEntries.count - 1)
        guard lo <= hi else {
            multiSelectedIDs.removeAll()
            return
        }
        var ids = Set(multiSelectedIDs)
        for entry in unifiedEntries[lo...hi] {
            if case .clipboard(let snapshot) = entry {
                ids.insert(snapshot.id)
            }
        }
        multiSelectedIDs = ids
    }

    /// 清除多选。
    func clearMultiSelection() {
        multiSelectedIDs.removeAll()
    }

    /// 点击条目处理：Cmd+Click 翻转选中，Shift+Click 区间选中，普通点击单选。
    /// - Parameter entry: 被点击的统一条目（点击它所在的下标）。
    func handleTap(entry: UnifiedSearchEntry) {
        guard let index = unifiedEntries.firstIndex(of: entry) else { return }
        let commandHeld = NSEvent.modifierFlags.contains(.command)
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)

        switch entry {
        case .tool:
            // 工具条目不参与多选：普通/Shift/Cmd 点击都只移动单选高亮。
            selectedIndex = index
            clearMultiSelection()
            anchorIndex = index
        case .clipboard(let snapshot):
            if commandHeld {
                if multiSelectedIDs.contains(snapshot.id) {
                    multiSelectedIDs.remove(snapshot.id)
                } else {
                    multiSelectedIDs.insert(snapshot.id)
                    anchorIndex = index
                }
                selectedIndex = index
            } else if shiftHeld {
                selectedIndex = index
                rebuildExtendedSelection(from: anchorIndex, to: index)
            } else {
                selectedIndex = index
                clearMultiSelection()
                anchorIndex = index
            }
        }
    }

    func moveUp(extending: Bool) {
        moveSelection(offset: -1, extending: extending)
    }

    func moveDown(extending: Bool) {
        moveSelection(offset: 1, extending: extending)
    }

    private func moveSelection(offset: Int, extending: Bool) {
        guard !unifiedEntries.isEmpty else { return }
        let newIndex = min(max(selectedIndex + offset, 0), unifiedEntries.count - 1)
        guard newIndex != selectedIndex else { return }

        selectedIndex = newIndex
        if extending {
            // Shift+方向键：扩展/收缩连续选区
            rebuildExtendedSelection(from: anchorIndex, to: newIndex)
        } else {
            // 普通方向键：单选移动，清除多选
            clearMultiSelection()
            anchorIndex = newIndex
        }
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

        // 修剪已不在当前结果中的多选 id（搜索词变化、条目被删除等场景）。
        let validIDs = Set(entries.compactMap { $0.clipboardSnapshot?.id })
        if multiSelectedIDs != multiSelectedIDs.intersection(validIDs) {
            multiSelectedIDs = multiSelectedIDs.intersection(validIDs)
        }
    }

    func select(index: Int) {
        guard index >= 0, index < unifiedEntries.count else { return }
        selectedIndex = index
    }

    /// 面板显示时的默认选中：与 master selectDefaultCard() 一致，条目多于
    /// 一条时选中第二条（第一条通常刚被上一轮粘贴顶到最前，是"最旧"的内容）。
    func selectDefault() {
        multiSelectedIDs.removeAll()
        guard !unifiedEntries.isEmpty else {
            selectedIndex = 0
            anchorIndex = 0
            return
        }
        selectedIndex = unifiedEntries.count > 1 ? 1 : 0
        anchorIndex = selectedIndex
    }

    func select(entry: UnifiedSearchEntry) {
        if let idx = unifiedEntries.firstIndex(of: entry) {
            selectedIndex = idx
        }
    }
}

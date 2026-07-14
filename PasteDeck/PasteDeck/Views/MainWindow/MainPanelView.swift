//
//  MainPanelView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Notification Names

extension Notification.Name {
    static let clearSearchText = Notification.Name("clearSearchText")
    static let clearSelection = Notification.Name("clearSelection")
    static let panelDidShow = Notification.Name("panelDidShow")
    static let panelDidRequestCardFocus = Notification.Name("panelDidRequestCardFocus")
    static let toggleMainPanel = Notification.Name("toggleMainPanel")
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
    /// 既有项目的置顶/收藏夹归属被就地修改（不改变 @Query 数组成员），需要刷新过滤缓存
    static let clipboardDataChanged = Notification.Name("clipboardDataChanged")
}

// MARK: - Focus Zone Enum

/// 焦点区域：卡片区 / 搜索栏
enum FocusZone {
    case cards
    case search
}

/// 翻页方向
enum ScrollDirection {
    case up
    case down
}

/// 主面板列表的实际视觉布局。横竖方向设置会映射到其中一种稳定布局。
enum MainPanelCollectionLayout: Equatable {
    case horizontal
    case verticalCompactList
    case verticalLargeCards
    case verticalAdaptiveGrid

    var isHorizontal: Bool {
        self == .horizontal
    }
}

/// 卡片集合布局共享的间距，确保滚动、分页和网格计算使用同一度量。
private enum MainPanelCollectionMetrics {
    static let itemSpacing: CGFloat = 12
}

/// 根据卡片框和真实滚动视口判断键盘选中的卡片是否完整可见。
///
/// `NSCollectionView.indexPathsForVisibleItems()` 会把只露出少量像素的预加载卡片
/// 也视为可见；键盘导航必须以完整可见为准，才能在窗口尺寸变化后及时滚动。
enum MainPanelCollectionViewport {
    static func contains(
        itemFrame: NSRect,
        viewport: NSRect,
        isHorizontal: Bool
    ) -> Bool {
        guard !itemFrame.isNull, !viewport.isNull else { return false }

        if isHorizontal {
            return itemFrame.minX >= viewport.minX && itemFrame.maxX <= viewport.maxX
        }

        return itemFrame.minY >= viewport.minY && itemFrame.maxY <= viewport.maxY
    }
}

/// 主面板键盘导航使用的四个物理方向。
enum MainPanelNavigationDirection {
    case left
    case right
    case up
    case down
}

/// 与 SwiftUI 状态解耦的导航计算，确保网格末行和边界行为可以稳定测试。
enum MainPanelNavigation {
    static func nextIndex(
        currentIndex: Int,
        itemCount: Int,
        layout: MainPanelCollectionLayout,
        gridColumnCount: Int,
        direction: MainPanelNavigationDirection
    ) -> Int {
        guard itemCount > 0 else { return 0 }

        let lastIndex = itemCount - 1
        let boundedCurrentIndex = min(max(0, currentIndex), lastIndex)

        switch layout {
        case .horizontal:
            switch direction {
            case .left:
                return max(0, boundedCurrentIndex - 1)
            case .right:
                return min(lastIndex, boundedCurrentIndex + 1)
            case .up, .down:
                return boundedCurrentIndex
            }
        case .verticalCompactList, .verticalLargeCards:
            switch direction {
            case .up:
                return max(0, boundedCurrentIndex - 1)
            case .down:
                return min(lastIndex, boundedCurrentIndex + 1)
            case .left, .right:
                return boundedCurrentIndex
            }
        case .verticalAdaptiveGrid:
            let columnCount = max(1, min(2, gridColumnCount))
            let currentColumn = boundedCurrentIndex % columnCount
            switch direction {
            case .left:
                guard currentColumn > 0 else { return boundedCurrentIndex }
                return boundedCurrentIndex - 1
            case .right:
                guard currentColumn < columnCount - 1,
                      boundedCurrentIndex < lastIndex else { return boundedCurrentIndex }
                return boundedCurrentIndex + 1
            case .up:
                guard boundedCurrentIndex >= columnCount else { return boundedCurrentIndex }
                return boundedCurrentIndex - columnCount
            case .down:
                let currentRow = boundedCurrentIndex / columnCount
                let lastRow = lastIndex / columnCount
                guard currentRow < lastRow else { return boundedCurrentIndex }
                return min(lastIndex, boundedCurrentIndex + columnCount)
            }
        }
    }
}

struct MainPanelView: View {
    @Query private var settings: [AppSettings]

    @StateObject private var historyStore = ClipboardHistoryStore(
        modelContext: ModelContext(AppModelContainer.container)
    )

    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilterOption = .all
    @State private var selectedSourceApp: String?
    @State private var selectedItemID: UUID?
    @State private var selectedIndex = 0

    /// 多选集合
    @State private var selectedItems: Set<UUID> = []
    /// Shift 选区锚点索引
    @State private var anchorIndex: Int = 0

    /// 当前焦点所在区域
    @State private var focusZone: FocusZone = .cards
    @State private var cardFocusRequest = 0
    /// 自适应网格当前实际列数（1 或 2），用于让键盘上下移动与可见布局保持一致。
    @State private var adaptiveGridColumnCount = 1
    /// 横向布局一屏完整可见的卡片数，用于上下方向键按当前面板尺寸翻页。
    @State private var horizontalPageCardCount = 1

    /// 搜索栏焦点绑定
    @FocusState private var isSearchFocused: Bool

    /// 预览窗口控制器（需要持有以防止被释放）
    @State private var previewController: PreviewWindowController?

    var closeHandler: (() -> Void)?
    var openSettingsHandler: (() -> Void)?

    // MARK: - Filtered & Sorted Items

    private var appSettings: AppSettings? {
        settings.first
    }

    private var panelOrientation: PanelOrientation {
        appSettings?.panelOrientation ?? .horizontal
    }

    private var verticalPanelStyle: VerticalPanelStyle {
        appSettings?.verticalPanelStyle ?? .compactList
    }

    private var collectionLayout: MainPanelCollectionLayout {
        guard panelOrientation == .vertical else { return .horizontal }

        switch verticalPanelStyle {
        case .compactList:
            return .verticalCompactList
        case .largeCards:
            return .verticalLargeCards
        case .adaptiveGrid:
            return .verticalAdaptiveGrid
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appSettings.flatMap({ AppTheme(rawValue: $0.themeMode) }) ?? .system {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// 当前筛选标签索引（用于 Tab 循环）
    private var filterOptions: [ClipboardFilterOption] {
        [.all] + historyStore.collections.map { .collection($0.id) }
    }

    /// 重算过滤缓存，并修正可能越界的选中索引
    private func reconcileSelection() {
        let items = historyStore.filteredItems
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
        if let selectedItemID,
           let index = items.firstIndex(where: { $0.id == selectedItemID }) {
            selectedIndex = index
        } else {
            selectedItemID = items.isEmpty ? nil : items[selectedIndex].id
        }
    }

    private func selectDefaultCard() {
        let items = historyStore.filteredItems
        if items.count > 1 {
            selectedIndex = 1
            selectedItemID = items[1].id
            anchorIndex = 1
        } else if !items.isEmpty {
            selectedIndex = 0
            selectedItemID = items.first?.id
            anchorIndex = 0
        } else {
            selectedIndex = 0
            selectedItemID = nil
            anchorIndex = 0
        }
    }

    private func focusCards() {
        isSearchFocused = false
        focusZone = .cards
        cardFocusRequest += 1
    }

    private func setSourceAppFilter(_ sourceApp: String?) {
        let normalizedSourceApp = ClipboardItem.normalizedSourceAppName(sourceApp)
        selectedSourceApp = normalizedSourceApp
        historyStore.setSourceAppFilter(normalizedSourceApp)
        clearMultiSelection()
        selectDefaultCard()
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            panelContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            historyStore.loadIfNeeded()
            reconcileSelection()
            selectDefaultCard()
            focusCards()
        }
        .onChange(of: searchText) { _, _ in
            historyStore.setSearchText(searchText)
        }
        .onChange(of: selectedFilter) { _, _ in
            historyStore.setFilter(selectedFilter)
        }
        .onChange(of: historyStore.sourceApps) { _, sourceApps in
            if let selectedSourceApp, !sourceApps.contains(selectedSourceApp) {
                setSourceAppFilter(nil)
            }
        }
        .onReceive(historyStore.$filteredItems) { items in
            if selectedItemID == nil && !items.isEmpty {
                selectDefaultCard()
            } else {
                reconcileSelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDataChanged)) { notification in
            if let itemID = notification.userInfo?[ClipboardDataChangeNotification.itemIDKey] as? UUID {
                let kind = notification.userInfo?[ClipboardDataChangeNotification.changeKindKey] as? String
                historyStore.refreshItem(
                    id: itemID,
                    insertIfMissing: kind == ClipboardDataChangeKind.inserted.rawValue
                )
            } else {
                historyStore.reloadFromDatabase()
            }
            reconcileSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearSearchText)) { _ in
            searchText = ""
            clearMultiSelection()
            selectedFilter = .all
            setSourceAppFilter(nil)
            historyStore.setSearchText("")
            historyStore.setFilter(.all)
            selectDefaultCard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            historyStore.loadIfNeeded()
            setSourceAppFilter(nil)
            selectDefaultCard()
            focusCards()
            clearMultiSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidRequestCardFocus)) { _ in
            focusCards()
        }
        .background(keyboardEventMonitor)
    }

    @ViewBuilder
    private var panelContent: some View {
        if historyStore.isLoading && historyStore.filteredItems.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if historyStore.filteredItems.isEmpty {
            EmptyStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            virtualizedList
        }
    }

    private var virtualizedList: some View {
        VirtualizedCardList(
            items: historyStore.filteredItems,
            collections: historyStore.collections,
            selectedItemId: selectedItemID,
            selectedItems: selectedItems,
            showSelection: focusZone == .cards,
            showPinOption: selectedFilter != .all,
            layout: collectionLayout,
            onGridColumnCountChange: updateAdaptiveGridColumnCount,
            onHorizontalPageCardCountChange: updateHorizontalPageCardCount,
            onItemTapped: handleItemTap,
            onItemDoubleTapped: { itemID in
                pasteItem(id: itemID)
            },
            onCopy: { itemID in
                historyStore.copyToPasteboard(id: itemID)
            },
            onPastePlain: { itemID in
                pasteItem(id: itemID, plainText: true)
            },
            onTogglePinned: historyStore.togglePinned,
            onToggleFavorite: historyStore.toggleDefaultFavorite,
            onToggleCollection: historyStore.toggleCollection,
            onSaveTitle: historyStore.saveTitle,
            onDelete: deleteItem
        )
        .padding(.top, panelOrientation == .horizontal ? 12 : 8)
    }

    private var keyboardEventMonitor: some View {
        KeyboardEventMonitorView(
            focusZone: $focusZone,
            selectedFilter: $selectedFilter,
            focusRequest: cardFocusRequest,
            filterOptions: filterOptions,
            onLeftArrow: handleLeftArrow,
            onRightArrow: handleRightArrow,
            onUpArrow: handleUpArrow,
            onDownArrow: handleDownArrow,
            onEnter: handleEnter,
            onEscape: closePreviewOrPanel,
            onSpace: previewSelectedItem,
            onDelete: deleteSelectedItem,
            onCmdF: focusSearch
        )
    }

    @ViewBuilder
    private var panelHeader: some View {
        if panelOrientation == .horizontal {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    panelSearchBar
                    sourceAppMenu
                    settingsButton
                }

                favoriteFilterTabs
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    panelSearchBar
                    settingsButton
                }

                HStack(spacing: 10) {
                    sourceAppMenu
                    favoriteFilterTabs
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private var panelSearchBar: some View {
        SearchBarView(text: $searchText, isFocused: $isSearchFocused)
            .onChange(of: isSearchFocused) { _, newValue in
                if newValue {
                    focusZone = .search
                }
            }
            .onChange(of: focusZone) { _, newZone in
                isSearchFocused = newZone == .search
            }
            .onSubmit {
                focusCards()
                if !historyStore.filteredItems.isEmpty {
                    selectedIndex = 0
                    selectedItemID = historyStore.filteredItems.first?.id
                    anchorIndex = 0
                    clearMultiSelection()
                }
            }
    }

    private var sourceAppMenu: some View {
        SourceAppFilterMenu(
            selectedSourceApp: selectedSourceApp,
            sourceApps: historyStore.sourceApps,
            onSelect: setSourceAppFilter
        )
    }

    private var settingsButton: some View {
        MainPanelSettingsButton {
            openSettingsHandler?()
        }
    }

    private var favoriteFilterTabs: some View {
        FavoriteFilterTabs(
            options: filterOptions,
            selectedFilter: $selectedFilter,
            collections: historyStore.collections,
            onCreateCollection: { name in
                historyStore.createCollection(name: name)
            }
        )
    }

    private func updateAdaptiveGridColumnCount(_ columnCount: Int) {
        let normalizedColumnCount = max(1, min(2, columnCount))
        guard adaptiveGridColumnCount != normalizedColumnCount else { return }
        adaptiveGridColumnCount = normalizedColumnCount
    }

    private func updateHorizontalPageCardCount(_ cardCount: Int) {
        let normalizedCardCount = max(1, cardCount)
        guard horizontalPageCardCount != normalizedCardCount else { return }
        horizontalPageCardCount = normalizedCardCount
    }

    private func handleLeftArrow(_ extending: Bool) {
        switch collectionLayout {
        case .horizontal, .verticalAdaptiveGrid:
            moveSelection(direction: .left, extending: extending)
        case .verticalCompactList, .verticalLargeCards:
            break
        }
    }

    private func handleRightArrow(_ extending: Bool) {
        switch collectionLayout {
        case .horizontal, .verticalAdaptiveGrid:
            moveSelection(direction: .right, extending: extending)
        case .verticalCompactList, .verticalLargeCards:
            break
        }
    }

    private func handleUpArrow(_ extending: Bool) {
        switch collectionLayout {
        case .horizontal:
            scrollPage(direction: .up)
        case .verticalCompactList, .verticalLargeCards:
            moveSelection(direction: .up, extending: extending)
        case .verticalAdaptiveGrid:
            moveSelection(direction: .up, extending: extending)
        }
    }

    private func handleDownArrow(_ extending: Bool) {
        switch collectionLayout {
        case .horizontal:
            scrollPage(direction: .down)
        case .verticalCompactList, .verticalLargeCards:
            moveSelection(direction: .down, extending: extending)
        case .verticalAdaptiveGrid:
            moveSelection(direction: .down, extending: extending)
        }
    }

    private func handleEnter(_ shiftHeld: Bool) {
        if focusZone == .search {
            focusCards()
            if !historyStore.filteredItems.isEmpty {
                selectedIndex = 0
                selectedItemID = historyStore.filteredItems.first?.id
                anchorIndex = 0
                clearMultiSelection()
            }
        } else {
            pasteSelectedItems(plainText: shiftHeld)
        }
    }

    private func previewSelectedItem() {
        guard let selectedItemID else { return }
        previewItem(id: selectedItemID)
    }

    private func focusSearch() {
        focusZone = .search
    }

    // MARK: - Selection Logic

    /// 按当前可见布局计算方向键的目标索引，再统一更新单选或 Shift 连续选区。
    private func moveSelection(direction: MainPanelNavigationDirection, extending: Bool) {
        let items = historyStore.filteredItems
        guard !items.isEmpty else { return }
        let newIndex = MainPanelNavigation.nextIndex(
            currentIndex: selectedIndex,
            itemCount: items.count,
            layout: collectionLayout,
            gridColumnCount: adaptiveGridColumnCount,
            direction: direction
        )
        guard newIndex != selectedIndex else { return }

        if extending {
            // Shift+方向键：扩展/收缩选区
            _ = selectedIndex
            selectedIndex = newIndex
            selectedItemID = items[newIndex].id
            rebuildExtendedSelection(from: anchorIndex, to: newIndex)
        } else {
            // 普通方向键：单选移动，清除多选
            selectedIndex = newIndex
            selectedItemID = items[newIndex].id
            clearMultiSelection()
            anchorIndex = newIndex
        }
    }

    /// 点击卡片处理
    private func handleItemTap(index: Int, itemID: UUID) {
        let isCmdHeld = NSEvent.modifierFlags.contains(.command)
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isCmdHeld {
            // Cmd+Click: toggle 选中
            if selectedItems.contains(itemID) {
                selectedItems.remove(itemID)
                // 如果移除的是当前选中项，更新当前选中
                if selectedItemID == itemID {
                    selectedItemID = selectedItems.isEmpty ? nil : historyStore.filteredItems.first(where: { selectedItems.contains($0.id) })?.id
                    selectedIndex = historyStore.filteredItems.firstIndex(where: { $0.id == (selectedItemID ?? UUID()) }) ?? index
                }
            } else {
                selectedItems.insert(itemID)
                selectedIndex = index
                selectedItemID = itemID
                anchorIndex = index
            }
        } else if isShiftHeld {
            // Shift+Click: 区间选中
            selectedIndex = index
            selectedItemID = itemID
            rebuildExtendedSelection(from: anchorIndex, to: index)
        } else {
            // 普通点击：清除多选，单选
            selectedIndex = index
            selectedItemID = itemID
            clearMultiSelection()
            anchorIndex = index
        }
        focusCards()
    }

    /// 重建 Shift 选区
    private func rebuildExtendedSelection(from: Int, to: Int) {
        let items = historyStore.filteredItems
        guard !items.isEmpty else {
            selectedItems.removeAll()
            return
        }
        let lo = min(min(from, to), items.count - 1)
        let hi = min(max(from, to), items.count - 1)
        selectedItems = Set(items[lo...hi].map { $0.id })
    }

    /// 清除多选
    private func clearMultiSelection() {
        selectedItems.removeAll()
    }

    // MARK: - Actions

    /// 批量粘贴所有选中项（若无多选则粘贴当前项）
    private func pasteSelectedItems(plainText: Bool = false) {
        if selectedItems.count <= 1 {
            guard let selectedItemID else { return }
            pasteItem(id: selectedItemID, plainText: plainText)
            return
        }

        let idsToPaste: [UUID]
        // 按显示顺序（newest first）排列
        idsToPaste = historyStore.filteredItems.map(\.id).filter { selectedItems.contains($0) }
        guard !idsToPaste.isEmpty else {
            return
        }

        historyStore.promotePastedItems(ids: idsToPaste)
        closeHandler?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            historyStore.batchPaste(ids: idsToPaste, plainText: plainText)
        }
    }

    private func pasteItem(id: UUID, plainText: Bool = false) {
        historyStore.promotePastedItems(ids: [id])
        historyStore.preparePaste(id: id, plainText: plainText)
        closeHandler?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteService.shared.performPaste()
        }
    }

    /// 上下键翻页：滚动卡片列表一屏
    private func scrollPage(direction: ScrollDirection) {
        let items = historyStore.filteredItems
        guard !items.isEmpty else { return }
        // 由 NSCollectionView 根据当前视口宽度和卡片尺寸计算，不能依赖固定面板宽度。
        let cardsPerPage = horizontalPageCardCount
        let offset = direction == .up ? -cardsPerPage : cardsPerPage
        let newIndex = max(0, min(items.count - 1, selectedIndex + offset))
        if newIndex != selectedIndex {
            selectedIndex = newIndex
            selectedItemID = items[newIndex].id
            clearMultiSelection()
            anchorIndex = newIndex
        }
    }

    /// Esc 统一处理：如果预览窗口打开则关闭预览，否则关闭主面板
    private func closePreviewOrPanel() {
        // 如果预览窗口打开且是 keyWindow，关闭预览窗口
        if let controller = previewController, controller.isWindowVisible {
            controller.performClose()
            return
        }
        // 否则关闭主面板
        closeHandler?()
    }

    private func previewItem(id: UUID) {
        guard let item = historyStore.fetchItem(id: id) else { return }
        if item.isTranslationHistory {
            Task { @MainActor in
                TranslationCoordinator.shared.openTranslationHistory(itemID: item.id)
            }
            return
        }
        previewController = PreviewWindowController()
        previewController?.show(item: item, onClose: {})
    }

    private func deleteSelectedItem() {
        guard let selectedItemID else { return }
        deleteItem(id: selectedItemID)
    }

    private func deleteItem(id: UUID) {
        let nextIndex = selectedIndex
        historyStore.deleteItem(id: id)

        let items = historyStore.filteredItems
        if !items.isEmpty {
            selectedIndex = min(nextIndex, items.count - 1)
            selectedItemID = items[selectedIndex].id
            anchorIndex = selectedIndex
        } else {
            selectedIndex = 0
            selectedItemID = nil
            anchorIndex = 0
        }
        clearMultiSelection()
    }
}

// MARK: - Filter Option

// MARK: - Settings Entry

struct MainPanelSettingsButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isHovering ? 0.09 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(isHovering ? 0.1 : 0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("打开设置")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct SourceAppFilterMenu: View {
    let selectedSourceApp: String?
    let sourceApps: [String]
    let onSelect: (String?) -> Void

    @State private var isHovering = false

    private var isActive: Bool {
        selectedSourceApp != nil
    }

    private var selectedTitle: String {
        selectedSourceApp ?? "全部"
    }

    var body: some View {
        Menu {
            sourceMenuItem(title: "全部来源", isSelected: !isActive) {
                onSelect(nil)
            }

            if !sourceApps.isEmpty {
                Divider()

                ForEach(sourceApps, id: \.self) { sourceApp in
                    sourceMenuItem(title: sourceApp, isSelected: selectedSourceApp == sourceApp) {
                        onSelect(sourceApp)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isActive ? .accentColor : .secondary)

                Text("来源")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Text(selectedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 88, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: true)
        .help("按来源应用筛选")
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(isHovering ? 0.16 : 0.12)
        }
        return Color.primary.opacity(isHovering ? 0.08 : 0.045)
    }

    private var borderColor: Color {
        if isActive {
            return Color.accentColor.opacity(isHovering ? 0.26 : 0.18)
        }
        return Color.primary.opacity(isHovering ? 0.1 : 0.05)
    }

    @ViewBuilder
    private func sourceMenuItem(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

// MARK: - Favorite Filter Tabs

struct FavoriteFilterTabs: View {
    let options: [ClipboardFilterOption]
    @Binding var selectedFilter: ClipboardFilterOption
    let collections: [ClipboardCollectionSnapshot]
    let onCreateCollection: (String) -> Void

    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = "新建收藏夹"

    var body: some View {
        HStack(spacing: 0) {
            // 标签栏（横向滚动）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Button(action: {
                            selectedFilter = option
                        }) {
                            Text(option.displayName(collections: collections))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedFilter == option ? .white : .primary)
                                .frame(minWidth: 60)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == option ? Color.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                    }
                }
            }

            // + 按钮
            Button(action: {
                newCollectionName = "新建收藏夹"
                showNewCollectionSheet = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showNewCollectionSheet) {
                VStack(spacing: 16) {
                    Text("新建收藏夹")
                        .font(.headline)

                    TextField("收藏夹名称", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)

                    HStack {
                        Button("取消") {
                            showNewCollectionSheet = false
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("创建") {
                            createCollection()
                            showNewCollectionSheet = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(24)
                .frame(width: 320)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.1))
        )
    }

    private func createCollection() {
        onCreateCollection(newCollectionName)
    }
}

// MARK: - Virtualized Card List

/// 布局感知的虚拟化剪切板列表，只为可见区域附近创建 SwiftUI 单元格。
struct VirtualizedCardList: NSViewRepresentable {
    /// 当前筛选后的剪切板快照，顺序即屏幕展示与键盘导航顺序。
    let items: [ClipboardItemSnapshot]
    /// 当前收藏夹快照，为所有可见单元格提供右键收藏菜单。
    let collections: [ClipboardCollectionSnapshot]
    /// 键盘主选项 ID；nil 表示当前没有可选择记录。
    let selectedItemId: UUID?
    /// Cmd 或 Shift 建立的连续/离散多选集合。
    let selectedItems: Set<UUID>
    /// 是否绘制选中状态；搜索框获得焦点时关闭，避免出现双重焦点提示。
    var showSelection: Bool = true
    /// 当前筛选上下文是否允许单元格展示置顶操作。
    var showPinOption: Bool = true
    /// 当前横向或竖向视觉布局，决定滚动轴、单元格尺寸和渲染器。
    let layout: MainPanelCollectionLayout
    /// 自适应网格列数变化回调，让键盘导航与 AppKit 实际布局使用同一列数。
    let onGridColumnCountChange: (Int) -> Void
    /// 横向布局完整可见卡片数变化回调，让上下键翻页与当前面板宽度保持一致。
    let onHorizontalPageCardCountChange: (Int) -> Void
    /// 单击单元格后的索引和稳定 ID 回调。
    let onItemTapped: (Int, UUID) -> Void
    /// 双击单元格后立即粘贴该记录的回调。
    let onItemDoubleTapped: (UUID) -> Void
    /// 将指定记录重新写入剪切板的回调。
    let onCopy: (UUID) -> Void
    /// 纯文本粘贴回调；nil 表示当前调用方不提供该能力。
    var onPastePlain: ((UUID) -> Void)? = nil
    /// 切换指定记录置顶状态的回调。
    let onTogglePinned: (UUID) -> Void
    /// 切换指定记录默认收藏状态的回调。
    let onToggleFavorite: (UUID) -> Void
    /// 切换指定记录与收藏夹归属关系的回调。
    let onToggleCollection: (UUID, UUID) -> Void
    /// 保存或清除指定记录用户别名的回调。
    let onSaveTitle: (UUID, String?) -> Void
    /// 删除指定剪切板记录的回调。
    let onDelete: (UUID) -> Void

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("PasteDeckCardCollectionViewItem")

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Swift arrays retain copy-on-write storage across view-state updates.
    /// Pointer identity lets keyboard selection avoid a deep 5000-item equality
    /// pass while any real snapshot replacement still triggers a data refresh.
    private static func sharesStorage<Element>(_ left: [Element], _ right: [Element]) -> Bool {
        guard left.count == right.count else { return false }
        guard !left.isEmpty else { return true }

        return left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                leftBuffer.baseAddress == rightBuffer.baseAddress
            }
        }
    }

    func makeNSView(context: Context) -> AdaptiveCardScrollView {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = MainPanelCollectionMetrics.itemSpacing
        flowLayout.minimumLineSpacing = MainPanelCollectionMetrics.itemSpacing

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(
            CardCollectionViewItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )

        let scrollView = AdaptiveCardScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        scrollView.panelLayout = layout
        scrollView.onViewportSizeChange = { [weak coordinator = context.coordinator] viewportSize in
            coordinator?.viewportDidChange(viewportSize)
        }
        context.coordinator.viewportDidChange(scrollView.contentSize)
        return scrollView
    }

    func updateNSView(_ scrollView: AdaptiveCardScrollView, context: Context) {
        let coordinator = context.coordinator
        let previousParent = coordinator.parent
        let dataChanged = !Self.sharesStorage(previousParent.items, items)
            || !Self.sharesStorage(previousParent.collections, collections)
        let presentationChanged = previousParent.layout != layout
            || previousParent.showSelection != showSelection
            || previousParent.showPinOption != showPinOption

        coordinator.parent = self
        if dataChanged {
            coordinator.rebuildItemIndexPaths()
        }
        scrollView.panelLayout = layout
        coordinator.viewportDidChange(scrollView.contentSize)

        if dataChanged || presentationChanged {
            coordinator.collectionView.reloadData()
        } else {
            coordinator.reloadSelectionChanges(from: previousParent)
        }

        if previousParent.selectedItemId != selectedItemId || presentationChanged {
            if presentationChanged {
                var scrollOrigin = scrollView.contentView.bounds.origin
                if layout.isHorizontal {
                    scrollOrigin.y = 0
                } else {
                    scrollOrigin.x = 0
                }
                scrollView.contentView.scroll(to: scrollOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            coordinator.scrollSelectedIntoViewIfNeeded(force: presentationChanged)
        }
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: VirtualizedCardList
        weak var collectionView: NSCollectionView!
        weak var scrollView: AdaptiveCardScrollView?
        private var currentMetrics = CollectionLayoutMetrics.horizontalFallback
        private var lastReportedGridColumnCount = 0
        private var lastReportedHorizontalPageCardCount = 0
        private var itemIndexPathsByID: [UUID: IndexPath] = [:]

        init(_ parent: VirtualizedCardList) {
            self.parent = parent
            super.init()
            rebuildItemIndexPaths()
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: VirtualizedCardList.itemIdentifier,
                for: indexPath
            )

            guard let cardItem = item as? CardCollectionViewItem,
                  indexPath.item < parent.items.count else {
                return item
            }

            configure(cardItem, at: indexPath)
            return cardItem
        }

        func viewportDidChange(_ viewportSize: NSSize) {
            let nextMetrics = CollectionLayoutMetrics.make(
                layout: parent.layout,
                viewportSize: viewportSize
            )
            guard nextMetrics != currentMetrics else { return }

            currentMetrics = nextMetrics
            guard let flowLayout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }

            flowLayout.scrollDirection = nextMetrics.isHorizontal ? .horizontal : .vertical
            flowLayout.sectionInset = nextMetrics.isHorizontal
                ? NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
                : NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            flowLayout.itemSize = nextMetrics.itemSize
            flowLayout.invalidateLayout()

            reportGridColumnCountIfNeeded(nextMetrics.gridColumnCount)
            reportHorizontalPageCardCountIfNeeded(nextMetrics.horizontalPageCardCount)
            reconfigureVisibleItems()
        }

        func reloadSelectionChanges(from previousParent: VirtualizedCardList) {
            var changedItemIDs = previousParent.selectedItems.symmetricDifference(parent.selectedItems)
            if (previousParent.selectedItems.count > 1) != (parent.selectedItems.count > 1) {
                changedItemIDs.formUnion(previousParent.selectedItems)
                changedItemIDs.formUnion(parent.selectedItems)
            }
            if let previousSelectedItemID = previousParent.selectedItemId {
                changedItemIDs.insert(previousSelectedItemID)
            }
            if let selectedItemID = parent.selectedItemId {
                changedItemIDs.insert(selectedItemID)
            }
            guard !changedItemIDs.isEmpty else { return }

            let indexPaths = changedItemIDs.compactMap { itemIndexPathsByID[$0] }
            guard !indexPaths.isEmpty else { return }

            collectionView.reloadItems(at: Set(indexPaths))
        }

        func rebuildItemIndexPaths() {
            itemIndexPathsByID = Dictionary(
                uniqueKeysWithValues: parent.items.enumerated().map { index, item in
                    (item.id, IndexPath(item: index, section: 0))
                }
            )
        }

        func scrollSelectedIntoViewIfNeeded(force: Bool = false) {
            guard let selectedItemId = parent.selectedItemId,
                  let indexPath = itemIndexPathsByID[selectedItemId] else {
                return
            }

            if !force, isItemFullyVisible(at: indexPath) {
                return
            }

            collectionView.scrollToItems(
                at: Set([indexPath]),
                scrollPosition: currentMetrics.isHorizontal ? .centeredHorizontally : .centeredVertically
            )
        }

        /// 只露出部分的边缘卡片必须被当作不可见，以便方向键立即将其滚入当前视口。
        private func isItemFullyVisible(at indexPath: IndexPath) -> Bool {
            guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return false
            }

            return MainPanelCollectionViewport.contains(
                itemFrame: layoutAttributes.frame,
                viewport: collectionView.visibleRect,
                isHorizontal: currentMetrics.isHorizontal
            )
        }

        private func configure(_ cardItem: CardCollectionViewItem, at indexPath: IndexPath) {
            guard indexPath.item < parent.items.count else { return }

            let snapshot = parent.items[indexPath.item]
            let index = indexPath.item
            let isSelected = parent.showSelection
                && (parent.selectedItems.contains(snapshot.id) || parent.selectedItemId == snapshot.id)
            let isMultiSelected = parent.showSelection
                && parent.selectedItems.contains(snapshot.id)
                && parent.selectedItems.count > 1

            switch parent.layout {
            case .verticalCompactList:
                let rootView = CompactClipRowView(
                    item: snapshot,
                    isSelected: isSelected,
                    isMultiSelected: isMultiSelected,
                    showPinOption: parent.showPinOption,
                    collections: parent.collections,
                    onCopy: { [weak self] in
                        self?.parent.onCopy(snapshot.id)
                    },
                    onPastePlain: { [weak self] in
                        self?.parent.onPastePlain?(snapshot.id)
                    },
                    onTogglePinned: { [weak self] in
                        self?.parent.onTogglePinned(snapshot.id)
                    },
                    onToggleFavorite: { [weak self] in
                        self?.parent.onToggleFavorite(snapshot.id)
                    },
                    onToggleCollection: { [weak self] collectionID in
                        self?.parent.onToggleCollection(snapshot.id, collectionID)
                    },
                    onSaveTitle: { [weak self] title in
                        self?.parent.onSaveTitle(snapshot.id, title)
                    },
                    onDelete: { [weak self] in
                        self?.parent.onDelete(snapshot.id)
                    }
                )
                .equatable()
                .gesture(cardInteractionGesture(index: index, itemID: snapshot.id))
                .frame(width: currentMetrics.itemSize.width, height: currentMetrics.itemSize.height)

                cardItem.configure(rootView)
            case .horizontal, .verticalLargeCards, .verticalAdaptiveGrid:
                let cardMetrics = currentMetrics.cardMetrics
                    ?? ClipCardLayoutMetrics(cardSize: .medium)
                let rootView = ClipCardView(
                    item: snapshot,
                    isSelected: isSelected,
                    isMultiSelected: isMultiSelected,
                    showPinOption: parent.showPinOption,
                    cardSize: .medium,
                    layoutMetrics: cardMetrics,
                    collections: parent.collections,
                    onCopy: { [weak self] in
                        self?.parent.onCopy(snapshot.id)
                    },
                    onPastePlain: { [weak self] in
                        self?.parent.onPastePlain?(snapshot.id)
                    },
                    onTogglePinned: { [weak self] in
                        self?.parent.onTogglePinned(snapshot.id)
                    },
                    onToggleFavorite: { [weak self] in
                        self?.parent.onToggleFavorite(snapshot.id)
                    },
                    onToggleCollection: { [weak self] collectionID in
                        self?.parent.onToggleCollection(snapshot.id, collectionID)
                    },
                    onSaveTitle: { [weak self] title in
                        self?.parent.onSaveTitle(snapshot.id, title)
                    },
                    onDelete: { [weak self] in
                        self?.parent.onDelete(snapshot.id)
                    }
                )
                .equatable()
                .gesture(cardInteractionGesture(index: index, itemID: snapshot.id))
                .frame(width: currentMetrics.itemSize.width, height: currentMetrics.itemSize.height)

                cardItem.configure(rootView)
            }
        }

        /// 先识别双击，再在双击失败后处理单击，避免两个独立点击手势竞争导致双击粘贴丢失。
        private func cardInteractionGesture(index: Int, itemID: UUID) -> some Gesture {
            TapGesture(count: 2)
                .onEnded { [weak self] _ in
                    self?.parent.onItemDoubleTapped(itemID)
                }
                .exclusively(before: TapGesture().onEnded { [weak self] _ in
                    self?.parent.onItemTapped(index, itemID)
                })
        }

        private func reconfigureVisibleItems() {
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard let cardItem = collectionView.item(at: indexPath) as? CardCollectionViewItem else { continue }
                configure(cardItem, at: indexPath)
            }
        }

        private func reportGridColumnCountIfNeeded(_ columnCount: Int) {
            guard columnCount != lastReportedGridColumnCount else { return }
            lastReportedGridColumnCount = columnCount

            DispatchQueue.main.async { [weak self] in
                self?.parent.onGridColumnCountChange(columnCount)
            }
        }

        private func reportHorizontalPageCardCountIfNeeded(_ cardCount: Int) {
            guard cardCount != lastReportedHorizontalPageCardCount else { return }
            lastReportedHorizontalPageCardCount = cardCount

            DispatchQueue.main.async { [weak self] in
                self?.parent.onHorizontalPageCardCountChange(cardCount)
            }
        }
    }

    /// AppKit flow layout 所需的固定度量。窗口 resize 只更新这些值并失效布局。
    struct CollectionLayoutMetrics: Equatable {
        /// 单元格在 `NSCollectionViewFlowLayout` 中占用的宽高。
        let itemSize: NSSize
        /// 大卡片渲染使用的内部预览和元信息尺寸；紧凑列表为 nil。
        let cardMetrics: ClipCardLayoutMetrics?
        /// 自适应网格当前实际列数；非网格布局固定为 1。
        let gridColumnCount: Int
        /// 横向布局一屏完整显示的卡片数；竖向布局固定为 1。
        let horizontalPageCardCount: Int
        /// 是否使用横向滚动轴，同时控制滚轮轴转换。
        let isHorizontal: Bool

        static let horizontalFallback = CollectionLayoutMetrics(
            itemSize: NSSize(width: 160, height: 156),
            cardMetrics: ClipCardLayoutMetrics(cardSize: .medium),
            gridColumnCount: 1,
            horizontalPageCardCount: 1,
            isHorizontal: true
        )

        static func make(
            layout: MainPanelCollectionLayout,
            viewportSize: NSSize
        ) -> CollectionLayoutMetrics {
            let viewportWidth = max(1, viewportSize.width)
            let viewportHeight = max(1, viewportSize.height)

            switch layout {
            case .horizontal:
                let previewHeight = min(max(viewportHeight - 48, 100), 200)
                let cardWidth = previewHeight * 1.25
                let cardMetrics = ClipCardLayoutMetrics(
                    width: cardWidth,
                    previewHeight: previewHeight,
                    metadataHeight: 26
                )
                let singleRowItemHeight = max(cardMetrics.totalHeight, viewportHeight - 16)
                let horizontalPageCardCount = max(
                    1,
                    Int(
                        (viewportWidth + MainPanelCollectionMetrics.itemSpacing)
                            / (cardWidth + MainPanelCollectionMetrics.itemSpacing)
                    )
                )
                return CollectionLayoutMetrics(
                    itemSize: NSSize(width: cardWidth, height: singleRowItemHeight),
                    cardMetrics: cardMetrics,
                    gridColumnCount: 1,
                    horizontalPageCardCount: horizontalPageCardCount,
                    isHorizontal: true
                )
            case .verticalCompactList:
                let availableWidth = max(240, viewportWidth - 32)
                return CollectionLayoutMetrics(
                    itemSize: NSSize(width: availableWidth, height: 72),
                    cardMetrics: nil,
                    gridColumnCount: 1,
                    horizontalPageCardCount: 1,
                    isHorizontal: false
                )
            case .verticalLargeCards:
                let availableWidth = max(240, viewportWidth - 32)
                let cardMetrics = ClipCardLayoutMetrics(
                    width: availableWidth,
                    previewHeight: 180,
                    metadataHeight: 28
                )
                return CollectionLayoutMetrics(
                    itemSize: NSSize(width: availableWidth, height: cardMetrics.totalHeight),
                    cardMetrics: cardMetrics,
                    gridColumnCount: 1,
                    horizontalPageCardCount: 1,
                    isHorizontal: false
                )
            case .verticalAdaptiveGrid:
                let availableWidth = max(240, viewportWidth - 32)
                let gridColumnCount = availableWidth >= 412 ? 2 : 1
                let totalSpacing = CGFloat(gridColumnCount - 1) * MainPanelCollectionMetrics.itemSpacing
                let cardWidth = (availableWidth - totalSpacing) / CGFloat(gridColumnCount)
                let cardMetrics = ClipCardLayoutMetrics(
                    width: cardWidth,
                    previewHeight: 140,
                    metadataHeight: 28
                )
                return CollectionLayoutMetrics(
                    itemSize: NSSize(width: cardWidth, height: cardMetrics.totalHeight),
                    cardMetrics: cardMetrics,
                    gridColumnCount: gridColumnCount,
                    horizontalPageCardCount: 1,
                    isHorizontal: false
                )
            }
        }
    }

    final class CardCollectionViewItem: NSCollectionViewItem {
        private var hostingView: NSHostingView<AnyView>?

        override func loadView() {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }

        func configure<V: View>(_ rootView: V) {
            let erased = AnyView(rootView)
            if let hostingView {
                hostingView.rootView = erased
            } else {
                let hostingView = NSHostingView(rootView: erased)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = NSColor.clear.cgColor
                view.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
                self.hostingView = hostingView
            }
        }
    }

    final class AdaptiveCardScrollView: NSScrollView {
        var panelLayout: MainPanelCollectionLayout = .horizontal
        var onViewportSizeChange: ((NSSize) -> Void)?
        private var lastViewportSize = NSSize.zero

        override func layout() {
            super.layout()

            let viewportSize = contentSize
            guard viewportSize != lastViewportSize else { return }
            lastViewportSize = viewportSize
            onViewportSizeChange?(viewportSize)
        }

        override func scrollWheel(with event: NSEvent) {
            if panelLayout.isHorizontal && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                var newOrigin = contentView.bounds.origin
                newOrigin.x -= event.scrollingDeltaY
                if let documentView {
                    let maxX = max(0, documentView.bounds.width - contentView.bounds.width)
                    newOrigin.x = min(max(newOrigin.x, 0), maxX)
                }
                contentView.scroll(to: newOrigin)
                reflectScrolledClipView(contentView)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}

// MARK: - Keyboard Event Monitor

/// 使用 NSEvent.addLocalMonitorForEvents 拦截键盘事件，
/// 无论焦点在搜索栏还是卡片区都能响应方向键、Enter 等。
struct KeyboardEventMonitorView: NSViewRepresentable {
    @Binding var focusZone: FocusZone
    @Binding var selectedFilter: ClipboardFilterOption
    let focusRequest: Int
    let filterOptions: [ClipboardFilterOption]
    var onLeftArrow: ((Bool) -> Void)?
    var onRightArrow: ((Bool) -> Void)?
    var onUpArrow: ((Bool) -> Void)?
    var onDownArrow: ((Bool) -> Void)?
    var onEnter: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCmdF: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = CardFocusNSView()
        context.coordinator.startMonitor()
        context.coordinator.lastFocusRequest = focusRequest
        requestCardFocus(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        requestCardFocus(for: nsView)
    }

    private func requestCardFocus(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window,
                  window.isVisible,
                  window.isKeyWindow else { return }

            window.makeFirstResponder(view)
        }
    }

    final class CardFocusNSView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    class Coordinator {
        var parent: KeyboardEventMonitorView
        private var monitor: Any?
        var lastFocusRequest = 0

        init(_ parent: KeyboardEventMonitorView) {
            self.parent = parent
        }

        func startMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                return self.handleKey(event)
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Esc 特殊处理：只处理实际收到该事件的 PasteDeck 弹窗。
            if keyCode == 53 {
                guard let eventWindow = event.window,
                      eventWindow.isKeyWindow,
                      eventWindow.level == .popUpMenu else {
                    return event
                }
                parent.onEscape?()
                return nil
            }

            // 其余按键只在主面板窗口激活时拦截，避免影响设置窗口和预览窗口
            guard let eventWindow = event.window,
                  eventWindow.isKeyWindow,
                  eventWindow.level == .popUpMenu,
                  eventWindow.delegate is MainPanelController else {
                return event
            }

            // Cmd+F -> 聚焦搜索框（任何模式下都响应）
            if keyCode == 3 && modifiers == .command {
                parent.onCmdF?()
                return nil
            }

            // ===== 搜索模式：只拦截 Enter 和 Cmd+F，其余全部交给 TextField =====
            if parent.focusZone == .search {
                if keyCode == 36 { // Enter -> 焦点回到卡片区
                    parent.onEnter?(false)
                    return nil
                }
                // 其余按键（方向键、空格、删除等）全部交给搜索栏自然处理
                return event
            }

            // ===== 卡片区模式：处理所有特殊键 =====
            switch keyCode {
            case 123: // Left arrow
                let extending = modifiers.contains(.shift)
                parent.onLeftArrow?(extending)
                return nil
            case 124: // Right arrow
                let extending = modifiers.contains(.shift)
                parent.onRightArrow?(extending)
                return nil
            case 126: // Up arrow
                parent.onUpArrow?(modifiers.contains(.shift))
                return nil
            case 125: // Down arrow
                parent.onDownArrow?(modifiers.contains(.shift))
                return nil
            case 36: // Enter
                parent.onEnter?(modifiers.contains(.shift))
                return nil
            case 49: // Space
                parent.onSpace?()
                return nil
            case 51: // Delete
                // 如果当前焦点在文本输入控件中，放行让 TextField 处理
                if Self.isEditingText { return event }
                parent.onDelete?()
                return nil
            case 48: // Tab
                cycleFilterTab()
                return nil
            default:
                break
            }

            // 普通字符输入（卡片区模式）-> 切到搜索栏，让 TextField 接收此事件
            if let chars = event.characters, !chars.isEmpty,
               modifiers.isEmpty || modifiers == .shift {
                parent.focusZone = .search
                return event
            }

            return event
        }

        /// 检查当前 keyWindow 的 firstResponder 是否是文本输入控件
        static var isEditingText: Bool {
            guard let keyWindow = NSApp.keyWindow else { return false }
            guard let firstResponder = keyWindow.firstResponder else { return false }
            // NSTextView 是 TextField 的底层编辑器，NSTextField 本身编辑时也指向其 fieldEditor
            return firstResponder is NSTextView || firstResponder is NSTextField
        }

        /// Tab 切换筛选标签
        private func cycleFilterTab() {
            let options = parent.filterOptions
            let current = parent.selectedFilter
            guard !options.isEmpty else { return }
            if let idx = options.firstIndex(of: current) {
                let nextIdx = (idx + 1) % options.count
                parent.selectedFilter = options[nextIdx]
            } else {
                parent.selectedFilter = options[0]
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("暂无剪切板历史")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)

            Text("复制内容后将自动记录到这里")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

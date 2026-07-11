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

    private var cardSize: CardSize {
        appSettings
            .flatMap { CardSize(rawValue: $0.cardSize) } ?? .medium
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
        } else if !items.isEmpty {
            selectedIndex = 0
            selectedItemID = items.first?.id
        } else {
            selectedIndex = 0
            selectedItemID = nil
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
            // 顶部搜索和筛选
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    SearchBarView(text: $searchText, isFocused: $isSearchFocused)
                        .onChange(of: isSearchFocused) { _, newValue in
                            if newValue {
                                focusZone = .search
                            }
                        }
                        .onChange(of: focusZone) { _, newZone in
                            if newZone == .search {
                                isSearchFocused = true
                            } else {
                                isSearchFocused = false
                            }
                        }
                        .onSubmit {
                            // 搜索框按 Enter → 焦点切到卡片区，选中第一个
                            focusCards()
                            if !historyStore.filteredItems.isEmpty {
                                selectedIndex = 0
                                selectedItemID = historyStore.filteredItems.first?.id
                                clearMultiSelection()
                            }
                        }

                    SourceAppFilterMenu(
                        selectedSourceApp: selectedSourceApp,
                        sourceApps: historyStore.sourceApps,
                        onSelect: setSourceAppFilter
                    )

                    MainPanelSettingsButton {
                        openSettingsHandler?()
                    }
                }

                FavoriteFilterTabs(
                    options: filterOptions,
                    selectedFilter: $selectedFilter,
                    collections: historyStore.collections,
                    onCreateCollection: { name in
                        historyStore.createCollection(name: name)
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // 卡片列表
            if historyStore.isLoading && historyStore.filteredItems.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if historyStore.filteredItems.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VirtualizedCardList(
                    items: historyStore.filteredItems,
                    collections: historyStore.collections,
                    selectedItemId: selectedItemID,
                    selectedItems: selectedItems,
                    showSelection: focusZone == .cards,
                    showPinOption: selectedFilter != .all,
                    cardSize: cardSize,
                    onItemTapped: { index, itemID in
                        handleItemTap(index: index, itemID: itemID)
                    },
                    onItemDoubleTapped: { itemID in
                        pasteItem(id: itemID)
                    },
                    onCopy: { itemID in
                        historyStore.copyToPasteboard(id: itemID)
                    },
                    onPastePlain: { itemID in
                        pasteItem(id: itemID, plainText: true)
                    },
                    onTogglePinned: { itemID in
                        historyStore.togglePinned(id: itemID)
                    },
                    onToggleFavorite: { itemID in
                        historyStore.toggleDefaultFavorite(id: itemID)
                    },
                    onToggleCollection: { itemID, collectionID in
                        historyStore.toggleCollection(itemID: itemID, collectionID: collectionID)
                    },
                    onSaveTitle: { itemID, title in
                        historyStore.saveTitle(id: itemID, title: title)
                    },
                    onDelete: { itemID in
                        deleteItem(id: itemID)
                    }
                )
                .padding(.top, 12)
            }
        }
        .frame(width: 800, height: 400)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            historyStore.loadIfNeeded()
            reconcileSelection()
            selectDefaultCard()
            // 打开面板时焦点默认在卡片区
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
        // 剪贴板监听或设置页清理会通过通知更新轻量缓存
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
        // 监听清空搜索通知
        .onReceive(NotificationCenter.default.publisher(for: .clearSearchText)) { _ in
            searchText = ""
            clearMultiSelection()
            selectedFilter = .all
            setSourceAppFilter(nil)
            historyStore.setSearchText("")
            historyStore.setFilter(.all)
            selectDefaultCard()
        }
        // 面板打开时重置焦点到卡片区，选中第二项
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            historyStore.loadIfNeeded()
            setSourceAppFilter(nil)
            selectDefaultCard()
            focusCards()
            clearMultiSelection()
        }
        // AppKit 在面板真正成为 key window 后再次确认卡片区 first responder。
        .onReceive(NotificationCenter.default.publisher(for: .panelDidRequestCardFocus)) { _ in
            focusCards()
        }
        // 使用 NSEvent 监听键盘
        .background(
            KeyboardEventMonitorView(
                focusZone: $focusZone,
                selectedFilter: $selectedFilter,
                focusRequest: cardFocusRequest,
                filterOptions: filterOptions,
                onLeftArrow: { extend in
                    moveSelection(by: -1, extending: extend)
                },
                onRightArrow: { extend in
                    moveSelection(by: 1, extending: extend)
                },
                onUpArrow: {
                    scrollPage(direction: .up)
                },
                onDownArrow: {
                    scrollPage(direction: .down)
                },
                onEnter: { shiftHeld in
                    // Enter 在搜索模式 → 焦点切到卡片区
                    if focusZone == .search {
                        focusCards()
                        if !historyStore.filteredItems.isEmpty {
                            selectedIndex = 0
                            selectedItemID = historyStore.filteredItems.first?.id
                            clearMultiSelection()
                        }
                    } else {
                        pasteSelectedItems(plainText: shiftHeld)
                    }
                },
                onEscape: {
                    closePreviewOrPanel()
                },
                onSpace: {
                    if let selectedItemID {
                        previewItem(id: selectedItemID)
                    }
                },
                onDelete: {
                    deleteSelectedItem()
                },
                onCmdF: {
                    focusZone = .search
                }
            )
        )
    }

    // MARK: - Selection Logic

    /// 单纯移动选区（方向键）
    private func moveSelection(by offset: Int, extending: Bool) {
        let items = historyStore.filteredItems
        guard !items.isEmpty else { return }
        let newIndex = max(0, min(items.count - 1, selectedIndex + offset))

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
        // 每页大约显示的卡片数（根据卡片宽度和间距估算）
        let cardsPerPage = 5
        let offset = direction == .up ? -cardsPerPage : cardsPerPage
        let newIndex = max(0, min(items.count - 1, selectedIndex + offset))
        if newIndex != selectedIndex {
            selectedIndex = newIndex
            selectedItemID = items[newIndex].id
            clearMultiSelection()
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
        } else {
            selectedIndex = 0
            selectedItemID = nil
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

/// 水平虚拟化卡片列表，只为可见区域附近创建卡片视图。
struct VirtualizedCardList: NSViewRepresentable {
    let items: [ClipboardItemSnapshot]
    let collections: [ClipboardCollectionSnapshot]
    let selectedItemId: UUID?
    let selectedItems: Set<UUID>
    var showSelection: Bool = true
    var showPinOption: Bool = true
    let cardSize: CardSize
    let onItemTapped: (Int, UUID) -> Void
    let onItemDoubleTapped: (UUID) -> Void
    let onCopy: (UUID) -> Void
    var onPastePlain: ((UUID) -> Void)? = nil
    let onTogglePinned: (UUID) -> Void
    let onToggleFavorite: (UUID) -> Void
    let onToggleCollection: (UUID, UUID) -> Void
    let onSaveTitle: (UUID, String?) -> Void
    let onDelete: (UUID) -> Void

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("PasteDeckCardCollectionViewItem")

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
        layout.itemSize = itemSize

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(
            CardCollectionViewItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )

        let scrollView = HorizontalCardScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.collectionView = collectionView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let oldSelectedID = context.coordinator.parent.selectedItemId
        context.coordinator.parent = self

        if let layout = context.coordinator.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            layout.itemSize = itemSize
        }

        context.coordinator.collectionView.reloadData()

        if oldSelectedID != selectedItemId {
            context.coordinator.scrollSelectedIntoViewIfNeeded()
        }
    }

    private var itemSize: NSSize {
        NSSize(width: cardSize.width, height: cardSize.height + 26)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: VirtualizedCardList
        weak var collectionView: NSCollectionView!

        init(_ parent: VirtualizedCardList) {
            self.parent = parent
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

            let snapshot = parent.items[indexPath.item]
            let index = indexPath.item
            let rootView = ClipCardView(
                item: snapshot,
                isSelected: parent.showSelection && (parent.selectedItems.contains(snapshot.id) || parent.selectedItemId == snapshot.id),
                isMultiSelected: parent.showSelection && parent.selectedItems.contains(snapshot.id) && parent.selectedItems.count > 1,
                showPinOption: parent.showPinOption,
                cardSize: parent.cardSize,
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
            .onTapGesture {
                self.parent.onItemTapped(index, snapshot.id)
            }
            .onTapGesture(count: 2) {
                self.parent.onItemDoubleTapped(snapshot.id)
            }
            .frame(width: parent.cardSize.width, height: parent.cardSize.height + 26)

            cardItem.configure(rootView)
            return cardItem
        }

        func scrollSelectedIntoViewIfNeeded() {
            guard let selectedItemId = parent.selectedItemId,
                  let index = parent.items.firstIndex(where: { $0.id == selectedItemId }) else {
                return
            }

            let indexPath = IndexPath(item: index, section: 0)
            if collectionView.indexPathsForVisibleItems().contains(indexPath) {
                return
            }

            collectionView.scrollToItems(
                at: Set([indexPath]),
                scrollPosition: .centeredHorizontally
            )
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

    final class HorizontalCardScrollView: NSScrollView {
        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
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
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
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

            // Cmd+F → 聚焦搜索框（任何模式下都响应）
            if keyCode == 3 && modifiers == .command {
                parent.onCmdF?()
                return nil
            }

            // ===== 搜索模式：只拦截 Enter 和 Cmd+F，其余全部交给 TextField =====
            if parent.focusZone == .search {
                if keyCode == 36 { // Enter → 焦点回到卡片区
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
                parent.onUpArrow?()
                return nil
            case 125: // Down arrow
                parent.onDownArrow?()
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

            // 普通字符输入（卡片区模式）→ 切到搜索栏，让 TextField 接收此事件
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

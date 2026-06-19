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
    static let toggleMainPanel = Notification.Name("toggleMainPanel")
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Query(sort: \FavoriteCollection.sortOrder) private var allCollections: [FavoriteCollection]

    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedItem: ClipboardItem?
    @State private var selectedIndex = 0

    /// 多选集合
    @State private var selectedItems: Set<UUID> = []
    /// Shift 选区锚点索引
    @State private var anchorIndex: Int = 0

    /// 当前焦点所在区域
    @State private var focusZone: FocusZone = .cards
    @State private var cardFocusRequest = 0

    /// 缓存的过滤结果，仅在 items/searchText/selectedFilter 变化时重算，
    /// 避免每次 body 求值都重复 O(n) 过滤整个历史
    @State private var filteredItems: [ClipboardItem] = []

    /// 搜索栏焦点绑定
    @FocusState private var isSearchFocused: Bool

    /// 预览窗口控制器（需要持有以防止被释放）
    @State private var previewController: PreviewWindowController?

    var closeHandler: (() -> Void)?

    private let cardSize: CardSize = .medium

    // MARK: - Filtered & Sorted Items

    /// 当前筛选标签索引（用于 Tab 循环）
    private var filterOptions: [FilterOption] {
        var options: [FilterOption] = [.all]
        for collection in allCollections {
            options.append(.collection(collection))
        }
        return options
    }

    private func computeFilteredItems() -> [ClipboardItem] {
        var result = items

        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { item in
                if item.displayTitle.localizedCaseInsensitiveContains(searchText) {
                    return true
                }

                switch item.contentType {
                case .text, .link:
                    return (item.textContent ?? "").localizedCaseInsensitiveContains(searchText)
                case .file:
                    return (item.fileName ?? "").localizedCaseInsensitiveContains(searchText)
                case .color:
                    return (item.colorHex ?? "").localizedCaseInsensitiveContains(searchText)
                case .image:
                    return false
                }
            }
        }

        // 收藏夹过滤
        switch selectedFilter {
        case .all:
            break
        case .collection(let collection):
            result = result.filter { item in
                item.collections?.contains(where: { $0.id == collection.id }) ?? false
            }
            // 收藏夹视图下，置顶项排最前
            result.sort { $0.isPinned && !$1.isPinned }
        }

        return result
    }

    /// 重算过滤缓存，并修正可能越界的选中索引
    private func refreshFilteredItems() {
        filteredItems = computeFilteredItems()
        if selectedIndex >= filteredItems.count {
            selectedIndex = max(0, filteredItems.count - 1)
        }
        selectedItem = filteredItems.isEmpty ? nil : filteredItems[selectedIndex]
    }

    private func selectDefaultCard() {
        if filteredItems.count > 1 {
            selectedIndex = 1
            selectedItem = filteredItems[1]
        } else if !filteredItems.isEmpty {
            selectedIndex = 0
            selectedItem = filteredItems.first
        } else {
            selectedIndex = 0
            selectedItem = nil
        }
    }

    private func focusCards() {
        isSearchFocused = false
        focusZone = .cards
        cardFocusRequest += 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部搜索和筛选
            VStack(spacing: 12) {
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
                    if !filteredItems.isEmpty {
                        selectedIndex = 0
                        selectedItem = filteredItems.first
                        clearMultiSelection()
                    }
                }

                FavoriteFilterTabs(
                    options: filterOptions,
                    selectedFilter: $selectedFilter,
                    modelContext: modelContext
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // 卡片列表
            if filteredItems.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    HorizontalScrollHostingView(
                        items: filteredItems,
                        selectedItemId: selectedItem?.id,
                        selectedItems: selectedItems,
                        showSelection: focusZone == .cards,
                        showPinOption: selectedFilter != .all,
                        cardSize: cardSize,
                        onItemTapped: { index, item in
                            handleItemTap(index: index, item: item)
                        },
                        onItemDoubleTapped: { item in
                            pasteItem(item)
                        },
                        onItemContextRequested: { item in
                            // context menu handled by SwiftUI
                        }
                    )
                    .padding(.top, 12)
                    // 当选中项变化时滚动：键盘导航是离散操作，即时跟随选中项。
                    // 套动画会在连按时互相打断造成卡顿，且高亮先于滚动到达，
                    // 视觉上表现为「先选中、卡片才慢慢出现」。
                    .onChange(of: selectedIndex) { _, newIndex in
                        guard newIndex >= 0, newIndex < filteredItems.count else { return }
                        proxy.scrollTo(filteredItems[newIndex].id, anchor: nil)
                    }
                }
            }
        }
        .frame(width: 800, height: 400)
        .onAppear {
            refreshFilteredItems()
            selectDefaultCard()
            // 打开面板时焦点默认在卡片区
            focusCards()
        }
        // 仅在真正的输入变化时重算过滤缓存
        .onChange(of: items) { _, _ in
            refreshFilteredItems()
        }
        .onChange(of: searchText) { _, _ in
            refreshFilteredItems()
        }
        .onChange(of: selectedFilter) { _, _ in
            refreshFilteredItems()
        }
        // 就地修改置顶/收藏夹归属后刷新缓存（@Query 数组成员未变，onChange(items) 不触发）
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDataChanged)) { _ in
            refreshFilteredItems()
        }
        // 监听清空搜索通知
        .onReceive(NotificationCenter.default.publisher(for: .clearSearchText)) { _ in
            searchText = ""
            clearMultiSelection()
            selectedFilter = .all
            if filteredItems.count > 1 {
                selectedIndex = 1
                selectedItem = filteredItems[1]
            } else if !filteredItems.isEmpty {
                selectedIndex = 0
                selectedItem = filteredItems.first
            }
        }
        // 面板打开时重置焦点到卡片区，选中第二项
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            refreshFilteredItems()
            selectDefaultCard()
            focusCards()
            clearMultiSelection()
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
                onEnter: {
                    // Enter 在搜索模式 → 焦点切到卡片区
                    if focusZone == .search {
                        focusCards()
                        if !filteredItems.isEmpty {
                            selectedIndex = 0
                            selectedItem = filteredItems.first
                            clearMultiSelection()
                        }
                    } else {
                        pasteSelectedItems()
                    }
                },
                onEscape: {
                    closePreviewOrPanel()
                },
                onSpace: {
                    if let item = selectedItem {
                        previewItem(item)
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
        guard !filteredItems.isEmpty else { return }
        let newIndex = max(0, min(filteredItems.count - 1, selectedIndex + offset))

        if extending {
            // Shift+方向键：扩展/收缩选区
            _ = selectedIndex
            selectedIndex = newIndex
            selectedItem = filteredItems[newIndex]
            rebuildExtendedSelection(from: anchorIndex, to: newIndex)
        } else {
            // 普通方向键：单选移动，清除多选
            selectedIndex = newIndex
            selectedItem = filteredItems[newIndex]
            clearMultiSelection()
            anchorIndex = newIndex
        }
    }

    /// 点击卡片处理
    private func handleItemTap(index: Int, item: ClipboardItem) {
        let isCmdHeld = NSEvent.modifierFlags.contains(.command)
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isCmdHeld {
            // Cmd+Click: toggle 选中
            if selectedItems.contains(item.id) {
                selectedItems.remove(item.id)
                // 如果移除的是当前选中项，更新当前选中
                if selectedItem?.id == item.id {
                    selectedItem = selectedItems.isEmpty ? nil : filteredItems.first(where: { selectedItems.contains($0.id) })
                    selectedIndex = filteredItems.firstIndex(where: { $0.id == (selectedItem?.id ?? UUID()) }) ?? index
                }
            } else {
                selectedItems.insert(item.id)
                selectedIndex = index
                selectedItem = item
                anchorIndex = index
            }
        } else if isShiftHeld {
            // Shift+Click: 区间选中
            selectedIndex = index
            selectedItem = item
            rebuildExtendedSelection(from: anchorIndex, to: index)
        } else {
            // 普通点击：清除多选，单选
            selectedIndex = index
            selectedItem = item
            clearMultiSelection()
            anchorIndex = index
        }
        focusCards()
    }

    /// 重建 Shift 选区
    private func rebuildExtendedSelection(from: Int, to: Int) {
        let lo = min(from, to)
        let hi = max(from, to)
        selectedItems = Set(filteredItems[lo...hi].map { $0.id })
    }

    /// 清除多选
    private func clearMultiSelection() {
        selectedItems.removeAll()
    }

    // MARK: - Actions

    /// 批量粘贴所有选中项（若无多选则粘贴当前项）
    private func pasteSelectedItems() {
        let itemsToPaste: [ClipboardItem]
        if selectedItems.count > 1 {
            // 按显示顺序（newest first）排列
            itemsToPaste = filteredItems.filter { selectedItems.contains($0.id) }
        } else if let item = selectedItem {
            itemsToPaste = [item]
        } else {
            return
        }

        promotePastedItems(itemsToPaste)
        closeHandler?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteService.shared.batchPaste(itemsToPaste)
        }
    }

    private func pasteItem(_ item: ClipboardItem) {
        promotePastedItems([item])
        PasteService.shared.preparePaste(item)
        closeHandler?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteService.shared.performPaste()
        }
    }

    private func promotePastedItems(_ items: [ClipboardItem]) {
        let baseDate = Date()
        for (index, item) in items.enumerated() {
            item.createdAt = baseDate.addingTimeInterval(Double(-index) * 0.001)
        }
        try? modelContext.save()
        refreshFilteredItems()
    }

    /// 上下键翻页：滚动卡片列表一屏
    private func scrollPage(direction: ScrollDirection) {
        guard !filteredItems.isEmpty else { return }
        // 每页大约显示的卡片数（根据卡片宽度和间距估算）
        let cardsPerPage = 5
        let offset = direction == .up ? -cardsPerPage : cardsPerPage
        let newIndex = max(0, min(filteredItems.count - 1, selectedIndex + offset))
        if newIndex != selectedIndex {
            selectedIndex = newIndex
            selectedItem = filteredItems[newIndex]
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

    private func previewItem(_ item: ClipboardItem) {
        previewController = PreviewWindowController()
        previewController?.show(item: item, onClose: {})
    }

    private func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        let nextIndex = selectedIndex
        modelContext.delete(item)
        try? modelContext.save()

        // 直接基于删除后的结果重算缓存，避免读到仍含已删项的旧缓存
        filteredItems = computeFilteredItems()
        if !filteredItems.isEmpty {
            selectedIndex = min(nextIndex, filteredItems.count - 1)
            selectedItem = filteredItems[selectedIndex]
        } else {
            selectedIndex = 0
            selectedItem = nil
        }
        clearMultiSelection()
    }
}

// MARK: - Filter Option

/// 筛选选项，替代原来的 ClipboardFilter 枚举
enum FilterOption: Equatable, Hashable {
    case all
    case collection(FavoriteCollection)

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .collection(let c): return c.name
        }
    }

    static func == (lhs: FilterOption, rhs: FilterOption) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all): return true
        case (.collection(let a), .collection(let b)): return a.id == b.id
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:
            hasher.combine("all")
        case .collection(let c):
            hasher.combine(c.id)
        }
    }
}

// MARK: - Favorite Filter Tabs

struct FavoriteFilterTabs: View {
    let options: [FilterOption]
    @Binding var selectedFilter: FilterOption
    let modelContext: ModelContext

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
                            Text(option.displayName)
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
        let maxOrder = options.compactMap { option -> Int? in
            if case .collection(let c) = option { return c.sortOrder }
            return nil
        }.max() ?? 0

        let newCollection = FavoriteCollection(
            name: newCollectionName.trimmingCharacters(in: .whitespaces),
            sortOrder: maxOrder + 1
        )
        modelContext.insert(newCollection)
        try? modelContext.save()
    }
}

// MARK: - Horizontal Scroll Hosting View (NSViewRepresentable for scroll wheel)

/// 包装卡片列表的 NSView，用于拦截鼠标滚轮事件实现横向滚动
struct HorizontalScrollHostingView: View {
    let items: [ClipboardItem]
    let selectedItemId: UUID?
    let selectedItems: Set<UUID>
    var showSelection: Bool = true
    var showPinOption: Bool = true
    let cardSize: CardSize
    let onItemTapped: (Int, ClipboardItem) -> Void
    let onItemDoubleTapped: (ClipboardItem) -> Void
    let onItemContextRequested: (ClipboardItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ClipCardView(
                        item: item,
                        isSelected: showSelection && (selectedItems.contains(item.id) || selectedItemId == item.id),
                        isMultiSelected: showSelection && selectedItems.contains(item.id) && selectedItems.count > 1,
                        showPinOption: showPinOption,
                        cardSize: cardSize
                    )
                    .equatable()
                    .id(item.id)
                    .onTapGesture {
                        onItemTapped(index, item)
                    }
                    .onTapGesture(count: 2) {
                        onItemDoubleTapped(item)
                    }
                    .contextMenu {
                        CardContextMenu(item: item, showPinOption: showPinOption)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(ScrollWheelInterceptor())
    }
}

/// 拦截鼠标滚轮事件，将垂直滚动转发为水平滚动
struct ScrollWheelInterceptor: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {}
}

class ScrollWheelNSView: NSView {
    override func scrollWheel(with event: NSEvent) {
        // 将垂直滚轮事件转发为水平滚动
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            // 查找最近的 NSScrollView 祖先并直接水平滚动
            var view: NSView? = self.superview
            while view != nil {
                if let scrollView = view as? NSScrollView {
                    let clipView = scrollView.contentView
                    var newOrigin = clipView.bounds.origin
                    newOrigin.x -= event.scrollingDeltaY
                    clipView.scroll(to: newOrigin)
                    scrollView.reflectScrolledClipView(clipView)
                    return
                }
                view = view?.superview
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Keyboard Event Monitor

/// 使用 NSEvent.addLocalMonitorForEvents 拦截键盘事件，
/// 无论焦点在搜索栏还是卡片区都能响应方向键、Enter 等。
struct KeyboardEventMonitorView: NSViewRepresentable {
    @Binding var focusZone: FocusZone
    @Binding var selectedFilter: FilterOption
    let focusRequest: Int
    let filterOptions: [FilterOption]
    var onLeftArrow: ((Bool) -> Void)?
    var onRightArrow: ((Bool) -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onEnter: (() -> Void)?
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
            view.window?.makeFirstResponder(view)
        }
    }

    final class CardFocusNSView: NSView {
        override var acceptsFirstResponder: Bool { true }
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

            // Esc 特殊处理：如果预览窗口是 keyWindow，关闭预览窗口
            if keyCode == 53 {
                guard let keyWindow = NSApp.keyWindow,
                      keyWindow.level == .popUpMenu else {
                    return event
                }
                parent.onEscape?()
                return nil
            }

            // 其余按键只在主面板窗口激活时拦截，避免影响设置窗口和预览窗口
            guard let keyWindow = NSApp.keyWindow,
                  keyWindow.level == .popUpMenu,
                  keyWindow.delegate == nil || keyWindow.delegate is MainPanelController else {
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
                    parent.onEnter?()
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
                parent.onEnter?()
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

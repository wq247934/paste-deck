//
//  WorkbenchView.swift
//  PasteDeck
//
//  Main 3-column macOS productivity workbench container for PasteDeck 2.0.
//

import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    static let workbenchDidRequestListFocus = Notification.Name("workbenchDidRequestListFocus")
}

enum WorkbenchFocusZone: Equatable {
    case list
    case search
}

struct WorkbenchView: View {
    @StateObject private var historyStore = ClipboardHistoryStore(
        modelContext: ModelContext(AppModelContainer.container)
    )
    @StateObject private var searchCoordinator = UnifiedSearchCoordinator()

    @State private var selectedDestination: WorkbenchDestination = .history
    @State private var viewMode: WorkbenchViewMode = .list
    @State private var sortOrder: WorkbenchSortOrder = .newestFirst
    @State private var selectedTypeFilter: ClipboardContentType?
    @State private var isInspectorVisible = true

    /// 工作台双焦点模式：默认处于列表浏览模式 (.list)，按 Space 可直接大预览；
    /// 键入任意字符时自动切入搜索模式 (.search)。
    @State private var focusZone: WorkbenchFocusZone = .list
    @State private var focusRequestToken = 0

    // Windows
    @State private var toolWindowController: ToolWindowController?
    @State private var previewController: PreviewWindowController?

    var onClose: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left Column: Navigation Sidebar
            WorkbenchSidebarView(
                selectedDestination: $selectedDestination,
                historyCount: historyStore.allItems.count,
                favoritesCount: historyStore.allItems.filter(\.isFavorite).count,
                categoryCounts: countByCategory(historyStore.allItems),
                onOpenSettings: onOpenSettings
            )

            Divider()
                .overlay(Color.primary.opacity(0.08))

            // Middle Column: Main Content Area
            mainContentArea
                .frame(minWidth: 420, maxWidth: .infinity)

            // Right Column: Context Inspector
            if isInspectorVisible && selectedDestination != .toolCenter && selectedDestination != .recentTools {
                Divider()
                    .overlay(Color.primary.opacity(0.08))

                WorkbenchInspectorView(
                    item: currentSelectedItem,
                    onCopy: { copyItem($0) },
                    onPastePlainText: { pastePlainText($0) },
                    onPreview: { openPreview($0) },
                    onToggleFavorite: { toggleFavorite($0) },
                    onOpenTool: { tool, prefill in
                        openToolWindow(tool: tool, prefill: prefill)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(workbenchKeyboardMonitor)
        .onAppear {
            historyStore.loadIfNeeded()
            searchCoordinator.setHistoryStore(historyStore)
            focusList()
        }
        .onChange(of: selectedDestination) { _, newDestination in
            applyDestinationFilter(newDestination)
        }
        .onChange(of: selectedTypeFilter) { _, newType in
            applyTypeFilter(newType)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workbenchDidRequestListFocus)) { _ in
            focusList()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private var mainContentArea: some View {
        switch selectedDestination {
        case .toolCenter, .recentTools:
            ToolCenterView { tool in
                openToolWindow(tool: tool, prefill: nil)
            }
        default:
            WorkbenchContentListView(
                searchCoordinator: searchCoordinator,
                items: sortedItems(historyStore.filteredItems),
                selectedItem: currentSelectedItem,
                selectedEntry: searchCoordinator.selectedEntry,
                viewMode: $viewMode,
                sortOrder: $sortOrder,
                selectedTypeFilter: $selectedTypeFilter,
                focusZone: $focusZone,
                onSelectEntry: { entry in
                    searchCoordinator.select(entry: entry)
                },
                onExecutePrimary: { entry in
                    executePrimaryAction(for: entry)
                },
                onCopyItem: { id in
                    historyStore.copyToPasteboard(id: id)
                },
                onPastePlainTextItem: { id in
                    historyStore.preparePaste(id: id, plainText: true)
                },
                onToggleFavorite: { id in
                    toggleFavorite(id)
                },
                onTogglePin: { id in
                    historyStore.togglePinned(id: id)
                },
                onDeleteItem: { id in
                    historyStore.deleteItem(id: id)
                },
                onPreviewItem: { item in
                    openPreview(item)
                },
                onOpenTool: { tool, prefill in
                    openToolWindow(tool: tool, prefill: prefill)
                }
            )
        }
    }

    // MARK: - Focus Management

    private func focusList() {
        focusZone = .list
        focusRequestToken += 1
    }

    private func focusSearch() {
        focusZone = .search
        focusRequestToken += 1
    }

    // MARK: - Selected Item Resolution

    private var currentSelectedItem: ClipboardItemSnapshot? {
        if let selected = searchCoordinator.selectedEntry?.clipboardSnapshot {
            return selected
        }
        return historyStore.filteredItems.first
    }

    // MARK: - Actions

    private func executePrimaryAction(for entry: UnifiedSearchEntry) {
        switch entry {
        case .tool(let toolMatch):
            openToolWindow(tool: toolMatch.tool, prefill: toolMatch.prefilledText)
        case .clipboard(let snapshot):
            copyItem(snapshot)
        }
    }

    private func copyItem(_ item: ClipboardItemSnapshot) {
        historyStore.copyToPasteboard(id: item.id)
    }

    private func pastePlainText(_ item: ClipboardItemSnapshot) {
        historyStore.preparePaste(id: item.id, plainText: true)
    }

    private func toggleFavorite(_ id: UUID) {
        historyStore.toggleDefaultFavorite(id: id)
    }

    private func openPreview(_ item: ClipboardItemSnapshot) {
        guard let fullItem = historyStore.fetchItem(id: item.id) else { return }
        if previewController == nil {
            previewController = PreviewWindowController()
        }
        previewController?.show(item: fullItem, onClose: {
            NotificationCenter.default.post(name: .workbenchDidRequestListFocus, object: nil)
        })
    }

    private func openToolWindow(tool: BuiltinTool, prefill: String?) {
        if toolWindowController == nil {
            toolWindowController = ToolWindowController()
        }
        let context: ToolContext
        if let prefill {
            context = .forSearch(prefillSuggestion: prefill)
        } else {
            context = .standalone
        }
        toolWindowController?.show(tool: tool, context: context) {
            self.toolWindowController = nil
        }
    }

    // MARK: - Filtering & Sorting

    private func applyDestinationFilter(_ destination: WorkbenchDestination) {
        switch destination {
        case .history:
            historyStore.setFilter(.all)
        case .favorites:
            if let defaultColl = historyStore.collections.first(where: \.isDefault) {
                historyStore.setFilter(.collection(defaultColl.id))
            }
        case .smartCategory(let type):
            // Filtering in UI list
            historyStore.setFilter(.all)
            selectedTypeFilter = type
        case .toolCenter, .recentTools:
            break
        }
    }

    private func applyTypeFilter(_ type: ClipboardContentType?) {
        // Will be reflected in sortedItems()
    }

    private func sortedItems(_ raw: [ClipboardItemSnapshot]) -> [ClipboardItemSnapshot] {
        var result = raw

        if let type = selectedTypeFilter {
            if type == .markdown {
                result = result.filter { $0.contentType == .markdown || $0.contentType == .json }
            } else {
                result = result.filter { $0.contentType == type }
            }
        }

        switch sortOrder {
        case .newestFirst:
            return result.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return result.sorted { $0.createdAt < $1.createdAt }
        case .size:
            return result.sorted { $0.displaySize > $1.displaySize }
        }
    }

    private func countByCategory(_ all: [ClipboardItemSnapshot]) -> [ClipboardContentType: Int] {
        var counts: [ClipboardContentType: Int] = [:]
        for item in all {
            counts[item.contentType, default: 0] += 1
        }
        return counts
    }

    // MARK: - Keyboard Monitor

    private var workbenchKeyboardMonitor: some View {
        WorkbenchKeyboardMonitor(
            focusZone: focusZone,
            focusRequest: focusRequestToken,
            onUpArrow: {
                searchCoordinator.moveUp()
                if focusZone == .search {
                    focusList()
                }
            },
            onDownArrow: {
                searchCoordinator.moveDown()
                if focusZone == .search {
                    focusList()
                }
            },
            onEnter: {
                if focusZone == .search {
                    // 输入文字后按回车：焦点立刻交还给剪切板列表，光标退出输入框
                    focusList()
                } else if let entry = searchCoordinator.selectedEntry {
                    executePrimaryAction(for: entry)
                }
            },
            onSpace: {
                if let item = currentSelectedItem {
                    openPreview(item)
                }
            },
            onEscape: {
                if !searchCoordinator.searchText.isEmpty {
                    searchCoordinator.searchText = ""
                    focusList()
                } else if focusZone == .search {
                    focusList()
                } else {
                    onClose()
                }
            },
            onCmdW: { onClose() },
            onCmdF: { focusSearch() },
            onStartSearching: { chars in
                searchCoordinator.searchText = chars
                focusSearch()
            }
        )
    }
}

/// 工作台窗口的按键拦截与双焦点原生视图。
///
/// - 列表浏览模式 (.list，默认)：聚焦列表区，Space 触发大预览，
///   Enter 执行选中项，↑↓ 移动选择，键入字符自动切入搜索。
/// - 搜索模式 (.search)：字符与空格正常输入用于搜索，Esc 先清词切回列表。
/// - ⌘W 与 Esc：严格只关闭当前工作台窗口自身（或前置子窗口），绝不冒泡。
private struct WorkbenchKeyboardMonitor: NSViewRepresentable {
    var focusZone: WorkbenchFocusZone
    var focusRequest: Int
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onEnter: () -> Void
    var onSpace: () -> Void
    var onEscape: () -> Void
    var onCmdW: () -> Void
    var onCmdF: () -> Void
    var onStartSearching: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WorkbenchListFocusNSView {
        let view = WorkbenchListFocusNSView()
        context.coordinator.listFocusView = view
        context.coordinator.startMonitor()
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.applyFocusZone()
        return view
    }

    func updateNSView(_ nsView: WorkbenchListFocusNSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.listFocusView = nsView
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.applyFocusZone()
    }

    final class WorkbenchListFocusNSView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    final class Coordinator {
        var parent: WorkbenchKeyboardMonitor
        weak var listFocusView: WorkbenchListFocusNSView?
        private var monitor: Any?
        private var focusObserver: NSObjectProtocol?
        var lastFocusRequest = 0

        init(_ parent: WorkbenchKeyboardMonitor) {
            self.parent = parent
        }

        func startMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKey(event)
            }

            focusObserver = NotificationCenter.default.addObserver(
                forName: .workbenchDidRequestListFocus,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyFocusZone()
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func applyFocusZone() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let window = NSApp.keyWindow,
                      window.identifier == WorkbenchWindowController.windowIdentifier,
                      window.isVisible else { return }

                switch self.parent.focusZone {
                case .list:
                    if let listView = self.listFocusView, window.firstResponder !== listView {
                        window.makeFirstResponder(listView)
                    }
                case .search:
                    let textField = WorkbenchSearchFieldRegistry.shared.field
                        ?? Self.findTextField(in: window.contentView)
                    guard let textField else { return }
                    if window.firstResponder === textField { return }
                    if let editor = window.fieldEditor(false, for: textField),
                       window.firstResponder === editor {
                        return
                    }
                    window.makeFirstResponder(textField)
                }
            }
        }

        private static func findTextField(in view: NSView?) -> NSTextField? {
            guard let view else { return nil }
            if let textField = view as? NSTextField,
               textField.identifier == WorkbenchSearchFieldIdentifier {
                return textField
            }
            for subview in view.subviews {
                if let found = findTextField(in: subview) {
                    return found
                }
            }
            return nil
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // 严格只拦截发给工作台窗口的按键
            guard let eventWindow = event.window,
                  eventWindow.isKeyWindow,
                  eventWindow.identifier == WorkbenchWindowController.windowIdentifier else {
                return event
            }

            // 1. ⌘W -> 严格只关闭当前最前层单个窗口，绝不连带穿透
            if keyCode == 13 && modifiers == .command {
                CloseWindowDispatcher.closeFrontmostWindowOnly()
                return nil
            }

            // 2. Esc -> 分级退出：清词 / 切回列表 / 关闭工作台
            if keyCode == 53 {
                // 子窗口关闭冷却期保护：子窗口刚关掉时，绝不穿透连带关闭工作台
                if WindowCloseCooldown.isInCooldown {
                    return nil
                }
                parent.onEscape()
                return nil
            }

            // 3. ⌘F -> 聚焦搜索框
            if keyCode == 3 && modifiers == .command {
                parent.onCmdF()
                return nil
            }

            // 4. 方向键 Up / Down -> 列表中切换选中项
            if keyCode == 126 { // Up
                parent.onUpArrow()
                return nil
            }
            if keyCode == 125 { // Down
                parent.onDownArrow()
                return nil
            }

            // 5. Enter -> 执行当前选中项
            if keyCode == 36 || keyCode == 76 {
                parent.onEnter()
                return nil
            }

            // 6. ===== 列表浏览模式 (.list) =====
            if parent.focusZone == .list {
                // 空格键 (49) -> 预览当前选中的卡片！
                if keyCode == 49 {
                    parent.onSpace()
                    return nil
                }

                // 键入可打印字符 -> 自动切入搜索模式
                if let chars = event.characters, !chars.isEmpty,
                   modifiers.isEmpty || modifiers == .shift {
                    let isPrintable = chars.unicodeScalars.allSatisfy {
                        !CharacterSet.controlCharacters.contains($0)
                    }
                    if isPrintable {
                        parent.onStartSearching(chars)
                        return nil
                    }
                }

                return event
            }

            // 7. ===== 搜索模式 (.search) =====
            // 空格、删除、输入法字符全部正常交由 TextField 处理
            return event
        }
    }
}

//
//  QuickPanelView.swift
//  PasteDeck
//
//  Compact, high-speed clipboard quick paste panel for PasteDeck 2.0.
//  Triggered via global hotkey (default ⌘⇧V), focused on rapid keyboard navigation.
//

import SwiftUI
import SwiftData
import AppKit

enum QuickPanelFocusZone: Equatable {
    case cards
    case search
}

struct QuickPanelView: View {
    @StateObject private var historyStore = ClipboardHistoryStore(
        modelContext: ModelContext(AppModelContainer.container)
    )
    @StateObject private var searchCoordinator = UnifiedSearchCoordinator()

    /// 当前焦点区域：呼出时默认停留在卡片区（.cards），按 Space 可预览；
    /// 键入任意字母/数字时自动切入搜索模式（.search）。
    @State private var focusZone: QuickPanelFocusZone = .cards

    @State private var previewController: PreviewWindowController?
    @State private var toolWindowController: ToolWindowController?
    /// 每次面板显示时递增，驱动 ScrollViewReader 滚回列表顶部。
    @State private var scrollResetToken = 0
    /// 原生聚焦请求计数：驱动 CardFocusNSView 或 NSTextField 进行 AppKit makeFirstResponder。
    @State private var nativeFocusRequest = 0
    /// 搜索框是否持有键盘焦点。
    @State private var isSearchFieldActive = false

    var onClose: () -> Void
    var onOpenWorkbench: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBarView
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Main List Area
            itemsListView
                .frame(maxHeight: .infinity)

            // Bottom Quick Tool (Recommended or First Tool)
            quickToolBannerView
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Bottom Shortcut Hints Footer
            footerShortcutsView
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: 480, height: 560)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .background(quickPanelKeyboardMonitor)
        .onAppear {
            historyStore.loadIfNeeded()
            searchCoordinator.setHistoryStore(historyStore)
            focusCards()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            resetPanelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidRequestCardFocus)) { _ in
            focusCards()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidRequestSearchFocus)) { _ in
            focusSearchField()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearSearchText)) { _ in
            searchCoordinator.searchText = ""
            focusCards()
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
        }
    }

    // MARK: - State Lifecycle

    /// 面板每次显示时重置到干净的默认状态：清空搜索与选择、
    /// 重新加载增量数据、滚回顶部并把焦点留在卡片区（支持空格预览）。
    private func resetPanelState() {
        historyStore.loadIfNeeded()
        searchCoordinator.searchText = ""
        searchCoordinator.select(index: 0)
        scrollResetToken += 1
        focusCards()
    }

    /// 聚焦卡片浏览区：让 CardFocusNSView 成为第一响应者，
    /// 此时按 Space 直接触发大预览，按 Enter 直接粘贴，键入字符自动进入搜索。
    private func focusCards() {
        focusZone = .cards
        nativeFocusRequest += 1
    }

    /// 聚焦搜索框：让原生 NSTextField 成为第一响应者。
    private func focusSearchField() {
        focusZone = .search
        nativeFocusRequest += 1
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            QuickPanelSearchField(
                text: $searchCoordinator.searchText,
                onEditingFocusChanged: { isEditing in
                    isSearchFieldActive = isEditing
                    if isEditing {
                        focusZone = .search
                    }
                }
            )
            .frame(maxWidth: .infinity)

            if !searchCoordinator.searchText.isEmpty {
                Button {
                    searchCoordinator.searchText = ""
                    focusCards()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Open Workbench shortcut button
            Button {
                onOpenWorkbench()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 10))
                    Text("⌘K")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .help("打开完整工作台 (⌘K)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    focusZone == .search
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.7)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusSearchField()
        }
    }

    // MARK: - Items List View

    private var itemsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(searchCoordinator.unifiedEntries.enumerated()), id: \.element.id) { index, entry in
                        let isSelected = searchCoordinator.selectedIndex == index

                        switch entry {
                        case .tool(let toolMatch):
                            quickPanelToolRow(toolMatch: toolMatch, isSelected: isSelected)
                                .id(entry.id)
                                .onTapGesture {
                                    searchCoordinator.select(index: index)
                                }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        executePrimaryAction(for: entry, plainText: false)
                                    }
                                )

                        case .clipboard(let snapshot):
                            let shortcutNumber = index + 1
                            quickPanelClipboardRow(
                                item: snapshot,
                                shortcutNumber: shortcutNumber <= 9 ? shortcutNumber : nil,
                                isSelected: isSelected
                            )
                            .id(entry.id)
                            .onTapGesture {
                                searchCoordinator.select(index: index)
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    executePrimaryAction(for: entry, plainText: false)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: searchCoordinator.selectedIndex) { _, newIndex in
                if searchCoordinator.unifiedEntries.indices.contains(newIndex) {
                    let entry = searchCoordinator.unifiedEntries[newIndex]
                    withAnimation(.easeInOut(duration: 0.08)) {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
            .onChange(of: scrollResetToken) { _, _ in
                // 面板重新显示：滚回列表顶部并选中第一条。
                if let first = searchCoordinator.unifiedEntries.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    // MARK: - Clipboard Row (Image 3)

    private func quickPanelClipboardRow(
        item: ClipboardItemSnapshot,
        shortcutNumber: Int?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 11) {
            // Type leading icon
            typeLeadingIconView(item: item)

            // Content preview & source
            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let app = item.displaySourceApp {
                        Image(systemName: "app.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Time
            Text(item.displayTime)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.85))

            // Right-hand badge: Return arrow if selected, shortcut number if not
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.15))
                    )
            } else if let num = shortcutNumber {
                Text("\(num)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.4)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Tool Row

    private func quickPanelToolRow(
        toolMatch: ToolSearchService.Result,
        isSelected: Bool
    ) -> some View {
        let descriptor = toolMatch.tool.descriptor

        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: descriptor.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(descriptor.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("工具")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.06))
                        )
                }

                Text(descriptor.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.4)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Type Leading Icon

    @ViewBuilder
    private func typeLeadingIconView(item: ClipboardItemSnapshot) -> some View {
        switch item.contentType {
        case .text:
            Text("T")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
        case .markdown, .json:
            Text("</>")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
        case .link:
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
        case .image:
            if let path = item.imagePath {
                AsyncLocalImage(path: path)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .frame(width: 32, height: 32)
            }
        case .color:
            if let hex = item.colorHex {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: hex) ?? Color.orange)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "paintpalette")
                    .frame(width: 32, height: 32)
            }
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    // MARK: - Quick Tool Banner View (Image 3)

    private var quickToolBannerView: some View {
        let recommendedTool = resolveBannerTool()
        let descriptor = recommendedTool.descriptor

        return VStack(alignment: .leading, spacing: 6) {
            Text("快速工具")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))

            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.08))
                        .frame(width: 36, height: 36)

                    Image(systemName: descriptor.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(descriptor.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    openToolWindow(tool: recommendedTool, prefill: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold))
                        Text("打开")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.08))
            )
        }
    }

    private func resolveBannerTool() -> BuiltinTool {
        // If selected clipboard item matches content recognition, recommend that tool
        if let currentItem = searchCoordinator.selectedEntry?.clipboardSnapshot {
            let matches = ContentRecognizer.recognize(currentItem)
            if let firstMatch = matches.first {
                return firstMatch.tool
            }
        }
        return .timestampConversion
    }

    // MARK: - Footer Shortcuts (Image 3)

    private var footerShortcutsView: some View {
        HStack {
            HStack(spacing: 5) {
                Text("Space")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("预览")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("粘贴")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("选择")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Text("Esc")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("关闭")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// 面板内回车 / 双击的主操作：工具打开独立窗口；剪贴板项执行完整粘贴链。
    private func executePrimaryAction(for entry: UnifiedSearchEntry, plainText: Bool) {
        switch entry {
        case .tool(let toolMatch):
            openToolWindow(tool: toolMatch.tool, prefill: toolMatch.prefilledText)
        case .clipboard(let snapshot):
            pasteSnapshot(snapshot, plainText: plainText)
        }
    }

    /// 与旧版主面板一致的粘贴链：提升排序 → 写入剪贴板并暂停监控 →
    /// 关闭面板让前台应用恢复焦点 → 100ms 后模拟 ⌘V 完成粘贴。
    private func pasteSnapshot(_ snapshot: ClipboardItemSnapshot, plainText: Bool) {
        guard historyStore.fetchItem(id: snapshot.id) != nil else { return }
        historyStore.promotePastedItems(ids: [snapshot.id])
        historyStore.preparePaste(id: snapshot.id, plainText: plainText)
        onClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteService.shared.performPaste()
        }
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

    private func openPreview(for snapshot: ClipboardItemSnapshot) {
        guard let item = historyStore.fetchItem(id: snapshot.id) else { return }
        if previewController == nil {
            previewController = PreviewWindowController()
        }
        previewController?.show(item: item, onClose: {
            // 预览窗口关闭后，焦点恢复回卡片区
            NotificationCenter.default.post(name: .panelDidRequestCardFocus, object: nil)
        })
    }

    // MARK: - Keyboard Handling

    /// 速贴面板键盘处理：复用旧版 KeyboardEventMonitorView 的成熟模式，
    /// 用 NSEvent 本地监听统一拦截按键（SwiftUI 隐藏按钮的 keyboardShortcut
    /// 在搜索框持有焦点时无法接住 Return / 方向键，实测全部失效）。
    private var quickPanelKeyboardMonitor: some View {
        QuickPanelKeyboardMonitor(
            focusZone: focusZone,
            focusRequest: nativeFocusRequest,
            onUpArrow: {
                searchCoordinator.moveUp()
                if focusZone == .search {
                    focusCards()
                }
            },
            onDownArrow: {
                searchCoordinator.moveDown()
                if focusZone == .search {
                    focusCards()
                }
            },
            onEnter: { shiftHeld in
                if let entry = searchCoordinator.selectedEntry {
                    executePrimaryAction(for: entry, plainText: shiftHeld)
                }
            },
            onEscape: {
                if !searchCoordinator.searchText.isEmpty {
                    searchCoordinator.searchText = ""
                    focusCards()
                } else {
                    onClose()
                }
            },
            onSpace: {
                if let entry = searchCoordinator.selectedEntry,
                   let snapshot = entry.clipboardSnapshot {
                    openPreview(for: snapshot)
                }
            },
            onCmdW: { onClose() },
            onCmdK: { onOpenWorkbench() },
            onCmdF: { focusSearchField() },
            onStartSearching: { chars in
                searchCoordinator.searchText = chars
                focusSearchField()
            }
        )
    }
}

/// 速贴面板的按键拦截与双焦点原生视图。
///
/// - 卡片区模式 (.cards，默认)：CardFocusNSView 成为第一响应者，
///   Space 触发大预览，Enter 粘贴，↑↓ 选择，键入字符自动进入搜索。
/// - 搜索模式 (.search)：NSTextField 成为第一响应者，字符与空格正常输入，
///   Esc 清空并切回卡片区，Enter 执行选中项。
private struct QuickPanelKeyboardMonitor: NSViewRepresentable {
    var focusZone: QuickPanelFocusZone
    var focusRequest: Int
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onEnter: (_ shiftHeld: Bool) -> Void
    var onEscape: () -> Void
    var onSpace: () -> Void
    var onCmdW: () -> Void
    var onCmdK: () -> Void
    var onCmdF: () -> Void
    var onStartSearching: (_ chars: String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CardFocusNSView {
        let view = CardFocusNSView()
        context.coordinator.cardFocusView = view
        context.coordinator.startMonitor()
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.applyFocusZone()
        return view
    }

    func updateNSView(_ nsView: CardFocusNSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.cardFocusView = nsView
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.applyFocusZone()
    }

    final class CardFocusNSView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    final class Coordinator {
        var parent: QuickPanelKeyboardMonitor
        weak var cardFocusView: CardFocusNSView?
        private var monitor: Any?
        private var focusObservers: [NSObjectProtocol] = []
        var lastFocusRequest = 0

        init(_ parent: QuickPanelKeyboardMonitor) {
            self.parent = parent
        }

        func startMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKey(event)
            }

            let focusNotificationNames: [Notification.Name] = [
                .panelDidRequestCardFocus,
                .panelDidRequestSearchFocus
            ]
            for name in focusNotificationNames {
                let observer = NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.applyFocusZone()
                }
                focusObservers.append(observer)
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyFocusZone()
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            for observer in focusObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func applyFocusZone() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let panel = NSApp.keyWindow,
                      panel.delegate is MainPanelController,
                      panel.isVisible else { return }

                switch self.parent.focusZone {
                case .cards:
                    if let cardView = self.cardFocusView {
                        if panel.firstResponder !== cardView {
                            panel.makeFirstResponder(cardView)
                        }
                    }
                case .search:
                    self.focusSearchTextField()
                }
            }
        }

        func focusSearchTextField() {
            DispatchQueue.main.async {
                guard let panel = NSApp.keyWindow,
                      panel.delegate is MainPanelController,
                      panel.isVisible else { return }

                let textField = QuickPanelSearchFieldRegistry.shared.field
                    ?? Self.findTextField(in: panel.contentView)

                guard let textField else { return }

                if panel.firstResponder === textField { return }
                if let editor = panel.fieldEditor(false, for: textField),
                   panel.firstResponder === editor {
                    return
                }

                panel.makeFirstResponder(textField)
            }
        }

        private static func findTextField(in view: NSView?) -> NSTextField? {
            guard let view else { return nil }
            if let textField = view as? NSTextField,
               textField.identifier == QuickPanelSearchFieldIdentifier {
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

            // Esc：严格区分窗口层级，绝不连带穿透
            if keyCode == 53 {
                // 子窗口关闭冷却期保护：子窗口刚关掉时，绝不穿透连带关闭速贴面板
                if WindowCloseCooldown.isInCooldown {
                    return nil
                }

                guard let eventWindow = event.window,
                      eventWindow.isKeyWindow,
                      eventWindow.level == .popUpMenu else {
                    return event
                }
                // 工具窗口自己有关闭监听，此处也可转发兜底
                if eventWindow.identifier == ToolWindowController.windowIdentifier {
                    NotificationCenter.default.post(
                        name: ToolWindowController.toolWindowShouldClose,
                        object: eventWindow
                    )
                    return nil
                }
                // 预览窗口正在展示且是 keyWindow 时，由预览窗口自身 monitor 关闭，速贴面板不响应 Esc
                if eventWindow.identifier == previewWindowIdentifier {
                    return event
                }
                // 仅当 keyWindow 为速贴面板自身时响应
                guard eventWindow.delegate is MainPanelController else {
                    return event
                }
                parent.onEscape()
                return nil
            }

            guard let eventWindow = event.window,
                  eventWindow.isKeyWindow,
                  eventWindow.level == .popUpMenu,
                  eventWindow.delegate is MainPanelController else {
                return event
            }

            // ⌘W -> 严格只关闭当前最前层单个窗口，绝不连带穿透
            if keyCode == 13 && modifiers == .command {
                CloseWindowDispatcher.closeFrontmostWindowOnly()
                return nil
            }

            // ⌘K -> 打开完整工作台
            if keyCode == 40 && modifiers == .command {
                parent.onCmdK()
                return nil
            }

            // ⌘F -> 聚焦搜索框
            if keyCode == 3 && modifiers == .command {
                parent.onCmdF()
                return nil
            }

            // ↑/↓：在任何模式下均可移动列表选择
            if keyCode == 126 { // Up
                parent.onUpArrow()
                return nil
            }
            if keyCode == 125 { // Down
                parent.onDownArrow()
                return nil
            }

            // Return / Enter：在任何模式下均执行选中项
            if keyCode == 36 || keyCode == 76 {
                parent.onEnter(modifiers.contains(.shift))
                return nil
            }

            // ===== 卡片模式 (.cards) =====
            if parent.focusZone == .cards {
                // 空格键 (49) -> 预览当前选中的卡片
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

            // ===== 搜索模式 (.search) =====
            // 空格、删除、输入法字符全部正常交由 NSTextField 处理
            return event
        }
    }
}

/// 速贴面板搜索框的稳定标识。AppKit 层聚焦需要可靠定位这个输入框，
/// 只靠类型遍历会命中视图树中的其它 NSTextField。
let QuickPanelSearchFieldIdentifier = NSUserInterfaceItemIdentifier(
    "PasteDeck.QuickPanel.SearchField"
)

/// 速贴面板的原生搜索输入框。
///
/// 必须使用原生 NSTextField 而非 SwiftUI TextField：速贴面板是不激活
/// 应用的 NSPanel，SwiftUI 的焦点系统在其中只更新内部状态、不真正安装
/// field editor（实测 makeFirstResponder 会被焦点占位符压回），用户键入
/// 的字符全部丢失。原生 NSTextField 与旧版 AppKit 焦点机制完全兼容。
private struct QuickPanelSearchField: NSViewRepresentable {
    @Binding var text: String
    var onEditingFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.identifier = QuickPanelSearchFieldIdentifier
        field.placeholderString = "快速搜索剪贴板与工具"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13.5)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        QuickPanelSearchFieldRegistry.shared.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        QuickPanelSearchFieldRegistry.shared.field = field

        // 关键防护：用户正在打字编辑时，严禁强行重设 stringValue，防止死循环
        if let currentEditor = field.currentEditor(), currentEditor === field.window?.firstResponder {
            return
        }

        if field.stringValue != text {
            field.stringValue = text
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        QuickPanelSearchFieldRegistry.shared.clear(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickPanelSearchField

        init(_ parent: QuickPanelSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingFocusChanged(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingFocusChanged(false)
        }
    }
}

/// 保存搜索框的原生实例，让 AppKit 层聚焦能直接命中它。
private final class QuickPanelSearchFieldRegistry {
    static let shared = QuickPanelSearchFieldRegistry()
    private weak var value: NSTextField?
    private let lock = NSLock()

    var field: NSTextField? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    func clear(_ field: NSTextField) {
        lock.lock()
        defer { lock.unlock() }
        if value === field { value = nil }
    }

    private init() {}
}

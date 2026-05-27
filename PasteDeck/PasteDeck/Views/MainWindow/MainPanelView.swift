//
//  MainPanelView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

// MARK: - Focus Zone Enum

/// 焦点区域：卡片区 / 搜索栏
enum FocusZone {
    case cards
    case search
}

struct MainPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedItem: ClipboardItem?
    @State private var selectedIndex = 0

    /// 当前焦点所在区域
    @State private var focusZone: FocusZone = .cards

    /// 键盘移动限流，防止按键重复导致频繁刷新
    @State private var lastMoveTime: Date = .distantPast

    /// 搜索栏焦点绑定
    @FocusState private var isSearchFocused: Bool

    var closeHandler: (() -> Void)?

    private let cardSize: CardSize = .medium
    private let itemsPerPage = 5 // 每页显示的卡片数

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
                    }
                }
                .onSubmit {
                    // 搜索框按 Enter → 焦点切到卡片区，选中第一个
                    focusZone = .cards
                    if !filteredItems.isEmpty {
                        selectedIndex = 0
                        selectedItem = filteredItems.first
                    }
                }

                FilterTabs(selectedFilter: $selectedFilter)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // 卡片列表
            if filteredItems.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipCardView(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id,
                                    cardSize: cardSize
                                )
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    selectedItem = item
                                    // 点击卡片后焦点切到卡片区
                                    focusZone = .cards
                                }
                                .onTapGesture(count: 2) {
                                    pasteItem(item)
                                }
                                .contextMenu {
                                    CardContextMenu(item: item)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .padding(.top, 12)
                    // 当选中项变化时滚动
                    .onChange(of: selectedIndex) { oldIndex, newIndex in
                        guard !filteredItems.isEmpty else { return }
                        proxy.scrollTo(filteredItems[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 800, height: 400)
        .onAppear {
            if !filteredItems.isEmpty {
                selectedIndex = 0
                selectedItem = filteredItems.first
            }
            // 打开面板时焦点默认在卡片区
            focusZone = .cards
        }
        .onChange(of: filteredItems.count) { _, _ in
            if selectedIndex >= filteredItems.count {
                selectedIndex = max(0, filteredItems.count - 1)
            }
            selectedItem = filteredItems.isEmpty ? nil : filteredItems[selectedIndex]
        }
        // 使用 NSEvent 监听键盘
        .background(
            KeyboardView(
                focusZone: $focusZone,
                onLeftArrow: {
                    moveSelection(by: -1)
                },
                onRightArrow: {
                    moveSelection(by: 1)
                },
                onUpArrow: {
                    // 上翻页
                    moveSelection(by: -itemsPerPage)
                },
                onDownArrow: {
                    // 下翻页
                    moveSelection(by: itemsPerPage)
                },
                onEnter: {
                    if focusZone == .search {
                        // 搜索栏回车 → 焦点切到卡片区
                        focusZone = .cards
                        if !filteredItems.isEmpty {
                            selectedIndex = 0
                            selectedItem = filteredItems.first
                        }
                    } else if let item = selectedItem {
                        pasteItem(item)
                    }
                },
                onEscape: {
                    if focusZone == .search {
                        // 搜索栏 Esc → 焦点回到卡片区
                        focusZone = .cards
                    }
                    // 卡片区 Esc 由 MainPanelController 的 NSEvent monitor 处理
                },
                onSpace: {
                    if let item = selectedItem {
                        showPreviewWindow(item: item)
                    }
                },
                onDelete: {
                    if let item = selectedItem {
                        deleteItem(item)
                    }
                }
            )
        )
    }

    private var filteredItems: [ClipboardItem] {
        var result = items

        if selectedFilter == .favorites {
            result = result.filter { $0.isFavorite }
        }

        if !searchText.isEmpty {
            result = result.filter { item in
                switch item.contentType {
                case .text, .link:
                    return item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
                case .file:
                    return item.fileName?.localizedCaseInsensitiveContains(searchText) ?? false
                case .image, .color:
                    return false
                }
            }
        }

        return result.sorted { $0.isPinned && !$1.isPinned }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }

        // 限流：50ms 内忽略重复的键盘事件（按键重复时）
        let now = Date()
        guard now.timeIntervalSince(lastMoveTime) >= 0.05 else { return }
        lastMoveTime = now

        let newIndex = max(0, min(filteredItems.count - 1, selectedIndex + offset))
        selectedIndex = newIndex
        selectedItem = filteredItems[newIndex]
    }

    private func pasteItem(_ item: ClipboardItem) {
        // 1. 先把内容复制到剪贴板
        PasteService.shared.preparePaste(item)
        // 2. 关闭面板，让之前的 app 重新获得焦点
        closeHandler?()
        // 3. 延迟一小段时间，等前一 app 激活后再模拟 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteService.shared.performPaste()
        }
    }

    private func showPreviewWindow(item: ClipboardItem) {
        // 保存当前主窗口引用
        MainWindowReference.window = NSApp.keyWindow

        // 创建预览视图
        let previewView = PreviewWindow(item: item, onClose: {
            // 关闭预览后，焦点回到剪切板窗口
            DispatchQueue.main.async {
                MainWindowReference.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        })
        let hostingController = NSHostingController(rootView: previewView)

        // 创建窗口
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .screenSaver  // 最顶层，确保在剪切板窗口上方
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 添加 ESC 键监听（窗口关闭时自动移除）
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 只在预览窗口是 keyWindow 时拦截 ESC
            guard event.keyCode == 53, NSApp.keyWindow === window else { return event }
            NSEvent.removeMonitor(escMonitor!)
            escMonitor = nil
            window.close()
            // 焦点回到主窗口
            DispatchQueue.main.async {
                MainWindowReference.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return nil
        }
        // 窗口关闭时也移除监听器（防止通过关闭按钮关闭时泄漏）
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()

        if !filteredItems.isEmpty {
            selectedIndex = min(selectedIndex, filteredItems.count - 1)
            selectedItem = filteredItems[selectedIndex]
        } else {
            selectedItem = nil
        }
    }
}

// MARK: - Keyboard View using NSEvent
struct KeyboardView: NSViewRepresentable {
    @Binding var focusZone: FocusZone
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onEnter: () -> Void
    var onEscape: () -> Void
    var onSpace: () -> Void
    var onDelete: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyboardNSView()
        view.focusZone = $focusZone
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        view.onEnter = onEnter
        view.onEscape = onEscape
        view.onSpace = onSpace
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyboardNSView {
            view.focusZone = $focusZone
            view.onLeftArrow = onLeftArrow
            view.onRightArrow = onRightArrow
            view.onUpArrow = onUpArrow
            view.onDownArrow = onDownArrow
            view.onEnter = onEnter
            view.onEscape = onEscape
            view.onSpace = onSpace
            view.onDelete = onDelete

            // 焦点区域变化时，控制 firstResponder
            if focusZone == .cards {
                view.window?.makeFirstResponder(view)
            }
        }
    }
}

class KeyboardNSView: NSView {
    var focusZone: Binding<FocusZone>?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch keyCode {
        case 123: // Left arrow
            onLeftArrow?()
        case 124: // Right arrow
            onRightArrow?()
        case 126: // Up arrow
            onUpArrow?()
        case 125: // Down arrow
            onDownArrow?()
        case 36: // Enter
            onEnter?()
        case 53: // Escape
            onEscape?()
        case 49: // Space
            onSpace?()
        case 51: // Delete (Backspace)
            onDelete?()
        case 48: // Tab → 切换焦点区域
            focusZone?.wrappedValue = (focusZone?.wrappedValue == .cards) ? .search : .cards
        default:
            // 普通字符输入 → 自动切到搜索栏
            // 方向键/功能键之外的按键（有字符输入且无修饰键）转发到搜索栏
            if let chars = event.characters, !chars.isEmpty,
               modifiers.isEmpty || modifiers == .shift {
                focusZone?.wrappedValue = .search
                // 将按键转发给搜索栏（带重试机制）
                forwardKeyEventToSearchField(event)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// 将按键事件转发到搜索栏，增加重试机制以等待 SwiftUI 焦点就绪
    private func forwardKeyEventToSearchField(_ event: NSEvent, retries: Int = 5) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }

            // 尝试寻找当前 firstResponder（搜索栏的 field editor）
            if let fieldEditor = window.firstResponder as? NSTextView,
               fieldEditor.inputContext != nil {
                // 焦点已经成功转移，让 field editor 消费这个按键
                fieldEditor.keyDown(with: event)
            } else if retries > 0 {
                // 焦点还没过去（SwiftUI 的状态更新需要时间），延迟 10 毫秒后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self?.forwardKeyEventToSearchField(event, retries: retries - 1)
                }
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 确保在主线程延迟执行，等待窗口完全加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            // 只在焦点区域为 cards 时抢占 firstResponder
            if self.focusZone?.wrappedValue == .cards {
                self.window?.makeFirstResponder(self)
            }
        }
    }
}

enum ClipboardFilter: String, CaseIterable {
    case all = "全部"
    case favorites = "收藏"
}

struct FilterTabs: View {
    @Binding var selectedFilter: ClipboardFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardFilter.allCases, id: \.self) { filter in
                Button(action: {
                    selectedFilter = filter
                }) {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                        .frame(minWidth: 60)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule()) // 扩大点击区域
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.1))
        )
    }
}

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

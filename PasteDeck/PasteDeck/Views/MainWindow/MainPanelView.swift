//
//  MainPanelView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

struct MainPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedItem: ClipboardItem?
    @State private var selectedIndex = 0

    var closeHandler: (() -> Void)?

    private let cardSize: CardSize = .medium

    var body: some View {
        VStack(spacing: 0) {
            // 顶部搜索和筛选
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("搜索剪切板历史...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)

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
                        HStack(spacing: 12) {
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
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(filteredItems[newIndex].id, anchor: .center)
                        }
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
                onLeftArrow: {
                    moveSelection(by: -1)
                },
                onRightArrow: {
                    moveSelection(by: 1)
                },
                onEnter: {
                    if let item = selectedItem {
                        pasteItem(item)
                    }
                },
                onEscape: {
                    closeHandler?()
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

        let newIndex = max(0, min(filteredItems.count - 1, selectedIndex + offset))
        selectedIndex = newIndex
        selectedItem = filteredItems[newIndex]
    }

    private func pasteItem(_ item: ClipboardItem) {
        PasteService.shared.paste(item)
        closeHandler?()
    }

    private func showPreviewWindow(item: ClipboardItem) {
        // 创建独立的预览窗口，不使用 sheet
        let previewView = PreviewWindow(item: item)
        let hostingController = NSHostingController(rootView: previewView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onEnter: () -> Void
    var onEscape: () -> Void
    var onSpace: () -> Void
    var onDelete: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyboardNSView()
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onEnter = onEnter
        view.onEscape = onEscape
        view.onSpace = onSpace
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyboardNSView {
            view.onLeftArrow = onLeftArrow
            view.onRightArrow = onRightArrow
            view.onEnter = onEnter
            view.onEscape = onEscape
            view.onSpace = onSpace
            view.onDelete = onDelete
        }
    }
}

class KeyboardNSView: NSView {
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode

        switch keyCode {
        case 123: // Left arrow
            onLeftArrow?()
        case 124: // Right arrow
            onRightArrow?()
        case 36: // Enter
            onEnter?()
        case 53: // Escape
            onEscape?()
        case 49: // Space
            onSpace?()
        case 51: // Delete
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
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

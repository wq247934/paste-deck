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
    @State private var showPreview = false
    @FocusState private var isSearchFocused: Bool

    var closeHandler: (() -> Void)?

    private let cardSize: CardSize = .medium

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                SearchBarView(text: $searchText, isFocused: $isSearchFocused)
                    .onSubmit {
                        if let item = filteredItems.first {
                            PasteService.shared.paste(item)
                            closeHandler?()
                        }
                    }
                FilterTabs(selectedFilter: $selectedFilter)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if filteredItems.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CardListView(
                    items: filteredItems,
                    selectedItem: $selectedItem,
                    cardSize: cardSize,
                    onItemDoubleTap: { item in
                        PasteService.shared.paste(item)
                        closeHandler?()
                    },
                    onSpacePressed: { item in
                        selectedItem = item
                        showPreview = true
                    },
                    onEnterPressed: { item in
                        PasteService.shared.paste(item)
                        closeHandler?()
                    },
                    onClose: {
                        closeHandler?()
                    }
                )
                .padding(.top, 12)
            }
        }
        .frame(width: 800, height: 400)
        .onAppear {
            isSearchFocused = true
            if filteredItems.first != nil {
                selectedItem = filteredItems.first
            }
        }
        .sheet(isPresented: $showPreview) {
            if let item = selectedItem {
                PreviewWindow(item: item)
            }
        }
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

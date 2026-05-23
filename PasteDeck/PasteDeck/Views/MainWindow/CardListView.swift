//
//  CardListView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

struct CardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedItem: ClipboardItem?
    let cardSize: CardSize
    let onItemDoubleTap: (ClipboardItem) -> Void
    let onSpacePressed: (ClipboardItem) -> Void
    let onEnterPressed: (ClipboardItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    ClipCardView(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        cardSize: cardSize
                    )
                    .onTapGesture {
                        selectedItem = item
                    }
                    .onTapGesture(count: 2) {
                        onItemDoubleTap(item)
                    }
                    .contextMenu {
                        CardContextMenu(item: item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .onKeyPress(.leftArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.space) {
            if let item = selectedItem {
                onSpacePressed(item)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let item = selectedItem {
                onEnterPressed(item)
            }
            return .handled
        }
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = items.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            selectedItem = items[newIndex]
        } else {
            selectedItem = items.first
        }
    }
}

struct CardContextMenu: View {
    let item: ClipboardItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button("复制") {
            PasteService.shared.copyToPasteboard(item)
        }

        Button(item.isPinned ? "取消置顶" : "置顶") {
            item.isPinned.toggle()
            try? modelContext.save()
        }

        Button(item.isFavorite ? "取消收藏" : "收藏") {
            item.isFavorite.toggle()
            try? modelContext.save()
        }

        Divider()

        Button("删除", role: .destructive) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }
}

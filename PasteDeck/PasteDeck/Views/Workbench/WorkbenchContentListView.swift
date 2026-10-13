//
//  WorkbenchContentListView.swift
//  PasteDeck
//
//  Central content view of PasteDeck 2.0 workbench, rendering unified search,
//  toolbar filters, and high-density clipboard & tool items.
//

import SwiftUI
import AppKit

struct WorkbenchContentListView: View {
    @ObservedObject var searchCoordinator: UnifiedSearchCoordinator
    let items: [ClipboardItemSnapshot]
    let selectedItem: ClipboardItemSnapshot?
    let selectedEntry: UnifiedSearchEntry?
    @Binding var viewMode: WorkbenchViewMode
    @Binding var sortOrder: WorkbenchSortOrder
    @Binding var selectedTypeFilter: ClipboardContentType?
    @Binding var focusZone: WorkbenchFocusZone
    
    let onSelectEntry: (UnifiedSearchEntry) -> Void
    let onExecutePrimary: (UnifiedSearchEntry) -> Void
    let onCopyItem: (UUID) -> Void
    let onPastePlainTextItem: (UUID) -> Void
    let onToggleFavorite: (UUID) -> Void
    let onTogglePin: (UUID) -> Void
    let onDeleteItem: (UUID) -> Void
    let onPreviewItem: (ClipboardItemSnapshot) -> Void
    let onOpenTool: (BuiltinTool, String?) -> Void
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar: Search + Controls
            topToolbarView
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Main List / Grid Content
            if searchCoordinator.isSearching {
                unifiedSearchResultsList
            } else if items.isEmpty {
                emptyStateView
            } else {
                switch viewMode {
                case .list:
                    dateGroupedListView
                case .grid:
                    historyGridView
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - Top Toolbar

    private var topToolbarView: some View {
        HStack(spacing: 12) {
            // Unified Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                WorkbenchSearchField(
                    text: $searchCoordinator.searchText,
                    onEditingFocusChanged: { isEditing in
                        if isEditing {
                            focusZone = .search
                        }
                    }
                )
                .frame(maxWidth: .infinity)

                if !searchCoordinator.searchText.isEmpty {
                    Button {
                        searchCoordinator.searchText = ""
                        focusZone = .list
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // ⌘K shortcut hint
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
                focusZone = .search
            }

            // View Mode Switcher
            HStack(spacing: 2) {
                Button {
                    viewMode = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewMode == .list ? Color(red: 1.0, green: 0.45, blue: 0.08) : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(viewMode == .list ? Color.primary.opacity(0.07) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    viewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewMode == .grid ? Color(red: 1.0, green: 0.45, blue: 0.08) : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(viewMode == .grid ? Color.primary.opacity(0.07) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.04))
            )

            // Content Type Filter Menu
            Menu {
                Button("全部类型") {
                    selectedTypeFilter = nil
                }
                Divider()
                Button("纯文本") { selectedTypeFilter = .text }
                Button("链接") { selectedTypeFilter = .link }
                Button("图像") { selectedTypeFilter = .image }
                Button("文件") { selectedTypeFilter = .file }
                Button("颜色") { selectedTypeFilter = .color }
                Button("代码 / JSON") { selectedTypeFilter = .markdown }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 11))
                    Text(selectedTypeFilterTitle)
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Sort Order Menu
            Menu {
                ForEach(WorkbenchSortOrder.allCases) { order in
                    Button(order.rawValue) {
                        sortOrder = order
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                    Text(sortOrder.rawValue)
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var selectedTypeFilterTitle: String {
        guard let filter = selectedTypeFilter else { return "全部类型" }
        switch filter {
        case .text: return "纯文本"
        case .link: return "链接"
        case .image: return "图像"
        case .file: return "文件"
        case .color: return "颜色"
        case .json, .markdown: return "代码"
        }
    }

    // MARK: - Unified Search Results List (Image 4)

    private var unifiedSearchResultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Tool Results Group
                    if !searchCoordinator.toolMatches.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("工具 (\(searchCoordinator.toolMatches.count))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            VStack(spacing: 4) {
                                ForEach(Array(searchCoordinator.toolMatches.enumerated()), id: \.element.id) { index, toolMatch in
                                    let entry = UnifiedSearchEntry.tool(toolMatch)
                                    let isSelected = searchCoordinator.selectedEntry == entry

                                    toolResultRow(
                                        toolMatch: toolMatch,
                                        shortcutIndex: index + 1,
                                        isSelected: isSelected
                                    )
                                    .id(entry.id)
                                    .onTapGesture {
                                        onSelectEntry(entry)
                                    }
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded {
                                            onExecutePrimary(entry)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }

                    // Clipboard History Results Group
                    let historyItems = searchCoordinator.unifiedEntries.compactMap(\.clipboardSnapshot)
                    if !historyItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("剪贴板历史 (\(historyItems.count))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, searchCoordinator.toolMatches.isEmpty ? 8 : 4)

                            VStack(spacing: 4) {
                                ForEach(historyItems) { item in
                                    let entry = UnifiedSearchEntry.clipboard(item)
                                    let isSelected = searchCoordinator.selectedEntry == entry

                                    clipboardRow(item: item, isSelected: isSelected)
                                        .id(entry.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onSelectEntry(entry)
                                        }
                                        .simultaneousGesture(
                                            TapGesture(count: 2).onEnded {
                                                onExecutePrimary(entry)
                                            }
                                        )
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    paginationSentinelView
                }
                .padding(.vertical, 8)
            }
            .onChange(of: searchCoordinator.selectedIndex) { _, newIndex in
                if searchCoordinator.unifiedEntries.indices.contains(newIndex) {
                    let entry = searchCoordinator.unifiedEntries[newIndex]
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Date Grouped List (Image 5)

    private var dateGroupedListView: some View {
        let grouped = groupItemsByDate(items)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(grouped, id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                let entry = UnifiedSearchEntry.clipboard(item)
                                let isSelected = selectedItem?.id == item.id

                                clipboardRow(item: item, isSelected: isSelected)
                                    .id(entry.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelectEntry(entry)
                                    }
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded {
                                            onExecutePrimary(entry)
                                        }
                                    )
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                        }
                    }
                    paginationSentinelView
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: searchCoordinator.selectedIndex) { _, newIndex in
                if searchCoordinator.unifiedEntries.indices.contains(newIndex) {
                    let entry = searchCoordinator.unifiedEntries[newIndex]
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Grid View

    private var historyGridView: some View {
        let columns = [
            GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    let entry = UnifiedSearchEntry.clipboard(item)
                    let isSelected = selectedItem?.id == item.id

                    gridCard(item: item, isSelected: isSelected)
                        .onTapGesture {
                            onSelectEntry(entry)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onExecutePrimary(entry)
                            }
                        )
                }
            }
            paginationSentinelView
            .padding(16)
        }
    }

    // MARK: - Pagination Sentinel

    @ViewBuilder
    private var paginationSentinelView: some View {
        if hasMore {
            HStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.vertical, 14)
                } else {
                    Color.clear
                        .frame(height: 24)
                        .onAppear {
                            onLoadMore()
                        }
                }
                Spacer()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))

            Text("暂无剪贴板记录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)

            Text("在其他应用中复制文本、图像或文件，内容将自动记录在此")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Tool Result Row (Image 4)

    private func toolResultRow(
        toolMatch: ToolSearchService.Result,
        shortcutIndex: Int,
        isSelected: Bool
    ) -> some View {
        WorkbenchToolRowItem(
            toolMatch: toolMatch,
            shortcutIndex: shortcutIndex,
            isSelected: isSelected
        )
    }

    // MARK: - Clipboard Row (Image 4 & 5)

    private func clipboardRow(
        item: ClipboardItemSnapshot,
        isSelected: Bool
    ) -> some View {
        WorkbenchClipboardRowView(
            item: item,
            isSelected: isSelected,
            onToggleFavorite: onToggleFavorite,
            onCopyItem: onCopyItem,
            onPastePlainTextItem: onPastePlainTextItem,
            onPreviewItem: onPreviewItem,
            onTogglePin: onTogglePin,
            onDeleteItem: onDeleteItem,
            onSelectEntry: { onSelectEntry($0) }
        )
    }

    // MARK: - Leading Icon / Badge

    @ViewBuilder
    fileprivate static func contentTypeLeadingView(item: ClipboardItemSnapshot) -> some View {
        switch item.contentType {
        case .text:
            if ContentRecognizer.recognizeText(item.textContent) != .unrecognized {
                Text("IP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
            } else {
                Text("T")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
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

    fileprivate static func contentSnippet(item: ClipboardItemSnapshot) -> String? {
        guard let text = item.textContent else { return nil }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 {
            return lines.joined(separator: " · ")
        }
        return text
    }

    // MARK: - Grid Card

    private func gridCard(item: ClipboardItemSnapshot, isSelected: Bool) -> some View {
        WorkbenchGridCardView(item: item, isSelected: isSelected)
    }

    // MARK: - Date Grouping Helper

    private struct DateSection {
        let title: String
        let items: [ClipboardItemSnapshot]
    }

    private func groupItemsByDate(_ items: [ClipboardItemSnapshot]) -> [DateSection] {
        guard !items.isEmpty else { return [] }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return [DateSection(title: "全部", items: items)]
        }

        var todayItems: [ClipboardItemSnapshot] = []
        var yesterdayItems: [ClipboardItemSnapshot] = []
        var earlierItems: [ClipboardItemSnapshot] = []

        for item in items {
            let itemDate = item.createdAt
            if itemDate >= startOfToday {
                todayItems.append(item)
            } else if itemDate >= startOfYesterday {
                yesterdayItems.append(item)
            } else {
                earlierItems.append(item)
            }
        }

        var sections: [DateSection] = []
        if !todayItems.isEmpty {
            sections.append(DateSection(title: "今天", items: todayItems))
        }
        if !yesterdayItems.isEmpty {
            sections.append(DateSection(title: "昨天", items: yesterdayItems))
        }
        if !earlierItems.isEmpty {
            sections.append(DateSection(title: "更早", items: earlierItems))
        }
        return sections
    }
}

// MARK: - Row Subviews with Hover & Full Hit Shape

private struct WorkbenchClipboardRowView: View {
    let item: ClipboardItemSnapshot
    let isSelected: Bool
    let onToggleFavorite: (UUID) -> Void
    let onCopyItem: (UUID) -> Void
    let onPastePlainTextItem: (UUID) -> Void
    let onPreviewItem: (ClipboardItemSnapshot) -> Void
    let onTogglePin: (UUID) -> Void
    let onDeleteItem: (UUID) -> Void
    let onSelectEntry: (UnifiedSearchEntry) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Type badge / icon
            WorkbenchContentListView.contentTypeLeadingView(item: item)

            // Content preview & metadata
            VStack(alignment: .leading, spacing: 3) {
                // Title
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Subtitle snippet (if multiline or detailed)
                if let snippet = WorkbenchContentListView.contentSnippet(item: item), snippet != item.displayTitle {
                    Text(snippet)
                        .font(item.contentType == .json || item.contentType == .markdown
                              ? .system(size: 11, design: .monospaced)
                              : .system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Source App
                HStack(spacing: 5) {
                    if let app = item.displaySourceApp {
                        Image(systemName: "app.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }

            Spacer(minLength: 8)

            // Type tag
            Text(item.contentType.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                )

            // Star favorite button
            Button {
                onToggleFavorite(item.id)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(item.isFavorite ? Color(red: 1.0, green: 0.55, blue: 0.1) : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Time
            Text(item.displayTime)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .frame(minWidth: 55, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.09)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.35)
                        : (isHovered ? Color.primary.opacity(0.08) : Color.clear),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("复制") {
                onSelectEntry(.clipboard(item))
                onCopyItem(item.id)
            }
            Button("粘贴为纯文本") {
                onSelectEntry(.clipboard(item))
                onPastePlainTextItem(item.id)
            }
            Button("预览内容") {
                onPreviewItem(item)
            }
            Divider()
            Button(item.isFavorite ? "取消收藏" : "加入收藏") {
                onToggleFavorite(item.id)
            }
            Button(item.isPinned ? "取消置顶" : "置顶") {
                onTogglePin(item.id)
            }
            Divider()
            Button("删除", role: .destructive) {
                onDeleteItem(item.id)
            }
        }
    }
}

private struct WorkbenchToolRowItem: View {
    let toolMatch: ToolSearchService.Result
    let shortcutIndex: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        let descriptor = toolMatch.tool.descriptor

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: descriptor.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(descriptor.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if toolMatch.reason == .contentSuggestion {
                        Text("内容识别")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                            )
                    }
                }

                Text(descriptor.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Badge
            Text("工具")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                )

            // Shortcut or Action indicator
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.15))
                    )
            } else if shortcutIndex <= 9 {
                Text("\(shortcutIndex)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.10)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.35)
                        : (isHovered ? Color.primary.opacity(0.08) : Color.clear),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct WorkbenchGridCardView: View {
    let item: ClipboardItemSnapshot
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WorkbenchContentListView.contentTypeLeadingView(item: item)
                Spacer()
                Text(item.displayTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(item.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)

            Spacer(minLength: 4)

            HStack {
                if let app = item.displaySourceApp {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundColor(item.isFavorite ? Color(red: 1.0, green: 0.55, blue: 0.1) : .secondary.opacity(0.4))
            }
        }
        .padding(10)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.08)
                        : (isHovered ? Color.primary.opacity(0.04) : Color(nsColor: .textBackgroundColor).opacity(0.6))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 1.0, green: 0.45, blue: 0.08) : (isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.07)),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

/// 工作台原生搜索框稳定标识
let WorkbenchSearchFieldIdentifier = NSUserInterfaceItemIdentifier("PasteDeck.Workbench.SearchField")

/// 工作台搜索框实例注册表，使 AppKit 层键盘监视器能以 O(1) 速度直接获取引用并安装 fieldEditor
final class WorkbenchSearchFieldRegistry {
    static let shared = WorkbenchSearchFieldRegistry()
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

/// 工作台原生搜索输入框。
/// 必须采用原生 NSTextField：保证在按键激活时 AppKit 能够立即正确挂载 NSTextView fieldEditor，
/// 避免系统输入法（如微信输入法 WeType、系统拼音等）因找不到 NSTextInputClient 而发生 XPC 挂起卡死。
struct WorkbenchSearchField: NSViewRepresentable {
    @Binding var text: String
    var onEditingFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.identifier = WorkbenchSearchFieldIdentifier
        field.placeholderString = "搜索剪贴板与工具"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        WorkbenchSearchFieldRegistry.shared.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        WorkbenchSearchFieldRegistry.shared.field = field

        // 关键防护：当用户正在输入编辑时（第一响应者是当前 fieldEditor），
        // 绝对不能强行重设 stringValue，否则会打断输入法并陷入 updateNSView 死循环导致卡死！
        if let currentEditor = field.currentEditor(), currentEditor === field.window?.firstResponder {
            return
        }

        if field.stringValue != text {
            field.stringValue = text
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        WorkbenchSearchFieldRegistry.shared.clear(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WorkbenchSearchField

        init(_ parent: WorkbenchSearchField) {
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

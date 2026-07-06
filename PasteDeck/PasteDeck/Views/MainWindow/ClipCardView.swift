//
//  ClipCardView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

/// 进程内图片缓存，避免卡片滚出再滚回时反复读盘解码
private final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(forPath path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func set(_ image: NSImage, forPath path: String) {
        cache.setObject(image, forKey: path as NSString)
    }
}

struct AsyncLocalImage: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        // 缓存命中时首帧即显示，避免 .task 异步延迟造成的占位闪烁
        _image = State(initialValue: ImageCache.shared.image(forPath: path))
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // init 已预填缓存命中项，仅处理未命中的后台解码
            guard image == nil else { return }
            if let loadedImage = await Task.detached(operation: { NSImage(contentsOfFile: path) }).value {
                ImageCache.shared.set(loadedImage, forPath: path)
                await MainActor.run {
                    self.image = loadedImage
                }
            }
        }
    }
}

enum CardContextMenuMode: Equatable {
    case history
    case cleanupQueue
}

struct ClipCardView: View, Equatable {
    let item: ClipboardItemSnapshot
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var showPinOption: Bool = true
    var contextMenuMode: CardContextMenuMode = .history
    let cardSize: CardSize
    let collections: [ClipboardCollectionSnapshot]
    let onCopy: () -> Void
    var onPastePlain: (() -> Void)? = nil
    let onTogglePinned: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleCollection: (UUID) -> Void
    let onSaveTitle: (String?) -> Void
    let onDelete: () -> Void
    var onRemoveFromCleanupQueue: (() -> Void)? = nil

    @State private var isEditingTitle = false
    @State private var titleDraft = ""

    /// 仅比较影响卡片外观的输入。item 为引用类型，需显式比较其可变展示属性
    /// （置顶/收藏/收藏夹归属），否则对选中卡就地改这些属性时不会重绘。
    static func == (lhs: ClipCardView, rhs: ClipCardView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isMultiSelected == rhs.isMultiSelected
            && lhs.showPinOption == rhs.showPinOption
            && lhs.contextMenuMode == rhs.contextMenuMode
            && lhs.cardSize == rhs.cardSize
            && lhs.item.contentType == rhs.item.contentType
            && lhs.item.textContent == rhs.item.textContent
            && lhs.item.linkWebsiteName == rhs.item.linkWebsiteName
            && lhs.item.sourceApp == rhs.item.sourceApp
            && lhs.item.fileName == rhs.item.fileName
            && lhs.item.imagePath == rhs.item.imagePath
            && lhs.item.colorHex == rhs.item.colorHex
            && lhs.item.isPinned == rhs.item.isPinned
            && lhs.item.isFavorite == rhs.item.isFavorite
            && lhs.item.customTitle == rhs.item.customTitle
            && lhs.item.collections.map(\.id) == rhs.item.collections.map(\.id)
            && lhs.collections.map(\.id) == rhs.collections.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentPreview
                .frame(width: cardSize.width, height: cardSize.height)
                .clipped()

            metadataBar
        }
        .frame(width: cardSize.width)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isMultiSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: isMultiSelected ? 3 : 2
                )
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }

                // 收藏星标
                Button(action: {
                    onToggleFavorite()
                }) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(item.isFavorite ? .yellow : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .shadow(color: .black.opacity(0.1), radius: isSelected ? 8 : 2, x: 0, y: isSelected ? 4 : 1)
        .contextMenu {
            cardContextMenu
        }
        .alert("重命名", isPresented: $isEditingTitle) {
            TextField("别名", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") {
                saveTitle()
            }
        } message: {
            Text("原始剪贴板内容不会被修改。")
        }
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        switch contextMenuMode {
        case .history:
            CardContextMenu(
                item: item,
                collections: collections,
                showPinOption: showPinOption,
                onEditTitle: {
                    titleDraft = item.customTitle ?? ""
                    isEditingTitle = true
                },
                onCopy: onCopy,
                onPastePlain: onPastePlain,
                onTogglePinned: onTogglePinned,
                onToggleCollection: onToggleCollection,
                onClearTitle: { onSaveTitle(nil) },
                onDelete: onDelete
            )
        case .cleanupQueue:
            CardContextMenu(
                item: item,
                collections: collections,
                showPinOption: false,
                collectionMenuTitle: "加入收藏",
                onCopy: onCopy,
                onPastePlain: nil,
                onTogglePinned: onTogglePinned,
                onToggleCollection: onToggleCollection,
                onClearTitle: { onSaveTitle(nil) },
                onRemoveFromCleanupQueue: onRemoveFromCleanupQueue,
                showDeleteOption: false,
                onDelete: onDelete
            )
        }
    }

    private var metadataBar: some View {
        HStack(spacing: 5) {
            Image(systemName: item.contentType.icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            Text(metadataText)
                .font(metadataFont)
                .foregroundColor(item.customTitle != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            collectionBadges

            Text(item.displayTime)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(height: 26)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.035))
    }

    private var metadataText: String {
        let detail = item.customTitle != nil ? item.displayTitle : item.displaySize
        guard let sourceApp = item.displaySourceApp else {
            return detail
        }
        return "\(sourceApp) · \(detail)"
    }

    private var metadataFont: Font {
        item.customTitle != nil ? .system(size: 10, weight: .medium) : .system(size: 10)
    }

    @ViewBuilder
    private var collectionBadges: some View {
        let nonDefault = item.nonDefaultCollections
        if !nonDefault.isEmpty {
            ForEach(nonDefault.prefix(1), id: \.id) { collection in
                Text(collection.name)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.75)))
            }

            if nonDefault.count > 1 {
                Text("+\(nonDefault.count - 1)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveTitle(trimmed.isEmpty ? nil : trimmed)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.contentType {
        case .text:
            textPreview
        case .markdown:
            markdownPreview
        case .json:
            codeTextPreview
        case .link:
            linkPreview
        case .image:
            imagePreview
        case .file:
            filePreview
        case .color:
            colorPreview
        }
    }

    private var textPreview: some View {
        Text(item.textContent ?? "")
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .lineLimit(nil)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var codeTextPreview: some View {
        Text(item.textContent ?? "")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.primary)
            .lineLimit(nil)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var markdownPreview: some View {
        MarkdownRenderedText(markdown: item.textContent ?? "", baseFontSize: 12)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "link")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.accentColor)

            if let websiteName = item.linkWebsiteName {
                Text(websiteName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Text(item.textContent ?? "")
                .font(.system(size: item.linkWebsiteName == nil ? 12 : 11, weight: item.linkWebsiteName == nil ? .medium : .regular))
                .foregroundColor(item.linkWebsiteName == nil ? .primary : .secondary)
                .lineLimit(item.linkWebsiteName == nil ? 5 : 4)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var imagePreview: some View {
        Group {
            if let imagePath = item.imagePath {
                AsyncLocalImage(path: imagePath)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var filePreview: some View {
        Group {
            if let filePath = item.filePath,
               ImageFilePreview.isSupportedImageFile(path: filePath) {
                AsyncLocalImage(path: filePath)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: fileIcon)
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text(item.fileName ?? "文件")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
        }
    }

    private var colorPreview: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: item.colorHex ?? "") ?? .clear)
                .frame(width: cardSize.width - 40, height: cardSize.height - 60)

            Text(item.colorHex ?? "")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private var fileIcon: String {
        guard let fileName = item.fileName else { return "doc" }
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp3", "wav", "flac", "m4a": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "video"
        case "swift", "js", "ts", "py", "java", "kt", "go", "rs", "cpp", "c", "h": return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml", "toml": return "doc.badge.gearshape"
        default: return "doc"
        }
    }
}

// MARK: - Card Context Menu

struct CardContextMenu: View {
    let item: ClipboardItemSnapshot
    let collections: [ClipboardCollectionSnapshot]
    var showPinOption: Bool = true
    var collectionMenuTitle = "添加到收藏夹"
    var onEditTitle: (() -> Void)?
    let onCopy: () -> Void
    var onPastePlain: (() -> Void)? = nil
    let onTogglePinned: () -> Void
    let onToggleCollection: (UUID) -> Void
    let onClearTitle: () -> Void
    var onRemoveFromCleanupQueue: (() -> Void)? = nil
    var showDeleteOption = true
    let onDelete: () -> Void

    var body: some View {
        Button("复制") {
            onCopy()
        }

        if let onPastePlain, item.contentType == .text || item.contentType == .markdown || item.contentType == .json {
            Button("纯文本粘贴") {
                onPastePlain()
            }
        }

        if showPinOption {
            Button(item.isPinned ? "取消置顶" : "置顶") {
                onTogglePinned()
            }
        }

        if let onEditTitle {
            Button(item.customTitle == nil ? "重命名" : "修改别名") {
                onEditTitle()
            }

            if item.customTitle != nil {
                Button("清除别名") {
                    onClearTitle()
                }
            }
        }

        // 收藏夹子菜单
        if collections.isEmpty {
            Button(collectionMenuTitle) {}
                .disabled(true)
        } else {
            Menu(collectionMenuTitle) {
                ForEach(collections, id: \.id) { collection in
                    let isInCollection = item.collectionIDs.contains(collection.id)
                    Button(action: {
                        onToggleCollection(collection.id)
                    }) {
                        HStack {
                            Text(collection.name)
                            if isInCollection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        if let onRemoveFromCleanupQueue {
            Divider()

            Button("移出清理队列") {
                onRemoveFromCleanupQueue()
            }
        }

        if showDeleteOption {
            Divider()

            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }
}

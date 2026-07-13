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
    @State private var loadedPath: String?

    init(path: String) {
        self.path = path
        // 缓存命中时首帧即显示，避免 .task 异步延迟造成的占位闪烁
        let cachedImage = ImageCache.shared.image(forPath: path)
        _image = State(initialValue: cachedImage)
        _loadedPath = State(initialValue: cachedImage == nil ? nil : path)
    }

    var body: some View {
        Group {
            if loadedPath == path, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
        }
        .task(id: path) {
            if let cachedImage = ImageCache.shared.image(forPath: path) {
                image = cachedImage
                loadedPath = path
                return
            }

            image = nil
            loadedPath = nil
            let requestedPath = path
            let loadedImage = await Task.detached {
                NSImage(contentsOfFile: requestedPath)
            }.value
            guard !Task.isCancelled, let loadedImage else { return }

            ImageCache.shared.set(loadedImage, forPath: requestedPath)
            image = loadedImage
            loadedPath = requestedPath
        }
    }
}

enum CardContextMenuMode: Equatable {
    case history
    case cleanupQueue
}

/// 卡片的实际渲染尺寸。主面板会根据窗口和布局计算该值，清理预览仍可由旧版 `CardSize` 转换。
struct ClipCardLayoutMetrics: Equatable {
    /// 卡片总宽度，用于内容预览、元信息栏和选中描边保持一致。
    let width: CGFloat
    /// 内容预览区域高度，不包含底部元信息栏。
    let previewHeight: CGFloat
    /// 底部来源、大小和时间等元信息区域高度。
    let metadataHeight: CGFloat

    /// 卡片包含预览区和元信息栏后的总高度。
    var totalHeight: CGFloat {
        previewHeight + metadataHeight
    }

    init(width: CGFloat, previewHeight: CGFloat, metadataHeight: CGFloat = 26) {
        self.width = width
        self.previewHeight = previewHeight
        self.metadataHeight = metadataHeight
    }

    init(cardSize: CardSize) {
        self.init(width: cardSize.width, previewHeight: cardSize.height)
    }
}

struct ClipCardView: View, Equatable {
    let item: ClipboardItemSnapshot
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var showPinOption: Bool = true
    var contextMenuMode: CardContextMenuMode = .history
    let cardSize: CardSize
    /// 主面板的响应式尺寸；nil 时使用 `cardSize`，兼容清理预览等固定尺寸调用方。
    var layoutMetrics: ClipCardLayoutMetrics? = nil
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
            && lhs.resolvedLayoutMetrics == rhs.resolvedLayoutMetrics
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
                .frame(width: resolvedLayoutMetrics.width, height: resolvedLayoutMetrics.previewHeight)
                .clipped()

            metadataBar
        }
        .frame(width: resolvedLayoutMetrics.width)
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

    private var resolvedLayoutMetrics: ClipCardLayoutMetrics {
        layoutMetrics ?? ClipCardLayoutMetrics(cardSize: cardSize)
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
        .frame(height: resolvedLayoutMetrics.metadataHeight)
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
                .frame(
                    width: max(44, resolvedLayoutMetrics.width - 40),
                    height: max(36, resolvedLayoutMetrics.previewHeight - 60)
                )

            Text(item.colorHex ?? "")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private var fileIcon: String {
        clipFileIconName(item.fileName)
    }
}

// MARK: - Compact Vertical Row

/// 竖向紧凑模式的单条剪切板记录，在固定行高中保留预览、摘要和关键元信息。
struct CompactClipRowView: View, Equatable {
    /// 当前行展示的不可变剪切板快照。
    let item: ClipboardItemSnapshot
    /// 当前行是否为键盘主选项，用于绘制强调色边框。
    let isSelected: Bool
    /// 当前行是否属于多选集合，用于绘制多选背景。
    var isMultiSelected = false
    /// 当前筛选上下文是否允许显示置顶操作。
    var showPinOption = true
    /// 当前可用收藏夹快照，用于构建右键收藏菜单。
    let collections: [ClipboardCollectionSnapshot]
    /// 将原始内容写回剪切板的回调。
    let onCopy: () -> Void
    /// 以纯文本形式粘贴支持内容的回调；nil 表示当前入口不提供该操作。
    var onPastePlain: (() -> Void)? = nil
    /// 切换记录置顶状态的回调。
    let onTogglePinned: () -> Void
    /// 切换默认收藏状态的回调。
    let onToggleFavorite: () -> Void
    /// 切换指定收藏夹归属的回调。
    let onToggleCollection: (UUID) -> Void
    /// 保存或清除用户别名的回调；nil 表示清除别名。
    let onSaveTitle: (String?) -> Void
    /// 删除当前记录的回调。
    let onDelete: () -> Void

    @State private var isEditingTitle = false
    @State private var titleDraft = ""

    static func == (lhs: CompactClipRowView, rhs: CompactClipRowView) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.isMultiSelected == rhs.isMultiSelected
            && lhs.showPinOption == rhs.showPinOption
            && lhs.collections == rhs.collections
    }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045)))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle.isEmpty ? item.contentType.displayName : item.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(metadataText)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    compactCollectionBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(item.isFavorite ? .yellow : .secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 18)
        }
        .padding(.horizontal, 10)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isMultiSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.04), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
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
        }
        .alert("重命名", isPresented: $isEditingTitle) {
            TextField("别名", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                onSaveTitle(trimmedTitle.isEmpty ? nil : trimmedTitle)
            }
        } message: {
            Text("原始剪切板内容不会被修改。")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.contentType {
        case .image:
            if let imagePath = item.imagePath {
                AsyncLocalImage(path: imagePath)
            } else {
                thumbnailIcon("photo")
            }
        case .file:
            if let filePath = item.filePath,
               ImageFilePreview.isSupportedImageFile(path: filePath) {
                AsyncLocalImage(path: filePath)
            } else {
                thumbnailIcon(clipFileIconName(item.fileName))
            }
        case .color:
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hex: item.colorHex ?? "") ?? .clear)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        default:
            thumbnailIcon(item.contentType.icon)
        }
    }

    private func thumbnailIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryText: String {
        switch item.contentType {
        case .text, .markdown, .json, .link:
            let normalizedText = (item.textContent ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedText.isEmpty ? item.displaySize : normalizedText
        case .image:
            return "\(item.imageWidth)×\(item.imageHeight) · \(item.displaySize)"
        case .file:
            return item.filePath ?? item.displaySize
        case .color:
            return item.colorHex ?? item.displaySize
        }
    }

    private var metadataText: String {
        [item.displaySourceApp, item.contentType.displayName, item.displaySize, item.displayTime]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var compactCollectionBadge: some View {
        let collections = item.nonDefaultCollections
        if let collection = collections.first {
            Text(collections.count > 1 ? "\(collection.name) +\(collections.count - 1)" : collection.name)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.78)))
        }
    }
}

private func clipFileIconName(_ fileName: String?) -> String {
    guard let fileName else { return "doc" }
    let fileExtension = (fileName as NSString).pathExtension.lowercased()

    switch fileExtension {
    case "pdf": return "doc.richtext"
    case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
    case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
    case "mp3", "wav", "flac", "m4a": return "music.note"
    case "mp4", "mov", "avi", "mkv": return "video"
    case "swift", "js", "ts", "py", "java", "kt", "go", "rs", "cpp", "c", "h":
        return "chevron.left.forwardslash.chevron.right"
    case "json", "xml", "yaml", "yml", "toml": return "doc.badge.gearshape"
    default: return "doc"
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

        // 翻译分类由翻译工作区自动维护，不能作为普通收藏夹手动关联。
        let assignableCollections = collections.filter { !$0.isTranslation }
        if assignableCollections.isEmpty {
            Button(collectionMenuTitle) {}
                .disabled(true)
        } else {
            Menu(collectionMenuTitle) {
                ForEach(assignableCollections, id: \.id) { collection in
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

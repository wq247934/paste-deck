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

struct ClipCardView: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var showPinOption: Bool = true
    let cardSize: CardSize

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingTitle = false
    @State private var titleDraft = ""

    /// 仅比较影响卡片外观的输入。item 为引用类型，需显式比较其可变展示属性
    /// （置顶/收藏/收藏夹归属），否则对选中卡就地改这些属性时不会重绘。
    static func == (lhs: ClipCardView, rhs: ClipCardView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isMultiSelected == rhs.isMultiSelected
            && lhs.showPinOption == rhs.showPinOption
            && lhs.cardSize == rhs.cardSize
            && lhs.item.isPinned == rhs.item.isPinned
            && lhs.item.isFavorite == rhs.item.isFavorite
            && lhs.item.customTitle == rhs.item.customTitle
            && (lhs.item.collections?.map { $0.id } ?? []) == (rhs.item.collections?.map { $0.id } ?? [])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            contentPreview
                .frame(width: cardSize.width, height: cardSize.height)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                topMetadata
                Spacer(minLength: 0)
                bottomMetadata
            }
            .padding(6)
        }
        .frame(width: cardSize.width, height: cardSize.height)
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
                    toggleDefaultFavorite()
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
            CardContextMenu(
                item: item,
                showPinOption: showPinOption,
                onEditTitle: {
                    titleDraft = item.customTitle ?? ""
                    isEditingTitle = true
                }
            )
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

    private var topMetadata: some View {
        HStack(spacing: 5) {
            Image(systemName: item.contentType.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            if item.customTitle != nil {
                Text(item.displayTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(item.contentType.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }

    private var bottomMetadata: some View {
        HStack(spacing: 4) {
            Text(item.displaySize)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("·")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            Text(item.displayTime)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            collectionBadges
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
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
        item.customTitle = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    /// 切换默认收藏夹
    private func toggleDefaultFavorite() {
        let descriptor = FetchDescriptor<FavoriteCollection>(
            predicate: #Predicate { $0.isDefault == true }
        )
        guard let defaultCollection = try? modelContext.fetch(descriptor).first else { return }

        if item.isFavorite {
            // 移出默认收藏夹
            item.collections?.removeAll(where: { $0.id == defaultCollection.id })
        } else {
            // 加入默认收藏夹
            if item.collections == nil {
                item.collections = []
            }
            if !(item.collections?.contains(where: { $0.id == defaultCollection.id }) ?? false) {
                item.collections?.append(defaultCollection)
            }
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.contentType {
        case .text:
            textPreview
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
            .padding(.horizontal, 8)
            .padding(.top, 32)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)

            Text(item.textContent ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.top, 34)
        .padding(.bottom, 30)
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
        .padding(.top, 18)
        .padding(.bottom, 20)
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
        .padding(.horizontal, 8)
        .padding(.top, 26)
        .padding(.bottom, 24)
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
    let item: ClipboardItem
    var showPinOption: Bool = true
    var onEditTitle: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteCollection.sortOrder) private var allCollections: [FavoriteCollection]

    var body: some View {
        Button("复制") {
            PasteService.shared.copyToPasteboard(item)
        }

        if showPinOption {
            Button(item.isPinned ? "取消置顶" : "置顶") {
                item.isPinned.toggle()
                try? modelContext.save()
                NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
            }
        }

        if let onEditTitle {
            Button(item.customTitle == nil ? "重命名" : "修改别名") {
                onEditTitle()
            }

            if item.customTitle != nil {
                Button("清除别名") {
                    item.customTitle = nil
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
                }
            }
        }

        // 收藏夹子菜单
        Menu("添加到收藏夹") {
            ForEach(allCollections, id: \.id) { collection in
                let isInCollection = item.collections?.contains(where: { $0.id == collection.id }) ?? false
                Button(action: {
                    toggleCollection(collection)
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

        Divider()

        Button("删除", role: .destructive) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    private func toggleCollection(_ collection: FavoriteCollection) {
        if item.collections == nil {
            item.collections = []
        }
        if let idx = item.collections?.firstIndex(where: { $0.id == collection.id }) {
            item.collections?.remove(at: idx)
        } else {
            item.collections?.append(collection)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }
}

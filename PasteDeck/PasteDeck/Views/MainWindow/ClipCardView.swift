//
//  ClipCardView.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI

struct AsyncLocalImage: View {
    let path: String
    @State private var image: NSImage?

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
            // 在后台线程读取图片
            if let loadedImage = await Task.detached(operation: { NSImage(contentsOfFile: path) }).value {
                await MainActor.run {
                    self.image = loadedImage
                }
            }
        }
    }
}

struct ClipCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let cardSize: CardSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentPreview
                .frame(width: cardSize.width, height: cardSize.height)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: item.contentType.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(item.displayTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Text(item.displaySize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
        }
        .frame(width: cardSize.width)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
            }
            .padding(6)
        }
        .shadow(color: .black.opacity(0.1), radius: isSelected ? 8 : 2, x: 0, y: isSelected ? 4 : 1)
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
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var linkPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text(item.textContent ?? "")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

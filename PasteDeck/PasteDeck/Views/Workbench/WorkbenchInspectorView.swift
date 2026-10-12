//
//  WorkbenchInspectorView.swift
//  PasteDeck
//
//  Context Inspector on the right side of PasteDeck 2.0 workbench,
//  showing content preview, metadata, actions, smart tool suggestions, and tags.
//

import SwiftUI
import AppKit

struct WorkbenchInspectorView: View {
    let item: ClipboardItemSnapshot?
    let onCopy: (ClipboardItemSnapshot) -> Void
    let onPastePlainText: (ClipboardItemSnapshot) -> Void
    let onPreview: (ClipboardItemSnapshot) -> Void
    let onToggleFavorite: (UUID) -> Void
    let onOpenTool: (BuiltinTool, String?) -> Void

    @State private var isCopiedFeedback = false

    private static let fullDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        return f
    }()

    var body: some View {
        Group {
            if let item {
                inspectorContent(item)
            } else {
                noSelectionPlaceholder
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    }

    // MARK: - Inspector Content

    private func inspectorContent(_ item: ClipboardItemSnapshot) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: headerIconName(for: item.contentType))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(headerTitle(for: item.contentType))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    onToggleFavorite(item.id)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundColor(item.isFavorite ? Color(red: 1.0, green: 0.55, blue: 0.1) : .secondary)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("复制") { onCopy(item) }
                    Button("粘贴为纯文本") { onPastePlainText(item) }
                    Button("预览") { onPreview(item) }
                    Divider()
                    Button(item.isFavorite ? "取消收藏" : "加入收藏") { onToggleFavorite(item.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Content Preview Box
                    contentPreviewCard(item)

                    // Metadata table
                    metadataSection(item)

                    // Action buttons
                    actionButtonsSection(item)

                    // Smart tool recommendation
                    let smartTools = ContentRecognizer.recognize(item)
                    if !smartTools.isEmpty {
                        smartToolRecommendationSection(item: item, matches: smartTools)
                    }

                    // Related tools section
                    relatedToolsSection(item)

                    // Related content tags
                    let tags = contextualTags(for: item)
                    if !tags.isEmpty {
                        relatedTagsSection(tags)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Placeholder

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.4))

            Text("选中项目查看详情")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content Preview Box

    @ViewBuilder
    private func contentPreviewCard(_ item: ClipboardItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item.contentType {
            case .text, .link:
                Text(item.textContent ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .markdown, .json:
                Text(item.textContent ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .image:
                if let path = item.imagePath {
                    AsyncLocalImage(path: path)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

            case .color:
                if let hex = item.colorHex {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: hex) ?? Color.orange)
                            .frame(width: 48, height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(hex)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            if let nsColor = NSColor(hex: hex) {
                                Text("RGB \(Int(nsColor.redComponent * 255)), \(Int(nsColor.greenComponent * 255)), \(Int(nsColor.blueComponent * 255))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

            case .file:
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName ?? "文件")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(item.displaySize)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Metadata Section

    private func metadataSection(_ item: ClipboardItemSnapshot) -> some View {
        VStack(spacing: 8) {
            metadataRow(label: "类型") {
                HStack(spacing: 4) {
                    Text(item.contentType.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
            }

            if let app = item.displaySourceApp {
                metadataRow(label: "来源应用") {
                    HStack(spacing: 4) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(app)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                    }
                }
            }

            metadataRow(label: "创建时间") {
                Text(Self.fullDateTimeFormatter.string(from: item.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if item.contentType == .text || item.contentType == .link || item.contentType == .markdown || item.contentType == .json {
                metadataRow(label: "字符数") {
                    Text("\(item.textContent?.count ?? 0)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else if item.contentType == .image {
                metadataRow(label: "尺寸") {
                    Text("\(item.imageWidth) × \(item.imageHeight)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                metadataRow(label: "大小") {
                    Text(item.displaySize)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else if item.contentType == .file {
                metadataRow(label: "大小") {
                    Text(item.displaySize)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func metadataRow<V: View>(label: String, @ViewBuilder content: () -> V) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Spacer()
            content()
        }
    }

    // MARK: - Action Buttons Section

    private func actionButtonsSection(_ item: ClipboardItemSnapshot) -> some View {
        VStack(spacing: 6) {
            // Primary Copy button
            Button {
                onCopy(item)
                isCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isCopiedFeedback = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isCopiedFeedback ? "已复制" : "复制")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("⌘C")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.08))
                )
            }
            .buttonStyle(.plain)

            // Secondary Paste as Plain Text
            Button {
                onPastePlainText(item)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 12))
                    Text("粘贴为纯文本")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⇧⌘V")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Preview button
            Button {
                onPreview(item)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                    Text("预览内容")
                        .font(.system(size: 12))
                    Spacer()
                    Text("Space")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Smart Tool Recommendation Section

    private func smartToolRecommendationSection(item: ClipboardItemSnapshot, matches: [ContentRecognizer.Match]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))

                Text("智能工具推荐")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("基于内容自动推荐")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(matches, id: \.tool.id) { match in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                                .frame(width: 30, height: 30)

                            Image(systemName: match.tool.descriptor.symbolName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(match.tool.descriptor.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text(match.tool.descriptor.summary)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("打开") {
                            onOpenTool(match.tool, match.prefilledText)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                        )
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
                }
            }
        }
    }

    // MARK: - Related Tools Section

    private func relatedToolsSection(_ item: ClipboardItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("相关工具")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("更多 >")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(BuiltinTool.allCases) { tool in
                    Button {
                        onOpenTool(tool, item.textContent)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tool.descriptor.symbolName)
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.10))
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.descriptor.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(tool.descriptor.summary)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Related Tags Section

    private func relatedTagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("相关内容")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            // Flow layout / flexible grid of tags
            FlexibleTagLayout(tags: tags)
        }
    }

    private func contextualTags(for item: ClipboardItemSnapshot) -> [String] {
        guard let text = item.textContent else {
            switch item.contentType {
            case .image: return ["OCR", "图像", "缩略图", "尺寸"]
            case .file: return ["文件", "磁盘", "路径"]
            case .color: return ["色彩", "十六进制", "RGB", "调色板"]
            default: return []
            }
        }

        switch ContentRecognizer.recognizeText(text) {
        case .ipv4Address, .ipv4CIDR:
            return ["局域网 IP", "私有 IP", "IPv4", "CIDR", "子网掩码", "网关", "DNS", "服务器"]
        case .unixTimestamp:
            return ["时间戳", "时间格式化", "日期计算", "时区转换", "Cron 表达式"]
        case .unrecognized:
            if item.contentType == .link {
                return ["网页链接", "URL", "域名", "安全"]
            } else if item.contentType == .json || item.contentType == .markdown {
                return ["代码片段", "JSON", "数据交换", "语法"]
            }
            return ["纯文本", "剪贴板", "字符"]
        }
    }

    private func headerTitle(for type: ClipboardContentType) -> String {
        switch type {
        case .text: return "文本内容"
        case .link: return "链接内容"
        case .image: return "图片内容"
        case .file: return "文件内容"
        case .color: return "颜色内容"
        case .json, .markdown: return "代码内容"
        }
    }

    private func headerIconName(for type: ClipboardContentType) -> String {
        switch type {
        case .text: return "doc.plaintext"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .json, .markdown: return "curlybraces"
        }
    }
}

// MARK: - Flexible Tag Layout

struct FlexibleTagLayout: View {
    let tags: [String]

    var body: some View {
        // Wrapping tag chips
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 6)], spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
    }
}

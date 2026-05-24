//
//  PreviewWindow.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI

// 保存主窗口的引用
class MainWindowReference {
    static var window: NSWindow?
}

struct PreviewWindow: View {
    let item: ClipboardItem
    var onClose: (() -> Void)?

    // 文件内容预览状态
    @State private var fileContent: String?
    @State private var previewMode: PreviewMode = .none
    @State private var isTruncated = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Image(systemName: item.contentType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text(item.contentType.displayName)
                    .font(.system(size: 13, weight: .medium))

                if item.contentType == .file, let fileName = item.fileName {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(fileName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.displayTime)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: {
                    closeWindow()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))

            Divider()

            // 预览内容
            ScrollView {
                previewContent
                    .padding(20)
            }

            // 截断提示
            if isTruncated {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("文件过大，仅显示前 512KB 内容")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.05))
            }

            Divider()

            // 底部操作栏
            HStack {
                Text(item.displaySize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button("复制") {
                    PasteService.shared.copyToPasteboard(item)
                }
                .buttonStyle(.bordered)

                Button("粘贴") {
                    PasteService.shared.paste(item)
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            loadFileContentIfNeeded()
        }
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
        onClose?()
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .text:
            ScrollView {
                Text(item.textContent ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

        case .link:
            VStack(spacing: 16) {
                Image(systemName: "link.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                if let url = URL(string: item.textContent ?? "") {
                    Link(destination: url) {
                        Text(item.textContent ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                            .underline()
                    }
                }
            }
            .frame(maxWidth: .infinity)

        case .image:
            VStack(spacing: 12) {
                if let imagePath = item.imagePath,
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }

                Text("\(item.imageWidth) x \(item.imageHeight)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .file:
            filePreviewContent

        case .color:
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: item.colorHex ?? "") ?? .clear)
                    .frame(width: 200, height: 200)

                VStack(spacing: 8) {
                    infoRow(label: "HEX", value: item.colorHex ?? "-")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - File Preview

    @ViewBuilder
    private var filePreviewContent: some View {
        if previewMode == .none {
            // 不预览内容，显示文件元信息
            VStack(spacing: 16) {
                Image(systemName: fileIcon)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text(item.fileName ?? "文件")
                    .font(.system(size: 16, weight: .medium))

                VStack(spacing: 8) {
                    infoRow(label: "类型", value: fileTypeDescription)
                    infoRow(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))
                    if let filePath = item.filePath {
                        infoRow(label: "路径", value: filePath)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else if let content = fileContent {
            // 有内容可预览
            switch previewMode {
            case .highlight:
                VStack(spacing: 0) {
                    // 语言标签
                    HStack {
                        if let lang = PreviewConfigManager.shared.highlightLanguage(for: item.fileName) {
                            Text(lang.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        if let filePath = item.filePath {
                            Text(filePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    CodeHighlightView(code: content, language: PreviewConfigManager.shared.highlightLanguage(for: item.fileName))
                        .padding(.top, 4)
                }

            case .plain:
                VStack(spacing: 0) {
                    HStack {
                        Text("TEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        if let filePath = item.filePath {
                            Text(filePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    PlainTextView(text: content)
                        .padding(.top, 4)
                }

            case .none:
                EmptyView()
            }
        } else if let error = loadError {
            // 加载失败
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)

                Text("无法读取文件")
                    .font(.system(size: 16, weight: .medium))

                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("在 Finder 中查看") {
                    if let filePath = item.filePath {
                        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // 加载中
            ProgressView("加载文件内容...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - File Content Loading

    private func loadFileContentIfNeeded() {
        guard item.contentType == .file else { return }

        let mode = PreviewConfigManager.shared.shouldPreviewContent(fileName: item.fileName)
        previewMode = mode

        guard mode != .none, let filePath = item.filePath else { return }

        // 检查文件是否存在
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: filePath) {
            loadError = "文件不存在。"
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let maxSize = PreviewConfigManager.shared.config.maxPreviewSize

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))

                let truncated = data.count > maxSize
                let readData = truncated ? data.prefix(maxSize) : data

                let content = String(data: readData, encoding: .utf8)
                    ?? String(data: readData, encoding: .ascii)
                    ?? ""

                DispatchQueue.main.async {
                    if content.isEmpty && !data.isEmpty {
                        self.loadError = "文件内容无法解码为文本。"
                    } else {
                        self.fileContent = content
                        self.isTruncated = truncated
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain &&
                       (nsError.code == NSFileReadNoPermissionError || nsError.code == 257) {
                        self.loadError = "没有文件访问权限。\n请在系统设置 → 隐私与安全性 → 文件和文件夹 中授权 PasteDeck。"
                    } else {
                        self.loadError = "读取文件失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - File Helpers

    private var fileTypeDescription: String {
        guard let fileName = item.fileName else { return "未知" }
        let ext = (fileName as NSString).pathExtension.lowercased()

        let typeMap: [String: String] = [
            "swift": "Swift 源代码",
            "go": "Go 源代码",
            "java": "Java 源代码",
            "py": "Python 脚本",
            "lua": "Lua 脚本",
            "html": "HTML 文档",
            "vue": "Vue 组件",
            "js": "JavaScript 脚本",
            "ts": "TypeScript 脚本",
            "json": "JSON 文件",
            "css": "CSS 样式表",
            "pdf": "PDF 文档",
            "doc": "Word 文档",
            "docx": "Word 文档",
            "xls": "Excel 表格",
            "xlsx": "Excel 表格",
            "ppt": "PowerPoint 演示",
            "pptx": "PowerPoint 演示",
            "png": "PNG 图片",
            "jpg": "JPEG 图片",
            "jpeg": "JPEG 图片",
            "gif": "GIF 图片",
            "mp4": "MP4 视频",
            "mov": "QuickTime 视频",
            "mp3": "MP3 音频",
            "zip": "ZIP 压缩包",
            "md": "Markdown 文档",
            "txt": "文本文件"
        ]

        return typeMap[ext] ?? ext.uppercased() + " 文件"
    }

    private var fileIcon: String {
        guard let fileName = item.fileName else { return "doc" }
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "play.rectangle"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp3", "wav", "flac", "m4a": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "video"
        case "swift", "go", "java", "py", "js", "ts", "rb", "php", "c", "cpp", "rs", "kt":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "vue", "css", "json", "xml", "yaml", "yml":
            return "curlybraces"
        case "md", "txt", "rtf":
            return "doc.text"
        default: return "doc"
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

// MARK: - Preview Window Controller

class PreviewWindowController {
    private var window: NSWindow?

    func show(item: ClipboardItem, onClose: @escaping () -> Void) {
        MainWindowReference.window = NSApp.keyWindow

        let previewView = PreviewWindow(item: item, onClose: onClose)
        let hostingController = NSHostingController(rootView: previewView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false

        self.window = window

        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, NSApp.keyWindow === window else { return event }
            NSEvent.removeMonitor(escMonitor!)
            escMonitor = nil
            window.close()
            onClose()
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}

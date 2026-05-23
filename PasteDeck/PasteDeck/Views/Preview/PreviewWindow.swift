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

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Image(systemName: item.contentType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text(item.contentType.displayName)
                    .font(.system(size: 13, weight: .medium))

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
        .frame(width: 600, height: 450)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func closeWindow() {
        // 关闭当前预览窗口
        NSApp.keyWindow?.close()
        // 回调
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
        // 保存当前主窗口
        MainWindowReference.window = NSApp.keyWindow

        // 创建预览视图
        let previewView = PreviewWindow(item: item, onClose: onClose)
        let hostingController = NSHostingController(rootView: previewView)

        // 创建窗口
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .screenSaver  // 最顶层
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false

        self.window = window

        // 添加全局键盘监听
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                window.close()
                onClose()
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}

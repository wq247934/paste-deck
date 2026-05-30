//
//  PreviewWindow.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData
import AppKit

/// 翻译结果缓存，按 ClipboardItem.id 索引，关闭面板时统一清空
class TranslateCache {
    static let shared = TranslateCache()
    private var cache: [UUID: [TranslateSegment]] = [:]

    func get(for id: UUID) -> [TranslateSegment]? {
        cache[id]
    }

    func set(_ segments: [TranslateSegment], for id: UUID) {
        cache[id] = segments
    }

    func clear() {
        cache.removeAll()
    }
}

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

    // 翻译状态
    @State private var translateSegments: [TranslateSegment] = []
    @State private var isTranslating = false
    @State private var translateError: String?
    @State private var targetLanguage: String = "zh"
    @State private var showTranslation = false

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
            previewContent
                .padding(20)

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

            // 翻译结果区域
            if showTranslation {
                Divider()
                translateResultArea
            }

            // 底部操作栏
            HStack {
                Text(item.displaySize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                // 翻译按钮（仅文本/链接类型可用）
                if item.contentType == .text || item.contentType == .link {
                    Button(action: {
                        if showTranslation {
                            showTranslation = false
                        } else {
                            startTranslate()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showTranslation ? "xmark.circle.fill" : "character.book.closed")
                            Text(showTranslation ? "关闭翻译" : "翻译")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTranslating)
                }

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

    // MARK: - Translate Result View

    @ViewBuilder
    private var translateResultArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "character.book.closed")
                    .foregroundColor(.accentColor)
                Text("翻译结果")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if isTranslating {
                    let completed = translateSegments.filter { $0.result != nil || $0.error != nil }.count
                    Text("正在翻译 \(completed)/\(translateSegments.count)...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if translateSegments.filter({ $0.result != nil }).count == translateSegments.count && !translateSegments.isEmpty {
                    Button("复制译文") {
                        let fullTranslation = translateSegments.compactMap { $0.result }.joined(separator: "\n\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullTranslation, forType: .string)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            if let error = translateError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(translateSegments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            if let result = segment.result {
                                Text(result)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                            } else if let error = segment.error {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            } else if segment.isTranslating {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("翻译中...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Translate Logic

    private func startTranslate() {
        let text: String
        switch item.contentType {
        case .text, .link:
            text = item.textContent ?? ""
        default:
            return
        }

        guard !text.isEmpty else { return }

        // 检查缓存
        if let cached = TranslateCache.shared.get(for: item.id) {
            translateSegments = cached
            showTranslation = true
            return
        }

        // 检查 API 配置
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first,
              settings.baiduTranslateEnabled,
              !settings.baiduTranslateAppId.isEmpty,
              !settings.baiduTranslateSecretKey.isEmpty else {
            translateError = "请先在设置中启用并配置百度翻译 API"
            showTranslation = true
            return
        }

        let service = TranslateService(
            appId: settings.baiduTranslateAppId,
            secretKey: settings.baiduTranslateSecretKey,
            isAdvanced: settings.baiduTranslateIsAdvanced
        )

        // 自动检测目标语言
        targetLanguage = TranslateService.detectTargetLanguage(for: text)

        // 拆分段落
        let segments = service.splitText(text)
        translateSegments = segments.enumerated().map { index, source in
            TranslateSegment(index: index, total: segments.count, source: source)
        }
        showTranslation = true
        isTranslating = true
        translateError = nil

        // 串行/并行翻译
        if settings.baiduTranslateIsAdvanced {
            // 高级版：并发（最多 5 个并发）
            translateParallel(service: service, maxConcurrent: 5)
        } else {
            // 普通版：串行
            translateSerial(service: service)
        }
    }

    private func translateSerial(service: TranslateService) {
        let total = translateSegments.count

        func translateNext(index: Int) {
            guard index < total else {
                isTranslating = false
                TranslateCache.shared.set(translateSegments, for: item.id)
                return
            }

            translateSegments[index].isTranslating = true

            service.translateSegment(translateSegments[index].source, to: targetLanguage) { [self] result in
                DispatchQueue.main.async {
                    if index < translateSegments.count {
                        switch result {
                        case .success(let translated):
                            translateSegments[index].result = translated
                        case .failure(let error):
                            translateSegments[index].error = error.localizedDescription
                        }
                        translateSegments[index].isTranslating = false
                    }
                    translateNext(index: index + 1)
                }
            }
        }

        translateNext(index: 0)
    }

    private func translateParallel(service: TranslateService, maxConcurrent: Int) {
        let total = translateSegments.count
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: maxConcurrent)

        for i in 0..<total {
            group.enter()
            semaphore.wait()

            DispatchQueue.main.async {
                self.translateSegments[i].isTranslating = true
            }

            service.translateSegment(translateSegments[i].source, to: targetLanguage) { result in
                semaphore.signal()

                DispatchQueue.main.async {
                    if i < self.translateSegments.count {
                        switch result {
                        case .success(let translated):
                            self.translateSegments[i].result = translated
                        case .failure(let error):
                            self.translateSegments[i].error = error.localizedDescription
                        }
                        self.translateSegments[i].isTranslating = false
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.isTranslating = false
            TranslateCache.shared.set(self.translateSegments, for: self.item.id)
        }
    }

    private func closeWindow() {
        // 只调用 onClose，由 PreviewWindowController 统一处理关闭和焦点恢复
        // 不直接调用 NSApp.keyWindow?.close()，避免重复关闭
        onClose?()
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .text:
            // 文本预览改用 NSScrollView，确保上下键可以滚动
            TextPreviewNSView(text: item.textContent ?? "")

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
            fileContentPreview

        case .color:
            VStack(spacing: 16) {
                if let hex = item.colorHex {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: hex) ?? .clear)
                        .frame(height: 200)

                    Text(hex)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var fileContentPreview: some View {
        if let error = loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if previewMode == .highlight, let content = fileContent {
            CodeHighlightView(
                code: content,
                language: PreviewConfigManager.shared.highlightLanguage(for: item.fileName),
                showLineNumbers: true
            )
        } else if previewMode == .plain, let content = fileContent {
            PlainTextView(text: content)
        } else if previewMode == .none {
            VStack(spacing: 12) {
                Image(systemName: fileIcon)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text(item.fileName ?? "文件")
                    .font(.system(size: 14, weight: .medium))

                Text(fileTypeDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                // 文件信息
                VStack(alignment: .leading, spacing: 4) {
                    if let path = item.filePath {
                        infoRow(label: "路径", value: path)
                    }
                    infoRow(label: "大小", value: item.displaySize)
                    infoRow(label: "时间", value: item.displayTime)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - File Content Loading

    private func loadFileContentIfNeeded() {
        guard item.contentType == .file else { return }

        let mode = PreviewConfigManager.shared.shouldPreviewContent(fileName: item.fileName)
        previewMode = mode

        guard mode != .none, let filePath = item.filePath else { return }

        // 检查文件大小
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = attrs[.size] as? Int else {
            loadError = "无法读取文件信息。"
            return
        }

        let maxSize = PreviewConfigManager.shared.config.maxPreviewSize
        let readSize = min(fileSize, maxSize)
        isTruncated = fileSize > maxSize

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
                let data = handle.readData(ofLength: readSize)
                handle.closeFile()

                let encoding: String.Encoding = .utf8
                guard let content = String(data: data, encoding: encoding) else {
                    DispatchQueue.main.async {
                        self.loadError = "文件内容无法解码为文本。"
                    }
                    return
                }

                DispatchQueue.main.async {
                    if content.isEmpty && !data.isEmpty {
                        self.loadError = "文件内容无法解码为文本。"
                    } else {
                        self.fileContent = content
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

// MARK: - Text Preview (NSScrollView based, 支持上下键滚动)

/// 文本预览使用 NSScrollView，打开时自动成为 firstResponder
struct TextPreviewNSView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = text

        // 打开后自动成为 firstResponder，使上下键可以滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.string = text
    }
}

// MARK: - Preview Window Controller

class PreviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    // Esc 监听已移至 KeyboardEventMonitorView 统一处理
    private var onCloseCallback: (() -> Void)?
    /// 标记是否已执行过关闭+恢复焦点，防止 windowWillClose 和 close() 重复执行
    private var didCloseAndRestore = false

    func show(item: ClipboardItem, onClose: @escaping () -> Void) {
        // 先清理可能残留的旧窗口和监听器
        cleanup()

        MainWindowReference.window = NSApp.keyWindow
        onCloseCallback = onClose
        didCloseAndRestore = false

        let previewView = PreviewWindow(item: item, onClose: { [weak self] in
            self?.performClose()
        })
        let hostingController = NSHostingController(rootView: previewView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 使用与主面板相同的层级，确保预览窗口显示在主面板前面
        window.level = .popUpMenu
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false
        window.delegate = self

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    /// 预览窗口是否可见
    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    /// 统一的关闭入口：关窗口 → 恢复焦点 → 回调
    /// public 以便 MainPanelView 的 Esc 处理调用
    func performClose() {
        guard !didCloseAndRestore else { return }
        didCloseAndRestore = true

        window?.close()
        window = nil

        // 恢复主面板焦点
        restoreMainPanelFocus()

        onCloseCallback?()
        onCloseCallback = nil
    }

    /// 清理残留的窗口和监听器（不触发恢复焦点和回调）
    private func cleanup() {
        window?.close()
        window = nil
        onCloseCallback = nil
        didCloseAndRestore = false
    }



    private func restoreMainPanelFocus() {
        guard let previousWindow = MainWindowReference.window, previousWindow.isVisible else { return }

        // 临时禁用主面板的 resignKey 自动关闭
        if let panelController = NSApp.windows
            .compactMap({ $0.delegate as? MainPanelController })
            .first {
            panelController.suspendAutoClose()
        }

        previousWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    @objc func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的兜底：如果 performClose 已执行则跳过，否则补执行
        guard !didCloseAndRestore else { return }
        performClose()
    }

    @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 点击关闭按钮时，走统一关闭流程，返回 false 阻止系统自动关闭
        performClose()
        return false
    }
}

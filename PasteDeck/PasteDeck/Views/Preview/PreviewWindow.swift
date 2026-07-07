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

private let previewWindowIdentifier = NSUserInterfaceItemIdentifier("PasteDeckPreviewWindow")

private enum PreviewWindowLayout {
    static let defaultWindowSize = CGSize(width: 600, height: 500)
    static let minimumWindowSize = CGSize(width: 360, height: 260)
    static let horizontalPadding: CGFloat = 40
    static let verticalChrome: CGFloat = 190

    static func allowsWindowResizing(for item: ClipboardItem) -> Bool {
        switch item.contentType {
        case .image:
            return false
        case .file:
            guard let filePath = item.filePath else { return true }
            return !ImageFilePreview.isSupportedImageFile(path: filePath)
        default:
            return true
        }
    }

    static func windowSize(for item: ClipboardItem, on screen: NSScreen?) -> CGSize {
        guard let imageSize = imagePixelSize(for: item) else {
            return defaultWindowSize
        }

        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let maxWindowSize = CGSize(
            width: max(minimumWindowSize.width, visibleFrame.width * 0.92),
            height: max(minimumWindowSize.height, visibleFrame.height * 0.88)
        )
        let desiredSize = CGSize(
            width: imageSize.width + horizontalPadding,
            height: imageSize.height + verticalChrome
        )

        return CGSize(
            width: min(max(desiredSize.width, minimumWindowSize.width), maxWindowSize.width),
            height: min(max(desiredSize.height, minimumWindowSize.height), maxWindowSize.height)
        )
    }

    static func imageViewportSize(for windowSize: CGSize) -> CGSize {
        CGSize(
            width: max(1, windowSize.width - horizontalPadding),
            height: max(1, windowSize.height - verticalChrome)
        )
    }

    static func centeredFrame(size: CGSize, on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func imagePixelSize(for item: ClipboardItem) -> CGSize? {
        switch item.contentType {
        case .image:
            if let imagePath = item.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                return image.pixelSize
            }
            let storedSize = CGSize(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
            return storedSize.width > 0 && storedSize.height > 0 ? storedSize : nil
        case .file:
            guard let filePath = item.filePath,
                  ImageFilePreview.isSupportedImageFile(path: filePath),
                  let image = NSImage(contentsOfFile: filePath) else {
                return nil
            }
            return image.pixelSize
        default:
            return nil
        }
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return size
    }
}

struct PreviewWindow: View {
    let item: ClipboardItem
    let windowSize: CGSize
    let allowsResizing: Bool
    var onClose: (() -> Void)?

    // 文件内容预览状态
    @State private var fileContent: String?
    @State private var previewMode: PreviewMode = .none
    @State private var isTruncated = false
    @State private var loadError: String?
    @State private var imageFilePreview: NSImage?

    // 翻译状态
    @State private var translateSegments: [TranslateSegment] = []
    @State private var isTranslating = false
    @State private var translateError: String?
    @State private var targetLanguage: String = "zh"
    @State private var showTranslation = false
    @State private var editableTextContent = ""
    @State private var editableColorHex = ""
    @State private var colorEditError: String?
    @State private var didInitializeEditableFields = false

    private var translatableText: String? {
        guard item.contentType == .text else {
            return nil
        }
        let trimmed = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentTextContent: String {
        didInitializeEditableFields ? editableTextContent : (item.textContent ?? "")
    }

    private var currentColorHex: String {
        didInitializeEditableFields ? editableColorHex : (item.colorHex ?? "")
    }

    private var sourceAppName: String? {
        ClipboardItem.normalizedSourceAppName(item.sourceApp)
    }

    /// 代码/文本预览使用的明暗主题，跟随设置中的外观模式。
    /// 预览窗口自身通过 window.appearance 生效；此属性用于代码高亮视图，
    /// 因为 Highlightr 主题无法靠 appearance 派生，需要显式传入。
    private var codePreviewTheme: CodePreviewTheme {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        let mode = (try? context.fetch(descriptor).first
            .flatMap { AppTheme(rawValue: $0.themeMode) })
            ?? .system
        return mode.codePreviewTheme
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack(spacing: 8) {
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
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let sourceAppName {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(sourceAppName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 12)

                Text(item.displayTime)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

                if translatableText != nil {
                    Button(action: {
                        if showTranslation {
                            showTranslation = false
                        } else {
                            startTranslate()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: showTranslation ? "xmark.circle.fill" : "character.book.closed")
                            Text(showTranslation ? "关闭翻译" : "翻译")
                            if !showTranslation {
                                KeycapLabel("T")
                            }
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
                    pasteAndClose()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(
            minWidth: allowsResizing ? PreviewWindowLayout.minimumWindowSize.width : windowSize.width,
            idealWidth: windowSize.width,
            maxWidth: allowsResizing ? .infinity : windowSize.width,
            minHeight: allowsResizing ? PreviewWindowLayout.minimumWindowSize.height : windowSize.height,
            idealHeight: windowSize.height,
            maxHeight: allowsResizing ? .infinity : windowSize.height
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            initializeEditableFieldsIfNeeded()
            loadFileContentIfNeeded()
        }
        .background(
            PreviewKeyboardMonitorView(
                onTranslate: {
                    triggerTranslateShortcut()
                },
                onPaste: {
                    pasteAndClose()
                }
            )
        )
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
        guard let text = translatableText else {
            return
        }

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

    private func triggerTranslateShortcut() {
        guard !isTranslating, !showTranslation else { return }
        startTranslate()
    }

    private func pasteAndClose() {
        PasteService.shared.paste(item)
        closeWindow()
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

    private func initializeEditableFieldsIfNeeded() {
        guard !didInitializeEditableFields else { return }
        editableTextContent = item.textContent ?? ""
        editableColorHex = item.colorHex ?? ""
        didInitializeEditableFields = true
    }

    private func saveTextContent(_ text: String) {
        editableTextContent = text
        item.textContent = text
        item.rtfData = nil
        try? item.modelContext?.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    private func saveColorHex(_ hex: String) -> Bool {
        let normalized = normalizeColorHex(hex)
        guard NSColor(hex: normalized) != nil else {
            colorEditError = "请输入 #RRGGBB 或 #RRGGBBAA"
            return false
        }

        colorEditError = nil
        editableColorHex = normalized
        item.colorHex = normalized
        item.textContent = normalized
        try? item.modelContext?.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
        return true
    }

    private func normalizeColorHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.replacingOccurrences(of: "#", with: "")
        return "#\(withoutHash.uppercased())"
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .text:
            if let codePreview = CodeSnippetPreviewDetector.detect(currentTextContent) {
                CodeEditorPreviewView(
                    code: currentTextContent,
                    language: codePreview.language,
                    title: codePreview.title,
                    showLineNumbers: true,
                    theme: codePreviewTheme,
                    onSave: saveTextContent
                )
            } else {
                EditablePlainTextPreview(
                    text: currentTextContent,
                    title: "文本",
                    onSave: saveTextContent
                )
            }

        case .markdown:
            CodeEditorPreviewView(
                code: currentTextContent,
                language: "markdown",
                title: "Markdown",
                showLineNumbers: true,
                theme: codePreviewTheme,
                onSave: saveTextContent
            )

        case .json:
            CodeEditorPreviewView(
                code: currentTextContent,
                language: "json",
                title: "JSON",
                showLineNumbers: true,
                onSave: saveTextContent
            )

        case .link:
            EditablePlainTextPreview(
                text: currentTextContent,
                title: "链接",
                systemImage: "link",
                singleLine: true,
                onSave: saveTextContent
            )

        case .image:
            VStack(spacing: 12) {
                if let imagePath = item.imagePath,
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    actualSizeImage(nsImage, displaySize: clipboardImageDisplaySize(for: nsImage))
                }

                Text("\(item.imageWidth) x \(item.imageHeight)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .file:
            fileContentPreview

        case .color:
            EditableColorPreview(
                hex: currentColorHex,
                error: colorEditError,
                onSave: saveColorHex
            )
        }
    }

    @ViewBuilder
    private var fileContentPreview: some View {
        if let imageFilePreview {
            VStack(spacing: 12) {
                actualSizeImage(imageFilePreview, displaySize: imageFilePreview.pixelSize)

                Text(item.fileName ?? "图片文件")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } else if let error = loadError {
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
            CodeEditorPreviewView(
                code: content,
                language: PreviewConfigManager.shared.highlightLanguage(for: item.fileName),
                title: item.fileName ?? "代码预览",
                showLineNumbers: true,
                allowEditing: false,
                theme: codePreviewTheme
            )
        } else if previewMode == .plain, let content = fileContent {
            CodeEditorPreviewView(
                code: content,
                language: "text",
                title: item.fileName ?? "文本预览",
                showLineNumbers: true,
                allowEditing: false,
                theme: codePreviewTheme
            )
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

    private func actualSizeImage(_ image: NSImage, displaySize: CGSize) -> some View {
        let viewportSize = PreviewWindowLayout.imageViewportSize(for: windowSize)

        return ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: displaySize.width, height: displaySize.height)
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func clipboardImageDisplaySize(for image: NSImage) -> CGSize {
        let storedSize = CGSize(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
        let pixelSize = image.pixelSize
        if pixelSize.width > 0, pixelSize.height > 0 {
            return pixelSize
        }
        return storedSize.width > 0 && storedSize.height > 0 ? storedSize : image.size
    }

    // MARK: - File Content Loading

    private func loadFileContentIfNeeded() {
        guard item.contentType == .file else { return }

        if let filePath = item.filePath,
           ImageFilePreview.isSupportedImageFile(path: filePath) {
            previewMode = .none
            DispatchQueue.global(qos: .userInitiated).async {
                let image = ImageFilePreview.loadImageIfSupported(path: filePath)
                DispatchQueue.main.async {
                    self.imageFilePreview = image
                }
            }
            return
        }

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


private struct CodeSnippetPreview {
    let language: String?
    let title: String
}

private enum CodeSnippetPreviewDetector {
    static func detect(_ text: String) -> CodeSnippetPreview? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return nil }

        if isLikelyJSON(trimmed) {
            return CodeSnippetPreview(language: "json", title: "JSON")
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }

        if looksLikeGo(trimmed, lines: lines) {
            return CodeSnippetPreview(language: "go", title: "代码片段")
        }

        if looksLikeCode(trimmed, lines: lines) {
            return CodeSnippetPreview(language: nil, title: "代码片段")
        }

        return nil
    }

    private static func isLikelyJSON(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last,
              (first == "{" && last == "}") || (first == "[" && last == "]"),
              let data = text.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func looksLikeGo(_ text: String, lines: [String]) -> Bool {
        let markers = [
            ":=", "map[", "func ", "package ", "struct {", "interface {",
            "nil", "context.", "error)", "go "
        ]
        let score = markers.reduce(0) { total, marker in
            text.contains(marker) ? total + 1 : total
        }
        return score >= 2 || lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("return ") }
    }

    private static func looksLikeCode(_ text: String, lines: [String]) -> Bool {
        var score = 0

        let structuralCharacters = ["{", "}", "(", ")", "[", "]", ";", "=>", "==", "!=", ":=", "->"]
        score += structuralCharacters.reduce(0) { total, marker in
            text.contains(marker) ? total + 1 : total
        }

        let indentedLines = lines.filter { line in
            line.hasPrefix("    ") || line.hasPrefix("\t")
        }.count
        if indentedLines >= 2 {
            score += 2
        }

        let assignmentLines = lines.filter { line in
            line.contains("=") || line.contains(":")
        }.count
        if assignmentLines >= max(2, lines.count / 3) {
            score += 2
        }

        let averageLineLength = lines.reduce(0) { $0 + $1.count } / max(lines.count, 1)
        if averageLineLength > 20 {
            score += 1
        }

        return score >= 5
    }
}

private struct EditablePlainTextPreview: View {
    let text: String
    let title: String
    var systemImage: String = "text.alignleft"
    var singleLine: Bool = false
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                if isEditing && draft != text {
                    Button(action: { draft = text }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("恢复原始内容")
                }

                Button(action: isEditing ? saveEditing : startEditing) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(isEditing ? .accentColor : .secondary)
                .help(isEditing ? "保存编辑" : "编辑内容")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.035))

            if isEditing {
                if singleLine {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    EditableTextView(text: $draft, onCommandSave: saveEditing)
                }
            } else {
                TextPreviewNSView(text: text, rtfData: nil)
            }
        }
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .background(commandSaveShortcut)
    }

    private var commandSaveShortcut: some View {
        Button(action: saveEditing) {
            EmptyView()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!isEditing)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func startEditing() {
        draft = text
        isEditing = true
    }

    private func saveEditing() {
        if draft != text {
            onSave(draft)
        }
        isEditing = false
    }
}

private struct EditableColorPreview: View {
    let hex: String
    let error: String?
    let onSave: (String) -> Bool

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("颜色")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(action: isEditing ? saveEditing : startEditing) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(isEditing ? .accentColor : .secondary)
                .help(isEditing ? "保存颜色" : "编辑颜色")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))

            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: isEditing ? draft : hex) ?? Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .frame(height: 200)

                if isEditing {
                    TextField("#RRGGBB", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .frame(width: 180)
                } else {
                    Text(hex)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .background(commandSaveShortcut)
    }

    private var commandSaveShortcut: some View {
        Button(action: saveEditing) {
            EmptyView()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!isEditing)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func startEditing() {
        draft = hex
        isEditing = true
    }

    private func saveEditing() {
        if draft != hex {
            if onSave(draft) {
                isEditing = false
            }
            return
        }
        isEditing = false
    }
}

private struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommandSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = CommandSavingTextView()
        textView.onCommandSave = onCommandSave
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        scrollView.documentView = textView

        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        (textView as? CommandSavingTextView)?.onCommandSave = onCommandSave
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Text Preview (NSScrollView based, 支持上下键滚动)

/// 文本预览使用 NSScrollView，打开时自动成为 firstResponder
/// 支持 RTF 富文本渲染，无 RTF 数据时回退到纯文本
struct TextPreviewNSView: NSViewRepresentable {
    let text: String
    let rtfData: Data?

    init(text: String, rtfData: Data? = nil) {
        self.text = text
        self.rtfData = rtfData
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor

        // 优先使用 RTF 富文本渲染
        if let rtfData = rtfData,
           let attributedString = try? NSAttributedString(data: rtfData, options: [
               .documentType: NSAttributedString.DocumentType.rtf,
               .characterEncoding: String.Encoding.utf8.rawValue
           ], documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributedString)
        } else {
            textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            textView.string = text
        }

        // 打开后自动成为 firstResponder，使上下键可以滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // 优先使用 RTF 富文本渲染
        if let rtfData = rtfData,
           let attributedString = try? NSAttributedString(data: rtfData, options: [
               .documentType: NSAttributedString.DocumentType.rtf,
               .characterEncoding: String.Encoding.utf8.rawValue
           ], documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributedString)
        } else {
            textView.string = text
        }
    }
}

/// Markdown 预览使用 NSScrollView 包裹 SwiftUI 渲染内容，保持与普通文本预览一致的上下键滚动体验
struct MarkdownPreviewNSView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = KeyboardScrollableMarkdownScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let hostingView = NSHostingView(rootView: markdownContent)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let container = FlippedHostingContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        scrollView.documentView = container

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        // 打开后自动成为 firstResponder，使上下键可以滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollView.window?.makeFirstResponder(scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let container = scrollView.documentView as? FlippedHostingContainer,
              let hostingView = container.subviews.first as? NSHostingView<AnyView> else {
            return
        }
        hostingView.rootView = AnyView(markdownContent)
    }

    private var markdownContent: AnyView {
        AnyView(
            MarkdownRenderedText(markdown: markdown, baseFontSize: 14)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
        )
    }
}

private final class FlippedHostingContainer: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

private final class KeyboardScrollableMarkdownScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            scrollVertically(by: -40)
        case 125: // Down arrow
            scrollVertically(by: 40)
        case 116: // Page Up
            scrollVertically(by: -contentView.bounds.height * 0.9)
        case 121: // Page Down
            scrollVertically(by: contentView.bounds.height * 0.9)
        default:
            super.keyDown(with: event)
        }
    }

    private func scrollVertically(by delta: CGFloat) {
        guard let documentView else { return }
        let maxY = max(0, documentView.bounds.height - contentView.bounds.height)
        let currentY = contentView.bounds.origin.y
        let nextY = min(max(currentY + delta, 0), maxY)
        contentView.scroll(to: NSPoint(x: 0, y: nextY))
        reflectScrolledClipView(contentView)
    }
}

private struct KeycapLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private struct PreviewKeyboardMonitorView: NSViewRepresentable {
    let onTranslate: () -> Void
    let onPaste: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator {
        var parent: PreviewKeyboardMonitorView
        private var monitor: Any?

        init(parent: PreviewKeyboardMonitorView) {
            self.parent = parent
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func startMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) ?? event
            }
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            guard NSApp.keyWindow?.identifier == previewWindowIdentifier else {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let nonShiftModifiers = modifiers.subtracting(.shift)
            guard nonShiftModifiers.isEmpty else {
                return event
            }

            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.isEditable {
                return event
            }

            switch event.keyCode {
            case 36, 76: // Return / keypad Enter
                parent.onPaste()
                return nil
            case 17: // T
                parent.onTranslate()
                return nil
            default:
                return event
            }
        }
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

        let screen = MainWindowReference.window?.screen
        let windowSize = PreviewWindowLayout.windowSize(for: item, on: screen)
        let allowsResizing = PreviewWindowLayout.allowsWindowResizing(for: item)
        let previewView = PreviewWindow(item: item, windowSize: windowSize, allowsResizing: allowsResizing, onClose: { [weak self] in
            self?.performClose()
        })
        let hostingController = NSHostingController(rootView: previewView)

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = previewWindowIdentifier
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if allowsResizing {
            styleMask.insert(.resizable)
            window.minSize = NSSize(
                width: PreviewWindowLayout.minimumWindowSize.width,
                height: PreviewWindowLayout.minimumWindowSize.height
            )
        }
        window.styleMask = styleMask
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 使用与主面板相同的层级，确保预览窗口显示在主面板前面
        window.level = .popUpMenu
        window.setContentSize(windowSize)
        window.setFrame(PreviewWindowLayout.centeredFrame(size: windowSize, on: screen), display: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.hidesOnDeactivate = false
        window.delegate = self

        // 按当前外观模式渲染顶/底栏、内容区与代码预览。
        window.appearance = AppearanceResolver.currentAppearance

        // 监听外观模式变更，实时更新已打开的预览窗口。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceModeChange),
            name: .appearanceModeDidChange,
            object: nil
        )

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

    // MARK: - Appearance

    @objc private func handleAppearanceModeChange() {
        window?.appearance = AppearanceResolver.currentAppearance
    }

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

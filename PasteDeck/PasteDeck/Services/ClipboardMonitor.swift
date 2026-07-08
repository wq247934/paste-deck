//
//  ClipboardMonitor.swift
//  PasteDeck
//
//  Monitors clipboard changes and saves content to SwiftData.
//  Supports text, links, images, files, and colors.
//  Includes deduplication and app blacklist filtering.
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import SwiftData

/// Monitors system clipboard for changes and records clipboard history
class ClipboardMonitor {
    private var modelContext: ModelContext
    private var changeCount: Int
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var startupMaintenanceWorkItem: DispatchWorkItem?
    private var cacheManager: CacheManager
    private var isPaused = false

    private struct PendingImageOCRJob: Sendable {
        let itemID: UUID
        let imagePath: String
    }

    private struct FrontmostApplicationInfo {
        /// 应用展示名，用于写入剪贴板历史的来源字段，方便用户识别内容来自哪里。
        let name: String

        /// 应用的 bundle identifier，用于黑名单匹配，避免展示名本地化或重名应用导致误判。
        let bundleIdentifier: String?
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.changeCount = NSPasteboard.general.changeCount
        self.cacheManager = CacheManager()
    }

    // MARK: - Public Methods

    /// Starts monitoring clipboard changes at regular intervals
    func startMonitoring() {
        scheduleStartupMaintenance()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.runAutoCleanupInBackground()
        }
    }

    /// Stops clipboard monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        startupMaintenanceWorkItem?.cancel()
        startupMaintenanceWorkItem = nil
    }

    /// Temporarily pauses monitoring (used during paste operations)
    func pause() {
        isPaused = true
    }

    /// Resumes monitoring after a brief delay to allow paste operation to complete
    func resume() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isPaused = false
            // Update changeCount to avoid recording pasted content
            self?.changeCount = NSPasteboard.general.changeCount
        }
    }

    // MARK: - Private Methods

    private func checkForChanges() {
        guard !isPaused else { return }

        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != changeCount else { return }
        changeCount = currentChangeCount

        // Ignore copies from PasteDeck itself
        let sourceApplication = getFrontmostApplication()
        if sourceApplication?.bundleIdentifier == Bundle.main.bundleIdentifier || sourceApplication?.name == "PasteDeck" {
            return
        }

        // Skip blacklisted apps
        if let bundleIdentifier = sourceApplication?.bundleIdentifier,
           isBlacklisted(bundleIdentifier: bundleIdentifier) {
            return
        }

        let parsedItems = parsePasteboard(pasteboard, sourceApp: sourceApplication?.name)
        for item in parsedItems {
            if !isDuplicate(item) {
                saveItem(item)
            }
        }
    }

    /// Checks if the item is a duplicate of the most recent entry
    private func isDuplicate(_ item: ClipboardItem) -> Bool {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let recentItems = try? modelContext.fetch(descriptor),
              let recent = recentItems.first else {
            return false
        }

        // 比较内容
        switch item.contentType {
        case .text, .link, .markdown, .json:
            return recent.textContent == item.textContent
        case .image:
            // 图片比较大小和尺寸
            return recent.imageWidth == item.imageWidth &&
                   recent.imageHeight == item.imageHeight &&
                   recent.fileSize == item.fileSize
        case .file:
            return recent.filePath == item.filePath
        case .color:
            return recent.colorHex == item.colorHex
        }
    }

    private func parsePasteboard(_ pasteboard: NSPasteboard, sourceApp: String?) -> [ClipboardItem] {
        guard let types = pasteboard.types else { return [] }

        // 文件优先于图片（Finder 复制文件时会同时带文件URL和图标预览图）
        if types.contains(.fileURL) {
            return parseFiles(pasteboard, sourceApp: sourceApp)
        }

        if types.contains(.tiff) || types.contains(.png) {
            if let item = parseImage(pasteboard, sourceApp: sourceApp) {
                return [item]
            }
            return []
        }

        if types.contains(.string) {
            if let item = parseText(pasteboard, sourceApp: sourceApp) {
                return [item]
            }
            return []
        }

        if types.contains(.color) {
            if let item = parseColor(pasteboard, sourceApp: sourceApp) {
                return [item]
            }
            return []
        }

        return []
    }

    private func parseImage(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return nil
        }

        guard let imagePath = cacheManager.saveImage(image) else {
            return nil
        }
        let pixelSize = NSImage(contentsOfFile: imagePath)?.pixelSize ?? image.pixelSize

        return ClipboardItem(
            contentType: .image,
            imagePath: imagePath,
            fileSize: cacheManager.getFileSize(at: imagePath),
            imageWidth: Int(pixelSize.width),
            imageHeight: Int(pixelSize.height),
            sourceApp: sourceApp
        )
    }

    private func parseFiles(_ pasteboard: NSPasteboard, sourceApp: String?) -> [ClipboardItem] {
        guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !fileURLs.isEmpty else {
            return []
        }

        return fileURLs.compactMap { fileURL in
            // 跳过不存在的文件路径
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return ClipboardItem(
                contentType: .file,
                filePath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                fileSize: cacheManager.getFileSize(at: fileURL.path),
                sourceApp: sourceApp
            )
        }
    }

    private func parseText(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }

        if let url = detectURL(text) {
            return ClipboardItem(
                contentType: .link,
                textContent: url.absoluteString,
                sourceApp: sourceApp
            )
        }

        // 尝试读取 RTF 富文本数据
        let rtfData = pasteboard.data(forType: .rtf)

        let contentType: ClipboardContentType
        if isJSONText(text) {
            contentType = .json
        } else if isMarkdownText(text, pasteboard: pasteboard) {
            contentType = .markdown
        } else {
            contentType = .text
        }

        return ClipboardItem(
            contentType: contentType,
            textContent: text,
            sourceApp: sourceApp,
            rtfData: rtfData
        )
    }

    private func parseColor(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let color = pasteboard.readObjects(forClasses: [NSColor.self], options: nil)?.first as? NSColor else {
            return nil
        }

        let hex = colorToHex(color)

        return ClipboardItem(
            contentType: .color,
            textContent: hex,
            colorHex: hex,
            sourceApp: sourceApp
        )
    }

    private func detectURL(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)

        if let match = detector?.firstMatch(in: text, options: [], range: range),
           match.range.location == 0,
           match.range.length == text.utf16.count,
           let url = match.url {
            return url
        }

        return nil
    }

    private func isJSONText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last,
              (first == "{" && last == "}") || (first == "[" && last == "]"),
              let data = trimmed.data(using: .utf8) else {
            return false
        }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func isMarkdownText(_ text: String, pasteboard: NSPasteboard) -> Bool {
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("public.markdown")) == true ||
            pasteboard.types?.contains(NSPasteboard.PasteboardType("net.daringfireball.markdown")) == true {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if trimmed.contains("```") {
            return true
        }

        if nonEmptyLines.contains(where: { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            return line.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil ||
                line.range(of: #"^>\s+\S"#, options: .regularExpression) != nil ||
                line.range(of: #"^[-*+]\s+\S"#, options: .regularExpression) != nil ||
                line.range(of: #"^\d+\.\s+\S"#, options: .regularExpression) != nil
        }) {
            return true
        }

        if nonEmptyLines.count >= 2,
           nonEmptyLines.contains(where: { line in
               line.range(of: #"^\s*\|?.+\|.+\|?\s*$"#, options: .regularExpression) != nil
           }),
           nonEmptyLines.contains(where: { line in
               line.range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#, options: .regularExpression) != nil
           }) {
            return true
        }

        let inlinePatterns = [
            #"!\[[^\]]+\]\([^)]+\)"#,
            #"\[[^\]]+\]\([^)]+\)"#,
            #"(^|\s)(\*\*|__)\S.+\S\2(\s|$)"#,
            #"(^|\s)`[^`\n]+`(\s|$)"#
        ]

        return inlinePatterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func colorToHex(_ color: NSColor) -> String {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func getFrontmostApplication() -> FrontmostApplicationInfo? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let name = application.localizedName else {
            return nil
        }

        return FrontmostApplicationInfo(
            name: name,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    private func isBlacklisted(bundleIdentifier: String) -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else {
            return false
        }
        return settings.blacklistedApps.contains(bundleIdentifier)
    }

    private func saveItem(_ item: ClipboardItem) {
        modelContext.insert(item)
        try? modelContext.save()
        DailyStatsUpdater.upsert(for: item, context: modelContext)
        postClipboardDataChanged(itemID: item.id, kind: .inserted)
        scheduleOCRIfNeeded(for: item)
    }

    private func postClipboardDataChanged(itemID: UUID? = nil, kind: ClipboardDataChangeKind? = nil) {
        var userInfo: [AnyHashable: Any] = [:]
        if let itemID {
            userInfo[ClipboardDataChangeNotification.itemIDKey] = itemID
        }
        if let kind {
            userInfo[ClipboardDataChangeNotification.changeKindKey] = kind.rawValue
        }

        NotificationCenter.default.post(
            name: .clipboardDataChanged,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    // MARK: - Image OCR

    private func scheduleOCRIfNeeded(for item: ClipboardItem) {
        guard item.contentType == .image,
              item.ocrProcessedAt == nil,
              let imagePath = item.imagePath else {
            return
        }

        scheduleOCR(itemID: item.id, imagePath: imagePath)
    }

    private func scheduleOCR(itemID: UUID, imagePath: String) {
        ImageOCRService.shared.recognizeText(inImageAt: imagePath) { [weak self] recognizedText in
            self?.saveOCRText(recognizedText, for: itemID)
        }
    }

    private static func pendingImageOCRJobs(limit: Int) -> [PendingImageOCRJob] {
        let context = ModelContext(AppModelContainer.container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.imagePath != nil && item.ocrProcessedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        guard let items = try? context.fetch(descriptor) else { return [] }
        return items.compactMap { item in
            guard let imagePath = item.imagePath else { return nil }
            return PendingImageOCRJob(itemID: item.id, imagePath: imagePath)
        }
    }

    private func saveOCRText(_ text: String?, for itemID: UUID) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.id == itemID
            }
        )

        guard let item = try? modelContext.fetch(descriptor).first,
              item.ocrProcessedAt == nil else {
            return
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        item.ocrText = trimmed.isEmpty ? nil : trimmed
        item.ocrProcessedAt = Date()
        try? modelContext.save()
        postClipboardDataChanged(itemID: itemID, kind: .updated)
    }

    // MARK: - Auto Cleanup

    private func scheduleStartupMaintenance() {
        startupMaintenanceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            DailyStatsUpdater.backfillIfNeeded()
            let deletedCount = Self.performAutoCleanup()
            let ocrJobs = Self.pendingImageOCRJobs(limit: 20)

            DispatchQueue.main.async {
                guard let self else { return }
                if deletedCount > 0 {
                    self.postClipboardDataChanged()
                    NSLog("[PasteDeck] Auto cleanup: removed \(deletedCount) items")
                }
                for job in ocrJobs {
                    self.scheduleOCR(itemID: job.itemID, imagePath: job.imagePath)
                }
            }
        }

        startupMaintenanceWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func runAutoCleanupInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let deletedCount = Self.performAutoCleanup()
            guard deletedCount > 0 else { return }

            DispatchQueue.main.async {
                self?.postClipboardDataChanged()
                NSLog("[PasteDeck] Auto cleanup: removed \(deletedCount) items")
            }
        }
    }

    /// 根据 AppSettings 的限制自动清理过期或超量的记录
    private static func performAutoCleanup() -> Int {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let appSettings = try? context.fetch(descriptor).first else { return 0 }

        var deletedCount = 0

        // 按天数清理
        if appSettings.historyDaysLimit > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -appSettings.historyDaysLimit, to: Date()) ?? Date()
            let oldDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.createdAt < cutoff }
            )
            if let oldItems = try? context.fetch(oldDescriptor) {
                for item in oldItems where item.isCleanupEligible {
                    context.delete(item)
                    deletedCount += 1
                }
            }
        }

        // 按条数清理（保留最新的 N 条）
        if appSettings.historyCountLimit > 0 {
            var allDescriptor = FetchDescriptor<ClipboardItem>()
            allDescriptor.sortBy = [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
            if let allItems: [ClipboardItem] = try? context.fetch(allDescriptor), allItems.count > appSettings.historyCountLimit {
                let protectedCount = allItems.filter { !$0.isCleanupEligible }.count
                let deletableLimit = max(0, appSettings.historyCountLimit - protectedCount)
                let cleanupCandidates = allItems.filter(\.isCleanupEligible)
                let toDelete = cleanupCandidates.dropFirst(deletableLimit)
                for item in toDelete {
                    context.delete(item)
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            try? context.save()
        }

        return deletedCount
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

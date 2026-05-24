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
    private var cacheManager: CacheManager
    private var isPaused = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.changeCount = NSPasteboard.general.changeCount
        self.cacheManager = CacheManager()
    }

    // MARK: - Public Methods

    /// Starts monitoring clipboard changes at regular intervals
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    /// Stops clipboard monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
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
        let sourceApp = getFrontmostAppName()
        if sourceApp == "PasteDeck" {
            return
        }

        // Skip blacklisted apps
        if let app = sourceApp, isBlacklisted(app) {
            return
        }

        if let item = parsePasteboard(pasteboard, sourceApp: sourceApp) {
            if !isDuplicate(item) {
                saveItem(item)
            }
        }
    }

    /// Checks if the item is a duplicate of the most recent entry
    private func isDuplicate(_ item: ClipboardItem) -> Bool {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let recentItems = try? modelContext.fetch(descriptor),
              let recent = recentItems.first else {
            return false
        }

        // 比较内容
        switch item.contentType {
        case .text, .link:
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

    private func parsePasteboard(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let types = pasteboard.types else { return nil }

        // 文件优先于图片（Finder 复制文件时会同时带文件URL和图标预览图）
        if types.contains(.fileURL) {
            return parseFile(pasteboard, sourceApp: sourceApp)
        }

        if types.contains(.tiff) || types.contains(.png) {
            return parseImage(pasteboard, sourceApp: sourceApp)
        }

        if types.contains(.string) {
            return parseText(pasteboard, sourceApp: sourceApp)
        }

        if types.contains(.color) {
            return parseColor(pasteboard, sourceApp: sourceApp)
        }

        return nil
    }

    private func parseImage(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return nil
        }

        guard let imagePath = cacheManager.saveImage(image) else {
            return nil
        }

        return ClipboardItem(
            contentType: .image,
            imagePath: imagePath,
            fileSize: cacheManager.getFileSize(at: imagePath),
            imageWidth: Int(image.size.width),
            imageHeight: Int(image.size.height),
            sourceApp: sourceApp
        )
    }

    private func parseFile(_ pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let fileURL = fileURLs.first else {
            return nil
        }

        return ClipboardItem(
            contentType: .file,
            filePath: fileURL.path,
            fileName: fileURL.lastPathComponent,
            fileSize: cacheManager.getFileSize(at: fileURL.path),
            sourceApp: sourceApp
        )
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

        return ClipboardItem(
            contentType: .text,
            textContent: text,
            sourceApp: sourceApp
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

    private func colorToHex(_ color: NSColor) -> String {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func getFrontmostAppName() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func isBlacklisted(_ appName: String) -> Bool {
        // TODO: Check against settings
        return false
    }

    private func saveItem(_ item: ClipboardItem) {
        modelContext.insert(item)
        try? modelContext.save()
    }
}

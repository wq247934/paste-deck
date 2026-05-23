//
//  ClipboardMonitor.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import SwiftData

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

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 暂停监听（粘贴时使用）
    func pause() {
        isPaused = true
    }

    /// 恢复监听
    func resume() {
        // 延迟恢复，给粘贴操作留出时间
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isPaused = false
            // 更新 changeCount，避免记录粘贴的内容
            self?.changeCount = NSPasteboard.general.changeCount
        }
    }

    private func checkForChanges() {
        // 暂停时不监听
        guard !isPaused else { return }

        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != changeCount else { return }
        changeCount = currentChangeCount

        // 检查是否来自 PasteDeck 自己
        let sourceApp = getFrontmostAppName()
        if sourceApp == "PasteDeck" {
            print("ClipboardMonitor: 忽略来自 PasteDeck 的复制")
            return
        }

        if let app = sourceApp, isBlacklisted(app) {
            return
        }

        if let item = parsePasteboard(pasteboard, sourceApp: sourceApp) {
            // 检查是否重复
            if !isDuplicate(item) {
                saveItem(item)
            } else {
                print("ClipboardMonitor: 忽略重复内容")
            }
        }
    }

    /// 检查是否与最近的内容重复
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

        if types.contains(.tiff) || types.contains(.png) {
            return parseImage(pasteboard, sourceApp: sourceApp)
        }

        if types.contains(.fileURL) {
            return parseFile(pasteboard, sourceApp: sourceApp)
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

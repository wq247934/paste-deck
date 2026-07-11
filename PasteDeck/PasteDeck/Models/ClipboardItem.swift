//
//  ClipboardItem.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import SwiftData
import SwiftUI

/// 剪切板历史记录项
@Model
final class ClipboardItem {
    // MARK: - Properties

    var id: UUID
    var contentType: ClipboardContentType
    var textContent: String?
    var imagePath: String?
    var filePath: String?
    var fileName: String?
    var fileSize: Int
    var imageWidth: Int
    var imageHeight: Int
    var ocrText: String?
    var ocrProcessedAt: Date?
    var colorHex: String?
    var sourceApp: String?
    var createdAt: Date
    var isPinned: Bool
    var customTitle: String?

    /// 网页元数据返回的代表性标题；nil 表示尚未成功获取或网页没有标题。
    var linkPageTitle: String?

    /// 标题抓取任务创建时间；nil 表示该链接未请求过后台标题抓取。
    var linkTitleRequestedAt: Date?

    /// 标题抓取完成时间；失败也会记录，用于避免短时间内重复请求。
    var linkTitleFetchedAt: Date?

    /// RTF 富文本数据（字体、颜色、样式等）
    var rtfData: Data?

    /// 收藏夹关联（多对多）
    var collections: [FavoriteCollection]?

    // MARK: - Computed Properties

    /// 是否在默认收藏夹中
    var isFavorite: Bool {
        get {
            collections?.contains(where: { $0.isDefault }) ?? false
        }
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        return originalDisplayTitle
    }

    var originalDisplayTitle: String {
        switch contentType {
        case .text, .markdown, .json:
            return String((textContent?.prefix(50) ?? "").replacingOccurrences(of: "\n", with: " "))
        case .link:
            return linkDisplayTitle
        case .image:
            return "图片 \(imageWidth)x\(imageHeight)"
        case .file:
            return fileName ?? "文件"
        case .color:
            return colorHex ?? ""
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var displaySize: String {
        switch contentType {
        case .text, .link, .markdown, .json:
            let count = textContent?.count ?? 0
            return "\(count) 字符"
        case .image, .file:
            return Self.byteCountFormatter.string(fromByteCount: Int64(fileSize))
        case .color:
            return colorHex ?? ""
        }
    }

    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var displayTime: String {
        Self.relativeDateTimeFormatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// 获取非默认收藏夹列表（用于显示 badge）
    var nonDefaultCollections: [FavoriteCollection] {
        (collections ?? []).filter { !$0.isDefault }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var isCleanupEligible: Bool {
        !isPinned && (collections?.isEmpty ?? true)
    }

    var linkWebsiteName: String? {
        guard contentType == .link else { return nil }
        return linkPageTitle ?? Self.makeLinkWebsiteName(from: textContent)
    }

    /// 网页标题未获取时使用完整 host，避免通过不完整公共后缀表猜错网站名称。
    var linkDisplayTitle: String {
        linkWebsiteName ?? textContent ?? ""
    }

    static func makeLinkWebsiteName(from textContent: String?) -> String? {
        guard let host = normalizedLinkHost(from: textContent) else { return nil }
        return host
    }

    static func makeLinkSearchText(from textContent: String?) -> String? {
        guard let host = normalizedLinkHost(from: textContent) else { return nil }
        let parts = [
            host,
            host.replacingOccurrences(of: ".", with: " ")
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func normalizedSourceAppName(_ sourceApp: String?) -> String? {
        let trimmed = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Initialization

    init(
        contentType: ClipboardContentType,
        textContent: String? = nil,
        imagePath: String? = nil,
        filePath: String? = nil,
        fileName: String? = nil,
        fileSize: Int = 0,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        colorHex: String? = nil,
        sourceApp: String? = nil,
        rtfData: Data? = nil
    ) {
        self.id = UUID()
        self.contentType = contentType
        self.textContent = textContent
        self.imagePath = imagePath
        self.filePath = filePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.ocrText = nil
        self.ocrProcessedAt = nil
        self.colorHex = colorHex
        self.sourceApp = sourceApp
        self.createdAt = Date()
        self.isPinned = false
        self.customTitle = nil
        self.linkPageTitle = nil
        self.linkTitleRequestedAt = nil
        self.linkTitleFetchedAt = nil
        self.rtfData = rtfData
    }

    // MARK: - Methods

    func loadImage() -> NSImage? {
        guard let path = imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    func loadColor() -> Color? {
        guard let hex = colorHex else { return nil }
        return Color(hex: hex)
    }

    private static func normalizedLinkHost(from textContent: String?) -> String? {
        guard let rawText = textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty else {
            return nil
        }

        let candidate = rawText.contains("://") ? rawText : "https://\(rawText)"
        guard let rawHost = URLComponents(string: candidate)?.host ?? URL(string: candidate)?.host else {
            return nil
        }

        let trimmedHost = rawHost
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !trimmedHost.isEmpty else { return nil }

        if trimmedHost.hasPrefix("www.") {
            return String(trimmedHost.dropFirst(4))
        }

        return trimmedHost
    }

}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        } else if length == 8 {
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}

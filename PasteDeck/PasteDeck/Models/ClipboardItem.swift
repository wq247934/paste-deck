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
            return linkWebsiteName ?? textContent ?? ""
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
        return Self.makeLinkWebsiteName(from: textContent)
    }

    static func makeLinkWebsiteName(from textContent: String?) -> String? {
        guard let host = normalizedLinkHost(from: textContent) else { return nil }
        guard let label = primaryDomainLabel(from: host) else { return host }
        return prettifyWebsiteName(label)
    }

    static func makeLinkSearchText(from textContent: String?) -> String? {
        guard let host = normalizedLinkHost(from: textContent) else { return nil }
        let label = primaryDomainLabel(from: host)
        let parts = [
            label.map { prettifyWebsiteName($0) },
            label,
            host,
            host.replacingOccurrences(of: ".", with: " ")
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
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

    private static func primaryDomainLabel(from host: String) -> String? {
        let labels = host
            .split(separator: ".")
            .map(String.init)

        guard labels.count >= 2 else {
            return host.isEmpty ? nil : host
        }

        let suffix = labels.suffix(2).joined(separator: ".")
        if labels.count >= 3, compoundPublicSuffixes.contains(suffix) {
            return labels[labels.count - 3]
        }

        return labels[labels.count - 2]
    }

    private static func prettifyWebsiteName(_ label: String) -> String {
        let normalizedLabel = label.lowercased()
        if let override = websiteNameOverrides[normalizedLabel] {
            return override
        }

        return label
            .split { $0 == "-" || $0 == "_" }
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static let compoundPublicSuffixes: Set<String> = [
        "co.jp",
        "co.kr",
        "co.uk",
        "com.au",
        "com.br",
        "com.cn",
        "com.hk",
        "com.sg",
        "com.tw",
        "github.io",
        "gov.cn",
        "net.cn",
        "org.cn"
    ]

    private static let websiteNameOverrides: [String: String] = [
        "apple": "Apple",
        "baidu": "Baidu",
        "bilibili": "Bilibili",
        "figma": "Figma",
        "github": "GitHub",
        "google": "Google",
        "linkedin": "LinkedIn",
        "medium": "Medium",
        "notion": "Notion",
        "openai": "OpenAI",
        "reddit": "Reddit",
        "stackoverflow": "Stack Overflow",
        "twitter": "Twitter",
        "x": "X",
        "youtube": "YouTube",
        "zhihu": "Zhihu"
    ]
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

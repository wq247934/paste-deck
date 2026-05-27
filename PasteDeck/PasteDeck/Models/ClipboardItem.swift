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
    var colorHex: String?
    var sourceApp: String?
    var createdAt: Date
    var isPinned: Bool
    var isFavorite: Bool
    var isDeleted: Bool

    // MARK: - Computed Properties

    var displayTitle: String {
        switch contentType {
        case .text:
            return String((textContent?.prefix(50) ?? "").replacingOccurrences(of: "\n", with: " "))
        case .link:
            return textContent ?? ""
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
        case .text, .link:
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
        sourceApp: String? = nil
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
        self.colorHex = colorHex
        self.sourceApp = sourceApp
        self.createdAt = Date()
        self.isPinned = false
        self.isFavorite = false
        self.isDeleted = false
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

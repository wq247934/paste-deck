//
//  ClipboardContentType.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import SwiftUI

/// 剪切板内容类型枚举
enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text = "text"
    case link = "link"
    case markdown = "markdown"
    case json = "json"
    case image = "image"
    case file = "file"
    case color = "color"

    /// 类型图标
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .markdown: return "doc.richtext"
        case .json: return "curlybraces"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    /// 类型显示名称
    var displayName: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .image: return "图片"
        case .file: return "文件"
        case .color: return "颜色"
        }
    }

    /// SF Symbols 图标
    var systemImage: Image {
        Image(systemName: icon)
    }
}

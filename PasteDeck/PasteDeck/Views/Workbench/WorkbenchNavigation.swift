//
//  WorkbenchNavigation.swift
//  PasteDeck
//
//  Defines navigation destinations, view modes, and sorting options
//  for the PasteDeck 2.0 workbench.
//

import Foundation
import SwiftUI

enum WorkbenchDestination: Hashable, Identifiable {
    case history
    case favorites
    case toolCenter
    case recentTools
    case smartCategory(ClipboardContentType)

    var id: String {
        switch self {
        case .history: return "history"
        case .favorites: return "favorites"
        case .toolCenter: return "toolCenter"
        case .recentTools: return "recentTools"
        case .smartCategory(let type): return "category_\(type.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .history: return "剪贴板历史"
        case .favorites: return "收藏夹"
        case .toolCenter: return "工具中心"
        case .recentTools: return "最近工具"
        case .smartCategory(let type):
            switch type {
            case .text: return "文本"
            case .link: return "链接"
            case .image: return "图像"
            case .file: return "文件"
            case .color: return "颜色"
            case .json, .markdown: return "代码"
            }
        }
    }

    var iconName: String {
        switch self {
        case .history: return "doc.on.clipboard"
        case .favorites: return "star"
        case .toolCenter: return "square.grid.2x2"
        case .recentTools: return "clock.arrow.circlepath"
        case .smartCategory(let type):
            switch type {
            case .text: return "doc.text"
            case .link: return "link"
            case .image: return "photo"
            case .file: return "doc"
            case .color: return "paintpalette"
            case .json, .markdown: return "curlybraces"
            }
        }
    }
}

enum WorkbenchViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "列表"
        case .grid: return "网格"
        }
    }

    var iconName: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum WorkbenchSortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "按时间排序"
    case oldestFirst = "最早优先"
    case size = "按大小排序"

    var id: String { rawValue }
}

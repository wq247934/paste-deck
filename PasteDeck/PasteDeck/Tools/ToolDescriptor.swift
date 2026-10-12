//
//  ToolDescriptor.swift
//  PasteDeck
//
//  内置智能工具的元数据与打开上下文。
//

import Foundation
import SwiftUI

/// 工具在搜索结果与上下文面板中展示的稳定元数据。
struct ToolDescriptor: Identifiable, Equatable {
    /// 稳定且唯一的工具 ID，跨版本保持不变。
    let id: String
    /// 展示名称。
    let name: String
    /// SF Symbol 图标名。
    let symbolName: String
    /// 一句话描述。
    let summary: String
    /// 搜索关键词（中英文并存）。
    let keywords: [String]
    /// 高权重别名：用户输入别名时优先命中。
    let aliases: [String]
    /// 独立工具窗口的建议内容尺寸。
    let preferredWindowSize: CGSize
}

/// 工具的打开来源。
enum ToolLaunchSource: Equatable {
    /// 从统一搜索结果打开。
    case search
    /// 从主面板右侧上下文工具面板打开，携带来源卡片。
    case contextCard(itemID: UUID)
    /// 从工作台工具中心直接独立打开。
    case standalone
}

/// 打开工具时传入的上下文：来源、可选来源卡片与预填文本。
struct ToolContext: Equatable {
    let launchSource: ToolLaunchSource
    /// 来源卡片快照；从搜索打开时通常为 nil。
    let sourceItem: ClipboardItemSnapshot?
    /// 预填进工具输入框的文本；nil 表示不预填。
    let prefilledText: String?

    static let standalone = ToolContext(launchSource: .standalone, sourceItem: nil, prefilledText: nil)

    static func standalone(prefill: String? = nil) -> ToolContext {
        ToolContext(launchSource: .standalone, sourceItem: nil, prefilledText: prefill)
    }

    static func forSearch(prefillSuggestion: String? = nil) -> ToolContext {
        ToolContext(launchSource: .search, sourceItem: nil, prefilledText: prefillSuggestion)
    }

    static func forContextCard(_ snapshot: ClipboardItemSnapshot, prefilledText: String?) -> ToolContext {
        ToolContext(
            launchSource: .contextCard(itemID: snapshot.id),
            sourceItem: snapshot,
            prefilledText: prefilledText
        )
    }
}

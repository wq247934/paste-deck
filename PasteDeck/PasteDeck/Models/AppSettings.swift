//
//  AppSettings.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import SwiftData

/// 应用设置模型
@Model
final class AppSettings {
    var launchAtLogin: Bool
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int
    var hotkeyDisplay: String
    var historyCountLimit: Int
    var historyDaysLimit: Int
    var cacheSizeLimit: Int
    /// 应用黑名单的 bundle identifier 列表，用于跳过指定来源应用的剪贴板记录。
    var blacklistedApps: [String]
    var themeMode: Int
    /// 旧版卡片尺寸原始值（0 小、1 中、2 大）；仅为兼容已有 SwiftData 数据保留，主面板布局不再读取。
    var cardSize: Int
    /// 主面板方向原始值（0 横向、1 竖向）；nil 用于兼容尚未保存该设置的旧版本数据。
    var panelOrientationRawValue: Int?
    /// 竖向主面板样式原始值（0 紧凑列表、1 大卡片、2 自适应网格）；nil 用于兼容旧版本数据。
    var verticalPanelStyleRawValue: Int?

    // 百度翻译 API
    var baiduTranslateEnabled: Bool
    var baiduTranslateAppId: String
    var baiduTranslateSecretKey: String
    var baiduTranslateIsAdvanced: Bool

    /// 统计面板历史数据回填完成时间，nil 表示尚未回填。
    var statsBackfilledAt: Date?

    /// 是否在复制公共网页链接后后台获取网页标题；nil 兼容旧版本并按关闭处理。
    var fetchLinkTitles: Bool?

    init() {
        self.launchAtLogin = true
        self.hotkeyKeyCode = 9
        self.hotkeyModifiers = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        self.hotkeyDisplay = "V"
        self.historyCountLimit = 500
        self.historyDaysLimit = 0
        self.cacheSizeLimit = 500
        self.blacklistedApps = []
        self.themeMode = 0
        self.cardSize = 1
        self.panelOrientationRawValue = nil
        self.verticalPanelStyleRawValue = nil
        self.baiduTranslateEnabled = false
        self.baiduTranslateAppId = ""
        self.baiduTranslateSecretKey = ""
        self.baiduTranslateIsAdvanced = false
        self.statsBackfilledAt = nil
        self.fetchLinkTitles = false
    }

    /// 主面板布局方向；nil 或未知原始值按横向处理，确保旧数据库与未来值均能安全回退。
    var panelOrientation: PanelOrientation {
        get {
            guard let rawValue = panelOrientationRawValue,
                  let typed = PanelOrientation(rawValue: rawValue) else {
                return .horizontal
            }

            return typed
        }
        set {
            panelOrientationRawValue = newValue.rawValue
        }
    }

    /// 竖向主面板展示样式；nil 或未知原始值按紧凑列表处理，避免破坏已有设置数据。
    var verticalPanelStyle: VerticalPanelStyle {
        get {
            guard let rawValue = verticalPanelStyleRawValue,
                  let typed = VerticalPanelStyle(rawValue: rawValue) else {
                return .compactList
            }

            return typed
        }
        set {
            verticalPanelStyleRawValue = newValue.rawValue
        }
    }
}

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }
}

/// 主面板内容的排列方向，raw value 作为稳定的 SwiftData 持久化协议，不应调整已有值。
enum PanelOrientation: Int, CaseIterable {
    /// 沿水平方向展示单行卡片。
    case horizontal = 0
    /// 沿垂直方向展示列表或网格。
    case vertical = 1

    var displayName: String {
        switch self {
        case .horizontal: return "横向"
        case .vertical: return "竖向"
        }
    }
}

/// 竖向主面板的内容样式，raw value 作为稳定的 SwiftData 持久化协议，不应调整已有值。
enum VerticalPanelStyle: Int, CaseIterable {
    /// 单列高密度列表，每行突出摘要和元信息。
    case compactList = 0
    /// 单列大尺寸卡片，优先展示内容预览。
    case largeCards = 1
    /// 根据可用宽度在一列与两列之间自动切换的网格。
    case adaptiveGrid = 2

    var displayName: String {
        switch self {
        case .compactList: return "紧凑列表"
        case .largeCards: return "大卡片"
        case .adaptiveGrid: return "自适应网格"
        }
    }
}

/// 旧版主面板卡片尺寸；仅为兼容已有设置数据及相关清理预览保留。
enum CardSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 120
        case .medium: return 160
        case .large: return 200
        }
    }

    var height: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 130
        case .large: return 160
        }
    }
}

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

    /// 是否启用划词后自动打开翻译窗口；nil 兼容旧数据并按关闭处理，避免升级后打扰用户。
    var automaticSelectionTranslationEnabled: Bool?
    /// 是否启用“翻译所选文本”全局快捷键；nil 兼容旧数据并按开启处理。
    var selectionTranslationShortcutEnabled: Bool?
    /// “翻译所选文本”快捷键的 macOS 虚拟键码；nil 时使用 D 键（2）。
    var selectionTranslationKeyCode: Int?
    /// “翻译所选文本”快捷键的 NSEvent 修饰键原始值；nil 时使用 Option。
    var selectionTranslationModifiers: Int?
    /// “翻译所选文本”快捷键的用户可读按键名称；nil 时显示 D。
    var selectionTranslationDisplay: String?
    /// 是否启用截图 OCR 翻译全局快捷键；nil 兼容旧数据并按开启处理。
    var screenshotTranslationShortcutEnabled: Bool?
    /// 截图 OCR 翻译快捷键的 macOS 虚拟键码；nil 时使用 S 键（1）。
    var screenshotTranslationKeyCode: Int?
    /// 截图 OCR 翻译快捷键的 NSEvent 修饰键原始值；nil 时使用 Option。
    var screenshotTranslationModifiers: Int?
    /// 截图 OCR 翻译快捷键的用户可读按键名称；nil 时显示 S。
    var screenshotTranslationDisplay: String?
    /// 是否启用输入翻译全局快捷键；nil 兼容旧数据并按开启处理。
    var inputTranslationShortcutEnabled: Bool?
    /// 输入翻译快捷键的 macOS 虚拟键码；nil 时使用 A 键（0）。
    var inputTranslationKeyCode: Int?
    /// 输入翻译快捷键的 NSEvent 修饰键原始值；nil 时使用 Option。
    var inputTranslationModifiers: Int?
    /// 输入翻译快捷键的用户可读按键名称；nil 时显示 A。
    var inputTranslationDisplay: String?
    /// 当前常规翻译服务商配置的 JSON；nil 时从旧版百度字段生成兼容配置。
    var translationProviderConfigurationJSON: String?
    /// 可配置多套 OpenAI-compatible 大模型端点的 JSON；nil 表示尚未配置大模型。
    var llmTranslationConfigurationsJSON: String?

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
        self.automaticSelectionTranslationEnabled = false
        self.selectionTranslationShortcutEnabled = true
        self.selectionTranslationKeyCode = 2
        self.selectionTranslationModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
        self.selectionTranslationDisplay = "D"
        self.screenshotTranslationShortcutEnabled = true
        self.screenshotTranslationKeyCode = 1
        self.screenshotTranslationModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
        self.screenshotTranslationDisplay = "S"
        self.inputTranslationShortcutEnabled = true
        self.inputTranslationKeyCode = 0
        self.inputTranslationModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
        self.inputTranslationDisplay = "A"
        self.translationProviderConfigurationJSON = nil
        self.llmTranslationConfigurationsJSON = nil
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

    /// 当前常规翻译服务商；优先读取新版 JSON，旧用户则无损沿用百度凭据。
    var translationProviderConfiguration: TranslationProviderConfiguration {
        get {
            if let data = translationProviderConfigurationJSON?.data(using: .utf8),
               let typed = try? JSONDecoder().decode(TranslationProviderConfiguration.self, from: data) {
                return typed
            }

            return TranslationProviderConfiguration(
                kind: .baidu,
                name: "百度翻译",
                enabled: baiduTranslateEnabled,
                credentialId: baiduTranslateAppId,
                credentialSecret: baiduTranslateSecretKey,
                region: "ap-guangzhou",
                allowsConcurrentRequests: baiduTranslateIsAdvanced
            )
        }
        set {
            translationProviderConfigurationJSON = try? String(
                data: JSONEncoder().encode(newValue),
                encoding: .utf8
            )
            if newValue.kind == .baidu {
                baiduTranslateEnabled = newValue.enabled
                baiduTranslateAppId = newValue.credentialId
                baiduTranslateSecretKey = newValue.credentialSecret
                baiduTranslateIsAdvanced = newValue.allowsConcurrentRequests
            }
        }
    }

    /// 所有已配置的大模型端点；损坏或缺失的 JSON 安全回退为空数组。
    var llmTranslationConfigurations: [LLMTranslationConfiguration] {
        get {
            guard let data = llmTranslationConfigurationsJSON?.data(using: .utf8),
                  let typed = try? JSONDecoder().decode([LLMTranslationConfiguration].self, from: data) else {
                return []
            }

            return typed
        }
        set {
            llmTranslationConfigurationsJSON = try? String(
                data: JSONEncoder().encode(newValue),
                encoding: .utf8
            )
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

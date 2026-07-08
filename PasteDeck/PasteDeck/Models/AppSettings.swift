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
    var cardSize: Int

    // 百度翻译 API
    var baiduTranslateEnabled: Bool
    var baiduTranslateAppId: String
    var baiduTranslateSecretKey: String
    var baiduTranslateIsAdvanced: Bool

    /// 统计面板历史数据回填完成时间，nil 表示尚未回填。
    var statsBackfilledAt: Date?

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
        self.baiduTranslateEnabled = false
        self.baiduTranslateAppId = ""
        self.baiduTranslateSecretKey = ""
        self.baiduTranslateIsAdvanced = false
        self.statsBackfilledAt = nil
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

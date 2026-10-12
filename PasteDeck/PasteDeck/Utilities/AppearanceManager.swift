//
//  AppearanceManager.swift
//  PasteDeck
//
//  Manages macOS system appearance resolution for PasteDeck 2.0.
//  In PasteDeck 2.0, the entire app automatically and dynamically follows
//  the native macOS system appearance (light and dark mode).
//

import AppKit
import SwiftUI
import SwiftData

// MARK: - AppTheme 扩展

extension AppTheme {
    /// 对应的 NSAppearance。默认返回 nil（让窗口自动跟随 macOS 系统外观）。
    var nsAppearance: NSAppearance? {
        nil
    }

    /// 用于代码/文本预览等需要显式明暗选项的场合。
    var codePreviewTheme: CodePreviewTheme {
        NSApp.effectiveAppearance.isDark ? .dark : .light
    }
}

extension NSAppearance {
    /// 判断当前外观是否为深色（考虑高对比度等变体）。
    var isDark: Bool {
        let name = self.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        return name == .darkAqua
    }
}

extension Notification.Name {
    /// 兼容已有通知名称引用。
    static let appearanceModeDidChange = Notification.Name("appearanceModeDidChange")
    static let themeStyleDidChange = Notification.Name("themeStyleDidChange")
}

/// 解析系统外观：默认 nil 保证窗口完全跟随 macOS 系统设置。
struct AppearanceResolver {
    static var currentThemeMode: AppTheme {
        .system
    }

    static var currentAppearance: NSAppearance? {
        nil
    }
}

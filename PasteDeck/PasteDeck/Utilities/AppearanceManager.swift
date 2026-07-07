//
//  AppearanceManager.swift
//  PasteDeck
//
//  Centralizes theme → NSAppearance resolution so that the main panel,
//  preview window, and settings window all reflect the user's chosen
//  appearance mode (system / light / dark) consistently.
//
//  Created on 2026-07-07.
//

import AppKit
import SwiftUI
import SwiftData

// MARK: - AppTheme 扩展

extension AppTheme {
    /// 对应的 NSAppearance。`.system` 返回 nil（让窗口跟随 macOS 外观）。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    /// 用于代码/文本预览等需要显式明暗选项的场合。
    var codePreviewTheme: CodePreviewTheme {
        switch self {
        case .system:
            return NSApp.effectiveAppearance.isDark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
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
    /// 设置中的外观模式变更后广播，让已打开的窗口实时更新 appearance。
    static let appearanceModeDidChange = Notification.Name("appearanceModeDidChange")
}

/// 读取当前 AppSettings 外观模式并解析为 NSAppearance。
struct AppearanceResolver {
    /// 从默认 ModelContainer 读取主题模式，失败时回退到 system。
    static var currentThemeMode: AppTheme {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first else {
            return .system
        }
        return AppTheme(rawValue: settings.themeMode) ?? .system
    }

    static var currentAppearance: NSAppearance? {
        currentThemeMode.nsAppearance
    }
}

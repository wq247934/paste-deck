//
//  ThemeStyle.swift
//  PasteDeck
//
//  Defines the visual theme system for PasteDeck: color palettes, font styles,
//  and code preview colors for each theme style across light and dark modes.
//
//  Created on 2026-07-19.
//

import AppKit
import SwiftUI
import SwiftData

// MARK: - Theme Style

/// 应用主题风格枚举；原始值用于 SwiftData 持久化，不应修改已有值。
enum ThemeStyle: Int, CaseIterable {
    case `default` = 0
    case cyber = 1
    case soft = 2
    case film = 3

    var displayName: String {
        switch self {
        case .default: return "跟随系统"
        case .cyber: return "赛博"
        case .soft: return "柔和"
        case .film: return "胶片"
        }
    }

    var iconName: String {
        switch self {
        case .default: return "circle.lefthalf.filled"
        case .cyber: return "cpu"
        case .soft: return "heart.fill"
        case .film: return "film.fill"
        }
    }

    /// 根据当前颜色方案返回对应的完整配色。
    func colors(for colorScheme: ColorScheme) -> ThemeColors {
        switch self {
        case .default:
            return .defaultTheme(for: colorScheme)
        case .cyber:
            return .cyberTheme(for: colorScheme)
        case .soft:
            return .softTheme(for: colorScheme)
        case .film:
            return .filmTheme(for: colorScheme)
        }
    }
}

// MARK: - Theme Colors

/// 一套主题风格的完整配色变量，用于替换硬编码的 accentColor / primary.opacity 等用法。
struct ThemeColors: Equatable {
    // 背景
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundTertiary: Color
    let backgroundMaterial: Color

    // 卡片
    let cardBackground: Color
    let cardBackgroundSelected: Color
    let cardBackgroundMultiSelected: Color
    let cardStroke: Color
    let cardStrokeSelected: Color

    // 文本
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // 强调色
    let accent: Color
    let accentDimmed: Color
    let accentGlow: Color

    // 收藏星标
    let starColor: Color

    // 标签/徽章
    let badgeBackground: Color
    let badgeText: Color

    // 边框/分隔线/阴影
    let border: Color
    let divider: Color
    let shadow: Color

    // 按钮/交互
    let buttonBackgroundHover: Color
    let buttonBackgroundActive: Color
    let buttonBorder: Color

    // 代码预览（仅颜色微调，不高亮主题本身）
    let codeCanvas: Color
    let codeHeader: Color
    let codeBorder: Color
    let codePrimaryText: Color
    let codeSecondaryText: Color
    let codeLineNumber: Color
    let codeSeparator: Color
    let codeAccent: Color
    let codeShadow: Color

    // 字体设计
    let fontDesign: Font.Design
    let cardCornerRadius: CGFloat
}

// MARK: - Default Theme

extension ThemeColors {
    static func defaultTheme(for colorScheme: ColorScheme) -> ThemeColors {
        let isDark = colorScheme == .dark

        let primaryText = isDark ? Color(red: 0.95, green: 0.96, blue: 0.97) : Color.black
        let secondaryText = isDark ? Color(red: 0.65, green: 0.68, blue: 0.72) : Color(red: 0.45, green: 0.48, blue: 0.52)
        let tertiaryText = isDark ? Color(red: 0.45, green: 0.48, blue: 0.52) : Color(red: 0.55, green: 0.58, blue: 0.62)

        let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
        let accentGlow = isDark ? accent.opacity(0.25) : accent.opacity(0.12)

        let cardBg = isDark ? Color(red: 0.11, green: 0.12, blue: 0.14) : Color.white
        let cardStroke = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let divider = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

        let codeCanvas = isDark ? Color(red: 0.055, green: 0.063, blue: 0.09) : Color.white
        let codeHeader = isDark ? Color(red: 0.075, green: 0.085, blue: 0.12) : Color(red: 0.965, green: 0.972, blue: 0.985)
        let codePrimaryText = isDark ? Color(red: 0.88, green: 0.91, blue: 0.96) : Color(red: 0.12, green: 0.14, blue: 0.18)
        let codeSecondaryText = isDark ? Color(red: 0.55, green: 0.60, blue: 0.68) : Color(red: 0.42, green: 0.47, blue: 0.55)
        let codeLineNumber = isDark ? Color(red: 0.36, green: 0.42, blue: 0.50) : Color(red: 0.58, green: 0.64, blue: 0.72)
        let codeSeparator = isDark ? Color(red: 0.22, green: 0.26, blue: 0.32) : Color(red: 0.82, green: 0.85, blue: 0.90)
        let codeAccent = isDark ? Color(red: 0.38, green: 0.72, blue: 1.0) : Color(red: 0.02, green: 0.36, blue: 0.82)

        return ThemeColors(
            backgroundPrimary: isDark ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color(red: 0.97, green: 0.97, blue: 0.97),
            backgroundSecondary: isDark ? Color(red: 0.12, green: 0.13, blue: 0.14) : Color(red: 0.94, green: 0.94, blue: 0.95),
            backgroundTertiary: isDark ? Color(red: 0.16, green: 0.17, blue: 0.18) : Color(red: 0.91, green: 0.91, blue: 0.92),
            backgroundMaterial: isDark ? Color(red: 0.10, green: 0.11, blue: 0.12) : Color(red: 0.98, green: 0.98, blue: 0.98),
            cardBackground: cardBg,
            cardBackgroundSelected: accent.opacity(isDark ? 0.12 : 0.08),
            cardBackgroundMultiSelected: accent.opacity(isDark ? 0.08 : 0.05),
            cardStroke: cardStroke,
            cardStrokeSelected: accent,
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            accent: accent,
            accentDimmed: accent.opacity(0.70),
            accentGlow: accentGlow,
            starColor: Color(red: 1.0, green: 0.80, blue: 0.0),
            badgeBackground: accent.opacity(0.75),
            badgeText: Color.white,
            border: cardStroke,
            divider: divider,
            shadow: isDark ? Color.black.opacity(0.18) : Color.black.opacity(0.08),
            buttonBackgroundHover: isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.045),
            buttonBackgroundActive: isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.075),
            buttonBorder: isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
            codeCanvas: codeCanvas,
            codeHeader: codeHeader,
            codeBorder: isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08),
            codePrimaryText: codePrimaryText,
            codeSecondaryText: codeSecondaryText,
            codeLineNumber: codeLineNumber,
            codeSeparator: codeSeparator,
            codeAccent: codeAccent,
            codeShadow: isDark ? Color.black.opacity(0.18) : Color.black.opacity(0.08),
            fontDesign: .default,
            cardCornerRadius: 12
        )
    }
}

// MARK: - Cyber Theme

extension ThemeColors {
    static func cyberTheme(for colorScheme: ColorScheme) -> ThemeColors {
        let isDark = colorScheme == .dark

        let accent = Color(red: 0.0, green: 0.85, blue: 1.0)
        let accentGlow = Color.cyan.opacity(0.25)

        let primaryText = isDark ? Color(red: 0.90, green: 0.95, blue: 1.0) : Color(red: 0.04, green: 0.08, blue: 0.14)
        let secondaryText = isDark ? Color(red: 0.50, green: 0.65, blue: 0.78) : Color(red: 0.30, green: 0.45, blue: 0.58)
        let tertiaryText = isDark ? Color(red: 0.40, green: 0.50, blue: 0.60) : Color(red: 0.45, green: 0.55, blue: 0.65)

        let bgPrimary = isDark ? Color(red: 0.04, green: 0.06, blue: 0.10) : Color(red: 0.94, green: 0.98, blue: 1.0)
        let cardBg = isDark ? Color(red: 0.06, green: 0.09, blue: 0.14) : Color(red: 0.98, green: 1.0, blue: 1.0)
        let cardStroke = isDark ? Color.cyan.opacity(0.18) : Color.cyan.opacity(0.20)
        let divider = isDark ? Color.cyan.opacity(0.08) : Color.cyan.opacity(0.12)

        let codeCanvas = isDark ? Color(red: 0.03, green: 0.05, blue: 0.08) : Color(red: 0.96, green: 0.99, blue: 1.0)
        let codeHeader = isDark ? Color(red: 0.06, green: 0.08, blue: 0.12) : Color(red: 0.92, green: 0.97, blue: 1.0)

        return ThemeColors(
            backgroundPrimary: bgPrimary,
            backgroundSecondary: isDark ? Color(red: 0.06, green: 0.08, blue: 0.12) : Color(red: 0.90, green: 0.95, blue: 0.98),
            backgroundTertiary: isDark ? Color(red: 0.08, green: 0.11, blue: 0.16) : Color(red: 0.86, green: 0.92, blue: 0.96),
            backgroundMaterial: isDark ? Color(red: 0.05, green: 0.07, blue: 0.10) : Color(red: 0.95, green: 0.98, blue: 1.0),
            cardBackground: cardBg,
            cardBackgroundSelected: accent.opacity(0.10),
            cardBackgroundMultiSelected: accent.opacity(0.06),
            cardStroke: cardStroke,
            cardStrokeSelected: accent,
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            accent: accent,
            accentDimmed: accent.opacity(0.70),
            accentGlow: accentGlow,
            starColor: Color(red: 0.0, green: 0.85, blue: 1.0),
            badgeBackground: accent.opacity(0.85),
            badgeText: Color.black,
            border: cardStroke,
            divider: divider,
            shadow: isDark ? Color.cyan.opacity(0.10) : Color.cyan.opacity(0.06),
            buttonBackgroundHover: isDark ? Color.cyan.opacity(0.10) : Color.cyan.opacity(0.08),
            buttonBackgroundActive: isDark ? Color.cyan.opacity(0.16) : Color.cyan.opacity(0.12),
            buttonBorder: isDark ? Color.cyan.opacity(0.22) : Color.cyan.opacity(0.24),
            codeCanvas: codeCanvas,
            codeHeader: codeHeader,
            codeBorder: isDark ? Color.cyan.opacity(0.12) : Color.cyan.opacity(0.16),
            codePrimaryText: primaryText,
            codeSecondaryText: secondaryText,
            codeLineNumber: isDark ? Color(red: 0.30, green: 0.50, blue: 0.65) : Color(red: 0.55, green: 0.70, blue: 0.80),
            codeSeparator: isDark ? Color.cyan.opacity(0.15) : Color.cyan.opacity(0.20),
            codeAccent: accent,
            codeShadow: isDark ? Color.cyan.opacity(0.12) : Color.cyan.opacity(0.06),
            fontDesign: .monospaced,
            cardCornerRadius: 10
        )
    }
}

// MARK: - Soft Theme

extension ThemeColors {
    static func softTheme(for colorScheme: ColorScheme) -> ThemeColors {
        let isDark = colorScheme == .dark

        let accent = Color(red: 1.0, green: 0.42, blue: 0.62)
        let accentGlow = Color.pink.opacity(0.15)

        let primaryText = isDark ? Color(red: 0.98, green: 0.94, blue: 0.95) : Color(red: 0.16, green: 0.12, blue: 0.14)
        let secondaryText = isDark ? Color(red: 0.75, green: 0.66, blue: 0.70) : Color(red: 0.55, green: 0.46, blue: 0.50)
        let tertiaryText = isDark ? Color(red: 0.60, green: 0.52, blue: 0.55) : Color(red: 0.65, green: 0.56, blue: 0.60)

        let bgPrimary = isDark ? Color(red: 0.16, green: 0.12, blue: 0.14) : Color(red: 1.0, green: 0.97, blue: 0.98)
        let cardBg = isDark ? Color(red: 0.20, green: 0.16, blue: 0.18) : Color(red: 1.0, green: 0.98, blue: 0.99)
        let cardStroke = isDark ? Color.pink.opacity(0.15) : Color.pink.opacity(0.18)
        let divider = isDark ? Color.pink.opacity(0.06) : Color.pink.opacity(0.08)

        let codeCanvas = isDark ? Color(red: 0.18, green: 0.14, blue: 0.16) : Color(red: 1.0, green: 0.98, blue: 0.99)
        let codeHeader = isDark ? Color(red: 0.22, green: 0.17, blue: 0.19) : Color(red: 1.0, green: 0.95, blue: 0.97)

        return ThemeColors(
            backgroundPrimary: bgPrimary,
            backgroundSecondary: isDark ? Color(red: 0.20, green: 0.16, blue: 0.18) : Color(red: 0.98, green: 0.94, blue: 0.96),
            backgroundTertiary: isDark ? Color(red: 0.24, green: 0.19, blue: 0.21) : Color(red: 0.96, green: 0.91, blue: 0.94),
            backgroundMaterial: isDark ? Color(red: 0.18, green: 0.14, blue: 0.16) : Color(red: 1.0, green: 0.98, blue: 0.99),
            cardBackground: cardBg,
            cardBackgroundSelected: accent.opacity(0.10),
            cardBackgroundMultiSelected: accent.opacity(0.06),
            cardStroke: cardStroke,
            cardStrokeSelected: accent,
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            accent: accent,
            accentDimmed: accent.opacity(0.70),
            accentGlow: accentGlow,
            starColor: Color(red: 1.0, green: 0.50, blue: 0.70),
            badgeBackground: accent.opacity(0.85),
            badgeText: Color.white,
            border: cardStroke,
            divider: divider,
            shadow: isDark ? Color.pink.opacity(0.10) : Color.pink.opacity(0.06),
            buttonBackgroundHover: isDark ? Color.pink.opacity(0.10) : Color.pink.opacity(0.08),
            buttonBackgroundActive: isDark ? Color.pink.opacity(0.16) : Color.pink.opacity(0.12),
            buttonBorder: isDark ? Color.pink.opacity(0.18) : Color.pink.opacity(0.22),
            codeCanvas: codeCanvas,
            codeHeader: codeHeader,
            codeBorder: isDark ? Color.pink.opacity(0.10) : Color.pink.opacity(0.14),
            codePrimaryText: primaryText,
            codeSecondaryText: secondaryText,
            codeLineNumber: isDark ? Color(red: 0.70, green: 0.55, blue: 0.62) : Color(red: 0.80, green: 0.65, blue: 0.72),
            codeSeparator: isDark ? Color.pink.opacity(0.12) : Color.pink.opacity(0.16),
            codeAccent: accent,
            codeShadow: isDark ? Color.pink.opacity(0.10) : Color.pink.opacity(0.06),
            fontDesign: .rounded,
            cardCornerRadius: 14
        )
    }
}

// MARK: - Film Theme

extension ThemeColors {
    static func filmTheme(for colorScheme: ColorScheme) -> ThemeColors {
        let isDark = colorScheme == .dark

        let accent = Color(red: 1.0, green: 0.62, blue: 0.26)
        let accentGlow = Color.orange.opacity(0.15)

        let primaryText = isDark ? Color(red: 0.95, green: 0.90, blue: 0.84) : Color(red: 0.18, green: 0.14, blue: 0.10)
        let secondaryText = isDark ? Color(red: 0.75, green: 0.68, blue: 0.58) : Color(red: 0.55, green: 0.46, blue: 0.36)
        let tertiaryText = isDark ? Color(red: 0.60, green: 0.54, blue: 0.46) : Color(red: 0.65, green: 0.56, blue: 0.46)

        let bgPrimary = isDark ? Color(red: 0.10, green: 0.08, blue: 0.06) : Color(red: 0.97, green: 0.95, blue: 0.91)
        let cardBg = isDark ? Color(red: 0.14, green: 0.11, blue: 0.08) : Color(red: 0.99, green: 0.97, blue: 0.94)
        let cardStroke = isDark ? Color(red: 0.40, green: 0.30, blue: 0.20) : Color(red: 0.80, green: 0.72, blue: 0.60)
        let divider = isDark ? Color(red: 0.35, green: 0.28, blue: 0.20) : Color(red: 0.85, green: 0.78, blue: 0.66)

        let codeCanvas = isDark ? Color(red: 0.11, green: 0.09, blue: 0.07) : Color(red: 0.98, green: 0.96, blue: 0.93)
        let codeHeader = isDark ? Color(red: 0.15, green: 0.12, blue: 0.09) : Color(red: 0.95, green: 0.93, blue: 0.89)

        return ThemeColors(
            backgroundPrimary: bgPrimary,
            backgroundSecondary: isDark ? Color(red: 0.14, green: 0.11, blue: 0.08) : Color(red: 0.94, green: 0.91, blue: 0.86),
            backgroundTertiary: isDark ? Color(red: 0.18, green: 0.14, blue: 0.10) : Color(red: 0.91, green: 0.88, blue: 0.82),
            backgroundMaterial: isDark ? Color(red: 0.12, green: 0.10, blue: 0.07) : Color(red: 0.98, green: 0.96, blue: 0.93),
            cardBackground: cardBg,
            cardBackgroundSelected: accent.opacity(0.10),
            cardBackgroundMultiSelected: accent.opacity(0.06),
            cardStroke: cardStroke,
            cardStrokeSelected: accent,
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            accent: accent,
            accentDimmed: accent.opacity(0.70),
            accentGlow: accentGlow,
            starColor: Color(red: 1.0, green: 0.62, blue: 0.26),
            badgeBackground: accent.opacity(0.85),
            badgeText: Color.black,
            border: cardStroke,
            divider: divider,
            shadow: isDark ? Color.orange.opacity(0.10) : Color.orange.opacity(0.06),
            buttonBackgroundHover: isDark ? Color(red: 0.25, green: 0.20, blue: 0.14) : Color(red: 0.92, green: 0.88, blue: 0.80),
            buttonBackgroundActive: isDark ? Color(red: 0.30, green: 0.24, blue: 0.17) : Color(red: 0.88, green: 0.84, blue: 0.75),
            buttonBorder: isDark ? Color(red: 0.45, green: 0.35, blue: 0.25) : Color(red: 0.82, green: 0.75, blue: 0.64),
            codeCanvas: codeCanvas,
            codeHeader: codeHeader,
            codeBorder: isDark ? Color(red: 0.40, green: 0.30, blue: 0.20) : Color(red: 0.80, green: 0.72, blue: 0.60),
            codePrimaryText: primaryText,
            codeSecondaryText: secondaryText,
            codeLineNumber: isDark ? Color(red: 0.65, green: 0.55, blue: 0.45) : Color(red: 0.75, green: 0.65, blue: 0.55),
            codeSeparator: isDark ? Color(red: 0.40, green: 0.30, blue: 0.20) : Color(red: 0.82, green: 0.74, blue: 0.62),
            codeAccent: accent,
            codeShadow: isDark ? Color.orange.opacity(0.10) : Color.orange.opacity(0.06),
            fontDesign: .serif,
            cardCornerRadius: 8
        )
    }
}

// MARK: - Theme Resolver

/// 读取当前 AppSettings 中的主题风格并解析为 ThemeColors。
struct ThemeResolver {
    static var currentThemeStyle: ThemeStyle {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first else {
            return .default
        }
        return ThemeStyle(rawValue: settings.themeStyle ?? 0) ?? .default
    }
}

// MARK: - Theme Store

/// 全局共享的主题风格状态：创建时及设置变更后从 AppSettings 读取，
/// 供各窗口根视图经 `themeStyled()` 注入 SwiftUI environment。
@MainActor
final class ThemeStyleStore: ObservableObject {
    static let shared = ThemeStyleStore()

    @Published private(set) var style: ThemeStyle

    private init() {
        style = ThemeResolver.currentThemeStyle
        _ = NotificationCenter.default.addObserver(
            forName: .themeStyleDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    private func reload() {
        style = ThemeResolver.currentThemeStyle
    }
}

/// 把当前主题风格注入 environment 的根修饰符。除 `themeColors` 外，
/// 还让系统控件（开关、选择器、输入框焦点等）跟随主题强调色。
private struct ThemeStyledModifier: ViewModifier {
    @ObservedObject private var store = ThemeStyleStore.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .tint(store.style.colors(for: colorScheme).accent)
            .environment(\.themeStyle, store.style)
    }
}

extension View {
    /// 在窗口或独立 NSHostingView 承载的视图根上应用，
    /// 使整棵视图树使用设置中选中的主题风格并随设置实时更新。
    func themeStyled() -> some View {
        modifier(ThemeStyledModifier())
    }
}

// MARK: - Environment

private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue: ThemeStyle = .default
}

extension EnvironmentValues {
    var themeStyle: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }

    var themeColors: ThemeColors {
        self[ThemeStyleKey.self].colors(for: colorScheme)
    }
}

extension ColorScheme {
    static func from(appearance: NSAppearance?) -> ColorScheme {
        guard let appearance else {
            return NSApp.effectiveAppearance.isDark ? .dark : .light
        }
        return appearance.isDark ? .dark : .light
    }
}

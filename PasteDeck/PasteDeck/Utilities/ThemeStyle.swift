//
//  ThemeStyle.swift
//  PasteDeck
//
//  Unified native macOS design tokens for PasteDeck 2.0.
//  Clean semantic colors automatically adapting to system light/dark appearance,
//  with the signature PasteDeck orange brand accent.
//

import AppKit
import SwiftUI
import SwiftData

// MARK: - Theme Style

/// 应用主题风格枚举；保留原始值用于兼容已有 SwiftData 数据库，统一指向原生设计。
enum ThemeStyle: Int, CaseIterable, Identifiable {
    case `default` = 0
    case cyber = 1
    case soft = 2
    case film = 3

    var id: Int { rawValue }

    var displayName: String {
        "原生系统"
    }

    var iconName: String {
        "circle.lefthalf.filled"
    }

    /// 返回统一的原生 macOS 配色方案（自动适配浅色与深色模式）。
    func colors(for colorScheme: ColorScheme) -> ThemeColors {
        .nativeTheme(for: colorScheme)
    }
}

// MARK: - Theme Colors

/// 统一的语义设计令牌，保证文字对比度、焦点可见性与系统原生材质协同。
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

    // 代码预览
    let codeCanvas: Color
    let codeHeader: Color
    let codeBorder: Color
    let codePrimaryText: Color
    let codeSecondaryText: Color
    let codeLineNumber: Color
    let codeSeparator: Color
    let codeAccent: Color
    let codeShadow: Color

    // 字体与圆角
    let fontDesign: Font.Design
    let cardCornerRadius: CGFloat
}

// MARK: - Native Theme

extension ThemeColors {
    static func defaultTheme(for colorScheme: ColorScheme) -> ThemeColors {
        nativeTheme(for: colorScheme)
    }

    static func nativeTheme(for colorScheme: ColorScheme) -> ThemeColors {
        let isDark = colorScheme == .dark

        // PasteDeck 统一品牌强调色
        let accent = Color(red: 1.0, green: 0.45, blue: 0.08)
        let accentGlow = accent.opacity(isDark ? 0.20 : 0.12)

        let primaryText = isDark ? Color(red: 0.95, green: 0.96, blue: 0.97) : Color(red: 0.12, green: 0.13, blue: 0.14)
        let secondaryText = isDark ? Color(red: 0.65, green: 0.68, blue: 0.72) : Color(red: 0.46, green: 0.48, blue: 0.52)
        let tertiaryText = isDark ? Color(red: 0.45, green: 0.48, blue: 0.52) : Color(red: 0.60, green: 0.62, blue: 0.65)

        let cardBg = isDark ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color.white
        let cardStroke = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let divider = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

        let codeCanvas = isDark ? Color(red: 0.08, green: 0.09, blue: 0.11) : Color(red: 0.98, green: 0.98, blue: 0.99)
        let codeHeader = isDark ? Color(red: 0.10, green: 0.11, blue: 0.13) : Color(red: 0.95, green: 0.95, blue: 0.97)
        let codePrimaryText = isDark ? Color(red: 0.88, green: 0.91, blue: 0.96) : Color(red: 0.12, green: 0.14, blue: 0.18)
        let codeSecondaryText = isDark ? Color(red: 0.55, green: 0.60, blue: 0.68) : Color(red: 0.42, green: 0.47, blue: 0.55)
        let codeLineNumber = isDark ? Color(red: 0.38, green: 0.43, blue: 0.50) : Color(red: 0.58, green: 0.63, blue: 0.70)
        let codeSeparator = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let codeAccent = accent

        return ThemeColors(
            backgroundPrimary: isDark ? Color(red: 0.09, green: 0.10, blue: 0.11) : Color(red: 0.97, green: 0.97, blue: 0.98),
            backgroundSecondary: isDark ? Color(red: 0.13, green: 0.14, blue: 0.15) : Color(red: 0.94, green: 0.94, blue: 0.95),
            backgroundTertiary: isDark ? Color(red: 0.16, green: 0.17, blue: 0.18) : Color(red: 0.91, green: 0.91, blue: 0.92),
            backgroundMaterial: isDark ? Color(red: 0.11, green: 0.12, blue: 0.13) : Color(red: 0.98, green: 0.98, blue: 0.99),
            cardBackground: cardBg,
            cardBackgroundSelected: accent.opacity(isDark ? 0.15 : 0.10),
            cardBackgroundMultiSelected: accent.opacity(isDark ? 0.09 : 0.06),
            cardStroke: cardStroke,
            cardStrokeSelected: accent,
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            accent: accent,
            accentDimmed: accent.opacity(0.75),
            accentGlow: accentGlow,
            starColor: Color(red: 1.0, green: 0.55, blue: 0.1),
            badgeBackground: accent.opacity(0.15),
            badgeText: accent,
            border: cardStroke,
            divider: divider,
            shadow: isDark ? Color.black.opacity(0.25) : Color.black.opacity(0.06),
            buttonBackgroundHover: isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
            buttonBackgroundActive: isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
            buttonBorder: isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
            codeCanvas: codeCanvas,
            codeHeader: codeHeader,
            codeBorder: isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
            codePrimaryText: codePrimaryText,
            codeSecondaryText: codeSecondaryText,
            codeLineNumber: codeLineNumber,
            codeSeparator: codeSeparator,
            codeAccent: codeAccent,
            codeShadow: isDark ? Color.black.opacity(0.20) : Color.black.opacity(0.06),
            fontDesign: .default,
            cardCornerRadius: 10
        )
    }
}

// MARK: - Theme Resolver

struct ThemeResolver {
    static var currentThemeStyle: ThemeStyle {
        .default
    }
}

// MARK: - Theme Store

@MainActor
final class ThemeStyleStore: ObservableObject {
    static let shared = ThemeStyleStore()

    @Published private(set) var style: ThemeStyle = .default
}

// MARK: - View Modifier

private struct ThemeStyledModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .tint(ThemeColors.nativeTheme(for: colorScheme).accent)
            .environment(\.themeStyle, .default)
    }
}

extension View {
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
        ThemeColors.nativeTheme(for: colorScheme)
    }
}

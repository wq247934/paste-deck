import AgentSpeedCore
import SwiftUI

/// Colors of the history window, tuned for the window background in both appearances. Secondary text keeps at least
/// 4.5:1 contrast (DESIGN section 7); Increase Contrast strengthens strokes and grid lines.
enum HistoryPalette {
    static func secondary(dark: Bool, increasedContrast: Bool) -> Color {
        DashboardPalette.secondary(dark: dark, increasedContrast: increasedContrast)
    }

    static func cardFill(dark: Bool) -> Color {
        if #available(macOS 26, *) {
            return dark ? Color.white.opacity(0.06) : Color.black.opacity(0.036)
        }
        return dark ? Color.white.opacity(0.05) : Color.black.opacity(0.028)
    }

    static func cardStroke(dark: Bool, increasedContrast: Bool) -> Color {
        let base = dark ? Color.white : Color.black
        return base.opacity(increasedContrast ? 0.4 : (dark ? 0.09 : 0.07))
    }

    static func grid(dark: Bool, increasedContrast: Bool) -> Color {
        let base = dark ? Color.white : Color.black
        return base.opacity(increasedContrast ? 0.3 : (dark ? 0.1 : 0.08))
    }

    static func monthRule(dark: Bool, increasedContrast: Bool) -> Color {
        let base = dark ? Color.white : Color.black
        return base.opacity(increasedContrast ? 0.45 : (dark ? 0.2 : 0.16))
    }

    /// The average-speed line: the label color, slightly softened.
    static func ink(dark: Bool, increasedContrast: Bool) -> Color {
        dark ? Color.white.opacity(increasedContrast ? 1 : 0.86) : Color.black.opacity(increasedContrast ? 0.92 : 0.78)
    }

    static func positive(dark: Bool) -> Color {
        dark ? RGBColor(hex: 0x3FC56B).color : RGBColor(hex: 0x1A7F37).color
    }

    static func negative(dark: Bool) -> Color {
        dark ? RGBColor(hex: 0xFF6B61).color : RGBColor(hex: 0xC4232F).color
    }

    /// Row tints of the daily table.
    static func stripe(dark: Bool) -> Color { (dark ? Color.white : Color.black).opacity(dark ? 0.035 : 0.025) }
    static func hover(dark: Bool) -> Color { (dark ? Color.white : Color.black).opacity(dark ? 0.08 : 0.055) }
    static func pressed(dark: Bool) -> Color { (dark ? Color.white : Color.black).opacity(dark ? 0.13 : 0.09) }

    /// The tint of sparklines and single-source marks: the source color, else the accent color.
    static func tint(_ source: SourceKind?, dark: Bool) -> Color {
        source?.tint(dark: dark) ?? Color.accentColor
    }
}

enum HistoryLayout {
    static let outerPadding = Spacing.xl
    static let sectionSpacing = Spacing.l
    static let cardSpacing = Spacing.s
    static let cardRadius: CGFloat = 12
    static let chartHeight: CGFloat = 260
    static let rowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 34
    /// From 860 pt of content width the five summary cards share one row, narrower they wrap 3 + 2 (DESIGN 9); the
    /// threshold leaves room for a legacy scroll bar, so the default window (872 pt of content) always qualifies.
    static let wideCards: CGFloat = 840
    static let tooltipWidth: CGFloat = 268
}

enum HistoryFont {
    static let title = Font.system(size: 26, weight: .bold)
    static let subtitle = Font.system(size: 13).monospacedDigit()
    static let cardLabel = Font.system(size: 12, weight: .medium)
    static let cardValue = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let cardUnit = Font.system(size: 13, weight: .medium)
    static let cardNote = Font.system(size: 11.5).monospacedDigit()
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let legend = Font.system(size: 11)
    static let axis = Font.system(size: 10.5).monospacedDigit()
    static let header = Font.system(size: 11, weight: .semibold)
    static let cell = Font.system(size: 12.5).monospacedDigit()
    static let tooltipTitle = Font.system(size: 12, weight: .semibold)
    static let tooltip = Font.system(size: 11.5).monospacedDigit()
    static let footer = Font.system(size: 11.5).monospacedDigit()
}

/// The rounded panel behind summary cards and the chart.
struct HistoryCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let increasedContrast = contrast == .increased
        let shape = RoundedRectangle(cornerRadius: HistoryLayout.cardRadius, style: .continuous)
        // macOS 26 draws content panels as quiet fills without outlines; the outline returns with Increase Contrast.
        let outlined = Self.usesOutline || increasedContrast
        content
            .background(shape.fill(HistoryPalette.cardFill(dark: dark)))
            .overlay {
                if outlined {
                    shape.strokeBorder(HistoryPalette.cardStroke(dark: dark, increasedContrast: increasedContrast), lineWidth: 1)
                }
            }
    }

    private static var usesOutline: Bool {
        if #available(macOS 26, *) { return false }
        return true
    }
}

/// Secondary text that keeps 4.5:1 contrast on the window background.
struct HistorySecondaryStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        HistoryPalette.secondary(
            dark: environment.colorScheme == .dark,
            increasedContrast: environment.colorSchemeContrast == .increased
        )
    }
}

extension ShapeStyle where Self == HistorySecondaryStyle {
    static var historySecondary: HistorySecondaryStyle { HistorySecondaryStyle() }
}

extension View {
    func historyCard() -> some View { modifier(HistoryCardBackground()) }
}

/// `進行中` in a small accent capsule: today's figures are still growing.
struct InProgressBadge: View {
    let l10n: Localizer

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(l10n("history.inProgress"))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.accentColor.opacity(contrast == .increased ? 0.22 : 0.14)))
            .overlay {
                if contrast == .increased {
                    Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
    }
}

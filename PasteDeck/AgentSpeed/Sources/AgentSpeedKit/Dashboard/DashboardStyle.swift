import SwiftUI

/// Layout constants of the dashboard popover (DESIGN section 4).
enum DashboardLayout {
    static let padding = Spacing.l
    static let sectionSpacing = Spacing.m
    static let rowSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 20
    static let headerSpacing = Spacing.s
    static let orbDiameter: CGFloat = 112
    static let chartHeight: CGFloat = 96
    /// Right gutter of the chart holding the y-axis labels.
    static let chartGutter: CGFloat = 30
    /// Right-aligned tok/s column shared by sources and agents so every live number lines up.
    static let speedColumn: CGFloat = 48
    static let tokensColumn: CGFloat = 52
    static let badgeWidth: CGFloat = 16
    static let subagentIndent: CGFloat = 12
    /// Deeper sub-agents share the last indent.
    static let maxAgentDepth = 2
    /// Agent rows of the collapsed list.
    static let maxAgents = 6
    /// Agent rows the expanded list shows before it scrolls.
    static let maxExpandedAgents = 12

    /// Height of `rows` agent rows stacked at `rowSpacing`.
    static func agentListHeight(rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing : 0
    }
}

enum DashboardFont {
    static let heroValue = Font.system(size: 44, weight: .bold).monospacedDigit()
    static let heroUnit = Font.system(size: 15, weight: .medium)
    static let tier = Font.system(size: 12, weight: .semibold)
    static let context = Font.system(size: 12).monospacedDigit()
    static let row = Font.system(size: 13)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let rowNumber = Font.system(size: 13, weight: .medium).monospacedDigit()
    static let detail = Font.system(size: 11).monospacedDigit()
    static let caption = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let metricValue = Font.system(size: 17, weight: .semibold).monospacedDigit()
    static let metricUnit = Font.system(size: 11, weight: .medium)
    static let chartLabel = Font.system(size: 10, weight: .semibold).monospacedDigit()
    static let chartUnit = Font.system(size: 8.5, weight: .medium)
    static let note = Font.system(size: 11)
}

/// Section title: small tracked caps for Latin, plain semibold for CJK.
struct SectionTitle: View {
    let text: String
    let latin: Bool

    var body: some View {
        Text(text)
            .font(.system(size: latin ? 11 : 12, weight: .semibold))
            .textCase(latin ? .uppercase : nil)
            .tracking(latin ? 0.7 : 0.2)
            .foregroundStyle(.dashboardSecondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Column caption aligned with a fixed-width numeric column.
struct ColumnCaption: View {
    let text: String
    let width: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.dashboardSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

/// A one-pixel separator in the system separator color.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

struct SectionDivider: View {
    var body: some View {
        Hairline().padding(.vertical, DashboardLayout.sectionSpacing)
    }
}

extension AgentSpeedModel {
    /// Layout spring, or a crossfade under Reduce Motion.
    var dashboardMotion: Animation { accessibility.reduceMotion ? Motion.fade : Motion.layout }

    /// Layout spring for sizes and positions; nil under Reduce Motion, where the layout changes at once and only
    /// opacity fades.
    var dashboardResizeMotion: Animation? { accessibility.reduceMotion ? nil : Motion.layout }

    var dashboardLatinCaps: Bool { l10n.language.usesLatinCase }
}

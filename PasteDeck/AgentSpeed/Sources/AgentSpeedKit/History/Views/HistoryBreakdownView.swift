import AgentSpeedCore
import AppKit
import SwiftUI

/// Takes the daily chart's place for a single day (DESIGN 4b, item 1): one horizontal bar per source (all sources) or
/// per model (one source), most output first, with output, share of the day and average speed. Bars are scaled to the
/// largest one. Today's bars wear the chart's in-progress hatching. A source row opens that source's model breakdown.
struct HistoryBreakdownCard: View {
    let breakdown: DayBreakdown
    let today: DayKey
    /// The selected source: its color paints every model bar, as in the chart tooltip's model shares.
    let source: SourceKind?
    let money: HistoryMoney
    let l10n: Localizer
    let reduceMotion: Bool
    /// Output or cost sorts and sizes the bars (DESIGN 9).
    @Binding var metric: HistoryChartMetric
    let onSelectSource: (SourceKind) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = colorScheme == .dark
        let columns = BreakdownColumns(names: breakdown.items.map { HistoryText.breakdownName($0.subject, l10n) })
        let inProgress = breakdown.day == today
        // Bars spring to their new lengths; under Reduce Motion the rows crossfade instead.
        let identity = reduceMotion ? "\(breakdown.day)-\(breakdown.kind)-\(breakdown.metric)-\(source?.rawValue ?? "all")" : "breakdown"
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            header(columns: columns, inProgress: inProgress)
            if breakdown.isEmpty {
                Text(l10n("history.empty"))
                    .font(HistoryFont.cell)
                    .foregroundStyle(.historySecondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                VStack(spacing: 0) {
                    ForEach(breakdown.items) { item in
                        row(item, columns: columns, inProgress: inProgress, dark: dark)
                            .transition(.opacity)
                    }
                }
                .id(identity)
                .transition(.opacity)
                .animation(reduceMotion ? nil : HistoryMotion.chart, value: breakdown)
            }
        }
        .animation(reduceMotion ? HistoryMotion.fade : nil, value: identity)
        .padding(.horizontal, Spacing.xs)
        .padding(.top, 14)
        .padding(.bottom, Spacing.xs)
        .historyCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n(breakdown.titleKey))
        .accessibilityChartDescriptor(HistoryBreakdownDescriptor(breakdown: breakdown, money: money, l10n: l10n))
    }

    /// The title (with 進行中 for today) over the names, the column captions over the numbers.
    private func header(columns: BreakdownColumns, inProgress: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BreakdownColumns.spacing) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Picker(l10n(breakdown.metric.titleKey), selection: $metric) {
                    ForEach(HistoryChartMetric.allCases) { metric in
                        Text(l10n(metric.titleKey)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                Text(l10n(breakdown.titleKey))
                    .font(HistoryFont.sectionTitle)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                if inProgress {
                    InProgressBadge(l10n: l10n)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(l10n("history.table.output"))
                    .frame(width: BreakdownColumns.output, alignment: .trailing)
                Text(l10n("history.table.cost"))
                    .frame(width: BreakdownColumns.cost, alignment: .trailing)
                Text(l10n("mac.history.breakdown.share"))
                    .frame(width: BreakdownColumns.share, alignment: .trailing)
                Text(l10n("history.table.speed"))
                    .frame(width: BreakdownColumns.speed, alignment: .trailing)
            }
            .font(HistoryFont.header)
            .foregroundStyle(.historySecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, BreakdownColumns.inset)
        .padding(.bottom, Spacing.xxs)
    }

    @ViewBuilder
    private func row(_ item: BreakdownItem, columns: BreakdownColumns, inProgress: Bool, dark: Bool) -> some View {
        let name = HistoryText.breakdownName(item.subject, l10n)
        let value = HistoryText.accessible(item, money: money, l10n)
        let content = BreakdownRowContent(
            item: item,
            name: name,
            tint: tint(item.subject, dark: dark),
            columns: columns,
            inProgress: inProgress,
            increasedContrast: contrast == .increased,
            money: money,
            l10n: l10n
        )
        if case .source(let kind) = item.subject {
            let hint = l10n("mac.history.breakdown.sourceHint")
            Button {
                onSelectSource(kind)
            } label: {
                content
            }
            .buttonStyle(BreakdownRowButtonStyle())
            .help("\(value)\n\(hint)")
            .accessibilityLabel(name)
            .accessibilityValue(value)
            .accessibilityHint(hint)
        } else {
            content
                .help(value)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(value)
        }
    }

    /// Sources in their own colors; models in the selected source's color; other models in a neutral grey.
    private func tint(_ subject: BreakdownItem.Subject, dark: Bool) -> Color {
        switch subject {
        case .source(let kind): kind.tint(dark: dark)
        case .model: HistoryPalette.tint(source, dark: dark)
        case .otherModels: HistoryPalette.secondary(dark: dark, increasedContrast: false).opacity(0.7)
        }
    }
}

/// Column widths shared by the header and the rows; the name column fits the longest name, within limits.
struct BreakdownColumns {
    static let inset: CGFloat = Spacing.xs
    static let spacing: CGFloat = Spacing.s
    static let output: CGFloat = 60
    static let cost: CGFloat = 80
    static let share: CGFloat = 44
    static let speed: CGFloat = 92
    static let swatch: CGFloat = 9
    static let swatchSpacing: CGFloat = 7

    let name: CGFloat

    init(names: [String]) {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let widest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        name = (ceil(widest) + Self.swatch + Self.swatchSpacing + 2).clamped(to: 120...210)
    }
}

/// Swatch and name, the bar, then output, share and speed in fixed columns.
private struct BreakdownRowContent: View {
    let item: BreakdownItem
    let name: String
    let tint: Color
    let columns: BreakdownColumns
    let inProgress: Bool
    let increasedContrast: Bool
    let money: HistoryMoney
    let l10n: Localizer

    var body: some View {
        HStack(spacing: BreakdownColumns.spacing) {
            HStack(spacing: BreakdownColumns.swatchSpacing) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(tint)
                    .frame(width: BreakdownColumns.swatch, height: BreakdownColumns.swatch)
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: columns.name, alignment: .leading)
            BreakdownBar(scale: item.scale, tint: tint, inProgress: inProgress, increasedContrast: increasedContrast)
                .frame(height: 12)
                .frame(maxWidth: .infinity)
                .help(item.traffic.map { TrafficText(l10n: l10n, bits: false).pair($0) } ?? "")
            Text(SpeedFormat.tokens(item.output))
                .font(HistoryFont.cell)
                .frame(width: BreakdownColumns.output, alignment: .trailing)
            cost
                .frame(width: BreakdownColumns.cost, alignment: .trailing)
            Text(HistoryText.percent(item.share))
                .font(HistoryFont.cell)
                .foregroundStyle(.historySecondary)
                .frame(width: BreakdownColumns.share, alignment: .trailing)
            speed
                .frame(width: BreakdownColumns.speed, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, BreakdownColumns.inset)
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    /// The cost cell: amount (with a small `≥`), `–`, or the subscription tag, quiet when not priced.
    private var cost: some View {
        let text = money.display(item.cost, subscriptionTag: l10n("cost.subscription.tag"))
        let quiet = item.cost.sortValue == nil
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            if text.hasPrefix("≥") {
                Text(verbatim: "≥")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.historySecondary)
            }
            Text(text.hasPrefix("≥") ? String(text.dropFirst()) : text)
                .font(quiet && text != "–" ? .system(size: 11.5) : HistoryFont.cell)
                .foregroundStyle(quiet ? AnyShapeStyle(.historySecondary) : AnyShapeStyle(.primary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .help(HistoryTable.costTooltip(item.cost, money: money, l10n) ?? text)
    }

    @ViewBuilder
    private var speed: some View {
        if let value = item.averageSpeed {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(SpeedFormat.speed(value))
                    .font(HistoryFont.cell)
                Text(l10n("unit.tokS"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.historySecondary)
            }
        } else {
            Text(verbatim: "–")
                .font(HistoryFont.cell)
                .foregroundStyle(.historySecondary)
                .help(l10n("history.noSpeed"))
        }
    }
}

/// A rounded bar scaled to the largest item; today's is lighter and hatched, like the chart's in-progress bar.
private struct BreakdownBar: View {
    let scale: Double
    let tint: Color
    let inProgress: Bool
    let increasedContrast: Bool

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            let width = scale > 0 ? max(4, proxy.size.width * CGFloat(scale.clamped(to: 0...1))) : 0
            shape
                .fill(LinearGradient(colors: [tint, tint.opacity(0.74)], startPoint: .leading, endPoint: .trailing))
                .opacity(inProgress ? 0.5 : 1)
                .overlay {
                    if inProgress {
                        Hatching(color: tint.opacity(0.9))
                            .clipShape(shape)
                    }
                }
                .overlay {
                    if increasedContrast {
                        shape.strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(width: width)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// Diagonal stripes, as on today's bar in the daily chart.
private struct Hatching: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var stripes = Path()
            let spacing: CGFloat = 4.5
            var offset = -size.height
            while offset < size.width + size.height {
                stripes.move(to: CGPoint(x: offset, y: size.height))
                stripes.addLine(to: CGPoint(x: offset + size.height, y: 0))
                offset += spacing
            }
            context.stroke(stripes, with: .color(color), lineWidth: 1.2)
        }
    }
}

/// Source rows: a hover and pressed tint like the daily table's rows.
private struct BreakdownRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BreakdownRowSurface(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct BreakdownRowSurface<Label: View>: View {
    let pressed: Bool
    @ViewBuilder let label: () -> Label

    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        label()
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(pressed ? HistoryPalette.pressed(dark: dark) : HistoryPalette.hover(dark: dark))
                    .opacity(hovered || pressed ? 1 : 0)
            }
            .onHover { hovered = $0 }
            .animation(HistoryMotion.fade, value: hovered)
    }
}

import AgentSpeedCore
import AppKit
import SwiftUI

/// Column titles; a click sorts by the column, again flips the order. Stays pinned while the rows scroll under it.
struct DailyTableHeader: View {
    let columns: [HistoryColumn]
    let widths: [CGFloat]
    var gap: CGFloat = HistoryColumnLayout.gap
    let sort: HistorySort
    let l10n: Localizer
    let onSort: (HistoryColumn) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.element) { index, column in
                header(column, width: widths[safe: index] ?? 60)
            }
        }
        .padding(.horizontal, DailyTableRow.inset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                .background(.bar)
                .padding(.horizontal, -HistoryLayout.outerPadding)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func header(_ column: HistoryColumn, width: CGFloat) -> some View {
        let title = l10n(column.headerKey)
        let active = sort.column == column
        // Only the sorted column carries its chevron, on the side away from the alignment edge, so the title never
        // moves and narrow columns keep their full width for the title.
        let indicator = Image(systemName: sort.descending ? "chevron.down" : "chevron.up")
            .font(.system(size: 8, weight: .bold))
        return Button {
            onSort(column)
        } label: {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                if column.isNumeric {
                    Spacer(minLength: 0)
                    if active { indicator }
                }
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(column.isNumeric ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !column.isNumeric {
                    if active { indicator }
                    Spacer(minLength: 0)
                }
            }
            .font(HistoryFont.header)
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.historySecondary))
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(active ? l10n(sort.descending ? "mac.history.sorted.desc" : "mac.history.sorted.asc") : "")
        .accessibilityAddTraits(active ? [.isHeader, .isSelected] : .isHeader)
    }
}

extension View {
    /// Keeps the view at the top of its scroll view once it would scroll past it, like a pinned section header. The
    /// offset is applied while drawing, so scrolling never changes state or layout.
    func stickyInScrollView() -> some View {
        visualEffect { content, geometry in
            content.offset(y: max(0, -geometry.frame(in: .scrollView).minY))
        }
    }
}

/// One day of the table: tabular digits, numbers right-aligned, a subtle tint on every other row, hover linked with
/// the chart, and a 1.2 s flash when the chart reveals it.
struct DailyTableRow: View {
    static let inset: CGFloat = 10

    let row: DaySummary
    let index: Int
    let columns: [HistoryColumn]
    let widths: [CGFloat]
    var gap: CGFloat = HistoryColumnLayout.gap
    let today: DayKey
    let money: HistoryMoney
    let l10n: Localizer
    let interaction: HistoryInteraction
    let tableFocused: Bool
    let onSelect: (DayKey) -> Void
    let onCopy: (DayKey) -> Void

    var body: some View {
        let selected = interaction.selection.contains(row.day)
        let emphasized = selected && tableFocused
        HStack(spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.element) { position, column in
                cell(column, emphasized: emphasized)
                    .frame(width: widths[safe: position] ?? 60, alignment: column.isNumeric ? .trailing : .leading)
            }
        }
        .padding(.horizontal, Self.inset)
        .frame(height: HistoryLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RowHighlight(mark: interaction.mark(for: row.day), striped: !index.isMultiple(of: 2), selected: selected,
                         emphasized: emphasized)
        }
        .background { FlashHighlight(day: row.day, interaction: interaction) }
        .contentShape(Rectangle())
        .onHover { inside in
            interaction.trackTableHover(row.day, inside: inside)
        }
        .onTapGesture { onSelect(row.day) }
        .contextMenu {
            Button(l10n("mac.history.copy")) { onCopy(row.day) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryText.dayTitle(row.day, today: today, l10n))
        .accessibilityValue(HistoryText.accessible(row, today: today, money: money, traffic: columns.contains(.traffic), l10n))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { onSelect(row.day) }
    }

    @ViewBuilder
    private func cell(_ column: HistoryColumn, emphasized: Bool) -> some View {
        let text = HistoryTable.cell(row, column, today: today, money: money, l10n)
        let help = HistoryTable.fullCell(row, column, money: money, l10n)
        let primary: AnyShapeStyle = emphasized ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
        let secondary: AnyShapeStyle = emphasized ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.historySecondary)
        switch column {
        case .date:
            HStack(spacing: 5) {
                Text(text)
                    .fontWeight(row.day == today ? .semibold : .regular)
                    .foregroundStyle(primary)
                if row.day == today {
                    Circle()
                        .fill(emphasized ? Color.white : Color.accentColor)
                        .frame(width: 5, height: 5)
                        .help(l10n("history.inProgress"))
                }
            }
            .font(HistoryFont.cell)
            .lineLimit(1)
            .help(help ?? text)
        case .speed, .peak:
            let value = column == .speed ? row.averageSpeed : row.peak
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text)
                    .foregroundStyle(value == nil ? secondary : primary)
                if value != nil {
                    Text(l10n("unit.tokS"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(secondary)
                }
            }
            .font(HistoryFont.cell)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .help(help ?? text)
        case .cost:
            // `≥` sits small and secondary in front, as on the orb (DESIGN 9); `–` and the subscription tag are quiet.
            let quiet = row.cost.sortValue == nil
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if text.hasPrefix("≥") {
                    Text(verbatim: "≥")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(secondary)
                }
                Text(text.hasPrefix("≥") ? String(text.dropFirst()) : text)
                    .foregroundStyle(quiet ? secondary : primary)
            }
            .font(quiet && text != "–" ? .system(size: 11.5) : HistoryFont.cell)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .help(help ?? text)
        case .traffic:
            Text(text)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(row.traffic == nil ? secondary : primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .help(help ?? text)
        case .models:
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(help ?? text)
        default:
            Text(text)
                .font(HistoryFont.cell)
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .help(help ?? text)
        }
    }
}

/// A row's selection, hover or stripe fill. Only this view reads the row's hover flag, so moving the pointer redraws
/// two of these and never re-evaluates a row's cells, their tooltips or the table's layout (macOS issue #21).
private struct RowHighlight: View {
    let mark: HistoryRowMark
    let striped: Bool
    let selected: Bool
    let emphasized: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill(dark: colorScheme == .dark))
    }

    private func fill(dark: Bool) -> Color {
        if emphasized { return Color(nsColor: .selectedContentBackgroundColor) }
        if selected { return Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
        if mark.hovered { return HistoryPalette.hover(dark: dark) }
        return striped ? HistoryPalette.stripe(dark: dark) : .clear
    }
}

/// The accent wash a revealed row shows for 1.2 s.
private struct FlashHighlight: View {
    let day: DayKey
    let interaction: HistoryInteraction

    @State private var opacity = 0.0

    var body: some View {
        let trigger = interaction.flash.flatMap { $0.day == day ? $0.id : nil }
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor)
            .opacity(opacity)
            .onChange(of: trigger) { _, id in
                guard id != nil else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    opacity = 0.3
                } completion: {
                    withAnimation(.easeIn(duration: 0.8).delay(0.28)) { opacity = 0 }
                }
            }
    }
}

import AgentSpeedCore
import SwiftUI

/// The summary cards: all five in one row from 860 pt of content width, else 3 + 2 (DESIGN 4b item 2, DESIGN 9).
struct SummaryCardsView: View {
    let cards: [SummaryCard]
    let source: SourceKind?
    let l10n: Localizer
    let wide: Bool

    var body: some View {
        let rows: [ArraySlice<SummaryCard>] = wide
            ? [cards[...]]
            : stride(from: 0, to: cards.count, by: 3).map { cards[$0..<min($0 + 3, cards.count)] }
        VStack(spacing: HistoryLayout.cardSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: HistoryLayout.cardSpacing) {
                    ForEach(rows[index]) { card in
                        SummaryCardView(card: card, source: source, l10n: l10n, compact: !wide && rows[index].count < 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SummaryCardView: View {
    let card: SummaryCard
    let source: SourceKind?
    let l10n: Localizer
    /// Two cards per row: the sparkline sits beside the value, so both rows stay short.
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let title = l10n(card.titleKey ?? card.metric.titleKey)
        let shortTitle = card.titleKey == nil ? card.metric.shortTitleKey.map { l10n($0) } : nil
        VStack(alignment: .leading, spacing: 0) {
            titleLabel(title, short: shortTitle)
            if compact {
                HStack(alignment: .bottom, spacing: Spacing.m) {
                    value
                    Sparkline(values: card.spark, highlight: card.sparkHighlight, tint: HistoryPalette.tint(source, dark: dark))
                        .frame(height: 26)
                        .padding(.bottom, 4)
                }
                .padding(.top, 4)
            } else {
                value
                    .padding(.top, 4)
                Sparkline(values: card.spark, highlight: card.sparkHighlight, tint: HistoryPalette.tint(source, dark: dark))
                    .frame(height: 24)
                    .padding(.top, 10)
            }
            secondary(dark: dark)
                .font(HistoryFont.cardNote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .historyCard()
        .help(card.help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(card.secondary.isEmpty ? spoken : "\(spoken), \(card.secondary)")
        .accessibilityHint(card.help ?? "")
    }

    private var spoken: String { card.spokenValue ?? card.fullValue }

    /// The full title, or its short form when the full one would not fit; never truncated.
    @ViewBuilder
    private func titleLabel(_ title: String, short: String?) -> some View {
        if let short {
            ViewThatFits(in: .horizontal) {
                label(title)
                label(short)
                    .minimumScaleFactor(0.8)
                    .help(title)
            }
        } else {
            label(title)
                .minimumScaleFactor(0.8)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(HistoryFont.cardLabel)
            .foregroundStyle(.historySecondary)
            .lineLimit(1)
    }

    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(card.value)
                .font(HistoryFont.cardValue)
                .contentTransition(.numericText())
            if let unit = card.unit {
                Text(unit)
                    .font(HistoryFont.cardUnit)
                    .foregroundStyle(.historySecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .fixedSize(horizontal: compact, vertical: false)
        .help(card.help ?? card.fullValue)
    }

    /// The change is the only colored part of the line.
    @ViewBuilder
    private func secondary(dark: Bool) -> some View {
        if let change = card.change {
            let changeText = HistoryText.change(change)
            let parts = card.secondary.components(separatedBy: changeText)
            // Money is never green or red (DESIGN 9 Principles): the cost card's change stays secondary.
            let color = card.neutralChange
                ? HistoryPalette.secondary(dark: dark, increasedContrast: false)
                : (change >= 0 ? HistoryPalette.positive(dark: dark) : HistoryPalette.negative(dark: dark))
            if parts.count == 2 {
                Text("\(Text(parts[0]).foregroundStyle(.historySecondary))\(Text(changeText).foregroundStyle(color).fontWeight(.semibold))\(Text(parts[1]).foregroundStyle(.historySecondary))")
            } else {
                Text(card.secondary).foregroundStyle(.historySecondary)
            }
        } else {
            Text(card.secondary.isEmpty ? " " : card.secondary)
                .foregroundStyle(.historySecondary)
        }
    }
}

/// A tiny line with a soft fill over one value per day; days without a value are skipped, so the trend stays one line.
/// The highlighted point (the selected day of a single-day range) is drawn as a ringed dot.
struct Sparkline: View {
    let values: [Double?]
    var highlight: Int?
    let tint: Color

    var body: some View {
        let ring = Color(nsColor: .windowBackgroundColor)
        Canvas { context, size in
            let values = Self.bridged(values)
            let points = values.enumerated().compactMap { index, value in value.map { (index, $0) } }
            guard let top = points.map(\.1).max(), top > 0, values.count > 0 else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                context.stroke(baseline, with: .color(tint.opacity(0.3)), lineWidth: 1)
                return
            }
            let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
            let inset: CGFloat = 1.5
            func point(_ index: Int, _ value: Double) -> CGPoint {
                let x = values.count > 1 ? CGFloat(index) * step : size.width / 2
                let y = inset + (size.height - inset * 2) * (1 - CGFloat(value / top))
                return CGPoint(x: x, y: y)
            }
            for run in HistoryChartMath.runs(values) {
                var line = Path()
                for index in run {
                    let p = point(index, values[index] ?? 0)
                    if index == run.lowerBound { line.move(to: p) } else { line.addLine(to: p) }
                }
                if run.count == 1, let value = values[run.lowerBound] {
                    let p = point(run.lowerBound, value)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(tint))
                    continue
                }
                var area = line
                area.addLine(to: CGPoint(x: point(run.upperBound - 1, 0).x, y: size.height))
                area.addLine(to: CGPoint(x: point(run.lowerBound, 0).x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.22), tint.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let highlight, values.indices.contains(highlight), let value = values[highlight] {
                let p = point(highlight, value)
                // Kept inside the canvas so the ring is never clipped at the trailing edge.
                let center = CGPoint(x: min(max(p.x, 4), size.width - 4), y: min(max(p.y, 4), size.height - 4))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(ring))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2.75, y: center.y - 2.75, width: 5.5, height: 5.5)), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }

    /// Fills inner gaps by linear interpolation; leading and trailing gaps stay empty.
    static func bridged(_ values: [Double?]) -> [Double?] {
        let known = values.indices.filter { values[$0] != nil }
        guard let first = known.first, known.count > 1 else { return values }
        var result = values
        var previous = first
        for index in known.dropFirst() {
            if index > previous + 1, let a = values[previous], let b = values[index] {
                for gap in (previous + 1)..<index {
                    let t = Double(gap - previous) / Double(index - previous)
                    result[gap] = a + (b - a) * t
                }
            }
            previous = index
        }
        return result
    }
}

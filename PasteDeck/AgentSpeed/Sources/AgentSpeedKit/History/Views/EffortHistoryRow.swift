import AgentSpeedCore
import SwiftUI

/// One effort or speed value in the history (DESIGN 4b, 3b): glyph, token, share-of-output bar, then requests, output
/// and average speed. Hovering shows its top three models.
struct EffortHistoryRow: View {
    let row: ModeHistoryRow
    let kind: ExecutionModeKind
    let share: Double
    let hovered: Bool
    let l10n: Localizer
    var reduceMotion = false

    static let columnSpacing = Spacing.s
    static let numberColumns: [(key: String, width: CGFloat)] = [
        ("history.table.requests", 64), ("history.table.output", 72), ("history.table.speed", 92),
    ]
    private static let glyphWidth: CGFloat = 22
    private static let tokenWidth: CGFloat = 92

    @Environment(\.self) private var environment

    var body: some View {
        let palette = EffortCapsulePalette(environment)
        HStack(spacing: Self.columnSpacing) {
            glyph
                .frame(width: Self.glyphWidth, alignment: .leading)
            Text(token)
                .font(HistoryFont.cell.weight(row.isUnknown ? .regular : .medium))
                .foregroundStyle(row.isUnknown ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.tokenWidth, alignment: .leading)
            ShareBar(share: share, fill: barFill(palette), track: Color.primary.opacity(0.06))
                .frame(height: 6)
                .frame(maxWidth: .infinity)
            Text(HistoryText.percent(share))
                .font(HistoryFont.cardNote)
                .foregroundStyle(.historySecondary)
                .frame(width: 36, alignment: .trailing)
            number(HistoryText.fullNumber(row.requests, l10n), column: 0)
            number(SpeedFormat.tokens(row.output), column: 1)
                .help(HistoryText.fullNumber(row.output, l10n))
            number(HistoryText.speed(row.averageSpeed, l10n), column: 2, muted: row.averageSpeed == nil)
        }
        .frame(height: HistoryLayout.rowHeight)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovered ? HistoryPalette.hover(dark: palette.dark) : .clear)
        )
        .padding(.horizontal, -6)
        .overlay(alignment: .topLeading) {
            if hovered, !row.models.isEmpty {
                ModelsCard(models: Array(row.models.prefix(3)), total: row.output, l10n: l10n)
                    .offset(x: Self.glyphWidth + Self.columnSpacing, y: HistoryLayout.rowHeight + 2)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(HistoryMotion.fade, value: hovered)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryText.join([
            token,
            HistoryText.percent(share),
            HistoryText.labelled(l10n("history.table.requests"), HistoryText.fullNumber(row.requests, l10n), l10n),
            HistoryText.labelled(l10n("history.table.output"), HistoryText.fullNumber(row.output, l10n), l10n),
            HistoryText.labelled(l10n("history.table.speed"), HistoryText.fullSpeed(row.averageSpeed, l10n), l10n),
        ], l10n))
    }

    private var token: String {
        if row.isUnknown { return l10n("modes.unrecorded") }
        return kind == .speed ? EffortCapsule.speedValue(row.mode, l10n) : row.mode
    }

    /// The capsule's meter for effort; bolts for speed, a hollow ring for `standard` and tokens without bolts.
    @ViewBuilder
    private var glyph: some View {
        if row.isUnknown {
            Color.clear.frame(width: 1, height: 1)
        } else if kind == .effort {
            if let level = ModeDisplay.effortLevel(row.mode) {
                EffortMeter(level: level, tone: EffortTone(row.mode), reduceMotion: reduceMotion)
            }
        } else if ModeDisplay.bolts(row.mode) > 0 {
            SpeedBolts(count: ModeDisplay.bolts(row.mode))
        } else {
            Circle()
                .strokeBorder(.historySecondary, lineWidth: 1)
                .frame(width: 6, height: 6)
                .padding(.leading, 1)
        }
    }

    private func barFill(_ palette: EffortCapsulePalette) -> AnyShapeStyle {
        if row.isUnknown { return AnyShapeStyle(palette.unknownBar) }
        if kind == .speed {
            return ModeDisplay.bolts(row.mode) > 0 ? AnyShapeStyle(palette.bolt) : palette.shareBar(.neutral)
        }
        return palette.shareBar(EffortTone(row.mode))
    }

    private func number(_ text: String, column: Int, muted: Bool = false) -> some View {
        Text(text)
            .font(HistoryFont.cell)
            .foregroundStyle(muted ? AnyShapeStyle(.historySecondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .frame(width: Self.numberColumns[column].width, alignment: .trailing)
    }
}

/// A thin capsule track filled to `share`.
private struct ShareBar: View {
    let share: Double
    let fill: AnyShapeStyle
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if share > 0 {
                    Capsule().fill(fill).frame(width: max(3, proxy.size.width * share.clamped(to: 0...1)))
                }
            }
        }
    }
}

/// The hovered row's top three models with their share of its output.
private struct ModelsCard: View {
    let models: [ModeHistoryRow.ModelOutput]
    let total: Int
    let l10n: Localizer

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = colorScheme == .dark
        VStack(alignment: .leading, spacing: 5) {
            Text(l10n("history.table.models"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.historySecondary)
            ForEach(models, id: \.model) { model in
                let share = total > 0 ? Double(model.output) / Double(total) : 0
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.model.isEmpty ? l10n("modes.unrecorded") : model.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(HistoryText.percent(share))
                            .foregroundStyle(.historySecondary)
                    }
                    .font(HistoryFont.tooltip)
                    ShareBar(share: share, fill: AnyShapeStyle(Color.accentColor), track: Color.primary.opacity(0.08))
                        .frame(height: 3)
                }
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dark ? Color(white: 0.19) : Color.white)
                .shadow(color: .black.opacity(dark ? 0.45 : 0.16), radius: 12, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(HistoryPalette.cardStroke(dark: dark, increasedContrast: contrast == .increased), lineWidth: 1)
                )
        }
    }
}

import AgentSpeedCore
import SwiftUI

/// Today's totals as a 2 × 2 grid plus the peak, with a History button on the title line (DESIGN section 4.5).
struct TodaySection: View {
    let model: AgentSpeedModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let l10n = model.l10n
        let snapshot = model.snapshot
        let today = snapshot.today
        let unit = l10n("unit.tokS")

        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                SectionTitle(text: l10n("dashboard.today"), latin: model.dashboardLatinCaps)
                Spacer(minLength: 0)
                Button {
                    model.commands?.showHistory(source: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(l10n("mac.dashboard.history"))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(DashboardInlineButtonStyle())
                .padding(.trailing, -7)
                .help(l10n("mac.dashboard.historyHint"))
                .accessibilityLabel(l10n("mac.dashboard.history"))
                .accessibilityHint(l10n("mac.dashboard.historyHint"))
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                GridRow {
                    MetricCell(label: l10n("today.output"), value: SpeedFormat.tokens(today.output))
                    MetricCell(label: l10n("today.input"), value: SpeedFormat.tokens(today.input))
                }
                GridRow {
                    MetricCell(
                        label: l10n("today.requests"),
                        value: today.requests.formatted(.number.locale(l10n.locale))
                    )
                    MetricCell(
                        label: l10n("today.average"),
                        value: snapshot.averageToday.map(SpeedFormat.speed) ?? "–",
                        unit: snapshot.averageToday == nil ? nil : unit
                    )
                }
            }
            PeakRow(
                title: l10n("today.peak"),
                value: model.value(of: snapshot.peakToday),
                time: snapshot.peakTodayAt,
                unit: unit,
                locale: l10n.locale,
                redline: model.settings.redline,
                dark: colorScheme == .dark,
                increasedContrast: contrast == .increased
            )
            .padding(.top, 2)
            TodayCostRow(model: model)
        }
    }
}

private struct MetricCell: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DashboardFont.note)
                .foregroundStyle(.dashboardSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DashboardFont.metricValue)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(DashboardFont.metricUnit)
                        .foregroundStyle(.dashboardSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PeakRow: View {
    let title: String
    let value: Double
    let time: Date?
    let unit: String
    let locale: Locale
    let redline: Double
    let dark: Bool
    let increasedContrast: Bool

    var body: some View {
        let heat = HeatPalette.heat(value: value, redline: redline)
        let hasPeak = value > 0
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hasPeak ? AnyShapeStyle(DashboardPalette.heatText(heat, dark: dark, increasedContrast: increasedContrast)) : AnyShapeStyle(.dashboardSecondary))
                .accessibilityHidden(true)
            Text(title)
                .font(DashboardFont.note)
                .foregroundStyle(.dashboardSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            if hasPeak {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(SpeedFormat.speed(value))
                        .font(DashboardFont.rowNumber.weight(.semibold))
                        .foregroundStyle(DashboardPalette.heatText(heat, dark: dark, increasedContrast: increasedContrast))
                    Text(unit)
                        .font(DashboardFont.metricUnit)
                        .foregroundStyle(.dashboardSecondary)
                }
                if let time {
                    Text("· " + time.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                        .font(DashboardFont.detail)
                        .foregroundStyle(.dashboardSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("–")
                    .font(DashboardFont.rowNumber)
                    .foregroundStyle(.dashboardSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

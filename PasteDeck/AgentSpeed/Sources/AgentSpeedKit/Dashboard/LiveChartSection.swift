import AgentSpeedCore
import SwiftUI

/// Live chart with its range picker (DESIGN section 4.2).
struct LiveChartSection: View {
    let model: AgentSpeedModel

    @AppStorage(ChartRange.storageKey) private var rangeValue = ChartRange.twoMinutes.rawValue
    @State private var domain: Double?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let l10n = model.l10n
        let snapshot = model.snapshot
        let range = ChartRange(rawValue: rangeValue) ?? .twoMinutes
        let series = ChartSeries(snapshot: snapshot, range: range, metric: model.settings.metric)
        let peak = model.value(of: snapshot.peakToday)
        let target = ChartDomain.target(maxTotal: series.maxTotal, peak: peak)
        let shown = domain ?? target
        let style = ChartStyle(
            redline: model.settings.redline,
            isDark: colorScheme == .dark,
            increasedContrast: contrast == .increased
        )
        let speedLabel: (String) -> String = { l10n("mac.settings.speedValue", $0) }
        // Next to a money hero the chart's token speed must name its unit, or 2.16k reads as money.
        let showsMoney = model.settings.liveUnit == .cost
        let peakText = showsMoney ? speedLabel(SpeedFormat.speed(peak)) : SpeedFormat.speed(peak)
        let summary = l10n(
            "mac.dashboard.chart.summary",
            SpeedFormat.speed(series.maxTotal),
            SpeedFormat.speed(series.live?.total ?? 0)
        )

        VStack(alignment: .leading, spacing: DashboardLayout.headerSpacing) {
            header(range: range, showsEstimate: series.hasEstimate)
            ZStack {
                ChartPlot(
                    series: series,
                    domain: shown,
                    peak: peak,
                    peakLabel: l10n("mac.dashboard.peakLine", peakText),
                    axisUnit: showsMoney ? l10n("unit.tokS") : nil,
                    style: style
                )
                ChartCrosshair(
                    series: series,
                    domain: shown,
                    style: style,
                    labels: .init(
                        locale: l10n.locale,
                        now: l10n("mac.dashboard.now"),
                        estimated: l10n("chart.estimated"),
                        speed: speedLabel
                    )
                )
            }
            .frame(height: DashboardLayout.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n("mac.dashboard.chart"))
            .accessibilityValue(summary)
            .accessibilityChartDescriptor(LiveChartDescriptor(
                series: series,
                domain: shown,
                title: l10n("mac.dashboard.chart"),
                summary: summary,
                timeTitle: l10n("mac.dashboard.chart.timeAxis"),
                valueTitle: l10n(model.settings.metric.titleKey),
                language: l10n.language
            ))
        }
        .onChange(of: target, initial: true) { _, newTarget in
            settleDomain(toward: newTarget)
        }
    }

    private func header(range: ChartRange, showsEstimate: Bool) -> some View {
        let l10n = model.l10n
        return HStack(spacing: Spacing.xs) {
            SectionTitle(text: l10n("dashboard.live"), latin: model.dashboardLatinCaps)
            if showsEstimate {
                EstimateLegend(text: l10n("chart.estimated"))
                    .transition(.opacity)
            }
            Spacer(minLength: Spacing.xs)
            Picker(l10n("mac.dashboard.range"), selection: $rangeValue) {
                ForEach(ChartRange.allCases) { option in
                    Text(l10n(option.titleKey)).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(l10n("mac.dashboard.range"))
        }
        .animation(Motion.fade, value: showsEstimate)
    }

    private func settleDomain(toward target: Double) {
        let next = ChartDomain.settle(current: domain, target: target)
        guard next != domain else { return }
        if domain == nil || model.accessibility.reduceMotion {
            domain = next
        } else {
            withAnimation(.smooth(duration: 0.7)) { domain = next }
        }
    }
}

/// Dashed swatch explaining the estimated part of the chart.
private struct EstimateLegend: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            DashedRule()
                .stroke(.dashboardSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 2]))
                .frame(width: 13, height: 2)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.dashboardSecondary)
                .lineLimit(1)
        }
    }
}

private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return path
    }
}

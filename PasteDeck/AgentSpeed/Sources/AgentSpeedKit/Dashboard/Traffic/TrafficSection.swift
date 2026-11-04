import AgentSpeedCore
import SwiftUI

/// The dashboard's Network section (DESIGN 10, Dashboard): this computer's live rates in the header, a 60 s mirrored
/// sparkline, the sources with traffic today (up to three, the rest in place), and what agent traffic includes — or
/// why it cannot be measured.
struct TrafficSection: View {
    let model: AgentSpeedModel

    @State private var expanded = false

    static let collapsedRows = 3

    var body: some View {
        let l10n = model.l10n
        let snapshot = model.visibleTraffic
        let text = TrafficText(model: model)
        let includeTools = model.settings.trafficIncludeTools
        let rows = Self.rows(snapshot, includeTools: includeTools)
        let shown = expanded ? rows : Array(rows.prefix(Self.collapsedRows))
        let window = Array(snapshot.machineHistory.suffix(Int(TrafficSparkline.window)))

        VStack(alignment: .leading, spacing: DashboardLayout.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                SectionTitle(text: l10n("traffic.title"), latin: model.dashboardLatinCaps)
                Spacer(minLength: Spacing.xs)
                HStack(spacing: Spacing.s) {
                    TrafficRateLabel(down: true, rate: snapshot.machineLive?.rx, text: text, size: 13, weight: .regular,
                                     numberStyle: AnyShapeStyle(.dashboardSecondary))
                    TrafficRateLabel(down: false, rate: snapshot.machineLive?.tx, text: text, size: 13, weight: .regular,
                                     numberStyle: AnyShapeStyle(.dashboardSecondary))
                }
                .help(l10n("traffic.machine.hint"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(l10n("traffic.machine"))
                .accessibilityValue(snapshot.machineLive.map(text.spokenRates) ?? "–")
            }
            TrafficSparkline(points: window, text: text, reduceMotion: model.accessibility.reduceMotion,
                             accessibilityLabel: chartLabel(window, text: text))
                .padding(.vertical, 4)
            if let reason = snapshot.processState.unavailableReason {
                Text(text.reason(reason))
                    .font(DashboardFont.note)
                    .foregroundStyle(.dashboardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if rows.isEmpty {
                Text(l10n("traffic.empty"))
                    .font(DashboardFont.note)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(shown, id: \.source) { source in
                    TrafficSourceRow(model: model, traffic: source, text: text, includeTools: includeTools)
                        .transition(.opacity)
                }
                if rows.count > Self.collapsedRows {
                    AgentsDisclosure(expanded: expanded, hidden: rows.count - Self.collapsedRows, total: rows.count,
                                     l10n: l10n, reduceMotion: model.accessibility.reduceMotion, title: expanded ? nil : l10n("traffic.expand", rows.count - Self.collapsedRows)) {
                        withAnimation(model.dashboardMotion) { expanded.toggle() }
                    }
                }
                Text(l10n(includeTools ? "traffic.includesTools" : "traffic.excludesTools"))
                    .font(DashboardFont.note)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .animation(model.dashboardMotion, value: shown.map(\.source))
    }

    /// Sources with traffic today or now, most bytes today first.
    static func rows(_ snapshot: TrafficSnapshot, includeTools: Bool) -> [SourceTraffic] {
        SourceKind.allCases.compactMap { kind -> SourceTraffic? in
            guard let traffic = snapshot.sources[kind] else { return nil }
            let today = traffic.today.total(includeTools: includeTools)
            let live = traffic.live(includeTools: includeTools)?.sum ?? 0
            return today.sum > 0 || live > 0 ? traffic : nil
        }
        .sorted { $0.today.total(includeTools: includeTools).sum > $1.today.total(includeTools: includeTools).sum }
    }

    private func chartLabel(_ window: [TrafficPoint], text: TrafficText) -> String {
        let rx = window.map(\.rate.rx).max() ?? 0
        let tx = window.map(\.rate.tx).max() ?? 0
        return model.l10n("traffic.a11y.chart", TrafficText.spoken(text.rate(rx)), TrafficText.spoken(text.rate(tx)))
    }
}

/// A source with traffic: dot, name over today's pair, and the live rates as two stacked lines in fixed cells; a
/// direction below 0.5 KB/s reads `–`. Opens Usage History on the traffic metric with the source selected.
private struct TrafficSourceRow: View {
    let model: AgentSpeedModel
    let traffic: SourceTraffic
    let text: TrafficText
    let includeTools: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let l10n = model.l10n
        let name = l10n(traffic.source.titleKey)
        let today = traffic.today.total(includeTools: includeTools)
        let live = traffic.live(includeTools: includeTools)
        Button {
            model.commands?.showHistory(source: traffic.source, metric: .traffic)
        } label: {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(traffic.source.tint(dark: colorScheme == .dark))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(DashboardFont.row)
                        .lineLimit(1)
                    Text(text.pair(today))
                        .font(DashboardFont.detail)
                        .foregroundStyle(.dashboardSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: 0) {
                    TrafficRateLabel(down: true, rate: live?.rx, text: text, dashBelow: 500)
                    TrafficRateLabel(down: false, rate: live?.tx, text: text, dashBelow: 500)
                }
            }
            .frame(minHeight: 32)
        }
        .buttonStyle(DashboardSourceRowButtonStyle(forcedHover: false))
        .focusEffectDisabled()
        .help(l10n("mac.dashboard.sourceHint"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue([text.spokenTotals(today), live.map(text.spokenRates)].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(l10n("mac.dashboard.sourceHint"))
        .accessibilityAddTraits(.isButton)
    }
}

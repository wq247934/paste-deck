import AgentSpeedCore
import SwiftUI

/// 今日費用 under the grid (DESIGN 9, dashboard Today): `today.cost` with the caption `cost.apiEquivalent`, the
/// billable amount trailing, and an ⓘ popover with the per-source breakdown, unpriced and excluded sources and the
/// rate line.
struct TodayCostRow: View {
    let model: AgentSpeedModel

    @State private var showsInfo = false

    var body: some View {
        let l10n = model.l10n
        let summary = TodayCostSummary(model: model)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "banknote")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.dashboardSecondary)
                .accessibilityHidden(true)
            Text(l10n("today.cost"))
                .font(DashboardFont.note)
                .foregroundStyle(.dashboardSecondary)
                .lineLimit(1)
            Text(l10n("cost.apiEquivalent"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            Text(summary.amountText)
                .font(DashboardFont.rowNumber.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(Motion.fade, value: model.cost.currency.code)
            Button {
                showsInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.dashboardSecondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(l10n("cost.apiEquivalent.hint"))
            .accessibilityLabel(l10n("cost.apiEquivalent"))
            .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                TodayCostPopover(model: model, summary: summary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(l10n("today.cost")) (\(l10n("cost.apiEquivalent"))) \(summary.spoken)")
    }
}

/// Today's billable cost and its parts (METRICS 9.4, 9.6).
struct TodayCostSummary {
    struct Part: Identifiable {
        var id: SourceKind { source }
        var source: SourceKind
        var cost: CostTally
        var requests: Int
    }

    var total = CostTally()
    var requests = 0
    var parts: [Part] = []
    var excluded: [SourceKind] = []
    let amountText: String
    let spoken: String

    @MainActor
    init(model: AgentSpeedModel) {
        let billable = model.cost.billable
        for status in model.snapshot.sources where status.today.requests > 0 {
            guard billable.contains(status.kind) else {
                excluded.append(status.kind)
                continue
            }
            total.add(status.todayCost)
            requests += status.today.requests
            parts.append(Part(source: status.kind, cost: status.todayCost, requests: status.today.requests))
        }
        parts.sort { $0.cost.costMicroUsd != $1.cost.costMicroUsd ? $0.cost.costMicroUsd > $1.cost.costMicroUsd : $0.source.rawValue < $1.source.rawValue }
        let text = model.cost.tallyText(total, requests: requests)
        amountText = requests == 0 ? model.cost.amountText(microUsd: 0) : text
        spoken = requests == 0 ? model.cost.spoken(model.cost.amount(microUsd: 0).number)
            : model.cost.spokenTally(total, requests: requests)
    }
}

struct TodayCostPopover: View {
    let model: AgentSpeedModel
    let summary: TodayCostSummary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let l10n = model.l10n
        let cost = model.cost
        let largest = summary.parts.map(\.cost.costMicroUsd).max() ?? 0
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(l10n("today.cost"))
                .font(.system(size: 13, weight: .semibold))
            Text(l10n("cost.apiEquivalent.hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !summary.parts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(summary.parts) { part in
                        HStack(spacing: Spacing.s) {
                            Circle()
                                .fill(part.source.tint(dark: colorScheme == .dark))
                                .frame(width: 7, height: 7)
                            Text(l10n(part.source.titleKey))
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: Spacing.xs)
                            Text(cost.tallyText(part.cost, requests: part.requests))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                        }
                        .overlay(alignment: .bottomLeading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(part.source.tint(dark: colorScheme == .dark).opacity(0.55))
                                    .frame(width: largest > 0 ? proxy.size.width * CGFloat(part.cost.costMicroUsd) / CGFloat(largest) : 0,
                                           height: 2)
                            }
                            .frame(height: 2)
                            .offset(y: 4)
                        }
                        .padding(.bottom, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if summary.total.unpricedRequests > 0 {
                Notice(text: l10n("cost.unpriced", summary.total.unpricedRequests), symbol: "questionmark.circle")
            }
            if !summary.excluded.isEmpty {
                Notice(text: l10n("cost.subscriptionExcluded",
                                  summary.excluded.map { l10n($0.titleKey) }.joined(separator: l10n("list.separator"))),
                       symbol: "creditcard")
            }
            if !cost.isUSD {
                Text(cost.rateStatus)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(Spacing.m)
        .frame(width: 280, alignment: .leading)
    }
}

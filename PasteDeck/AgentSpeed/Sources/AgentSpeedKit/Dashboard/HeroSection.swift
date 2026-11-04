import AgentSpeedCore
import SwiftUI

/// The embedded orb with the big live readout, speed title and agent context (DESIGN section 4.1).
struct HeroSection: View {
    let model: AgentSpeedModel

    /// The orb's aura reaches 0.25 × diameter past its frame; this keeps it inside the popover.
    private static let auraRoom: CGFloat = 8

    var body: some View {
        let l10n = model.l10n
        let gauge = model.gauge
        let value = gauge.readoutValue
        let tier = gauge.tier
        let title = gauge.title
        let snapshot = model.snapshot
        let speed = SpeedFormat.speed(value)
        let titleName = model.titles.text(title, in: model.titles.general, l10n: l10n)
        let context = l10n("agents.context", snapshot.generatingCount, snapshot.toolsCount)
        // The money unit (DESIGN 9): the billable live cost rate; heat and title keep following tokens.
        let money: LiveMoney? = model.settings.liveUnit == .cost
            ? model.cost.live(OrbSubset.cost(snapshot, sources: nil, billable: model.cost.billable), agentCount: snapshot.agents.count)
            : nil
        let toggleUnit = { model.settings.liveUnit = model.settings.liveUnit == .cost ? .tokens : .cost }

        HStack(spacing: Spacing.l) {
            OrbView(model: model, diameter: DashboardLayout.orbDiameter, surface: .embedded)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HeroReadout(
                    value: money?.value ?? value,
                    text: money?.number ?? speed,
                    unit: money?.unit ?? l10n("unit.tokS"),
                    isIdle: tier == .idle || money?.unknown == true,
                    atLeast: money?.atLeast ?? false,
                    hint: l10n("orbs.unit.toggleHint"),
                    reduceMotion: model.accessibility.reduceMotion,
                    toggleUnit: toggleUnit
                )
                .id(money == nil)
                .transition(model.accessibility.reduceMotion ? .opacity : .push(from: .bottom).combined(with: .opacity))
                SpeedTitleLabel(
                    title: title,
                    text: titleName,
                    heat: HeatPalette.heat(value: value, redline: model.settings.redline),
                    latin: model.dashboardLatinCaps,
                    reduceMotion: model.accessibility.reduceMotion
                )
                Text(context)
                    .font(DashboardFont.context)
                    .foregroundStyle(.dashboardSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.auraRoom)
        .padding(.top, Self.auraRoom)
        .animation(model.accessibility.reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3), value: money == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroLabel(money: money, speed: speed, title: titleName))
        .accessibilityValue(context)
        .accessibilityAction(named: l10n("a11y.orb.toggleUnit"), toggleUnit)
    }

    private func heroLabel(money: LiveMoney?, speed: String, title: String) -> String {
        let l10n = model.l10n
        guard let money else { return l10n("a11y.orb", speed, title) }
        if money.unknown { return l10n("a11y.orb.costUnknown", title) }
        let amount = money.atLeast ? l10n("a11y.orb.costAtLeast", money.number) : money.number
        return l10n("a11y.orb.cost", amount, model.cost.currencyName, title)
    }
}

private struct HeroReadout: View {
    let value: Double
    let text: String
    let unit: String
    let isIdle: Bool
    /// A small `≥` (60 %, secondary) before a partly priced money value (DESIGN 9).
    var atLeast = false
    let hint: String
    let reduceMotion: Bool
    let toggleUnit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if atLeast {
                    Text(verbatim: "≥")
                        .font(.system(size: 44 * 0.6, weight: .bold))
                        .foregroundStyle(.dashboardSecondary)
                }
                Text(text)
                    .font(DashboardFont.heroValue)
                    .foregroundStyle(isIdle ? AnyShapeStyle(.dashboardSecondary) : AnyShapeStyle(.primary))
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
                    .animation(reduceMotion ? Motion.fade : Motion.digits, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            HeroUnitButton(unit: unit, hint: hint, toggle: toggleUnit)
        }
        .animation(Motion.fade, value: isIdle)
    }
}

/// The speed title in the heat color; a new title slides up into place (0.35 s). It shrinks to fit, never truncating.
private struct SpeedTitleLabel: View {
    let title: SpeedTitle
    let text: String
    let heat: Double
    let latin: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = DashboardPalette.heatText(heat, dark: colorScheme == .dark, increasedContrast: contrast == .increased)
        ZStack(alignment: .leading) {
            Text(text)
                .font(DashboardFont.tier)
                .textCase(latin ? .uppercase : nil)
                .tracking(latin ? 1.4 : 0.8)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(TitleFit.minimumScale)
                .allowsTightening(true)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.25), value: text)
                .id(title)
                .transition(transition)
        }
        .clipped()
        .animation(reduceMotion ? Motion.fade : .spring(response: 0.35, dampingFraction: 0.86), value: title)
    }

    /// Staggered like the orb's label: the old title leaves over the first 40 % of the 0.35 s change, the new one
    /// arrives from 35 %, so the two never overlap legibly; Reduce Motion keeps the stagger as a crossfade. A theme
    /// change renames the level in place (0.25 s crossfade).
    private var transition: AnyTransition {
        let removal: AnyTransition = reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
        let insertion: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        return .asymmetric(
            insertion: insertion.animation(.easeOut(duration: 0.23).delay(0.12)),
            removal: removal.animation(.easeIn(duration: 0.14))
        )
    }
}

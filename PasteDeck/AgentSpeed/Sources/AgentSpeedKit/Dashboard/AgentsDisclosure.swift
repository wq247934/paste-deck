import SwiftUI

/// The row under the agents list: "+4 agents" opens a collapsed list, "Show less" closes an expanded one
/// (DESIGN section 4.4). The chevron sits in the badge column and the title lines up with the project names.
struct AgentsDisclosure: View {
    let expanded: Bool
    /// Agents the collapsed list leaves out.
    let hidden: Int
    let total: Int
    let l10n: Localizer
    let reduceMotion: Bool
    /// Replaces the collapsed title (the traffic list says `+2 more` sources, not agents).
    var title: String?
    let action: () -> Void

    var body: some View {
        let title = expanded ? l10n("agents.collapse") : self.title ?? l10n("agents.expand", hidden)
        let label = expanded ? title : l10n("agents.expand.a11y", total)
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(reduceMotion ? nil : Motion.layout, value: expanded)
                    .frame(width: DashboardLayout.badgeWidth)
                Text(title)
                    .font(DashboardFont.detail)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DashboardRowButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

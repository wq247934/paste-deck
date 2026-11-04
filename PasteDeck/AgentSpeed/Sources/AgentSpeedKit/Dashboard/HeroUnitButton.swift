import SwiftUI

/// The hero's unit (DESIGN 9, Menu bar, taskbar and dashboard): a single click toggles tok/s and the money unit at
/// once (the hero has no double-click action). Hovering raises it from 55 % to 85 % with a 0.5 pt underline at 40 %
/// (0.15 s), with the pointing hand and the `orbs.unit.toggleHint` tooltip.
struct HeroUnitButton: View {
    let unit: String
    let hint: String
    let toggle: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            Text(unit)
                .font(DashboardFont.heroUnit)
                .foregroundStyle(.primary)
                .opacity(hovered ? 0.85 : 0.55)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.primary)
                        .frame(height: 0.5)
                        .opacity(hovered ? 0.4 : 0)
                        .offset(y: 1)
                }
                .fixedSize()
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

import AgentSpeedCore
import SwiftUI

/// The right-aligned live tok/s slot of an agent or source row (DESIGN section 4, items 3–4). A value that would read
/// as "0" is never shown as a number: running tools shows a breathing hourglass, anything else a tertiary en dash.
/// Every form shares the digits' baseline and the fixed slot width, and they crossfade in 0.2 s.
struct LiveSpeedValue: View {
    /// Values below this display as "0" or "0.0".
    static let visibleMinimum = 0.05

    let speed: Double
    /// The agent's phase; nil for a source row, which shows the dash below the minimum.
    var phase: AgentPhase?
    let l10n: Localizer
    var reduceMotion = false
    var width: CGFloat = DashboardLayout.speedColumn

    private enum Form: Equatable {
        case number(String)
        case hourglass
        case dash

        var kind: Int {
            switch self {
            case .number: 0
            case .hourglass: 1
            case .dash: 2
            }
        }
    }

    var body: some View {
        let form = form
        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
            // Holds the digits' line height and baseline whichever form is shown.
            Text(verbatim: "0")
                .font(DashboardFont.rowNumber)
                .hidden()
            switch form {
            case .number(let text):
                Text(verbatim: text)
                    .font(DashboardFont.rowNumber)
                    .foregroundStyle(.primary)
                    .contentTransition(.identity)
                    .lineLimit(1)
                    .transition(.opacity)
            case .hourglass:
                HourglassGlyph(breathes: !reduceMotion)
                    .transition(.opacity)
            case .dash:
                Text(verbatim: "–")
                    .font(DashboardFont.rowNumber)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .frame(width: width, alignment: .trailing)
        .animation(Motion.fade, value: form.kind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(form))
    }

    private var form: Form {
        if speed.isFinite, speed >= Self.visibleMinimum { return .number(SpeedFormat.speed(speed)) }
        return phase == .tools ? .hourglass : .dash
    }

    /// What VoiceOver reads for the value: the speed, or the phase in its place.
    var accessibilityText: String { accessibilityText(form) }

    private func accessibilityText(_ form: Form) -> String {
        switch form {
        case .number(let text): l10n("mac.settings.speedValue", text)
        case .hourglass: l10n("phase.tools")
        case .dash: l10n(phase == .generating ? "phase.generating" : "phase.idle")
        }
    }
}

/// SF Symbol `hourglass`, 11 pt in the secondary color, breathing between 55 % and 100 % over 2 s.
private struct HourglassGlyph: View {
    let breathes: Bool

    var body: some View {
        let glyph = Text(Image(systemName: "hourglass"))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.dashboardSecondary)
        if breathes {
            glyph.phaseAnimator([false, true]) { content, bright in
                content.opacity(bright ? 1 : 0.55)
            } animation: { _ in
                .easeInOut(duration: 1)
            }
        } else {
            glyph
        }
    }
}

import AgentSpeedCore
import SwiftUI

/// Slim banner while the effects preview feeds sample data.
struct PreviewBanner: View {
    let model: AgentSpeedModel

    var body: some View {
        let l10n = model.l10n
        HStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(l10n("mac.dashboard.preview"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs)
            Button(l10n("mac.dashboard.stopPreview")) {
                model.stopPreview()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Updated to 1.2.0", shown once after relaunching into a new version (UPDATES section 4).
/// PasteDeck 无独立更新系统，此横幅不再使用；保留类型供上游视图复用路径编译。
struct UpdatedBanner: View {
    let model: AgentSpeedModel
    let version: String

    var body: some View {
        EmptyView()
    }
}

/// Startup progress while today's transcripts are read.
struct LoadingState: View {
    let model: AgentSpeedModel
    let progress: Double

    var body: some View {
        let l10n = model.l10n
        let fraction = progress.isFinite ? progress.clamped(to: 0...1) : 0
        StateMessage {
            ProgressView(value: fraction) {
                EmptyView()
            } currentValueLabel: {
                Text(l10n("mac.settings.percentValue", Int((fraction * 100).rounded())))
            }
            .progressViewStyle(GaugeProgressStyle())
                .accessibilityLabel(l10n("state.loading"))
                .accessibilityValue(l10n("mac.settings.percentValue", Int((fraction * 100).rounded())))
        } message: {
            Text(l10n("state.loading"))
                .accessibilityHidden(true)
        }
    }
}

/// No transcript folder was found for any enabled source.
struct NoSourcesState: View {
    let model: AgentSpeedModel

    var body: some View {
        let l10n = model.l10n
        StateMessage {
            RestingGauge(lineWidth: 3)
                .frame(width: 44, height: 44)
        } message: {
            Text(l10n("state.noSources"))
        } action: {
            Button(l10n("mac.dashboard.openSettings")) {
                model.commands?.showAgentSpeedSettings()
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Centered illustration, message and optional action.
private struct StateMessage<Illustration: View, Message: View, Action: View>: View {
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var message: Message
    @ViewBuilder var action: Action

    init(
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder message: () -> Message,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.illustration = illustration()
        self.message = message()
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            illustration
            message
                .font(.system(size: 13))
                .foregroundStyle(.dashboardSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }
}

/// The brand's 270° ring as a determinate progress indicator.
private struct GaugeProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GaugeProgressRing(fraction: configuration.fractionCompleted ?? 0, label: configuration.currentValueLabel)
    }

    private struct GaugeProgressRing<Label: View>: View {
        let fraction: Double
        let label: Label?

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let dark = colorScheme == .dark
            GaugeGlyph(
                fraction: fraction,
                fill: HeatPalette.color(0.12 + 0.2 * fraction, dark: dark).color,
                track: DashboardPalette.secondary(dark: dark, increasedContrast: false).opacity(0.25),
                lineWidth: 3.5
            )
            .frame(width: 44, height: 44)
            .overlay {
                label
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.dashboardSecondary)
                    .offset(y: 1)
            }
            .animation(Motion.layout, value: fraction)
        }
    }
}

/// Subtle note about history that could not be fully read.
struct WarningsFootnote: View {
    let model: AgentSpeedModel
    let warnings: [MonitorWarning]

    var body: some View {
        let l10n = model.l10n
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(text(for: warning, l10n))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol(for: warning))
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .labelStyle(FootnoteLabelStyle())
            }
        }
        .font(DashboardFont.note)
        .foregroundStyle(.dashboardSecondary)
    }

    /// Known limitations get an info mark; read failures a warning triangle.
    private func symbol(for warning: MonitorWarning) -> String {
        switch warning {
        case .partialHistory, .unfinalizedUsage: "info.circle"
        case .unreadableFiles, .malformedLines, .unsupportedFormat: "exclamationmark.triangle"
        }
    }

    private func text(for warning: MonitorWarning, _ l10n: Localizer) -> String {
        switch warning {
        case .partialHistory: l10n("warning.partialHistory")
        case .unreadableFiles(let count): l10n("warning.unreadable", count)
        case .malformedLines(let count): l10n("warning.malformed", count)
        case .unfinalizedUsage(let count): l10n("warning.unfinalized", count)
        case .unsupportedFormat(let source): l10n("warning.unsupportedFormat", l10n(source.titleKey))
        }
    }
}

private struct FootnoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

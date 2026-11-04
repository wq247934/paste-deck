import AgentSpeedCore
import SwiftUI

/// Analysis state on the left (progress while the background analysis runs, else when it last finished) with the
/// unknown-price notice, the rate note and the privacy note on the right (DESIGN 4b item 5, DESIGN 9).
struct HistoryFooter: View {
    let store: HistoryStore
    let l10n: Localizer
    /// Why the range's unpriced requests have no price (METRICS 9.10).
    var unpriced: UnpricedView = .empty
    /// `以 2026/10/22 的匯率換算` for a non-USD currency.
    var rateNote: String?
    /// `網路流量自 10/22 開始記錄` when the range starts before traffic was recorded (DESIGN 10).
    var trafficSince: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            state
            if let trafficSince {
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(trafficSince)
                    .lineLimit(1)
                    .fixedSize()
            }
            if unpriced.unpriced > 0 {
                UnpricedNotice(view: unpriced, l10n: l10n)
                    .padding(.leading, Spacing.xs)
                    .layoutPriority(0.5)
            }
            Spacer(minLength: Spacing.m)
            if let rateNote {
                Text(rateNote)
                    .lineLimit(1)
                    .fixedSize()
                    .help(rateNote)
                Text(verbatim: "·")
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                privacy(l10n("history.privacy"))
                privacy(l10n("history.privacy.short"))
                privacyIcon
            }
            .help(l10n("history.privacy"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n("history.privacy"))
            .layoutPriority(-1)
        }
        .font(HistoryFont.footer)
        .foregroundStyle(.historySecondary)
        .padding(.horizontal, HistoryLayout.outerPadding)
        .frame(height: HistoryLayout.footerHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .contain)
    }

    /// The privacy note gives way first when the footer is crowded: full text, short text, then the icon (DESIGN 4b).
    private func privacy(_ text: String) -> some View {
        HStack(spacing: 5) {
            privacyIcon
            Text(text)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var privacyIcon: some View {
        Image(systemName: "lock.shield")
            .imageScale(.small)
    }

    @ViewBuilder
    private var state: some View {
        switch store.state {
        case .analyzing(let progress, let done, let total):
            HStack(spacing: Spacing.xs) {
                ProgressView(value: progress.clamped(to: 0...1))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 88)
                    .accessibilityHidden(true)
                Text(HistoryText.analyzing(progress, l10n))
                    .lineLimit(1)
                if total > 0 {
                    Text(HistoryText.analyzingFiles(done: done, total: total, l10n))
                        .lineLimit(1)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        case .ready(let updatedAt):
            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(HistoryText.updated(updatedAt, now: context.date, l10n))
                        .lineLimit(1)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(l10n("mac.history.refresh"))
                .accessibilityLabel(l10n("mac.history.refresh"))
            }
            .fixedSize()
            .transition(.opacity)
        case .failed:
            Label(l10n("mac.history.failed"), systemImage: "exclamationmark.triangle")
                .lineLimit(1)
                .fixedSize()
        case .notLoaded:
            EmptyView()
        }
    }
}

/// Centered muted gauge with `history.empty`; while the first analysis runs it fills with the progress instead.
struct HistoryEmptyState: View {
    let state: HistoryState
    let l10n: Localizer

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Spacing.s) {
            switch state {
            case .analyzing(let progress, let done, let total):
                ZStack {
                    RestingGauge(lineWidth: 3.2)
                        .opacity(0.5)
                    GaugeGlyph(
                        fraction: max(0.02, progress),
                        fill: Color.accentColor,
                        track: .clear,
                        lineWidth: 3.2
                    )
                    .animation(.easeOut(duration: 0.4), value: progress)
                }
                .frame(width: 52, height: 52)
                .padding(.bottom, Spacing.xxs)
                Text(HistoryText.analyzing(progress, l10n))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                if total > 0 {
                    Text(HistoryText.analyzingFiles(done: done, total: total, l10n))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.historySecondary)
                }
            default:
                RestingGauge(lineWidth: 3.2)
                    .frame(width: 52, height: 52)
                    .padding(.bottom, Spacing.xxs)
                Text(l10n("history.empty"))
                    .font(.system(size: 15, weight: .semibold))
                Text(l10n("history.empty.hint"))
                    .font(.system(size: 13))
                    .foregroundStyle(.historySecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

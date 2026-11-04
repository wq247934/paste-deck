import AgentSpeedCore
import AppKit
import SwiftUI

/// `1,234 筆請求的模型價格未知，未計入費用 · 查看`: the link opens the unknown-prices popover (DESIGN 9).
struct UnpricedNotice: View {
    let view: UnpricedView
    let l10n: Localizer

    @State private var shown = false

    var body: some View {
        let count = view.unpriced
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(l10n("history.unpricedNotice", count))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(l10n("history.unpricedNotice", count))
            Button(l10n("history.unpricedNotice.show")) { shown.toggle() }
                .buttonStyle(.link)
                .fixedSize()
                .popover(isPresented: $shown, arrowEdge: .top) {
                    UnpricedPopover(view: view, l10n: l10n)
                }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Every unpriced request of the window's view, grouped by source with the reason, provider, Fast and lookup key of
/// each row, the requests the current table prices now, and the copyable diagnostics (DESIGN 9 *Unknown prices*).
struct UnpricedPopover: View {
    static let width: CGFloat = 380
    /// Beyond this content height the groups scroll; the header and the footer stay put.
    static let maxContentHeight: CGFloat = 440
    static let minGroupsHeight: CGFloat = 120

    let view: UnpricedView
    let l10n: Localizer
    /// Previews show the copy button's later states, or every row.
    var copyState: CopyDiagnosticsButton.Outcome?
    var unboundedGroups = false

    @State private var headerHeight: CGFloat = 24
    @State private var footerHeight: CGFloat = 120

    var body: some View {
        let groups = view.groups.filter { !$0.rows.isEmpty }
        let groupsHeight = unboundedGroups ? .infinity
            : max(Self.minGroupsHeight, Self.maxContentHeight - headerHeight - footerHeight - 12)
        VStack(alignment: .leading, spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if !groups.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            UnpricedGroupView(group: group, l10n: l10n)
                                .padding(.top, index == 0 ? 0 : 12)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: groupsHeight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
            footer(afterGroups: !groups.isEmpty)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(Spacing.m)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l10n("cost.unknown"))
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: Spacing.s)
            Text(HistoryText.fullNumber(view.unpriced, l10n))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.historySecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func footer(afterGroups: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if view.pricedNow > 0 {
                Text(l10n("history.unpricedModels.pricedNow", view.pricedNow))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.historySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, afterGroups ? 12 : 10)
            }
            Divider()
                .padding(.vertical, 12)
            Text(l10n("history.unpricedModels.hint"))
                .font(.system(size: 11.5))
                .foregroundStyle(.historySecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 10) {
                CopyDiagnosticsButton(l10n: l10n, preview: copyState) {
                    UnpricedText.render(view, app: .current(version: AppInfo.version))
                }
                Text(l10n("history.unpricedModels.copyHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)
        }
    }
}

/// A source with its rows: the dot, the name and the Σ requests of its rows, then up to 20 rows.
private struct UnpricedGroupView: View {
    let group: UnpricedGroup
    let l10n: Localizer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(group.source.tint(dark: colorScheme == .dark))
                    .frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(l10n(group.source.titleKey))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                Text(HistoryText.fullNumber(group.rowRequests, l10n))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.historySecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(UnpricedDisplay.groupLabel(group, l10n))
            .accessibilityAddTraits(.isHeader)
            ForEach(group.rows.prefix(UnpricedDisplay.rowsPerGroup)) { row in
                UnpricedRowView(row: row, l10n: l10n)
                    .padding(.leading, 14)
            }
            if let more = UnpricedDisplay.more(group, l10n) {
                Text(more)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 14)
            }
        }
    }
}

/// Two lines: the model with its requests, then the reason chip with the provider, Fast and the lookup key.
private struct UnpricedRowView: View {
    let row: UnpricedRow
    let l10n: Localizer

    @Environment(\.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                if row.key.model.isEmpty {
                    Text(l10n("cost.noModelName"))
                        .font(.system(size: 12.5, weight: .medium))
                        .italic()
                        .foregroundStyle(.historySecondary)
                } else {
                    Text(row.key.model)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(row.key.model)
                }
                Spacer(minLength: Spacing.xs)
                Text(HistoryText.fullNumber(row.requests, l10n))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.historySecondary)
                    .fixedSize()
            }
            HStack(spacing: 0) {
                ReasonChip(diagnosis: row.diagnosis, l10n: l10n)
                    .fixedSize()
                detail
                    .font(.system(size: 11))
                    .foregroundStyle(.historySecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(UnpricedDisplay.lineHelp(row, l10n))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UnpricedDisplay.model(row, l10n))
        .accessibilityValue(UnpricedDisplay.accessibilityValue(row, l10n))
        .accessibilityHint(UnpricedDisplay.reasonHelp(row.diagnosis, l10n))
    }

    /// ` · 經由 custom · ⚡Fast · 查詢名稱 neko-model-ab`, the bolt in the speed color.
    private var detail: Text {
        let details = UnpricedDisplay.details(row, l10n)
        var text = Text(verbatim: "")
        if let provider = details.provider { text = text + Text(verbatim: UnpricedDisplay.separator) + Text(provider) }
        if details.fast {
            text = text + Text(verbatim: UnpricedDisplay.separator)
                + Text(Image(systemName: "bolt.fill")).foregroundStyle(EffortCapsulePalette(environment).bolt)
                + Text(verbatim: "\u{2009}") + Text(l10n("speed.value.fast"))
        }
        if let lookup = details.lookup { text = text + Text(verbatim: UnpricedDisplay.separator) + Text(lookup) }
        return text
    }
}

/// The reason as a neutral capsule: an unknown price is a gap, not an error, so every reason looks alike.
private struct ReasonChip: View {
    let diagnosis: UnpricedDiagnosis
    let l10n: Localizer

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        Text(UnpricedDisplay.reasonLabel(diagnosis.reason, l10n))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.historySecondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(increased ? 0.14 : 0.09)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(increased ? 0.5 : 0.16), lineWidth: increased ? 1 : 0.5))
            .help(UnpricedDisplay.reasonHelp(diagnosis, l10n))
    }
}

/// Copies the diagnostics text, then shows `已複製` (or the failure) for 1.6 s in place, keeping its width.
struct CopyDiagnosticsButton: View {
    enum Outcome: Equatable {
        case copied, failed
    }

    static let shownFor: TimeInterval = 1.6
    /// Long translations of a state shrink a little, then truncate, so the hint beside the button keeps its room.
    static let maxLabelWidth: CGFloat = 190

    let l10n: Localizer
    var preview: Outcome?
    let text: () -> String

    @State private var outcome: Outcome?
    @State private var token = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = preview ?? outcome
        Button(action: copy) {
            ZStack {
                label("doc.on.doc", "history.unpricedModels.copy").opacity(shown == nil ? 1 : 0)
                label("checkmark", "history.unpricedModels.copied").opacity(shown == .copied ? 1 : 0)
                label("exclamationmark.triangle", "history.unpricedModels.copyFailed").opacity(shown == .failed ? 1 : 0)
            }
            .frame(maxWidth: Self.maxLabelWidth)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: shown)
        .help(shown == .failed ? l10n("history.unpricedModels.copyFailed") : "")
        .accessibilityLabel(l10n("history.unpricedModels.copy"))
        .accessibilityValue(shown.map { $0 == .copied ? l10n("history.unpricedModels.copied") : l10n("history.unpricedModels.copyFailed") } ?? "")
    }

    private func label(_ symbol: String, _ key: String) -> some View {
        Label(l10n(key), systemImage: symbol)
            .font(.system(size: 11.5))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .accessibilityHidden(true)
    }

    private func copy() {
        let text = text()
        if Self.write(text) {
            finish(.copied)
        } else {
            // Another app may hold the pasteboard for a moment: one retry.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                finish(Self.write(text) ? .copied : .failed)
            }
        }
    }

    private static func write(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func finish(_ result: Outcome) {
        outcome = result
        token &+= 1
        let current = token
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: l10n(result == .copied ? "history.unpricedModels.copied" : "history.unpricedModels.copyFailed"),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shownFor) {
            if token == current { outcome = nil }
        }
    }
}

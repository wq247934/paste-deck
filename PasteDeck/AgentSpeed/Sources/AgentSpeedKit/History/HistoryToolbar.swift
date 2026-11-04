import AgentSpeedCore
import AppKit
import SwiftUI

/// The window's unified toolbar (DESIGN 4b, item 1): source picker leading, range control centered, CSV export
/// trailing. Native AppKit items, kept in sync with the view model and the app language. It never wraps or hides an
/// item in the overflow menu: as the window narrows it tightens the range segments, shows export as an icon, then
/// shortens the range labels (`Fit.ladder`).
@MainActor
final class HistoryToolbar: NSObject, NSToolbarDelegate {
    private static let sourceID = NSToolbarItem.Identifier("history.source")
    private static let subscriptionsID = NSToolbarItem.Identifier("history.subscriptions")
    private static let rangeID = NSToolbarItem.Identifier("history.range")
    private static let exportID = NSToolbarItem.Identifier("history.export")
    private static let ranges: [HistoryRangeKind] = HistoryRangeKind.allCases

    /// What the toolbar gives up to stay on one line.
    private struct Fit: Equatable {
        /// Short range labels (`7D`, `YTD`) and a calendar for 自訂…; the full labels stay in the tooltips.
        var shortLabels = false
        /// Room around a label in a segment that hugs it; nil keeps the control's own widths. Whether hugging is
        /// narrower depends on how the system insets toolbar segments, so both are measured.
        var segmentPadding: CGFloat?
        var iconExport = false
        /// The `history.includeSubscriptions` checkbox becomes an icon toggle, its label kept as the tooltip.
        var iconSubscriptions = false

        /// Least given up first.
        static let ladder: [Fit] = [
            Fit(),
            Fit(segmentPadding: 8),
            Fit(iconExport: true),
            Fit(segmentPadding: 8, iconExport: true),
            Fit(segmentPadding: 8, iconExport: true, iconSubscriptions: true),
            Fit(shortLabels: true, iconExport: true, iconSubscriptions: true),
            Fit(shortLabels: true, segmentPadding: 4, iconExport: true, iconSubscriptions: true),
        ]
    }

    /// Room the toolbar needs beyond its items: the gaps between them and the trailing margin.
    private static let gaps: CGFloat = 32
    /// Where the first item starts when it has not been laid out yet (after the window buttons).
    private static let defaultLeading: CGFloat = 96
    private static let iconExportWidth: CGFloat = 40

    private let model: HistoryViewModel
    private let onExport: () -> Void
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rangeControl = NSSegmentedControl()
    private let subscriptionsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var sourceItem: NSToolbarItem?
    private var subscriptionsItem: NSToolbarItem?
    /// Marked subscription sources and the language the source menu was built for.
    private var shownMarks: Set<SourceKind> = []
    private var rangeItem: NSToolbarItem?
    private var exportItem: NSToolbarItem?
    private var popover: NSPopover?
    private var loop: ObservationLoop?
    private var shownSources: [SourceKind?] = []
    private var shownLanguage: AppLanguage?
    private var fit = Fit.ladder[0]
    /// Extra room learned when the toolbar still overflowed at a fit the estimate allowed.
    private var learnedSlack: CGFloat = 0
    /// The range control's width at each rung of the ladder, for a language and whether it sat in the toolbar.
    private var measured: (key: String, widths: [CGFloat])?
    nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?

    let toolbar: NSToolbar

    init(model: HistoryViewModel, onExport: @escaping () -> Void) {
        self.model = model
        self.onExport = onExport
        toolbar = NSToolbar(identifier: "AgentSpeedHistoryToolbar")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.rangeID]

        sourcePopup.bezelStyle = .toolbar
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged(_:))

        rangeControl.segmentCount = Self.ranges.count
        rangeControl.trackingMode = .selectOne
        rangeControl.segmentDistribution = .fit
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))

        subscriptionsButton.target = self
        subscriptionsButton.action = #selector(subscriptionsChanged(_:))
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window, window.toolbar === self.toolbar else { return }
                self.refit()
            }
        }

        loop = ObservationLoop { [weak self] in self?.sync() }
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sourceID, .flexibleSpace, Self.rangeID, .flexibleSpace, Self.exportID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [Self.subscriptionsID]
    }

    /// Items are added as the toolbar joins a window; fit it once it is there.
    func toolbarWillAddItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.refit() }
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.sourceID:
            item.view = sourcePopup
            item.visibilityPriority = .high
            sourceItem = item
        case Self.rangeID:
            item.view = rangeControl
            item.visibilityPriority = .high
            rangeItem = item
        case Self.exportID:
            item.isBordered = true
            item.target = self
            item.action = #selector(export(_:))
            exportItem = item
        case Self.subscriptionsID:
            item.view = subscriptionsButton
            item.visibilityPriority = .high
            subscriptionsItem = item
        default:
            return nil
        }
        applyLabels(model.l10n)
        sync()
        return item
    }

    // MARK: Sync

    private func sync() {
        let l10n = model.l10n
        let content = model.content
        let language = l10n.language
        let sources: [SourceKind?] = [nil] + content.pickerSources.map { Optional($0) }
        let marks = content.costOptions.marked
        if sources != shownSources || language != shownLanguage || marks != shownMarks {
            shownMarks = marks
            rebuildSourceMenu(sources, l10n: l10n)
        }
        syncSubscriptions(offered: content.offersSubscriptionToggle, l10n: l10n)
        if let index = shownSources.firstIndex(of: model.source), sourcePopup.selectedTag() != index {
            sourcePopup.selectItem(withTag: index)
        }
        if language != shownLanguage {
            shownLanguage = language
            applyLabels(l10n)
            refit()
        }
        if let index = Self.ranges.firstIndex(of: model.rangeKind), rangeControl.selectedSegment != index {
            rangeControl.selectedSegment = index
        }
        let canExport = !content.rows.isEmpty
        if exportItem?.isEnabled != canExport { exportItem?.isEnabled = canExport }
        _ = model.accessibility.reduceMotion
    }

    /// Localized labels of the controls and items at the current fit; runs on a language or fit change and for every
    /// new item.
    private func applyLabels(_ l10n: Localizer) {
        Self.configure(rangeControl, fit: fit, l10n: l10n)
        rangeControl.setAccessibilityLabel(l10n("mac.history.range"))
        sourcePopup.setAccessibilityLabel(l10n("dashboard.sources"))
        sourceItem?.label = l10n("dashboard.sources")
        sourceItem?.toolTip = l10n("dashboard.sources")
        rangeItem?.label = l10n("mac.history.range")
        let export = l10n("history.export")
        exportItem?.label = export
        exportItem?.toolTip = export
        if fit.iconExport {
            exportItem?.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: export)
            exportItem?.title = ""
        } else {
            exportItem?.image = nil
            exportItem?.title = export
        }
        Self.configure(subscriptionsButton, icon: fit.iconSubscriptions, l10n: l10n)
        subscriptionsItem?.label = l10n("history.includeSubscriptions")
        subscriptionsItem?.toolTip = l10n("history.includeSubscriptions")
        sourcePopup.sizeToFit()
        rangeControl.sizeToFit()
    }

    /// A checkbox with `history.includeSubscriptions`, or an icon toggle when the toolbar is tight.
    private static func configure(_ button: NSButton, icon: Bool, l10n: Localizer) {
        let title = l10n("history.includeSubscriptions")
        if icon {
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .toolbar
            button.title = ""
            button.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: title)
            button.alternateImage = NSImage(systemSymbolName: "creditcard.fill", accessibilityDescription: title)
            button.imagePosition = .imageOnly
        } else {
            button.setButtonType(.switch)
            button.image = nil
            button.alternateImage = nil
            button.imagePosition = .noImage
            button.title = title
        }
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.sizeToFit()
    }

    /// Shows the checkbox while at least one source is marked as a subscription (DESIGN 9) and mirrors the choice.
    /// The item is inserted or removed on the next turn, never while the toolbar is building its items.
    private func syncSubscriptions(offered: Bool, l10n: Localizer) {
        let state: NSControl.StateValue = model.includeSubscriptions ? .on : .off
        if subscriptionsButton.state != state { subscriptionsButton.state = state }
        DispatchQueue.main.async { [weak self] in self?.placeSubscriptions(offered: offered) }
    }

    private func placeSubscriptions(offered: Bool) {
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.subscriptionsID }
        guard let source = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.sourceID }) else { return }
        if offered, index == nil {
            toolbar.insertItem(withItemIdentifier: Self.subscriptionsID, at: source + 1)
            refit()
        } else if !offered, let index {
            toolbar.removeItem(at: index)
            subscriptionsItem = nil
            refit()
        }
    }

    /// Range labels and segment widths of `fit`; a shortened label keeps the full one as the segment's tooltip.
    private static func configure(_ control: NSSegmentedControl, fit: Fit, l10n: Localizer) {
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for (index, kind) in ranges.enumerated() {
            let full = l10n(kind.titleKey)
            let icon = fit.shortLabels && kind == .custom
                ? NSImage(systemSymbolName: "calendar", accessibilityDescription: full)
                : nil
            let label = icon != nil ? "" : (fit.shortLabels ? l10n(kind.shortTitleKey) : full)
            control.setLabel(label, forSegment: index)
            control.setImage(icon, forSegment: index)
            control.setToolTip(label == full ? nil : full, forSegment: index)
            if let padding = fit.segmentPadding {
                let content = icon?.size.width ?? (label as NSString).size(withAttributes: [.font: font]).width
                control.setWidth(ceil(content + padding), forSegment: index)
            } else {
                control.setWidth(0, forSegment: index)
            }
        }
        control.sizeToFit()
    }

    // MARK: Fit

    /// The window showing this toolbar. An item in the overflow menu has no window, so it is looked up by toolbar.
    private var window: NSWindow? {
        NSApp.windows.first { $0.toolbar === toolbar }
    }

    /// Picks the most generous fit the window's width allows, then makes sure nothing went to the overflow menu.
    private func refit() {
        guard let window else { return }
        let width = window.frame.width
        let l10n = model.l10n
        let required = requiredWidths(l10n)
        let index = required.firstIndex { $0 + learnedSlack <= width } ?? Fit.ladder.count - 1
        if Fit.ladder[index] != fit {
            fit = Fit.ladder[index]
            applyLabels(l10n)
        }
        DispatchQueue.main.async { [weak self] in self?.checkOverflow() }
    }

    /// The toolbar hid an item although the estimate said it fits (another system's metrics): learn the difference and
    /// step down.
    private func checkOverflow() {
        guard let window, let visible = toolbar.visibleItems?.map(\.itemIdentifier), fit != Fit.ladder.last else { return }
        let wanted = [Self.sourceID, Self.rangeID, Self.exportID] + (subscriptionsItem == nil ? [] : [Self.subscriptionsID])
        guard !wanted.allSatisfy(visible.contains),
              let index = Fit.ladder.firstIndex(of: fit) else { return }
        learnedSlack = max(learnedSlack, requiredWidths(model.l10n)[index] - window.frame.width + 8)
        refit()
    }

    /// The width the toolbar needs at each rung of the ladder. The range control is measured in place (a toolbar insets
    /// its segments) and only once per language; the current fit is restored before anything is drawn.
    private func requiredWidths(_ l10n: Localizer) -> [CGFloat] {
        let key = "\(l10n.language)-\(rangeControl.window != nil)"
        let ranges: [CGFloat]
        if let measured, measured.key == key {
            ranges = measured.widths
        } else {
            ranges = Fit.ladder.map { candidate in
                Self.configure(rangeControl, fit: candidate, l10n: l10n)
                return rangeControl.fittingSize.width
            }
            Self.configure(rangeControl, fit: fit, l10n: l10n)
            measured = (key, ranges)
        }
        let popupFrame = sourcePopup.window == nil ? nil : sourcePopup.convert(sourcePopup.bounds, to: nil)
        let leading = popupFrame.map(\.minX).flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultLeading
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textExport = ceil((l10n("history.export") as NSString).size(withAttributes: [.font: font]).width) + 28
        let checkbox = ceil((l10n("history.includeSubscriptions") as NSString).size(withAttributes: [.font: font]).width) + 34
        let offered = subscriptionsItem != nil
        return zip(Fit.ladder, ranges).map { candidate, range in
            let subscriptions: CGFloat = offered ? (candidate.iconSubscriptions ? Self.iconExportWidth : checkbox) + 8 : 0
            return leading + sourcePopup.frame.width + subscriptions + range
                + (candidate.iconExport ? Self.iconExportWidth : textExport) + Self.gaps
        }
    }

    private func rebuildSourceMenu(_ sources: [SourceKind?], l10n: Localizer) {
        let menu = NSMenu()
        for (index, source) in sources.enumerated() {
            let title = source.map { l10n($0.titleKey) } ?? l10n("history.allSources")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let source, shownMarks.contains(source) {
                // A subscription source carries `cost.subscription.tag` (DESIGN 9) as a badge, which leaves the
                // popup's width to the names.
                item.badge = NSMenuItemBadge(string: l10n("cost.subscription.tag"))
                item.setAccessibilityLabel("\(title), \(l10n("cost.subscription.tag"))")
            }
            item.image = Self.swatch(source.map { [$0] } ?? Array(sources.compactMap { $0 }.prefix(4)))
            item.tag = index
            menu.addItem(item)
            if source == nil, sources.count > 1 { menu.addItem(.separator()) }
        }
        sourcePopup.menu = menu
        shownSources = sources
        if let index = sources.firstIndex(of: model.source) { sourcePopup.selectItem(withTag: index) }
        sourcePopup.sizeToFit()
    }

    /// A small dot in the source color; for all sources, a dot split between the sources' colors.
    private static func swatch(_ sources: [SourceKind]) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            guard !sources.isEmpty else {
                NSColor.secondaryLabelColor.setFill()
                circle.fill()
                return true
            }
            circle.addClip()
            let colors = sources.map { $0.tint.darkened(dark ? 0 : 0.14).nsColor }
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let step = 360 / CGFloat(colors.count)
            for (index, color) in colors.enumerated() {
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: rect.width, startAngle: 90 - step * CGFloat(index + 1), endAngle: 90 - step * CGFloat(index))
                wedge.close()
                color.setFill()
                wedge.fill()
            }
            return true
        }
        return image
    }

    // MARK: Actions

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        let index = sender.selectedTag()
        guard shownSources.indices.contains(index) else { return }
        model.select(source: shownSources[index])
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard Self.ranges.indices.contains(index) else { return }
        let kind = Self.ranges[index]
        if kind == .custom {
            showCustomRange()
        } else {
            popover?.close()
            model.select(range: kind)
        }
    }

    @objc private func export(_ sender: Any?) {
        onExport()
    }

    @objc private func subscriptionsChanged(_ sender: NSButton) {
        model.setIncludeSubscriptions(sender.state == .on)
    }

    // MARK: Custom range

    #if DEBUG
    /// Opens the custom range popover as a click on its segment would (screenshots).
    func debugShowCustomRange() -> NSPopover? {
        showCustomRange()
        return popover
    }
    #endif

    private func showCustomRange() {
        // The control shows the custom segment only once a custom range is applied.
        if let index = Self.ranges.firstIndex(of: model.rangeKind) { rangeControl.selectedSegment = index }
        if let popover, popover.isShown {
            popover.close()
            return
        }
        let content = model.content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !model.accessibility.reduceMotion
        let view = CustomRangeView(
            bounds: content.selectableBounds,
            initial: content.range,
            l10n: model.l10n
        ) { [weak self, weak popover] from, to in
            self?.model.applyCustom(from: from, to: to)
            popover?.performClose(nil)
        }
        let host = NSHostingController(rootView: view.environment(\.locale, model.l10n.locale))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        self.popover = popover
        // Below the control: its bottom edge is maxY when the view is flipped.
        popover.show(relativeTo: customSegmentRect(), of: rangeControl, preferredEdge: rangeControl.isFlipped ? .maxY : .minY)
    }

    /// The custom segment is the last one; its width is set when the segments are tight, else follows its label.
    private func customSegmentRect() -> NSRect {
        let bounds = rangeControl.bounds
        let index = Self.ranges.count - 1
        let label = rangeControl.label(forSegment: index) ?? ""
        let font = rangeControl.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let set = rangeControl.width(forSegment: index)
        let width = min(bounds.width, set > 0 ? set : (label as NSString).size(withAttributes: [.font: font]).width + 24)
        return NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
    }
}

/// From / to date pickers clamped to the days with data (the end never before the start) and Apply.
struct CustomRangeView: View {
    let bounds: DayRange
    let l10n: Localizer
    let onApply: (DayKey, DayKey) -> Void

    @State private var from: Date
    @State private var to: Date

    init(bounds: DayRange, initial: DayRange, l10n: Localizer, onApply: @escaping (DayKey, DayKey) -> Void) {
        self.bounds = bounds
        self.l10n = l10n
        self.onApply = onApply
        let calendar = HistoryDates.calendar
        let clamped = HistoryRanges.clamp(from: initial.start, to: initial.end, within: bounds)
        _from = State(initialValue: clamped.start.date(in: calendar))
        _to = State(initialValue: clamped.end.date(in: calendar))
    }

    var body: some View {
        let calendar = HistoryDates.calendar
        let minimum = bounds.start.date(in: calendar)
        let maximum = bounds.end.date(in: calendar)
        let start = DayKey(from, calendar: calendar)
        let end = max(start, DayKey(to, calendar: calendar))
        VStack(alignment: .leading, spacing: Spacing.s) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.xs) {
                GridRow {
                    Text(l10n("history.range.from"))
                        .foregroundStyle(.historySecondary)
                        .gridColumnAlignment(.trailing)
                    DatePicker(l10n("history.range.from"), selection: $from, in: minimum...maximum, displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text(l10n("history.range.to"))
                        .foregroundStyle(.historySecondary)
                    DatePicker(l10n("history.range.to"), selection: $to, in: max(minimum, from)...maximum, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .datePickerStyle(.compact)
            HStack {
                Text(HistoryText.days(DayRange(start, end).count, l10n))
                    .monospacedDigit()
                    .foregroundStyle(.historySecondary)
                    .contentTransition(.numericText())
                Spacer(minLength: Spacing.m)
                Button(l10n("history.range.apply")) {
                    onApply(start, end)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(Spacing.m)
        .frame(width: 260)
        .environment(\.calendar, calendar)
        .onChange(of: from) { _, newValue in
            if to < newValue { to = newValue }
        }
    }
}

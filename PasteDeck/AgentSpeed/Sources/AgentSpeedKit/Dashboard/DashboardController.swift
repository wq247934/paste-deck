import AppKit
import SwiftUI

/// Hosts the dashboard in a transient popover anchored to the status item.
@MainActor
final class DashboardController: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 368

    /// Room kept free between the popover and the screen's visible edges (arrow included).
    private static let screenMargin: CGFloat = 28

    private let model: AgentSpeedModel
    private var popover: NSPopover?
    /// The agent rows' score cards, alive while the panel is open.
    private var scoreCards: DashboardScoreCards?
    private var closedAt: TimeInterval = 0
    private var appearanceObservation: NSKeyValueObservation?
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AgentSpeedModel) {
        self.model = model
    }

    var isShown: Bool { popover?.isShown ?? false }

    #if DEBUG
    var debugPopover: NSPopover? { popover }
    #endif

    func toggle(relativeTo view: NSView) {
        if isShown {
            close()
        } else if Clock.now - closedAt > 0.15 {
            show(relativeTo: view)
        }
    }

    func show(relativeTo view: NSView) {
        guard !isShown else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !model.accessibility.reduceMotion
        popover.delegate = self
        // The content keeps its ideal height, which the popover follows frame by frame through the preferred content
        // size, and stays pinned to the top, so a window a point off never squeezes, shifts or re-centres it.
        let cards = DashboardScoreCards(model: model)
        scoreCards = cards
        let root = DashboardView(model: model, maxHeight: Self.maxHeight(below: view))
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .environment(\.dashboardScoreCards, cards)
            .appEnvironment(model)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        self.popover = popover
        applyAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
        NSApp.activate()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        onVisibilityChange?(true)
    }

    func close() {
        popover?.performClose(nil)
    }

    func popoverWillClose(_ notification: Notification) {
        scoreCards?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        scoreCards?.close()
        scoreCards = nil
        appearanceObservation = nil
        closedAt = Clock.now
        popover?.contentViewController = nil
        popover = nil
        onVisibilityChange?(false)
    }

    /// A popover takes its appearance from the menu bar it hangs from, which on macOS 26 follows the desktop picture
    /// rather than the app. The dashboard follows the app's Appearance setting (and the system under Auto) instead.
    private func applyAppearance() {
        guard let popover else { return }
        let wanted: NSAppearance?
        if let chosen = NSApp.appearance {
            wanted = chosen
        } else if #available(macOS 26, *) {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        } else {
            wanted = nil
        }
        if popover.appearance?.name != wanted?.name { popover.appearance = wanted }
    }

    /// Height available under the anchor on its screen, so the popover never runs off the bottom edge.
    private static func maxHeight(below view: NSView) -> CGFloat? {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return nil }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let available = anchor.minY - screen.visibleFrame.minY - screenMargin
        return available > 240 ? available : nil
    }
}

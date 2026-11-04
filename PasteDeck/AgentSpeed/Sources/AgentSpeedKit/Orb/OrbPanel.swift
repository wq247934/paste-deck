import AppKit

/// Borderless, non-activating, transparent panel that hosts the floating orb. It never becomes key or main, so
/// clicking the orb never steals focus from the app the user is working in.
final class OrbPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        canHide = false
        acceptsMouseMovedEvents = true
        alphaValue = 0
        setAccessibilitySubrole(.floatingWindow)
    }

    /// Window side for a disc diameter: the canvas is `OrbView.canvasScale` × the disc, with whole-point margins so
    /// the disc edge stays on the pixel grid.
    static func side(for diameter: CGFloat) -> CGFloat {
        diameter + 2 * (diameter * (OrbView.canvasScale - 1) / 2).rounded(.up)
    }

    func apply(alwaysOnTop: Bool, allSpaces: Bool) {
        let nextLevel: NSWindow.Level = alwaysOnTop ? .floating : .normal
        if level != nextLevel { level = nextLevel }
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
        behavior.insert(allSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        if collectionBehavior != behavior { collectionBehavior = behavior }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Placement is fully managed by `OrbWindowController`; AppKit must not nudge the frame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

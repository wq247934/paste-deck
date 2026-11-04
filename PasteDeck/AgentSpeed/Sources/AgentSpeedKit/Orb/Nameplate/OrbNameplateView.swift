import AppKit

/// The plate's window: a borderless, non-activating, transparent panel, a child of the orb's panel so it moves with
/// it. It never becomes key; outside the capsule it lets every click through.
final class OrbNameplateWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        becomesKeyOnlyIfNeeded = true
        canHide = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The plate's content: the desktop blur clipped to the capsule and a layer with the drawn plate, redrawn only when
/// its scene changes. Pointer input on the capsule goes to the orb (DESIGN 2b, Name plate, Window and pointer).
final class OrbNameplateView: NSView {
    weak var delegate: OrbHostViewDelegate?
    var cursor: NSCursor?

    private let blur = NameplateBlurView(frame: .zero)
    private let canvas = NameplateCanvasView(frame: .zero)
    private var trackingArea: NSTrackingArea?
    /// The capsule as drawn now, for hit testing (view coordinates).
    private(set) var capsule: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        blur.autoresizingMask = []
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(blur)
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `scene` (view coordinates): the blur follows the capsule (hidden with solid fills), the canvas redraws.
    func show(_ scene: NameplateScene?) {
        guard let scene else {
            capsule = .zero
            canvas.scene = nil
            blur.isHidden = true
            return
        }
        let rect = scene.plate
        let scaled = CGRect(x: rect.midX - rect.width * scene.scale / 2, y: rect.midY - rect.height * scene.scale / 2,
                            width: rect.width * scene.scale, height: rect.height * scene.scale)
        capsule = scaled
        let showsBlur = !scene.tokens.solid && scene.opacity > 0.001
        if blur.isHidden == showsBlur { blur.isHidden = !showsBlur }
        if showsBlur {
            blur.setDark(scene.tokens.isDark)
            if blur.frame != scaled { blur.frame = scaled }
            if blur.alphaValue != scene.opacity { blur.alphaValue = scene.opacity }
        }
        canvas.scene = scene
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    /// Whether a point in view coordinates is on the capsule (1 pt of tolerance plus `slack`).
    func capsuleContains(_ point: NSPoint, slack: CGFloat = 0) -> Bool {
        guard capsule.width > 0 else { return false }
        let rect = capsule.insetBy(dx: -1 - slack, dy: -1 - slack)
        guard rect.contains(point) else { return false }
        let radius = rect.height / 2
        let x = min(max(point.x, rect.minX + radius), rect.maxX - radius)
        return hypot(point.x - x, point.y - rect.midY) <= radius
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return capsuleContains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { delegate?.hostPointerMoved() }
    override func mouseExited(with event: NSEvent) { delegate?.hostPointerMoved() }
    override func mouseMoved(with event: NSEvent) { delegate?.hostPointerMoved() }

    override func cursorUpdate(with event: NSEvent) {
        if let cursor, capsuleContains(convert(event.locationInWindow, from: nil)) {
            cursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) { delegate?.hostMouseDown(event) }
    override func mouseDragged(with event: NSEvent) { delegate?.hostMouseDragged(event) }
    override func mouseUp(with event: NSEvent) { delegate?.hostMouseUp(event) }
    override func rightMouseDown(with event: NSEvent) { delegate?.hostShowMenu(event) }
}

/// Draws the plate's scene into its cached layer; AppKit keeps the result until the scene changes.
final class NameplateCanvasView: NSView {
    var scene: NameplateScene? {
        didSet { if scene != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    #if DEBUG
    /// Plate redraws so far (`--nameplates-demo` checks that static plates draw nothing).
    static var draws = 0
    #endif

    override func draw(_ dirtyRect: NSRect) {
        guard let scene, let context = NSGraphicsContext.current?.cgContext else { return }
        #if DEBUG
        Self.draws += 1
        #endif
        NameplateRenderer.draw(scene, in: context)
    }
}

/// The desktop blur behind the capsule: `.hudWindow` on dark plates, `.popover` on light ones.
final class NameplateBlurView: NSVisualEffectView {
    private var maskHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        material = .hudWindow
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setDark(_ dark: Bool) {
        let next: NSVisualEffectView.Material = dark ? .hudWindow : .popover
        if material != next { material = next }
        let wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        if appearance?.name != wanted?.name { appearance = wanted }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMask()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    /// A stretchable capsule, so width changes need no new mask.
    private func updateMask() {
        let height = bounds.height
        guard height > 0, abs(height - maskHeight) > 0.01 else { return }
        maskHeight = height
        let inset: CGFloat = 0.5
        let image = NSImage(size: NSSize(width: height + 2, height: height), flipped: false) { rect in
            NSColor.black.setFill()
            let shape = rect.insetBy(dx: inset, dy: inset)
            NSBezierPath(roundedRect: shape, xRadius: shape.height / 2, yRadius: shape.height / 2).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2)
        image.resizingMode = .stretch
        maskImage = image
    }
}

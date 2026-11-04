import AgentSpeedOrbModel
import AppKit

/// The desktop undo chip when its orb shows a name plate (DESIGN 2b, Name plate, Chip and undo): stacked 4 pt beyond
/// the plate, in the plate's metrics and material, with `orbs.undo` in the accent color as its button.
@MainActor
final class OrbNameplateUndoChip {
    static let stackGap: CGFloat = 4

    let panel: NSPanel
    private let view = NameplateUndoChipView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    private(set) var isShown = false
    private var generation = 0
    private var capsuleSize: CGSize = .zero

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.alphaValue = 0
        panel.contentView = view
    }

    /// Shows the chip; `place` turns the capsule's size into its frame in screen points.
    func show(message: String, action: String, metrics: NameplateMetrics, tokens: NameplateTokens, level: NSWindow.Level,
              onAction: @escaping () -> Void, place: (CGSize) -> CGRect) {
        let typesetter = NameplateTypesetter.shared
        let face = NameplateFace.expanded(
            [NameplateFace.Item(dot: nil, text: message, role: .text), NameplateFace.Item(dot: nil, text: action, role: .accent)],
            metrics: metrics
        ) { text, tracking in typesetter.width(text, size: metrics.fontSize, tracking: tracking) }
        capsuleSize = CGSize(width: face.width, height: metrics.height)
        view.configure(face: face, metrics: metrics, tokens: tokens, onAction: onAction)
        panel.level = level
        reposition(place: place)
        generation &+= 1
        if !isShown {
            isShown = true
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func reposition(place: (CGSize) -> CGRect) {
        guard capsuleSize.width > 0 else { return }
        let capsule = place(capsuleSize)
        let margin = NameplateRenderer.margin
        let frame = capsule.insetBy(dx: -margin, dy: -margin).integral
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.place(capsule: capsule.offsetBy(dx: -frame.minX, dy: -frame.minY))
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        generation &+= 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Draws the undo chip and turns a click on its accent text into the action.
final class NameplateUndoChipView: NSView {
    private let blur = NameplateBlurView(frame: .zero)
    private let canvas = NameplateCanvasView(frame: .zero)
    private var face: NameplateFace?
    private var metrics: NameplateMetrics?
    private var tokens: NameplateTokens?
    private var onAction: (() -> Void)?
    private var capsule: CGRect = .zero
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(blur)
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(face: NameplateFace, metrics: NameplateMetrics, tokens: NameplateTokens, onAction: @escaping () -> Void) {
        self.face = face
        self.metrics = metrics
        self.tokens = tokens
        self.onAction = onAction
        redraw()
    }

    func place(capsule: CGRect) {
        self.capsule = capsule
        redraw()
    }

    private func redraw() {
        guard let face, let metrics, let tokens, capsule.width > 0 else { return }
        var scene = NameplateScene(plate: capsule, metrics: metrics, tokens: tokens)
        scene.add(face, originX: capsule.minX, alpha: 1)
        blur.isHidden = tokens.solid
        blur.setDark(tokens.isDark)
        if blur.frame != capsule { blur.frame = capsule }
        canvas.scene = scene
    }

    /// The accent text's hit area: from just before it to the capsule's end, the capsule's full height.
    private var actionRect: CGRect {
        guard let face, let metrics, let run = face.runs.last else { return .zero }
        let start = capsule.minX + run.x - metrics.itemGap / 2
        return CGRect(x: start, y: capsule.minY, width: capsule.maxX - start, height: capsule.height)
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return capsule.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect], owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(event)
    }

    private func updateCursor(_ event: NSEvent) {
        (actionRect.contains(convert(event.locationInWindow, from: nil)) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseUp(with event: NSEvent) {
        if actionRect.contains(convert(event.locationInWindow, from: nil)) { onAction?() }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { face?.runs.map(\.text).joined(separator: " · ") }

    override func accessibilityPerformPress() -> Bool {
        onAction?()
        return true
    }
}

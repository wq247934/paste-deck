import AgentSpeedOrbModel
import AppKit
import QuartzCore

/// One orb's name plate (DESIGN 2b, Name plate): a child window of the orb's panel that shows the plate in the slot the
/// placement solver gave it, follows the disc (through the hover scale and drags), widens to the chip's content, and
/// animates appearing, disappearing, renaming and moving. Static plates draw nothing; the display link runs only
/// while something moves.
@MainActor
final class OrbNameplateController {
    let window = OrbNameplateWindow()
    private let view: OrbNameplateView
    private weak var parent: NSWindow?
    private var motion = NameplateMotion()
    private var link: CADisplayLink?
    private lazy var proxy = NameplateDisplayLinkProxy(owner: self)
    private var appearTimer: Timer?

    /// The chip content, read when the plate widens.
    var chipItems: (() -> [NameplateFace.Item])?

    private(set) var content: OrbNameplateContent?
    private(set) var tokens = NameplateTokens(dark: true, reduceTransparency: false, increaseContrast: false)
    private var reduceMotion = false
    private var orbShown = false
    /// The resolved placement at rest.
    private(set) var slot: NameplateSlot?
    /// The disc as drawn now (hover and entrance scale included) and the usable area of its display.
    private var disc = OrbDisc(center: .zero, radius: 0)
    private var area: CGRect = .zero
    private var wantsExpanded = false
    private var pendingAppearDelay: TimeInterval = 0

    // What is on screen.
    private(set) var isPresenting = false
    private var shownSlot: NameplateSlot?
    private var face: NameplateFace?
    private var previous: NameplateFace?
    private var expanded: NameplateFace?
    private var movingToNewSlot = false

    init(parent: NSWindow, delegate: OrbHostViewDelegate) {
        self.parent = parent
        view = OrbNameplateView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.delegate = delegate
        window.contentView = view
        window.alphaValue = 0
    }

    func close() {
        stopLink()
        appearTimer?.invalidate()
        detach()
        window.close()
    }

    // MARK: Inputs

    /// nil when the orb shows no plate (its setting, the auto rule, or below 80 pt).
    func setContent(_ content: OrbNameplateContent?) {
        guard content != self.content else { return }
        self.content = content
        refresh()
    }

    func setTokens(_ tokens: NameplateTokens, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard tokens != self.tokens else { return }
        self.tokens = tokens
        layout()
    }

    func setOrbShown(_ shown: Bool) {
        guard shown != orbShown else { return }
        orbShown = shown
        refresh()
    }

    /// The placement solver's result; nil hides the plate (nothing fits, or not wanted).
    func setSlot(_ slot: NameplateSlot?) {
        guard slot != self.slot else { return }
        self.slot = slot
        refresh()
    }

    /// The next appearance waits this long (new orbs: 0.28 s after landing).
    func delayNextAppearance(_ delay: TimeInterval) {
        pendingAppearDelay = delay
    }

    /// The disc moved or scaled (every frame of the orb's own animation, and drags).
    func follow(disc: OrbDisc, area: CGRect) {
        guard disc != self.disc || area != self.area else { return }
        self.disc = disc
        self.area = area
        if isPresenting || motion.isActive { layout() }
    }

    func setLevel(_ level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) {
        if window.level != level { window.level = level }
        if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
    }

    func setAppearance(_ appearance: NSAppearance?) {
        window.appearance = appearance
    }

    var cursor: NSCursor? {
        get { view.cursor }
        set { view.cursor = newValue }
    }

    // MARK: State

    var wantsPlate: Bool { content != nil }
    var isExpanded: Bool { wantsExpanded }
    /// A plate is on (or coming onto) the desktop, so the source chip folds into it.
    var foldsChip: Bool { isPresenting }

    /// The plate at rest in screen coordinates, at the disc's current position.
    var restFrame: CGRect? {
        guard isPresenting, let slot = shownSlot, let face else { return nil }
        let edges = restEdges(width: face.width, side: slot.side)
        return capsule(left: edges.left, right: edges.right, side: slot.side, approach: 0)
    }

    var restSide: NameplateSide? { isPresenting ? shownSlot?.side : nil }

    /// Whether a screen point is on the capsule, or within `slack` of it (keeping a hover while the disc's hover scale
    /// moves the plate, and across the gap to the disc).
    func contains(screenPoint point: NSPoint, slack: CGFloat = 0) -> Bool {
        guard isPresenting, window.isVisible, motion.sample(at: CACurrentMediaTime()).presence > 0.5 else { return false }
        let local = NSPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        return view.capsuleContains(local, slack: slack)
    }

    /// The hover slack: the gap to the disc and a little more.
    var hoverSlack: CGFloat { (content?.metrics.gap ?? 4) + 3 }

    /// The capsule takes the mouse only while the pointer is over it.
    func setAcceptsMouse(_ accepts: Bool) {
        if window.ignoresMouseEvents == accepts { window.ignoresMouseEvents = !accepts }
    }

    /// Widens to the chip's content (hover after 0.35 s, drags, 2 s after a sources change) or returns.
    func setExpanded(_ expanded: Bool) {
        guard expanded != wantsExpanded else { return }
        wantsExpanded = expanded
        updateExpansion()
    }

    /// Re-reads the chip content while widened (a source became available, a new language).
    func refreshExpansion() {
        guard wantsExpanded else { return }
        updateExpansion()
    }

    // MARK: Decisions

    private var shouldShow: Bool { content != nil && orbShown && slot != nil }

    private func refresh() {
        let now = CACurrentMediaTime()
        guard shouldShow, let slot, let content else {
            if isPresenting {
                isPresenting = false
                movingToNewSlot = false
                appearTimer?.invalidate()
                motion.disappear(duration: reduceMotion ? 0.15 : 0.18, reduceMotion: reduceMotion, at: now)
                run()
            }
            return
        }
        if !isPresenting {
            isPresenting = true
            install(slot, content: content)
            attach()
            appear(duration: 0.28)
            return
        }
        guard let shown = shownSlot else { return }
        if slot.side != shown.side {
            if reduceMotion {
                install(slot, content: content)
                layout()
            } else if !movingToNewSlot {
                movingToNewSlot = true
                motion.disappear(duration: 0.12, reduceMotion: false, at: now)
                run()
            }
            return
        }
        let next = content.collapsed(budget: slot.budget).face
        shownSlot = slot
        if next != face {
            previous = face
            face = next
            motion.startMorph(duration: reduceMotion ? 0.15 : 0.2, at: now)
        }
        updateExpansion()
        run()
    }

    /// Puts the plate in `slot` at once.
    private func install(_ slot: NameplateSlot, content: OrbNameplateContent) {
        shownSlot = slot
        face = content.collapsed(budget: slot.budget).face
        previous = nil
        expanded = nil
        motion.setExpand(0, duration: nil, at: 0)
        motion.startMorph(duration: nil, at: 0)
        let edges = restEdges(width: face?.width ?? 0, side: slot.side)
        motion.setEdges(left: edges.left, right: edges.right, motion: nil, at: 0)
        if wantsExpanded { updateExpansion(animated: false) }
    }

    private func appear(duration: TimeInterval) {
        let delay = pendingAppearDelay
        pendingAppearDelay = 0
        appearTimer?.invalidate()
        motion.hide()
        layout()
        let start = { @MainActor [weak self] in
            guard let self, self.isPresenting else { return }
            self.motion.appear(duration: self.reduceMotion ? 0.15 : duration, reduceMotion: self.reduceMotion, at: CACurrentMediaTime())
            self.run()
        }
        guard delay > 0 else { start(); return }
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { start() } }
        RunLoop.main.add(timer, forMode: .common)
        appearTimer = timer
    }

    private func updateExpansion(animated: Bool = true) {
        guard let slot = shownSlot, let face, let content else { return }
        let now = CACurrentMediaTime()
        let spring: OrbWindowMotion? = animated && !reduceMotion ? NameplateMotion.widthSpring : nil
        let fade: Double? = animated ? 0.15 : nil
        if wantsExpanded, let items = chipItems?(), let wide = content.expanded(items, comparedTo: face) {
            expanded = wide
            let edges = restEdges(width: wide.width, side: slot.side)
            motion.setEdges(left: edges.left, right: edges.right, motion: spring, at: now)
            motion.setExpand(1, duration: fade, at: now)
        } else {
            let edges = restEdges(width: face.width, side: slot.side)
            motion.setEdges(left: edges.left, right: edges.right, motion: spring, at: now)
            motion.setExpand(0, duration: expanded == nil ? nil : fade, at: now)
        }
        run()
    }

    // MARK: Geometry

    /// The capsule's edges relative to its anchor: centered above and below, growing away from the disc on a side.
    private func restEdges(width: CGFloat, side: NameplateSide) -> (left: CGFloat, right: CGFloat) {
        switch side {
        case .below, .above: (-width / 2, width / 2)
        case .right: (0, width)
        case .left: (-width, 0)
        }
    }

    private var pixel: CGFloat { 1 / max(1, parent?.backingScaleFactor ?? 2) }

    private func snap(_ value: CGFloat) -> CGFloat {
        (value / pixel).rounded() * pixel
    }

    /// The anchor x (disc center above and below, the disc-facing edge on a side) and the capsule's bottom, in screen
    /// points, moved `approach` toward the disc.
    private func anchor(side: NameplateSide, approach: CGFloat) -> (x: CGFloat, y: CGFloat) {
        guard let metrics = content?.metrics else { return (disc.center.x, disc.center.y) }
        let c = disc.center
        let r = disc.radius
        let g = metrics.gap
        let h = metrics.height
        switch side {
        case .below: return (snap(c.x), snap(c.y - r - g - h) + approach)
        case .above: return (snap(c.x), snap(c.y + r + g) - approach)
        case .right: return (snap(c.x + r + g) - approach, snap(c.y - h / 2))
        case .left: return (snap(c.x - r - g) + approach, snap(c.y - h / 2))
        }
    }

    private func capsule(left: CGFloat, right: CGFloat, side: NameplateSide, approach: CGFloat) -> CGRect {
        let point = anchor(side: side, approach: approach)
        let height = content?.metrics.height ?? 0
        return CGRect(x: point.x + left, y: point.y, width: max(0, right - left), height: height)
    }

    /// Keeps a plate above or below inside the usable area (3 pt inset) while it is wider than its slot.
    private func clampShift(_ rect: CGRect, side: NameplateSide) -> CGFloat {
        guard !side.isSide, area.width > 0 else { return 0 }
        let inset = NameplateMetrics.areaInset
        if rect.minX < area.minX + inset { return area.minX + inset - rect.minX }
        if rect.maxX > area.maxX - inset { return max(area.maxX - inset - rect.maxX, area.minX + inset - rect.minX) }
        return 0
    }

    // MARK: Drawing

    private func layout() {
        guard let slot = shownSlot, let face, let metrics = content?.metrics else {
            view.show(nil)
            return
        }
        let sample = motion.sample(at: CACurrentMediaTime())
        let side = slot.side
        var plate = capsule(left: sample.left, right: sample.right, side: side, approach: sample.approach)
        let shift = clampShift(plate, side: side)
        plate.origin.x += shift
        let anchorX = anchor(side: side, approach: sample.approach).x + shift

        // The window covers the capsule at rest, widened and as drawn now, with room for the shadow and the approach.
        var extent = plate
        let rest = restEdges(width: face.width, side: side)
        extent = extent.union(capsule(left: rest.left, right: rest.right, side: side, approach: 0).offsetBy(dx: shift, dy: 0))
        if let expanded {
            let wide = restEdges(width: expanded.width, side: side)
            extent = extent.union(capsule(left: wide.left, right: wide.right, side: side, approach: 0).offsetBy(dx: shift, dy: 0))
        }
        let pad = NameplateRenderer.margin + 4
        let frame = extent.insetBy(dx: -pad, dy: -pad).integral
        if window.frame != frame { window.setFrame(frame, display: false) }

        let origin = frame.origin
        var scene = NameplateScene(plate: plate.offsetBy(dx: -origin.x, dy: -origin.y), metrics: metrics, tokens: tokens,
                                   opacity: sample.presence, scale: sample.scale)
        let local = anchorX - origin.x
        let collapsedAlpha = 1 - sample.expand
        if let previous, sample.morph < 1 {
            addMorph(from: previous, to: face, progress: sample.morph, anchor: local, side: side, alpha: collapsedAlpha, into: &scene)
        } else {
            scene.add(face, originX: local + restEdges(width: face.width, side: side).left, alpha: collapsedAlpha)
        }
        if let expanded {
            scene.add(expanded, originX: local + restEdges(width: expanded.width, side: side).left, alpha: sample.expand)
        }
        view.show(scene)
    }

    /// A name change: the text crossfades, kept dots slide to their new places, added or removed dots scale in or out.
    private func addMorph(from old: NameplateFace, to new: NameplateFace, progress t: CGFloat, anchor: CGFloat, side: NameplateSide,
                          alpha: CGFloat, into scene: inout NameplateScene) {
        guard alpha > 0.001 else { return }
        let oldOrigin = anchor + restEdges(width: old.width, side: side).left
        let newOrigin = anchor + restEdges(width: new.width, side: side).left
        let oldRing = old.dots.count > 1
        let newRing = new.dots.count > 1
        var dots: [NameplateScene.Dot] = []
        for dot in new.dots {
            if let match = old.dots.first(where: { $0.dot == dot.dot }) {
                let x = oldOrigin + match.x + (newOrigin + dot.x - oldOrigin - match.x) * t
                dots.append(NameplateScene.Dot(dot: dot.dot, x: x, alpha: alpha, ring: oldRing || newRing))
            } else {
                dots.append(NameplateScene.Dot(dot: dot.dot, x: newOrigin + dot.x, scale: t, alpha: alpha, ring: newRing))
            }
        }
        for dot in old.dots where !new.dots.contains(where: { $0.dot == dot.dot }) {
            dots.append(NameplateScene.Dot(dot: dot.dot, x: oldOrigin + dot.x, scale: 1 - t, alpha: alpha, ring: oldRing))
        }
        scene.dots += dots
        for run in old.runs {
            scene.runs.append(NameplateScene.Run(text: run.text, x: oldOrigin + run.x, role: run.role, tracking: run.tracking,
                                                 ideographic: old.ideographic, alpha: alpha * (1 - t)))
        }
        for run in new.runs {
            scene.runs.append(NameplateScene.Run(text: run.text, x: newOrigin + run.x, role: run.role, tracking: run.tracking,
                                                 ideographic: new.ideographic, alpha: alpha * t))
        }
    }

    // MARK: Window

    private func attach() {
        guard let parent, window.parent == nil else { return }
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
    }

    private func detach() {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    // MARK: Animation

    private func run() {
        guard window.isVisible || !motion.isActive else {
            motion.settle(at: CACurrentMediaTime() + 60)
            layout()
            finishTransitions()
            return
        }
        layout()
        guard motion.isActive else {
            finishTransitions()
            return
        }
        guard link == nil else { return }
        let link = view.displayLink(target: proxy, selector: #selector(NameplateDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        motion.settle(at: link.targetTimestamp)
        layout()
        if !motion.isActive {
            stopLink()
            finishTransitions()
        }
    }

    /// Ends what the finished animations started: a hidden plate leaves the screen, a moving plate fades in at its new
    /// slot, finished crossfades drop their old faces.
    private func finishTransitions() {
        let sample = motion.sample(at: CACurrentMediaTime())
        if !isPresenting, sample.presence <= 0.001 {
            shownSlot = nil
            face = nil
            previous = nil
            expanded = nil
            view.show(nil)
            detach()
            return
        }
        if movingToNewSlot, sample.presence <= 0.001, let slot, let content {
            movingToNewSlot = false
            install(slot, content: content)
            appear(duration: 0.2)
            return
        }
        var changed = false
        if previous != nil, sample.morph >= 1 {
            previous = nil
            changed = true
        }
        if expanded != nil, motion.expandTarget == 0, sample.expand <= 0.001 {
            expanded = nil
            changed = true
        }
        if changed { layout() }
    }
}

/// Breaks the retain cycle between `CADisplayLink` (which retains its target) and the controller.
@MainActor
private final class NameplateDisplayLinkProxy: NSObject {
    private weak var owner: OrbNameplateController?

    init(owner: OrbNameplateController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.tick(link)
    }
}

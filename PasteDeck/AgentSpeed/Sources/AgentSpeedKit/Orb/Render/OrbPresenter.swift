import AgentSpeedCore
import AgentSpeedOrbModel
import AppKit

/// Binds one orb's animator, feed and content to a canvas on the shared frame clock: the canvas asks for the
/// animator's frame class, draws once when static content changes, and builds its scene from the current content.
/// Used by floating orbs and by the Settings thumbnails and style cards.
@MainActor
final class OrbPresenter {
    let animator: OrbAnimator
    let canvas: OrbCanvasView
    let feed: OrbFeed
    private(set) var content: OrbContent

    /// The disc diameter (animated by the window while resizing).
    var diameter: CGFloat {
        didSet { if diameter != oldValue { refreshContent() } }
    }
    /// The 1.03 hover scale of the floating orb.
    var hoverScale: CGFloat = 1 {
        didSet { if hoverScale != oldValue { canvas.setNeedsFrame() } }
    }
    var dark: Bool {
        didSet { if dark != oldValue { refreshContent() } }
    }
    /// Previews cap their rate and draw only while their Settings pane is visible.
    var cap: Double? {
        didSet { applyRequest() }
    }
    var isActive = true {
        didSet { if isActive != oldValue { applyRequest() } }
    }
    /// Adjusts content after it is resolved (previews: the thumbnail flag, scripted strings).
    var contentAdjustment: ((inout OrbContent) -> Void)? {
        didSet { refreshContent() }
    }
    /// The orb's title theme (read when the content refreshes; observable reads re-run it); nil = General.
    var titleTheme: (() -> TitleTheme)? {
        didSet { refreshContent() }
    }

    private weak var model: AgentSpeedModel?
    private var loops: [ObservationLoop] = []

    init(model: AgentSpeedModel, feed: OrbFeed, surface: OrbSurface, style: OrbStyleKind, diameter: CGFloat, dark: Bool,
         interaction: OrbInteraction?, canvas: OrbCanvasView) {
        self.model = model
        self.feed = feed
        self.canvas = canvas
        self.diameter = diameter
        self.dark = dark
        animator = OrbAnimator(surface: surface, style: style)
        content = OrbContentBuilder.content(model: model, feed: feed, diameter: diameter, dark: dark, contrast: false,
                                            style: style, showsReadout: true)
        canvas.sceneProvider = { [weak self] scene, size, scale, time in
            guard let self, let model = self.model else { return }
            OrbSceneBuilder.build(into: &scene, content: self.content, animator: self.animator, model: model, feed: self.feed,
                                  canvasSide: size.width, scale: scale, time: time, contentScale: self.hoverScale)
        }
        canvas.onFrame = { [weak self] in self?.animator.reevaluate() }
        animator.attach(model: model, feed: feed, interaction: interaction)
        loops.append(ObservationLoop { [weak self] in self?.refreshContent() })
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            _ = self.animator.frameClass
            self.applyRequest()
        })
    }

    func setStyle(_ style: OrbStyleKind) {
        guard style != animator.style else { return }
        animator.setStyle(style)
        refreshContent()
    }

    func stop() {
        loops.forEach { $0.cancel() }
        loops.removeAll()
        animator.detach()
        canvas.request = .none
        canvas.sceneProvider = nil
        canvas.onFrame = nil
    }

    private func applyRequest() {
        let frameClass = isActive ? animator.frameClass : .none
        canvas.request = OrbFrameRequest(frameClass: frameClass, cap: cap, countsForCrowd: cap == nil)
    }

    private func refreshContent() {
        guard let model else { return }
        var next = OrbContentBuilder.content(model: model, feed: feed, diameter: diameter, dark: dark, contrast: false,
                                             style: animator.style, showsReadout: true, theme: titleTheme?())
        contentAdjustment?(&next)
        _ = (feed.gauge.title, feed.gauge.previousTitle)
        content = next
        canvas.setNeedsFrame()
    }
}

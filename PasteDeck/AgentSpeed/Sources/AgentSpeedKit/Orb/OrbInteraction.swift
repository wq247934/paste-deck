import Observation

/// Pointer and visibility state of the floating orb, written by `OrbWindowController` and read by `OrbView`.
@MainActor
@Observable
final class OrbInteraction {
    var isHovered = false
    var isDragging = false
    /// False while the panel is hidden, off screen or fully occluded; the renderer pauses.
    var isVisibleOnScreen = true
}

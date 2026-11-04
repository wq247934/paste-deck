import AppKit

/// Desktop blur behind the orb body, clipped to the disc. `.hudWindow` in dark appearances, `.popover` in light.
final class OrbBlurView: NSVisualEffectView {
    /// Keeps the antialiased blur edge just inside the body's own edge so no halo shows.
    private static let edgeInset: CGFloat = 0.5
    private var maskSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        updateMaterial()
        updateMask()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMask()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }

    private func updateMaterial() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let next: NSVisualEffectView.Material = dark ? .hudWindow : .popover
        if material != next { material = next }
    }

    private func updateMask() {
        let size = bounds.size
        guard size != maskSize, size.width > 0, size.height > 0 else { return }
        maskSize = size
        let inset = Self.edgeInset
        maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
    }
}

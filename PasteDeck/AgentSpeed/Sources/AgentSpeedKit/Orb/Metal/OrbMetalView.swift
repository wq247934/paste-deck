import MetalKit
import SwiftUI

/// Hosts the GPU-drawn layers of the dashboard's embedded orb. Runs at the display's cadence while active and draws
/// only on demand while paused. (Floating orbs and Settings previews draw through `OrbCanvasView` on the shared
/// frame clock instead.)
struct OrbMetalView: NSViewRepresentable {
    let mode: OrbAnimator.FrameMode
    /// Active frames follow the display's cadence (the refresh rate divided down to no less than 60 fps) instead of a
    /// fixed 60 fps, which a 144 Hz display can only show at 48 (the dashboard hero, DESIGN 4c).
    var followsDisplay = false
    /// Frames per second at most while active (Settings previews); nil = no cap.
    var frameCap: Int?
    /// Changes whenever a paused orb must redraw once (content or settled values changed).
    let redrawKey: AnyHashable
    let scene: @MainActor (inout OrbScene, CGSize, CGFloat, TimeInterval) -> Void

    func makeNSView(context: Context) -> OrbMTKView {
        let view = OrbMTKView()
        view.sceneProvider = scene
        view.followsDisplay = followsDisplay
        view.frameCap = frameCap
        view.apply(mode)
        return view
    }

    func updateNSView(_ view: OrbMTKView, context: Context) {
        view.sceneProvider = scene
        view.followsDisplay = followsDisplay
        view.frameCap = frameCap
        view.apply(mode)
        if view.redrawKey != redrawKey {
            view.redrawKey = redrawKey
            if view.isPaused { view.needsDisplay = true }
        }
    }

    static func dismantleNSView(_ view: OrbMTKView, coordinator: ()) {
        view.isPaused = true
        view.sceneProvider = nil
    }
}

final class OrbMTKView: MTKView, MTKViewDelegate {
    var sceneProvider: (@MainActor (inout OrbScene, CGSize, CGFloat, TimeInterval) -> Void)?
    var redrawKey: AnyHashable?
    var followsDisplay = false {
        didSet { if followsDisplay != oldValue { reapply() } }
    }
    var frameCap: Int? {
        didSet { if frameCap != oldValue { reapply() } }
    }
    private let encoder: OrbEncoder?
    private var mode: OrbAnimator.FrameMode?
    private var scene = OrbScene(capacity: 1024)

    init() {
        let gpu = OrbGPU.shared
        encoder = gpu.map(OrbEncoder.init)
        super.init(frame: .zero, device: gpu?.device)
        colorPixelFormat = OrbGPU.pixelFormat
        framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    func apply(_ newMode: OrbAnimator.FrameMode) {
        guard newMode != mode else { return }
        mode = newMode
        reapply()
    }

    private func reapply() {
        guard let mode else { return }
        switch mode {
        case .active:
            enableSetNeedsDisplay = false
            preferredFramesPerSecond = min(activeRate, frameCap ?? .max)
            isPaused = false
        case .ambient(let fps):
            enableSetNeedsDisplay = false
            preferredFramesPerSecond = min(fps, frameCap ?? .max)
            isPaused = false
        case .paused:
            isPaused = true
            enableSetNeedsDisplay = true
            needsDisplay = true
        }
    }

    /// 60 fps, or with `followsDisplay` the display rate divided by the largest integer that keeps it at 60 fps or
    /// more (144 Hz → 72, 120 Hz → 60), so every frame lands on a refresh.
    private var activeRate: Int {
        guard followsDisplay, let maximum = window?.screen?.maximumFramesPerSecond, maximum > 60 else { return 60 }
        var divisor = 1
        while maximum / (divisor + 1) >= 60 { divisor += 1 }
        return maximum / divisor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if followsDisplay { reapply() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let encoder, let sceneProvider, bounds.width > 0,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable else { return }
        let scale = window?.backingScaleFactor ?? 2
        sceneProvider(&scene, bounds.size, scale, Clock.now)
        encoder.render(scene, size: bounds.size, scale: scale, pass: pass, present: drawable)
    }
}

/// Renders a scene offscreen (previews and the frame harness).
@MainActor
enum OrbSnapshot {
    private static var encoder: OrbEncoder?

    static func image(_ scene: OrbScene, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let gpu = OrbGPU.shared else { return nil }
        let pixels = Int((side * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OrbGPU.pixelFormat, width: pixels, height: pixels, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let encoder = Self.encoder ?? OrbEncoder(gpu: gpu)
        Self.encoder = encoder
        encoder.render(scene, size: CGSize(width: side, height: side), scale: scale, pass: pass, present: nil, waitUntilCompleted: true)
        let bytesPerRow = pixels * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixels)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

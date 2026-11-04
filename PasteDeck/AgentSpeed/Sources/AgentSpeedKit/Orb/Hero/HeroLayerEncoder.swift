import AgentSpeedHero
import CoreGraphics
import Metal
import os
import simd

/// The hero vehicle layer's pipelines, compiled once per device (blending as `OrbGPU`).
final class HeroLayerGPU: Sendable {
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    let over: MTLRenderPipelineState
    let additive: MTLRenderPipelineState

    init?(device: MTLDevice) {
        let logger = Logger(subsystem: "io.github.zoefix.agentspeed", category: "orb")
        do {
            let library = try device.makeLibrary(source: HeroShaderSource.source, options: nil)
            guard let vertex = library.makeFunction(name: "hero_vertex"),
                  let fragment = library.makeFunction(name: "hero_fragment") else {
                logger.error("Hero shader functions are missing")
                return nil
            }
            over = try Self.pipeline(device: device, vertex: vertex, fragment: fragment, additive: false)
            additive = try Self.pipeline(device: device, vertex: vertex, fragment: fragment, additive: true)
        } catch {
            logger.error("Hero shaders failed to compile")
            return nil
        }
        self.device = device
    }

    /// Uses 16 × 16 pixel tiles for `pass` on Apple GPUs. The layer's fragment work sits in a small part of the
    /// drawable and each tile is shaded by one GPU core, so smaller tiles spread a heavy frame over more cores.
    func configure(_ pass: MTLRenderPassDescriptor) {
        guard device.supportsFamily(.apple4) else { return }
        pass.tileWidth = 16
        pass.tileHeight = 16
    }

    private static func pipeline(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction, additive: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

/// Layout of `HeroUniforms` in `HeroShaderSource`.
private struct HeroLayerUniforms {
    /// Width, height (points), pixels per point, pass (0 crisp, 1 glow).
    var viewport: SIMD4<Float>
    /// Origin x, y (points), points per canvas unit, one pixel in canvas units.
    var layer: SIMD4<Float>
    var mask: SIMD4<Float>
    var sweepBand: SIMD4<Float>
    var sweepColor: SIMD4<Float>
}

/// Encodes a `HeroDrawList` into a render pass: the crisp items in list order, then the glow of every item on top.
///
/// Each call copies the list, plus the bounds of every `HeroShaderSource.chunk` segments (the shader's culling
/// table), into the next buffer of a ring of grow-only buffers, so a warm encoder never allocates. Call it at most once
/// per frame with at most `ringSize` frames in flight.
final class HeroLayerEncoder {
    private static let ringSize = 3
    private static let minimumLength = 64 * 1024
    /// Offset alignment of each section of a ring buffer (the strictest Mac GPU requirement).
    private static let alignment = 256

    private let gpu: HeroLayerGPU
    private var buffers: [MTLBuffer?]
    private var index = 0

    init(gpu: HeroLayerGPU) {
        self.gpu = gpu
        buffers = Array(repeating: nil, count: Self.ringSize)
    }

    /// Draws `list` with canvas unit (0, 0) at `origin` and `unit` points per canvas unit. `viewport` is the drawable
    /// size in points and `scale` its pixels per point. Leaves the encoder's pipeline and buffers changed.
    func encode(_ list: HeroDrawList, origin: CGPoint, unit: CGFloat, viewport: CGSize, scale: CGFloat, alpha: Float = 1,
                into encoder: MTLRenderCommandEncoder) {
        let items = list.items
        let points = list.points
        guard !items.isEmpty, unit > 0, scale > 0, viewport.width > 0, viewport.height > 0 else { return }

        let chunk = HeroShaderSource.chunk
        let stride = MemoryLayout<SIMD4<Float>>.stride
        let itemBytes = items.count * MemoryLayout<HeroDrawItem>.stride
        let pointBytes = points.count * stride
        let chunkCount = (points.count + chunk - 1) / chunk
        let pointsOffset = Self.aligned(itemBytes)
        let chunksOffset = pointsOffset + Self.aligned(pointBytes)
        index = (index + 1) % Self.ringSize
        guard let buffer = buffer(minimumLength: chunksOffset + max(chunkCount, 1) * stride) else { return }
        let contents = buffer.contents()
        items.withUnsafeBytes { source in
            if let base = source.baseAddress { contents.copyMemory(from: base, byteCount: itemBytes) }
        }
        points.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            (contents + pointsOffset).copyMemory(from: base, byteCount: pointBytes)
            // Bounds of the drawn (pen-down) segments ending in each chunk; a chunk without any gets an inverted box.
            let boxes = contents + chunksOffset
            for c in 0..<chunkCount {
                var lower = SIMD2<Float>(repeating: 1e18)
                var upper = -lower
                for i in max(c * chunk, 1)..<min((c + 1) * chunk, source.count) where base[i].w < 0.5 {
                    let a = SIMD2(base[i - 1].x, base[i - 1].y), b = SIMD2(base[i].x, base[i].y)
                    lower = simd_min(lower, simd_min(a, b))
                    upper = simd_max(upper, simd_max(a, b))
                }
                boxes.storeBytes(of: SIMD4(lowHalf: lower, highHalf: upper), toByteOffset: c * stride, as: SIMD4<Float>.self)
            }
        }

        var uniforms = HeroLayerUniforms(
            viewport: SIMD4(Float(viewport.width), Float(viewport.height), Float(scale), 0),
            layer: SIMD4(Float(origin.x), Float(origin.y), Float(unit), Float(1 / (unit * scale))),
            mask: list.mask,
            sweepBand: list.sweep.band,
            sweepColor: list.sweep.color
        )
        uniforms.sweepBand.w = alpha
        let uniformLength = MemoryLayout<HeroLayerUniforms>.stride
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(buffer, offset: pointsOffset, index: 1)
        encoder.setFragmentBuffer(buffer, offset: chunksOffset, index: 3)

        uniforms.viewport.w = 0
        encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
        encoder.setFragmentBytes(&uniforms, length: uniformLength, index: 2)
        var first = 0
        while first < items.count {
            let additive = items[first].flags.contains(.additive)
            var end = first + 1
            while end < items.count, items[end].flags.contains(.additive) == additive { end += 1 }
            encoder.setRenderPipelineState(additive ? gpu.additive : gpu.over)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: end - first, baseInstance: first)
            first = end
        }

        // Glow goes on top, as light added to the strokes (dark) or a soft halo over them (light): one draw over the
        // range of glowing items; the vertex shader collapses the others.
        var firstGlow = -1, lastGlow = -1
        for (offset, item) in items.enumerated() where item.stroke.z > 0 && item.kind != .radial {
            if firstGlow < 0 { firstGlow = offset }
            lastGlow = offset
        }
        if firstGlow >= 0 {
            uniforms.viewport.w = 1
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setFragmentBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setRenderPipelineState(list.dark ? gpu.additive : gpu.over)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                   instanceCount: lastGlow - firstGlow + 1, baseInstance: firstGlow)
        }
    }

    private static func aligned(_ length: Int) -> Int {
        (length + alignment - 1) / alignment * alignment
    }

    private func buffer(minimumLength: Int) -> MTLBuffer? {
        if let buffer = buffers[index], buffer.length >= minimumLength { return buffer }
        let length = max(minimumLength, Self.minimumLength)
        let buffer = gpu.device.makeBuffer(length: length, options: .storageModeShared)
        buffers[index] = buffer
        return buffer
    }
}

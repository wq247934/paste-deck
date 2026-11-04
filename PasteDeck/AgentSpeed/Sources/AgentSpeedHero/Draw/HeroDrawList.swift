import simd

/// What one draw item is (`header.x`).
public enum HeroDrawKind: Float, Sendable {
    /// Segments between consecutive points (stroked and/or filled, see `HeroDrawFlags`).
    case polyline = 0
    /// A stroked circle: `shape` = center x, center y, radius.
    case circle = 1
    /// A filled radial gradient: `color` at the center, `fill` at 45 % of the radius, transparent at the radius.
    case radial = 2
}

/// Bits of `header.w`.
public struct HeroDrawFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Stroke the geometry with `color` at half width `stroke.x`.
    public static let stroke = HeroDrawFlags(rawValue: 1)
    /// Fill closed subpaths (even-odd) with `fill`.
    public static let fill = HeroDrawFlags(rawValue: 2)
    /// Opacity falls linearly from 1 at arc length `shape.x` to 0 at `shape.y` (polylines).
    public static let fade = HeroDrawFlags(rawValue: 4)
    /// The stroke is drawn as a soft Gaussian profile of sigma `stroke.w` instead of a crisp edge.
    public static let soft = HeroDrawFlags(rawValue: 8)
    /// Adds light (dark appearance) instead of covering what is below.
    public static let additive = HeroDrawFlags(rawValue: 16)
}

/// One draw of the vehicle layer, in canvas units (0–100, y down, DESIGN 4c), laid out for the GPU
/// (`HeroItem` in the shader). Colors are straight-alpha sRGB.
public struct HeroDrawItem: Sendable, Equatable {
    /// Kind, index of the first point, point count, flags.
    public var header: SIMD4<Float>
    /// Stroke half width, stroke opacity, glow opacity (0 = no glow), glow sigma (all in canvas units).
    public var stroke: SIMD4<Float>
    /// Stroke color (or the center color of a radial gradient).
    public var color: SIMD4<Float>
    /// Fill color (or the mid color of a radial gradient).
    public var fill: SIMD4<Float>
    /// Circle and radial: center x, center y, radius. Polyline with `fade`: arc length where the fade starts and ends.
    public var shape: SIMD4<Float>
    /// Geometry bounds before stroke width and glow: min x, min y, max x, max y.
    public var bounds: SIMD4<Float>

    public var kind: HeroDrawKind { HeroDrawKind(rawValue: header.x) ?? .polyline }
    public var flags: HeroDrawFlags { HeroDrawFlags(rawValue: UInt32(header.w)) }
}

/// Which part of the layer an item belongs to (checks and debugging).
public enum HeroDrawSection: UInt8, Sendable {
    case scenery, speedLines, vehicle, ghost, trails, particles, flash
}

/// The idle light band (DESIGN 4c, Idle): mixed over the crisp strokes, in fixed layer coordinates.
public struct HeroSweep: Sendable, Equatable {
    /// Band center (canvas x), half width, strength 0…1, unused.
    public var band: SIMD4<Float> = .zero
    public var color: SIMD4<Float> = .zero

    public init() {}
}

/// Every draw of one frame of the vehicle layer, rebuilt in place each frame without allocating once warm.
///
/// Points are `x, y, arc length from the item's first point, 1 when the point starts a new subpath`. The renderer
/// draws the crisp items in order, then the glow of every item with glow opacity > 0 on top (blurred analytically by
/// `stroke.w`), and multiplies everything by the soft circular mask (`mask`, fixed layer coordinates).
public final class HeroDrawList: @unchecked Sendable {
    public static let itemCapacity = 1024
    public static let pointCapacity = 16384

    public private(set) var items: [HeroDrawItem] = []
    public private(set) var points: [SIMD4<Float>] = []
    /// The section of each item, parallel to `items`.
    public private(set) var sections: [HeroDrawSection] = []
    /// Section given to the items added next.
    public var section = HeroDrawSection.vehicle
    /// Mask center x, center y, solid radius, clear radius.
    public var mask = SIMD4<Float>(50, 50, 42, 49)
    public var sweep = HeroSweep()
    /// Dark appearance: glow adds light; light appearance: glow blends normally.
    public var dark = true
    /// Items dropped this frame because a capacity was reached (should stay 0).
    public private(set) var overflow = 0

    private var openItem: Int?
    private var minX: Float = 0, minY: Float = 0, maxX: Float = 0, maxY: Float = 0
    private var length: Float = 0
    private var last = SIMD2<Float>.zero
    private var pendingMove = true

    public init() {
        items.reserveCapacity(Self.itemCapacity)
        points.reserveCapacity(Self.pointCapacity)
        sections.reserveCapacity(Self.itemCapacity)
    }

    public func reset() {
        items.removeAll(keepingCapacity: true)
        points.removeAll(keepingCapacity: true)
        sections.removeAll(keepingCapacity: true)
        section = .vehicle
        sweep = HeroSweep()
        overflow = 0
        openItem = nil
    }

    // MARK: Polylines

    /// Starts a polyline item; add points with `move` / `line`, then `end`.
    public func begin(flags: HeroDrawFlags, halfWidth: Double, opacity: Double, color: SIMD4<Float>,
                      fill: SIMD4<Float> = .zero, glow: Double = 0, sigma: Double = 0) {
        precondition(openItem == nil, "HeroDrawList.begin while an item is open")
        guard items.count < Self.itemCapacity else {
            overflow += 1
            openItem = nil
            pendingMove = true
            return
        }
        let item = HeroDrawItem(
            header: SIMD4(HeroDrawKind.polyline.rawValue, Float(points.count), 0, Float(flags.rawValue)),
            stroke: SIMD4(Float(halfWidth), Float(opacity), Float(glow), Float(sigma)),
            color: color,
            fill: fill,
            shape: .zero,
            bounds: .zero
        )
        items.append(item)
        sections.append(section)
        openItem = items.count - 1
        minX = .greatestFiniteMagnitude
        minY = .greatestFiniteMagnitude
        maxX = -.greatestFiniteMagnitude
        maxY = -.greatestFiniteMagnitude
        length = 0
        pendingMove = true
    }

    public func move(_ x: Double, _ y: Double) {
        add(Float(x), Float(y), move: true)
    }

    public func line(_ x: Double, _ y: Double) {
        add(Float(x), Float(y), move: false)
    }

    /// Sets the fade of the open item: opacity 1 at arc length `from`, 0 at `to`.
    public func fade(from: Double, to: Double) {
        guard let index = openItem else { return }
        items[index].shape.x = Float(from)
        items[index].shape.y = Float(to)
    }

    /// Arc length of the open item so far.
    public var currentLength: Double { Double(length) }

    public func end() {
        guard let index = openItem else { return }
        openItem = nil
        let count = points.count - Int(items[index].header.y)
        if count < 2 {
            points.removeLast(count)
            items.removeLast()
            sections.removeLast()
            return
        }
        items[index].header.z = Float(count)
        items[index].bounds = SIMD4(minX, minY, maxX, maxY)
    }

    private func add(_ x: Float, _ y: Float, move: Bool) {
        guard openItem != nil else { return }
        guard points.count < Self.pointCapacity else {
            overflow += 1
            return
        }
        let starts = move || pendingMove
        if !starts {
            let dx = x - last.x, dy = y - last.y
            length += (dx * dx + dy * dy).squareRoot()
        }
        points.append(SIMD4(x, y, length, starts ? 1 : 0))
        last = SIMD2(x, y)
        pendingMove = false
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }

    // MARK: Analytic shapes

    public func circle(cx: Double, cy: Double, radius: Double, halfWidth: Double, opacity: Double, color: SIMD4<Float>,
                       glow: Double = 0, sigma: Double = 0, flags: HeroDrawFlags = .stroke) {
        guard items.count < Self.itemCapacity else {
            overflow += 1
            return
        }
        let x = Float(cx), y = Float(cy), r = Float(radius)
        sections.append(section)
        items.append(HeroDrawItem(
            header: SIMD4(HeroDrawKind.circle.rawValue, 0, 0, Float(flags.union(.stroke).rawValue)),
            stroke: SIMD4(Float(halfWidth), Float(opacity), Float(glow), Float(sigma)),
            color: color,
            fill: .zero,
            shape: SIMD4(x, y, r, 0),
            bounds: SIMD4(x - r, y - r, x + r, y + r)
        ))
    }

    public func radial(cx: Double, cy: Double, radius: Double, center: SIMD4<Float>, mid: SIMD4<Float>,
                       flags: HeroDrawFlags = []) {
        guard items.count < Self.itemCapacity else {
            overflow += 1
            return
        }
        let x = Float(cx), y = Float(cy), r = Float(radius)
        sections.append(section)
        items.append(HeroDrawItem(
            header: SIMD4(HeroDrawKind.radial.rawValue, 0, 0, Float(flags.rawValue)),
            stroke: SIMD4(0, 1, 0, 0),
            color: center,
            fill: mid,
            shape: SIMD4(x, y, r, 0),
            bounds: SIMD4(x - r, y - r, x + r, y + r)
        ))
    }
}

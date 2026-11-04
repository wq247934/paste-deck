import CoreGraphics
import Foundation

/// Placement of floating windows of mixed shapes, boards among orbs (DESIGN 2c: placement and snapping treat both as
/// obstacles, using the rounded square + 12 pt for a board). For discs alone it gives `OrbPlacement`'s results.
public enum FloatingPlacement {
    public static let gap = OrbPlacement.gap
    public static let grid = OrbPlacement.grid
    static let tolerance: CGFloat = 0.5

    // MARK: Tests

    public static func isClear(_ shape: FloatingShape, from other: FloatingShape) -> Bool {
        shape.distance(to: other) >= gap - tolerance
    }

    public static func isFree(_ shape: FloatingShape, others: [FloatingShape]) -> Bool {
        others.allSatisfy { isClear(shape, from: $0) }
    }

    /// Whether the whole bounding square lies inside the usable area.
    public static func fits(_ shape: FloatingShape, in visible: CGRect) -> Bool {
        OrbPlacement.fits(shape.center, radius: shape.half, in: visible)
    }

    /// The outline `shape`'s center follows when it touches `other` at the 12 pt gap.
    static func contour(of other: FloatingShape, for shape: FloatingShape) -> (half: CGFloat, corner: CGFloat) {
        (other.half + shape.half + gap, other.corner + shape.corner + gap)
    }

    // MARK: New windows

    /// The four touching positions around `anchor` in the order left, below, right, above (centers aligned, 12 pt gap).
    public static func touchingSlots(of anchor: FloatingShape, half: CGFloat) -> [CGPoint] {
        let d = anchor.half + gap + half
        let c = anchor.center
        return [CGPoint(x: c.x - d, y: c.y), CGPoint(x: c.x, y: c.y - d), CGPoint(x: c.x + d, y: c.y), CGPoint(x: c.x, y: c.y + d)]
    }

    /// Where a new window of `template`'s size appears (DESIGN 2b Placement, used by `boards.add`): the first
    /// touching slot of the window it came from that fits and keeps clear; else the nearest free point of a 24 pt grid
    /// around it; else cascaded +24 / +24 pt. Without an anchor the default corner is the starting point.
    public static func placeNew(_ template: FloatingShape, near anchor: FloatingShape?, others: [FloatingShape],
                                visible: CGRect) -> CGPoint {
        guard let anchor else {
            let start = OrbSnap.defaultCenter(radius: template.half, in: visible)
            if isFree(template.moved(to: start), others: others) { return start }
            return gridSearch(from: start, template: template, others: others, visible: visible)
                ?? cascade(from: start, half: template.half, visible: visible)
        }
        let occupied = others.contains(anchor) ? others : others + [anchor]
        for slot in touchingSlots(of: anchor, half: template.half) {
            let shape = template.moved(to: slot)
            if fits(shape, in: visible), isFree(shape, others: occupied) { return slot }
        }
        return gridSearch(from: anchor.center, template: template, others: occupied, visible: visible)
            ?? cascade(from: anchor.center, half: template.half, visible: visible)
    }

    /// The free grid point (24 pt steps from `origin`) nearest to it, or nil when the display is full.
    public static func gridSearch(from origin: CGPoint, template: FloatingShape, others: [FloatingShape],
                                  visible: CGRect) -> CGPoint? {
        let half = template.half
        let lowX = Int(((visible.minX + half - origin.x) / grid).rounded(.up))
        let highX = Int(((visible.maxX - half - origin.x) / grid).rounded(.down))
        let lowY = Int(((visible.minY + half - origin.y) / grid).rounded(.up))
        let highY = Int(((visible.maxY - half - origin.y) / grid).rounded(.down))
        guard lowX <= highX, lowY <= highY else { return nil }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for j in lowY...highY {
            for i in lowX...highX {
                let point = CGPoint(x: origin.x + CGFloat(i) * grid, y: origin.y + CGFloat(j) * grid)
                let d = hypot(point.x - origin.x, point.y - origin.y)
                guard d < bestDistance - 0.001, isFree(template.moved(to: point), others: others) else { continue }
                best = point
                bestDistance = d
            }
        }
        return best
    }

    static func cascade(from origin: CGPoint, half: CGFloat, visible: CGRect) -> CGPoint {
        OrbSnap.clamped(CGPoint(x: origin.x + grid, y: origin.y - grid), radius: half, in: visible)
    }

    // MARK: Overlaps

    /// Keeps the shape's center when it is clear of every other window (after clamping it inside the usable area);
    /// else the nearest free touching position around the windows it overlaps; else the nearest free grid point.
    public static func resolveOverlap(_ shape: FloatingShape, others: [FloatingShape], visible: CGRect) -> CGPoint {
        let start = OrbSnap.clamped(shape.center, radius: shape.half, in: visible)
        let placed = shape.moved(to: start)
        if isFree(placed, others: others) { return start }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for other in others where !isClear(placed, from: other) {
            let (half, corner) = contour(of: other, for: shape)
            let outline = BoardPerimeter(width: Double(2 * half + 0.02), height: Double(2 * half + 0.02), radius: Double(corner + 0.01))
            for step in 0..<72 {
                let p = outline.point(fraction: Double(step) / 72)
                let point = CGPoint(x: other.center.x + CGFloat(p.x) - half - 0.01, y: other.center.y + CGFloat(p.y) - half - 0.01)
                let d = hypot(point.x - start.x, point.y - start.y)
                let candidate = shape.moved(to: point)
                guard d < bestDistance, fits(candidate, in: visible), isFree(candidate, others: others) else { continue }
                best = point
                bestDistance = d
            }
        }
        if let best { return best }
        return gridSearch(from: start, template: shape, others: others, visible: visible) ?? start
    }
}

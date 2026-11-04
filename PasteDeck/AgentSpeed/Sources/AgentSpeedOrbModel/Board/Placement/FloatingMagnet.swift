import CoreGraphics
import Foundation

/// Magnetism and alignment for windows of mixed shapes while dragging and on release (DESIGN 2b, applied to boards
/// by 2c). The touching position is the nearest point of the 12 pt clearance outline around the other window, which
/// for two discs is the line between the centers (`OrbMagnet`). Priority: screen edge, then touching, then alignment.
public enum FloatingMagnet {
    public static let pullDistance = OrbMagnet.pullDistance
    public static let alignDistance = OrbMagnet.alignDistance
    public static let alignReach = OrbMagnet.alignReach

    /// The touching position of `shape` against `other` nearest to `point`.
    public static func touching(_ point: CGPoint, shape: FloatingShape, against other: FloatingShape) -> CGPoint {
        let (half, corner) = FloatingPlacement.contour(of: other, for: shape)
        var relative = CGPoint(x: point.x - other.center.x, y: point.y - other.center.y)
        if hypot(relative.x, relative.y) < 0.001 { relative = CGPoint(x: 1, y: 0) }
        let nearest = FloatingShape.nearestOnOutline(relative, half: half, corner: corner)
        return CGPoint(x: other.center.x + nearest.x, y: other.center.y + nearest.y)
    }

    /// Where the dragged window is drawn for the pointer position `raw`: pulled onto the nearest touching position
    /// within 16 pt, else aligned with another window's center x and/or y, with the guides to show.
    public static func dragTarget(raw: CGPoint, shape: FloatingShape, others: [FloatingShape], visible: CGRect) -> OrbMagnetResult {
        if let (index, point) = nearestTouching(raw, shape: shape, others: others) {
            return OrbMagnetResult(target: point, attachedTo: index)
        }
        let docked = dockedAxes(raw, half: shape.half, visible: visible)
        return aligned(raw, shape: shape, others: others, lockX: docked.x, lockY: docked.y)
    }

    /// Where the window settles when released at `raw`: fully inside `visible` and clear of every other window.
    public static func releaseTarget(raw: CGPoint, shape: FloatingShape, others: [FloatingShape], visible: CGRect) -> CGPoint {
        let half = shape.half
        let snapped = OrbSnap.snapped(raw, radius: half, in: visible)
        let docked = dockedAxes(raw, half: half, visible: visible)
        let lockX = abs(snapped.x - raw.x) > 0.001 || docked.x
        let lockY = abs(snapped.y - raw.y) > 0.001 || docked.y
        var target = snapped
        var attached = false
        switch (lockX, lockY) {
        case (false, false):
            if let (_, point) = nearestTouching(snapped, shape: shape, others: others) {
                target = point
                attached = true
            }
        case (true, false):
            if let y = constrainedTouching(fixed: snapped.x, free: snapped.y, shape: shape, others: others, vertical: true) {
                target.y = y
                attached = true
            }
        case (false, true):
            if let x = constrainedTouching(fixed: snapped.y, free: snapped.x, shape: shape, others: others, vertical: false) {
                target.x = x
                attached = true
            }
        case (true, true):
            break
        }
        if !attached {
            target = aligned(target, shape: shape, others: others, lockX: lockX, lockY: lockY).target
        }
        return FloatingPlacement.resolveOverlap(shape.moved(to: target), others: others, visible: visible)
    }

    // MARK: Helpers

    static func nearestTouching(_ point: CGPoint, shape: FloatingShape, others: [FloatingShape]) -> (Int, CGPoint)? {
        var best: (Int, CGPoint)?
        var bestDistance = pullDistance + 0.0001
        for (index, other) in others.enumerated() {
            let candidate = touching(point, shape: shape, against: other)
            let d = hypot(candidate.x - point.x, candidate.y - point.y)
            if d <= bestDistance {
                best = (index, candidate)
                bestDistance = d
            }
        }
        return best
    }

    /// Touching another window while one axis stays where an edge put it: the free coordinate on the clearance
    /// outline, on the side nearest `free`, within the pull distance.
    static func constrainedTouching(fixed: CGFloat, free: CGFloat, shape: FloatingShape, others: [FloatingShape],
                                    vertical: Bool) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = pullDistance + 0.0001
        for other in others {
            let (half, corner) = FloatingPlacement.contour(of: other, for: shape)
            let offset = fixed - (vertical ? other.center.x : other.center.y)
            guard let span = FloatingShape.outlineSpan(offset: offset, half: half, corner: corner) else { continue }
            let base = vertical ? other.center.y : other.center.x
            for candidate in [base - span, base + span] {
                let d = abs(candidate - free)
                if d <= bestDistance {
                    best = candidate
                    bestDistance = d
                }
            }
        }
        return best
    }

    static func dockedAxes(_ point: CGPoint, half: CGFloat, visible: CGRect) -> (x: Bool, y: Bool) {
        OrbMagnet.dockedAxes(point, radius: half, visible: visible)
    }

    static func aligned(_ point: CGPoint, shape: FloatingShape, others: [FloatingShape], lockX: Bool, lockY: Bool) -> OrbMagnetResult {
        var target = point
        var guides: [OrbGuide] = []
        let moved = shape.moved(to: point)
        func near(_ other: FloatingShape) -> Bool { moved.distance(to: other) <= alignReach }
        if !lockX, let other = others.filter({ abs($0.center.x - point.x) <= alignDistance && near($0) })
            .min(by: { abs($0.center.x - point.x) < abs($1.center.x - point.x) }) {
            target.x = other.center.x
            guides.append(OrbGuide(axis: .vertical, position: other.center.x,
                                   from: min(point.y - shape.half, other.center.y - other.half),
                                   to: max(point.y + shape.half, other.center.y + other.half)))
        }
        if !lockY, let other = others.filter({ abs($0.center.y - point.y) <= alignDistance && near($0) })
            .min(by: { abs($0.center.y - point.y) < abs($1.center.y - point.y) }) {
            target.y = other.center.y
            guides.append(OrbGuide(axis: .horizontal, position: other.center.y,
                                   from: min(point.x - shape.half, other.center.x - other.half),
                                   to: max(point.x + shape.half, other.center.x + other.half)))
        }
        return OrbMagnetResult(target: target, guides: guides)
    }
}

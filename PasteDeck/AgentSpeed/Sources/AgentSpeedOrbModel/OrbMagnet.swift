import CoreGraphics
import Foundation

/// A 1 pt dashed alignment guide shown while dragging (DESIGN 2b, Alignment): a vertical guide is the line
/// x = `position` from y = `from` to `to`; a horizontal one is y = `position` from x = `from` to `to`.
public struct OrbGuide: Equatable, Hashable, Sendable {
    public enum Axis: Equatable, Hashable, Sendable {
        case vertical, horizontal
    }

    public var axis: Axis
    public var position: CGFloat
    public var from: CGFloat
    public var to: CGFloat

    public init(axis: Axis, position: CGFloat, from: CGFloat, to: CGFloat) {
        self.axis = axis
        self.position = position
        self.from = from
        self.to = to
    }
}

public struct OrbMagnetResult: Equatable, Sendable {
    /// Where the disc wants to be. The app moves the disc toward it through a critically damped spring
    /// (settle 0.12 s) so the pull feels magnetic rather than sticky.
    public var target: CGPoint
    public var guides: [OrbGuide]
    /// Index into `others` of the orb the disc is pulled against.
    public var attachedTo: Int?

    public init(target: CGPoint, guides: [OrbGuide] = [], attachedTo: Int? = nil) {
        self.target = target
        self.guides = guides
        self.attachedTo = attachedTo
    }
}

/// Orb-to-orb magnetism and alignment while dragging and on release (DESIGN 2b). Priority: screen edge, then
/// orb-to-orb touching, then alignment; alignment alone never pulls a disc off an edge it is docked to.
public enum OrbMagnet {
    /// Distance from a touching position within which the dragged disc is pulled in.
    public static let pullDistance: CGFloat = 16
    /// Center offset within which the disc aligns with another orb.
    public static let alignDistance: CGFloat = 8
    /// Largest edge-to-edge distance between two discs that still align.
    public static let alignReach: CGFloat = 64

    /// The touching position against `other` along the line between the centers (12 pt gap).
    public static func touching(_ point: CGPoint, radius: CGFloat, against other: OrbDisc) -> CGPoint {
        var dx = point.x - other.center.x
        var dy = point.y - other.center.y
        var length = hypot(dx, dy)
        if length < 0.001 {
            dx = 1
            dy = 0
            length = 1
        }
        let reach = other.radius + OrbPlacement.gap + radius
        return CGPoint(x: other.center.x + dx / length * reach, y: other.center.y + dy / length * reach)
    }

    /// Where the dragged disc is drawn for the pointer position `raw`: pulled onto the nearest touching position
    /// within 16 pt, else aligned with another orb's center x and/or y, with the guides to show.
    public static func dragTarget(raw: CGPoint, radius: CGFloat, others: [OrbDisc], visible: CGRect) -> OrbMagnetResult {
        if let (index, point) = nearestTouching(raw, radius: radius, others: others) {
            return OrbMagnetResult(target: point, attachedTo: index)
        }
        let docked = dockedAxes(raw, radius: radius, visible: visible)
        return aligned(raw, radius: radius, others: others, lockX: docked.x, lockY: docked.y)
    }

    /// Where the disc settles when released at `raw`: screen-edge snapping first (per axis), then orb-to-orb
    /// touching, then alignment; finally any overlap is resolved. The result is fully inside `visible` and clear of
    /// every other orb.
    public static func releaseTarget(raw: CGPoint, radius: CGFloat, others: [OrbDisc], visible: CGRect) -> CGPoint {
        let snapped = OrbSnap.snapped(raw, radius: radius, in: visible)
        let lockX = abs(snapped.x - raw.x) > 0.001 || dockedAxes(raw, radius: radius, visible: visible).x
        let lockY = abs(snapped.y - raw.y) > 0.001 || dockedAxes(raw, radius: radius, visible: visible).y
        var target = snapped
        var attached = false
        switch (lockX, lockY) {
        case (false, false):
            if let (_, point) = nearestTouching(snapped, radius: radius, others: others) {
                target = point
                attached = true
            }
        case (true, false):
            if let y = constrainedTouching(fixed: snapped.x, free: snapped.y, radius: radius, others: others, vertical: true) {
                target.y = y
                attached = true
            }
        case (false, true):
            if let x = constrainedTouching(fixed: snapped.y, free: snapped.x, radius: radius, others: others, vertical: false) {
                target.x = x
                attached = true
            }
        case (true, true):
            break
        }
        if !attached {
            target = aligned(target, radius: radius, others: others, lockX: lockX, lockY: lockY).target
        }
        return OrbPlacement.resolveOverlap(target, radius: radius, others: others, visible: visible)
    }

    // MARK: Helpers

    static func nearestTouching(_ point: CGPoint, radius: CGFloat, others: [OrbDisc]) -> (Int, CGPoint)? {
        var best: (Int, CGPoint)?
        var bestDistance = pullDistance + 0.0001
        for (index, other) in others.enumerated() {
            let candidate = touching(point, radius: radius, against: other)
            let d = hypot(candidate.x - point.x, candidate.y - point.y)
            if d <= bestDistance {
                best = (index, candidate)
                bestDistance = d
            }
        }
        return best
    }

    /// Touching another orb while one axis stays where an edge put it: the free coordinate at the 12 pt gap,
    /// on the side nearest `free`, within the pull distance.
    static func constrainedTouching(fixed: CGFloat, free: CGFloat, radius: CGFloat, others: [OrbDisc], vertical: Bool) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = pullDistance + 0.0001
        for other in others {
            let reach = other.radius + OrbPlacement.gap + radius
            let offset = fixed - (vertical ? other.center.x : other.center.y)
            guard abs(offset) <= reach else { continue }
            let span = sqrt(reach * reach - offset * offset)
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

    /// Which axes are docked to a screen edge (x: left/right edge; y: top/bottom edge).
    static func dockedAxes(_ point: CGPoint, radius: CGFloat, visible: CGRect) -> (x: Bool, y: Bool) {
        let threshold = OrbSnap.threshold
        let x = point.x - radius - visible.minX <= threshold || visible.maxX - (point.x + radius) <= threshold
        let y = point.y - radius - visible.minY <= threshold || visible.maxY - (point.y + radius) <= threshold
        return (x, y)
    }

    static func aligned(_ point: CGPoint, radius: CGFloat, others: [OrbDisc], lockX: Bool, lockY: Bool) -> OrbMagnetResult {
        var target = point
        var guides: [OrbGuide] = []
        func near(_ other: OrbDisc) -> Bool {
            hypot(point.x - other.center.x, point.y - other.center.y) - radius - other.radius <= alignReach
        }
        if !lockX, let other = others.filter({ abs($0.center.x - point.x) <= alignDistance && near($0) })
            .min(by: { abs($0.center.x - point.x) < abs($1.center.x - point.x) }) {
            target.x = other.center.x
            guides.append(OrbGuide(axis: .vertical, position: other.center.x,
                                   from: min(point.y - radius, other.center.y - other.radius),
                                   to: max(point.y + radius, other.center.y + other.radius)))
        }
        if !lockY, let other = others.filter({ abs($0.center.y - point.y) <= alignDistance && near($0) })
            .min(by: { abs($0.center.y - point.y) < abs($1.center.y - point.y) }) {
            target.y = other.center.y
            guides.append(OrbGuide(axis: .horizontal, position: other.center.y,
                                   from: min(point.x - radius, other.center.x - other.radius),
                                   to: max(point.x + radius, other.center.x + other.radius)))
        }
        return OrbMagnetResult(target: target, guides: guides)
    }
}

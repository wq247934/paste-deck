import CoreGraphics
import Foundation

/// A floating orb's disc in global screen points (AppKit, y up).
public struct OrbDisc: Equatable, Hashable, Sendable {
    public var center: CGPoint
    public var radius: CGFloat

    public init(center: CGPoint, radius: CGFloat) {
        self.center = center
        self.radius = radius
    }
}

/// The screen edge a disc is docked to (within `OrbSnap.threshold`).
public enum OrbDockedEdge: Equatable, Sendable {
    case left, right, top, bottom

    public var isVertical: Bool { self == .left || self == .right }
}

/// Pure placement geometry for several orbs (DESIGN 2b, Creating, placing and snapping; Split; Accessibility).
public enum OrbPlacement {
    /// Edge-to-edge gap between touching orbs, also the clearance an orb keeps from every other one.
    public static let gap: CGFloat = 12
    /// Grid of the free-spot search and the cascade offset.
    public static let grid: CGFloat = 24
    /// Rounding allowance so touching positions count as free.
    static let tolerance: CGFloat = 0.5

    // MARK: Tests

    /// Whether two discs keep at least the 12 pt clearance.
    public static func isClear(_ center: CGPoint, radius: CGFloat, from other: OrbDisc) -> Bool {
        distance(center, other.center) >= radius + other.radius + gap - tolerance
    }

    public static func isFree(_ center: CGPoint, radius: CGFloat, others: [OrbDisc]) -> Bool {
        others.allSatisfy { isClear(center, radius: radius, from: $0) }
    }

    /// Whether the whole disc lies inside the usable area.
    public static func fits(_ center: CGPoint, radius: CGFloat, in visible: CGRect) -> Bool {
        center.x - radius >= visible.minX - tolerance && center.x + radius <= visible.maxX + tolerance
            && center.y - radius >= visible.minY - tolerance && center.y + radius <= visible.maxY + tolerance
    }

    // MARK: New orbs

    /// The four touching positions around `anchor` for a disc of `radius`, in the order left, below, right, above
    /// (centers aligned, 12 pt gap).
    public static func touchingSlots(of anchor: OrbDisc, radius: CGFloat) -> [CGPoint] {
        let d = anchor.radius + gap + radius
        let c = anchor.center
        return [
            CGPoint(x: c.x - d, y: c.y),
            CGPoint(x: c.x, y: c.y - d),
            CGPoint(x: c.x + d, y: c.y),
            CGPoint(x: c.x, y: c.y + d),
        ]
    }

    /// Where a new orb appears (DESIGN 2b, Placement): the first touching slot of the orb it came from that lies
    /// inside the usable area and keeps clear of every orb; else the nearest free spot of a 24 pt grid around that
    /// orb; if the display is full, cascaded +24 / +24 pt (right and down) from it, clamped inside. Without an
    /// anchor the default corner is the starting point.
    public static func placeNew(radius: CGFloat, near anchor: OrbDisc?, others: [OrbDisc], visible: CGRect) -> CGPoint {
        guard let anchor else {
            let start = OrbSnap.defaultCenter(radius: radius, in: visible)
            if isFree(start, radius: radius, others: others) { return start }
            return gridSearch(from: start, radius: radius, others: others, visible: visible)
                ?? cascade(from: start, radius: radius, visible: visible)
        }
        let occupied = others.contains(anchor) ? others : others + [anchor]
        for slot in touchingSlots(of: anchor, radius: radius)
            where fits(slot, radius: radius, in: visible) && isFree(slot, radius: radius, others: occupied) {
            return slot
        }
        return gridSearch(from: anchor.center, radius: radius, others: occupied, visible: visible)
            ?? cascade(from: anchor.center, radius: radius, visible: visible)
    }

    /// The free grid point (24 pt steps from `origin`) nearest to it, or nil when the display is full.
    public static func gridSearch(from origin: CGPoint, radius: CGFloat, others: [OrbDisc], visible: CGRect) -> CGPoint? {
        let lowX = Int(((visible.minX + radius - origin.x) / grid).rounded(.up))
        let highX = Int(((visible.maxX - radius - origin.x) / grid).rounded(.down))
        let lowY = Int(((visible.minY + radius - origin.y) / grid).rounded(.up))
        let highY = Int(((visible.maxY - radius - origin.y) / grid).rounded(.down))
        guard lowX <= highX, lowY <= highY else { return nil }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for j in lowY...highY {
            for i in lowX...highX {
                let point = CGPoint(x: origin.x + CGFloat(i) * grid, y: origin.y + CGFloat(j) * grid)
                let d = distance(point, origin)
                guard d < bestDistance - 0.001, isFree(point, radius: radius, others: others) else { continue }
                best = point
                bestDistance = d
            }
        }
        return best
    }

    static func cascade(from origin: CGPoint, radius: CGFloat, visible: CGRect) -> CGPoint {
        OrbSnap.clamped(CGPoint(x: origin.x + grid, y: origin.y - grid), radius: radius, in: visible)
    }

    // MARK: Overlaps

    /// Keeps `center` when it is clear of every orb (after clamping it inside the usable area); else the nearest
    /// free touching position around the orbs it overlaps; else the nearest free grid spot. Never off-screen.
    public static func resolveOverlap(_ center: CGPoint, radius: CGFloat, others: [OrbDisc], visible: CGRect) -> CGPoint {
        let start = OrbSnap.clamped(center, radius: radius, in: visible)
        if isFree(start, radius: radius, others: others) { return start }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for other in others where !isClear(start, radius: radius, from: other) {
            let reach = other.radius + gap + radius + 0.01
            for step in 0..<72 {
                let angle = Double(step) * 5 * .pi / 180
                let point = CGPoint(x: other.center.x + reach * cos(angle), y: other.center.y + reach * sin(angle))
                let d = distance(point, start)
                guard d < bestDistance, fits(point, radius: radius, in: visible),
                      isFree(point, radius: radius, others: others) else { continue }
                best = point
                bestDistance = d
            }
        }
        if let best { return best }
        return gridSearch(from: start, radius: radius, others: others, visible: visible) ?? start
    }

    // MARK: Split

    /// The edge a disc is docked to: left or right first (a corner orb docked to both counts as left/right), then
    /// top or bottom.
    public static func dockedEdge(of disc: OrbDisc, visible: CGRect) -> OrbDockedEdge? {
        let left = disc.center.x - disc.radius - visible.minX
        let right = visible.maxX - (disc.center.x + disc.radius)
        let bottom = disc.center.y - disc.radius - visible.minY
        let top = visible.maxY - (disc.center.y + disc.radius)
        let threshold = OrbSnap.threshold
        if min(left, right) <= threshold { return left <= right ? .left : .right }
        if min(top, bottom) <= threshold { return top <= bottom ? .top : .bottom }
        return nil
    }

    /// Where the orbs of a split go (DESIGN 2b, Split): a tidy row from the original toward the screen interior (a
    /// column when the original is docked to the left or right edge), 12 pt gaps, centers aligned, wrapping into the
    /// next row or column (again toward the interior) when the display runs out. Orbs in `others` that are in the
    /// way are pushed along the same axis; their new centers are returned by index into `others`.
    public static func splitLayout(
        origin: OrbDisc,
        radii: [CGFloat],
        visible: CGRect,
        others: [OrbDisc],
        dockedEdge: OrbDockedEdge?
    ) -> (children: [CGPoint], pushed: [Int: CGPoint]) {
        let vertical = dockedEdge?.isVertical ?? false
        // Main axis: x for a row, y for a column. Directions point toward the interior.
        let main: (CGPoint) -> CGFloat = { vertical ? $0.y : $0.x }
        let make: (CGFloat, CGFloat) -> CGPoint = { m, c in vertical ? CGPoint(x: c, y: m) : CGPoint(x: m, y: c) }
        let mainLow = vertical ? visible.minY : visible.minX
        let mainHigh = vertical ? visible.maxY : visible.maxX
        let crossLow = vertical ? visible.minX : visible.minY
        let crossHigh = vertical ? visible.maxX : visible.maxY
        let mainDirection: CGFloat = main(origin.center) > (mainLow + mainHigh) / 2 ? -1 : 1
        let crossValue = vertical ? origin.center.x : origin.center.y
        let crossDirection: CGFloat = crossValue > (crossLow + crossHigh) / 2 ? -1 : 1

        var children: [CGPoint] = []
        var cross = crossValue
        var previousMain = main(origin.center)
        var previousRadius = origin.radius
        var lineRadius = origin.radius
        for radius in radii {
            var position = previousMain + mainDirection * (previousRadius + gap + radius)
            if position - radius < mainLow - tolerance || position + radius > mainHigh + tolerance {
                // Wrap: the next line, toward the interior, starts level with the original.
                cross += crossDirection * (lineRadius + gap + radius)
                position = main(origin.center)
                lineRadius = radius
            } else {
                lineRadius = max(lineRadius, radius)
            }
            let clampedCross = min(max(cross, crossLow + radius), crossHigh - radius)
            children.append(OrbSnap.clamped(make(position, clampedCross), radius: radius, in: visible))
            previousMain = position
            previousRadius = radius
        }

        let layout = [origin] + zip(children, radii).map { OrbDisc(center: $0, radius: $1) }
        var positions = others.map(\.center)
        var pushed: [Int: CGPoint] = [:]
        let order = others.indices.sorted { mainDirection * main(others[$0].center) < mainDirection * main(others[$1].center) }
        for index in order {
            let radius = others[index].radius
            guard !isFree(positions[index], radius: radius, others: layout) else { continue }
            func obstacles() -> [OrbDisc] {
                layout + others.indices.filter { $0 != index }.map { OrbDisc(center: positions[$0], radius: others[$0].radius) }
            }
            var center = positions[index]
            for _ in 0..<64 {
                guard let blocker = obstacles().first(where: { !isClear(center, radius: radius, from: $0) }) else { break }
                let target = main(blocker.center) + mainDirection * (blocker.radius + gap + radius)
                center = vertical ? CGPoint(x: center.x, y: target) : CGPoint(x: target, y: center.y)
            }
            if !fits(center, radius: radius, in: visible) || !isFree(center, radius: radius, others: obstacles()) {
                center = resolveOverlap(others[index].center, radius: radius, others: obstacles(), visible: visible)
            }
            positions[index] = center
            pushed[index] = center
        }
        return (children, pushed)
    }

    // MARK: Accessibility

    /// The four corners of the usable area at the snap margin, in the order of the "move to next corner" action:
    /// top-right, bottom-right, bottom-left, top-left.
    public static func corners(radius: CGFloat, visible: CGRect) -> [CGPoint] {
        let inset = OrbSnap.margin + radius
        let points = [
            CGPoint(x: visible.maxX - inset, y: visible.maxY - inset),
            CGPoint(x: visible.maxX - inset, y: visible.minY + inset),
            CGPoint(x: visible.minX + inset, y: visible.minY + inset),
            CGPoint(x: visible.minX + inset, y: visible.maxY - inset),
        ]
        return points.map { OrbSnap.clamped($0, radius: radius, in: visible) }
    }

    /// The accessibility action `a11y.orb.moveCorner`: from the corner nearest the disc to the next one in the cycle
    /// top-right → bottom-right → bottom-left → top-left, skipping corners another orb occupies; when every corner
    /// is taken, the nearest free touching position at the next corner.
    public static func cornerCycle(current: OrbDisc, visible: CGRect, others: [OrbDisc]) -> CGPoint {
        let radius = current.radius
        let points = corners(radius: radius, visible: visible)
        let nearest = points.indices.min { distance(points[$0], current.center) < distance(points[$1], current.center) } ?? 0
        for step in 1...3 {
            let candidate = points[(nearest + step) % 4]
            if isFree(candidate, radius: radius, others: others) { return candidate }
        }
        let next = points[(nearest + 1) % 4]
        return resolveOverlap(next, radius: radius, others: others, visible: visible)
    }

    // MARK: Helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

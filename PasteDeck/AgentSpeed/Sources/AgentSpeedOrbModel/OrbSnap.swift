import CoreGraphics

/// A display's full and usable frames in global screen coordinates.
public struct OrbSnapScreen: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Pure placement geometry for the floating orb. Every position is the disc center; distances are measured from
/// the disc edge.
public enum OrbSnap {
    /// Releasing the disc this close to a usable edge (or past it) snaps it to `margin`.
    public static let threshold: CGFloat = 24
    public static let margin: CGFloat = 12
    /// Default distance from the top-right corner of the usable area.
    public static let defaultInset: CGFloat = 24

    // MARK: Release

    public static func snapped(_ center: CGPoint, radius: CGFloat, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: snapAxis(center.x, radius: radius, low: visible.minX, high: visible.maxX),
            y: snapAxis(center.y, radius: radius, low: visible.minY, high: visible.maxY)
        )
    }

    public static func clamped(_ center: CGPoint, radius: CGFloat, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: clampAxis(center.x, radius: radius, low: visible.minX, high: visible.maxX),
            y: clampAxis(center.y, radius: radius, low: visible.minY, high: visible.maxY)
        )
    }

    public static func defaultCenter(radius: CGFloat, in visible: CGRect) -> CGPoint {
        clamped(
            CGPoint(x: visible.maxX - defaultInset - radius, y: visible.maxY - defaultInset - radius),
            radius: radius,
            in: visible
        )
    }

    /// New center after a diameter change: edges the disc is docked to keep their distance, otherwise the center
    /// stays put; the result is always fully inside `visible`.
    public static func resized(_ center: CGPoint, from oldRadius: CGFloat, to newRadius: CGFloat, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: resizeAxis(center.x, from: oldRadius, to: newRadius, low: visible.minX, high: visible.maxX),
            y: resizeAxis(center.y, from: oldRadius, to: newRadius, low: visible.minY, high: visible.maxY)
        )
    }

    /// Index of the screen the disc belongs to: the one whose frame contains the center, else the nearest.
    public static func screenIndex(for point: CGPoint, in screens: [OrbSnapScreen]) -> Int? {
        if let index = screens.firstIndex(where: { $0.frame.contains(point) }) { return index }
        return screens.indices.min { distanceSquared(point, to: screens[$0].frame) < distanceSquared(point, to: screens[$1].frame) }
    }

    // MARK: Drag

    /// Rects the disc center can occupy while dragging without resistance: each usable area inset by the radius,
    /// plus bridges across edges shared by two displays so the disc can travel between them.
    public static func dragRegion(screens: [OrbSnapScreen], radius: CGFloat) -> [CGRect] {
        let allowed = screens.map { inset($0.visibleFrame, by: radius) }
        var region = allowed
        for i in screens.indices {
            for j in screens.indices where j != i {
                let a = screens[i].frame
                let b = screens[j].frame
                if abs(a.maxX - b.minX) < 1, let bridge = bridge(
                    across: (allowed[i].maxX, allowed[j].minX),
                    along: (a.minY, a.maxY, b.minY, b.maxY),
                    allowed: (allowed[i].minY, allowed[i].maxY, allowed[j].minY, allowed[j].maxY),
                    radius: radius
                ) {
                    region.append(CGRect(x: bridge.across.lowerBound, y: bridge.along.lowerBound,
                                         width: bridge.across.upperBound - bridge.across.lowerBound,
                                         height: bridge.along.upperBound - bridge.along.lowerBound))
                }
                if abs(a.maxY - b.minY) < 1, let bridge = bridge(
                    across: (allowed[i].maxY, allowed[j].minY),
                    along: (a.minX, a.maxX, b.minX, b.maxX),
                    allowed: (allowed[i].minX, allowed[i].maxX, allowed[j].minX, allowed[j].maxX),
                    radius: radius
                ) {
                    region.append(CGRect(x: bridge.along.lowerBound, y: bridge.across.lowerBound,
                                         width: bridge.along.upperBound - bridge.along.lowerBound,
                                         height: bridge.across.upperBound - bridge.across.lowerBound))
                }
            }
        }
        return region
    }

    /// Follows `point` freely inside `region` and resists beyond it like a rubber band. Each rect proposes its own
    /// stretched position; they are blended by inverse distance so the result stays continuous around the concave
    /// corners of multi-display arrangements.
    public static func rubberBanded(_ point: CGPoint, region: [CGRect], radius: CGFloat) -> CGPoint {
        guard !region.isEmpty else { return point }
        let limit = max(24, radius * 0.6)
        var sum = CGPoint.zero
        var totalWeight: CGFloat = 0
        for rect in region {
            let nearest = CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
            let distance = hypot(point.x - nearest.x, point.y - nearest.y)
            if distance < 0.001 { return point }
            let scale = limit * (1 - 1 / (distance * 0.55 / limit + 1)) / distance
            let weight = 1 / pow(distance, 4)
            sum.x += (nearest.x + (point.x - nearest.x) * scale) * weight
            sum.y += (nearest.y + (point.y - nearest.y) * scale) * weight
            totalWeight += weight
        }
        return CGPoint(x: sum.x / totalWeight, y: sum.y / totalWeight)
    }

    // MARK: Axes

    public static func clampAxis(_ value: CGFloat, radius: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        let lower = low + radius
        let upper = high - radius
        guard lower <= upper else { return (low + high) / 2 }
        return min(max(value, lower), upper)
    }

    private static func snapAxis(_ value: CGFloat, radius: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high - low >= 2 * (radius + margin) else { return clampAxis(value, radius: radius, low: low, high: high) }
        let toLow = value - radius - low
        let toHigh = high - (value + radius)
        if toLow <= threshold, toLow <= toHigh { return low + margin + radius }
        if toHigh <= threshold { return high - margin - radius }
        return value
    }

    private static func resizeAxis(_ value: CGFloat, from old: CGFloat, to new: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        let toLow = value - old - low
        let toHigh = high - (value + old)
        var next = value
        if toLow <= threshold, toLow <= toHigh {
            next = low + max(toLow, 0) + new
        } else if toHigh <= threshold {
            next = high - max(toHigh, 0) - new
        }
        return clampAxis(next, radius: new, low: low, high: high)
    }

    private static func inset(_ rect: CGRect, by radius: CGFloat) -> CGRect {
        let x = rect.width >= 2 * radius ? (rect.minX + radius, rect.maxX - radius) : (rect.midX, rect.midX)
        let y = rect.height >= 2 * radius ? (rect.minY + radius, rect.maxY - radius) : (rect.midY, rect.midY)
        return CGRect(x: x.0, y: y.0, width: x.1 - x.0, height: y.1 - y.0)
    }

    /// A crossing between two displays that share an edge; `along` is the shared span the disc fits into.
    private static func bridge(
        across: (CGFloat, CGFloat),
        along frames: (CGFloat, CGFloat, CGFloat, CGFloat),
        allowed: (CGFloat, CGFloat, CGFloat, CGFloat),
        radius: CGFloat
    ) -> (across: ClosedRange<CGFloat>, along: ClosedRange<CGFloat>)? {
        let sharedLow = max(frames.0, frames.2)
        let sharedHigh = min(frames.1, frames.3)
        guard sharedHigh > sharedLow else { return nil }
        var low = max(allowed.0, allowed.2, sharedLow + radius)
        var high = min(allowed.1, allowed.3, sharedHigh - radius)
        if low > high {
            let middle = min(max((sharedLow + sharedHigh) / 2, max(allowed.0, allowed.2)), min(allowed.1, allowed.3))
            low = middle
            high = middle
        }
        let start = min(across.0, across.1)
        let end = max(across.0, across.1)
        return (start...end, low...high)
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

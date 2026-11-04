import CoreGraphics
import Foundation

/// A floating window's footprint for placement (DESIGN 2b, 2c): an axis-aligned rounded square in global screen points
/// (AppKit, y up). An orb is a disc, a rounded square whose corner radius is its half side; a board is its rounded
/// square. Both keep the 12 pt clearance from every other one.
public struct FloatingShape: Equatable, Hashable, Sendable {
    public var center: CGPoint
    /// Half the side of the bounding square.
    public var half: CGFloat
    public var corner: CGFloat

    public init(center: CGPoint, half: CGFloat, corner: CGFloat) {
        self.center = center
        self.half = max(0, half)
        self.corner = min(max(0, corner), self.half)
    }

    public init(_ disc: OrbDisc) {
        self.init(center: disc.center, half: disc.radius, corner: disc.radius)
    }

    public static func board(center: CGPoint, side: CGFloat, corner: CGFloat) -> FloatingShape {
        FloatingShape(center: center, half: side / 2, corner: corner)
    }

    public var isDisc: Bool { abs(half - corner) < 0.001 }

    public func moved(to center: CGPoint) -> FloatingShape {
        var copy = self
        copy.center = center
        return copy
    }

    /// Edge-to-edge distance to `other` (negative when they overlap): the signed distance of the other center to the
    /// Minkowski sum of both shapes, a rounded square of the summed half sides and corner radii.
    public func distance(to other: FloatingShape) -> CGFloat {
        Self.roundedBoxDistance(CGPoint(x: other.center.x - center.x, y: other.center.y - center.y),
                                half: half + other.half, corner: corner + other.corner)
    }

    /// Signed distance from `p` (relative to the center) to a rounded square.
    static func roundedBoxDistance(_ p: CGPoint, half: CGFloat, corner: CGFloat) -> CGFloat {
        let kx = abs(p.x) - half + corner
        let ky = abs(p.y) - half + corner
        let outside = hypot(max(kx, 0), max(ky, 0))
        return outside + min(max(kx, ky), 0) - corner
    }

    /// The point on a rounded square's outline nearest to `p` (both relative to its center).
    static func nearestOnOutline(_ p: CGPoint, half: CGFloat, corner: CGFloat) -> CGPoint {
        let inner = half - corner
        let q = CGPoint(x: min(max(p.x, -inner), inner), y: min(max(p.y, -inner), inner))
        let dx = p.x - q.x, dy = p.y - q.y
        let length = hypot(dx, dy)
        if length > 0.0001 {
            return CGPoint(x: q.x + dx / length * corner, y: q.y + dy / length * corner)
        }
        // Inside the inner square: straight out through the nearest side.
        if half - abs(p.x) <= half - abs(p.y) {
            return CGPoint(x: p.x < 0 ? -half : half, y: p.y)
        }
        return CGPoint(x: p.x, y: p.y < 0 ? -half : half)
    }

    /// Where on a line `axis = fixed` (relative offset) a rounded square's outline lies: the half span of the
    /// outline across that line, nil when the line misses it.
    static func outlineSpan(offset: CGFloat, half: CGFloat, corner: CGFloat) -> CGFloat? {
        let o = abs(offset)
        guard o <= half else { return nil }
        let inner = half - corner
        guard o > inner else { return half }
        let u = o - inner
        return inner + sqrt(max(0, corner * corner - u * u))
    }
}

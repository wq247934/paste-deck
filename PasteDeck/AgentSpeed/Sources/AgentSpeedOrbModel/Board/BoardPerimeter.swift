import Foundation

/// The outline of a rounded rectangle walked clockwise on screen (y down) from the end of the top-left corner, as
/// the prototype's `perimeterPoint` and the SVG rect path the comets run on.
public struct BoardPerimeter: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var radius: Double

    public init(width: Double, height: Double, radius: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.radius = min(max(0, radius), min(self.width, self.height) / 2)
    }

    private var straightW: Double { width - 2 * radius }
    private var straightH: Double { height - 2 * radius }
    private var arc: Double { .pi * radius / 2 }

    public var length: Double { 2 * straightW + 2 * straightH + 4 * arc }

    /// The point `distance` along the outline (wrapping), with the unit tangent (direction of travel).
    public func point(at distance: Double) -> (x: Double, y: Double, tx: Double, ty: Double) {
        let total = length
        guard total > 0 else { return (0, 0, 1, 0) }
        var d = distance.truncatingRemainder(dividingBy: total)
        if d < 0 { d += total }
        let r = radius, w = width, h = height
        func corner(_ cx: Double, _ cy: Double, _ start: Double, _ s: Double) -> (Double, Double, Double, Double) {
            let a = start + (r > 0 ? s / r : 0)
            return (cx + cos(a) * r, cy + sin(a) * r, -sin(a), cos(a))
        }
        if d <= straightW { return (r + d, 0, 1, 0) }
        d -= straightW
        if d <= arc { return corner(w - r, r, -.pi / 2, d) }
        d -= arc
        if d <= straightH { return (w, r + d, 0, 1) }
        d -= straightH
        if d <= arc { return corner(w - r, h - r, 0, d) }
        d -= arc
        if d <= straightW { return (w - r - d, h, -1, 0) }
        d -= straightW
        if d <= arc { return corner(r, h - r, .pi / 2, d) }
        d -= arc
        if d <= straightH { return (0, h - r - d, 0, -1) }
        d -= straightH
        return corner(r, r, .pi, min(d, arc))
    }

    /// The point at `fraction` of the outline (0...1, wrapping).
    public func point(fraction: Double) -> (x: Double, y: Double, tx: Double, ty: Double) {
        point(at: fraction * length)
    }
}

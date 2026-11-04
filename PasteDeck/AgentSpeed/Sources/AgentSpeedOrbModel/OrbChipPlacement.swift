import CoreGraphics

/// Where a chip goes (DESIGN 2b): centered 6 pt below the disc; when another orb or the screen edge is in the way, on
/// the side facing the screen center, vertically centered; always inside the usable area. `stack` pushes it further
/// down (the undo chip under the source chip). The chip size includes its 8 pt shadow margin.
public enum OrbChipPlacement {
    public static func frame(size: CGSize, disc: OrbDisc, visible: CGRect, others: [OrbDisc], stack: CGFloat = 0) -> CGRect {
        let margin: CGFloat = 8
        let gap: CGFloat = 6
        var below = CGRect(x: disc.center.x - size.width / 2, y: disc.center.y - disc.radius - gap + margin - size.height - stack,
                           width: size.width, height: size.height)
        let core = below.insetBy(dx: margin, dy: margin)
        let blocked = core.minY < visible.minY
            || others.contains { CGRect(x: $0.center.x - $0.radius, y: $0.center.y - $0.radius, width: 2 * $0.radius, height: 2 * $0.radius).intersects(core) }
        if blocked {
            let left = disc.center.x > visible.midX
            let x = left ? disc.center.x - disc.radius - gap - (size.width - margin) : disc.center.x + disc.radius + gap - margin
            below = CGRect(x: x, y: disc.center.y - size.height / 2 - stack, width: size.width, height: size.height)
        }
        let minX = visible.minX - margin
        let maxX = visible.maxX + margin - size.width
        let minY = visible.minY - margin
        let maxY = visible.maxY + margin - size.height
        below.origin.x = min(max(below.origin.x, minX), max(minX, maxX))
        below.origin.y = min(max(below.origin.y, minY), max(minY, maxY))
        return below
    }
}

import CoreGraphics
import QuartzCore

/// One press on the disc: stays a click until the pointer travels past `threshold`, then moves the disc 1:1 with
/// the pointer and remembers recent positions for the release velocity.
struct OrbDragSession {
    static let threshold: CGFloat = 3
    private static let velocityWindow: CFTimeInterval = 0.08
    private static let staleAfter: CFTimeInterval = 0.05
    private static let maxSpeed: CGFloat = 4000

    let startPointer: CGPoint
    let startCenter: CGPoint
    private(set) var isMoving = false
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []

    init(pointer: CGPoint, center: CGPoint) {
        startPointer = pointer
        startCenter = center
    }

    /// Unconstrained disc center for `pointer`, or nil while the press is still a click.
    mutating func center(for pointer: CGPoint) -> CGPoint? {
        let dx = pointer.x - startPointer.x
        let dy = pointer.y - startPointer.y
        if !isMoving, hypot(dx, dy) < Self.threshold { return nil }
        isMoving = true
        return CGPoint(x: startCenter.x + dx, y: startCenter.y + dy)
    }

    /// Records where the disc was actually drawn, for the release velocity.
    mutating func record(_ center: CGPoint, at time: CFTimeInterval = CACurrentMediaTime()) {
        samples.append((time, center))
        samples.removeAll { time - $0.time > Self.velocityWindow }
    }

    func releaseVelocity(at time: CFTimeInterval = CACurrentMediaTime()) -> CGVector {
        guard let first = samples.first, let last = samples.last, time - last.time < Self.staleAfter else { return .zero }
        let dt = last.time - first.time
        guard dt > 0.008 else { return .zero }
        var velocity = CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > Self.maxSpeed {
            velocity.dx *= Self.maxSpeed / speed
            velocity.dy *= Self.maxSpeed / speed
        }
        return velocity
    }
}

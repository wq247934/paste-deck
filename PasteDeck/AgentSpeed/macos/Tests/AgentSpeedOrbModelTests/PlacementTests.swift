import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Orb placement")
struct PlacementTests {
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let r: CGFloat = 74

    static func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat = r) -> OrbDisc {
        OrbDisc(center: CGPoint(x: x, y: y), radius: radius)
    }

    @Test func touchingSlotsAreLeftBelowRightAbove() {
        let slots = OrbPlacement.touchingSlots(of: Self.disc(500, 400), radius: 56)
        #expect(slots == [CGPoint(x: 358, y: 400), CGPoint(x: 500, y: 258), CGPoint(x: 642, y: 400), CGPoint(x: 500, y: 542)])
    }

    @Test func newOrbTakesTheFirstFreeTouchingSlot() {
        let anchor = Self.disc(500, 400)
        #expect(OrbPlacement.placeNew(radius: Self.r, near: anchor, others: [anchor], visible: Self.visible) == CGPoint(x: 340, y: 400))
        // Left is off screen for an orb docked at the left edge: below.
        let left = Self.disc(86, 400)
        #expect(OrbPlacement.placeNew(radius: Self.r, near: left, others: [left], visible: Self.visible) == CGPoint(x: 86, y: 240))
        // Left taken: below.
        let blocker = Self.disc(340, 400)
        #expect(OrbPlacement.placeNew(radius: Self.r, near: anchor, others: [anchor, blocker], visible: Self.visible) == CGPoint(x: 500, y: 240))
    }

    @Test func newOrbSearchesTheGridWhenAllSlotsAreTaken() throws {
        let anchor = Self.disc(500, 400)
        let others = [anchor] + OrbPlacement.touchingSlots(of: anchor, radius: Self.r).map { OrbDisc(center: $0, radius: Self.r) }
        let point = OrbPlacement.placeNew(radius: Self.r, near: anchor, others: others, visible: Self.visible)
        #expect(OrbPlacement.isFree(point, radius: Self.r, others: others))
        #expect(OrbPlacement.fits(point, radius: Self.r, in: Self.visible))
        let dx = (point.x - 500) / 24, dy = (point.y - 400) / 24
        #expect(dx == dx.rounded() && dy == dy.rounded(), "on the 24 pt grid")
        // Nearest: no free grid point is closer.
        let distance = hypot(point.x - 500, point.y - 400)
        #expect(distance < 260)
    }

    @Test func newOrbCascadesOnAFullDisplay() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 200)
        let anchor = Self.disc(100, 100, 90)
        let point = OrbPlacement.placeNew(radius: 90, near: anchor, others: [anchor], visible: small)
        #expect(point == CGPoint(x: 110, y: 90))
        #expect(OrbPlacement.fits(point, radius: 90, in: small))
    }

    @Test func newOrbWithoutAnchorUsesTheDefaultCorner() {
        let point = OrbPlacement.placeNew(radius: Self.r, near: nil, others: [], visible: Self.visible)
        #expect(point == OrbSnap.defaultCenter(radius: Self.r, in: Self.visible))
    }

    @Test func overlapResolvesToTheNearestTouchingPosition() {
        let other = Self.disc(600, 400)
        #expect(OrbPlacement.resolveOverlap(CGPoint(x: 300, y: 300), radius: Self.r, others: [other], visible: Self.visible) == CGPoint(x: 300, y: 300))
        let resolved = OrbPlacement.resolveOverlap(CGPoint(x: 560, y: 400), radius: Self.r, others: [other], visible: Self.visible)
        #expect(OrbPlacement.isFree(resolved, radius: Self.r, others: [other]))
        #expect(abs(hypot(resolved.x - 600, resolved.y - 400) - (2 * Self.r + 12)) < 1)
        #expect(resolved.x < 600, "stays on the side it came from")
        // Off-screen input is clamped first.
        let clamped = OrbPlacement.resolveOverlap(CGPoint(x: -50, y: 2000), radius: Self.r, others: [], visible: Self.visible)
        #expect(clamped == CGPoint(x: Self.r, y: 875 - Self.r))
    }

    @Test func dockedEdgePrefersLeftAndRight() {
        #expect(OrbPlacement.dockedEdge(of: Self.disc(1440 - 12 - Self.r, 875 - 12 - Self.r), visible: Self.visible) == .right)
        #expect(OrbPlacement.dockedEdge(of: Self.disc(700, 875 - 12 - Self.r), visible: Self.visible) == .top)
        #expect(OrbPlacement.dockedEdge(of: Self.disc(700, 400), visible: Self.visible) == nil)
    }

    @Test func splitMakesARowTowardTheInterior() {
        let origin = Self.disc(1440 - 12 - Self.r - 200, 400)
        let layout = OrbPlacement.splitLayout(origin: origin, radii: [Self.r, Self.r], visible: Self.visible, others: [], dockedEdge: nil)
        #expect(layout.children == [CGPoint(x: origin.center.x - 160, y: 400), CGPoint(x: origin.center.x - 320, y: 400)])
        #expect(layout.pushed.isEmpty)
    }

    @Test func splitMakesAColumnWhenDockedLeftOrRight() {
        let origin = Self.disc(1440 - 12 - Self.r, 875 - 12 - Self.r)
        let layout = OrbPlacement.splitLayout(origin: origin, radii: [Self.r, Self.r], visible: Self.visible, others: [],
                                              dockedEdge: OrbPlacement.dockedEdge(of: origin, visible: Self.visible))
        #expect(layout.children.map(\.x) == [origin.center.x, origin.center.x])
        #expect(layout.children.map(\.y) == [origin.center.y - 160, origin.center.y - 320])
    }

    @Test func splitWrapsIntoTheNextColumn() {
        let origin = Self.disc(1440 - 12 - Self.r, 875 - 12 - Self.r)
        let layout = OrbPlacement.splitLayout(origin: origin, radii: Array(repeating: Self.r, count: 6), visible: Self.visible,
                                              others: [], dockedEdge: .right)
        // 875 pt fits five orbs per column; the sixth starts a new column toward the interior, level with the original.
        let xs = layout.children.map(\.x)
        #expect(xs.prefix(4).allSatisfy { $0 == origin.center.x })
        #expect(xs[4] == origin.center.x - 160 && layout.children[4].y == origin.center.y)
        #expect(xs[5] == origin.center.x - 160 && layout.children[5].y == origin.center.y - 160)
        let all = [origin] + layout.children.map { OrbDisc(center: $0, radius: Self.r) }
        for (i, a) in all.enumerated() {
            #expect(OrbPlacement.fits(a.center, radius: Self.r, in: Self.visible))
            for b in all[(i + 1)...] { #expect(OrbPlacement.isClear(a.center, radius: Self.r, from: b)) }
        }
    }

    @Test func splitPushesOrbsInTheWayAlongTheAxis() {
        let origin = Self.disc(300, 400)
        let blocker = Self.disc(470, 400)
        let bystander = Self.disc(300, 700)
        let layout = OrbPlacement.splitLayout(origin: origin, radii: [Self.r], visible: Self.visible, others: [blocker, bystander], dockedEdge: nil)
        #expect(layout.children == [CGPoint(x: 460, y: 400)])
        #expect(layout.pushed[0] == CGPoint(x: 620, y: 400))
        #expect(layout.pushed[1] == nil)
    }

    @Test func cornerCycleGoesClockwiseFromTopRight() {
        let corners = OrbPlacement.corners(radius: Self.r, visible: Self.visible)
        let topRight = OrbDisc(center: corners[0], radius: Self.r)
        #expect(OrbPlacement.cornerCycle(current: topRight, visible: Self.visible, others: []) == corners[1])
        let bottomRight = OrbDisc(center: corners[1], radius: Self.r)
        #expect(OrbPlacement.cornerCycle(current: bottomRight, visible: Self.visible, others: []) == corners[2])
        let topLeft = OrbDisc(center: corners[3], radius: Self.r)
        #expect(OrbPlacement.cornerCycle(current: topLeft, visible: Self.visible, others: []) == corners[0])
        // A middle orb counts as being at its nearest corner.
        #expect(OrbPlacement.cornerCycle(current: Self.disc(1000, 600), visible: Self.visible, others: []) == corners[1])
    }

    @Test func cornerCycleSkipsOccupiedCorners() {
        let corners = OrbPlacement.corners(radius: Self.r, visible: Self.visible)
        let topRight = OrbDisc(center: corners[0], radius: Self.r)
        let occupied = [OrbDisc(center: corners[1], radius: Self.r)]
        #expect(OrbPlacement.cornerCycle(current: topRight, visible: Self.visible, others: occupied) == corners[2])
        let all = [1, 2, 3].map { OrbDisc(center: corners[$0], radius: Self.r) }
        let point = OrbPlacement.cornerCycle(current: topRight, visible: Self.visible, others: all)
        #expect(OrbPlacement.isFree(point, radius: Self.r, others: all))
        #expect(abs(hypot(point.x - corners[1].x, point.y - corners[1].y) - (2 * Self.r + 12)) < 1, "touching the next corner's orb")
    }
}

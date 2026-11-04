import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Boards among orbs")
struct FloatingPlacementTests {
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    static func board(_ x: CGFloat, _ y: CGFloat, side: CGFloat = 340, corner: CGFloat = 22) -> FloatingShape {
        .board(center: CGPoint(x: x, y: y), side: side, corner: corner)
    }

    static func orb(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat = 74) -> FloatingShape {
        FloatingShape(OrbDisc(center: CGPoint(x: x, y: y), radius: r))
    }

    @Test func distancesBetweenDiscsAndRoundedSquares() {
        #expect(abs(Self.orb(0, 0).distance(to: Self.orb(200, 0)) - 52) < 0.001)
        #expect(abs(Self.board(0, 0).distance(to: Self.board(352, 0)) - 12) < 0.001, "side by side")
        #expect(abs(Self.board(0, 0).distance(to: Self.orb(170 + 12 + 74, 30)) - 12) < 0.001, "an orb beside a side")
        // Corner to corner: the rounded corners keep them further apart than the bounding squares.
        let diagonal = Self.board(0, 0).distance(to: Self.board(345, 345))
        #expect(diagonal > 5)
        #expect(Self.board(0, 0).distance(to: Self.board(100, 0)) < 0)
    }

    @Test func discsAloneBehaveLikeOrbMagnet() {
        var random = LedRandom(seed: 7)
        for _ in 0..<300 {
            let others = (0..<3).map { _ in
                OrbDisc(center: CGPoint(x: random.range(100...1300), y: random.range(100...780)), radius: random.range(40...110))
            }
            let radius = CGFloat(random.range(40...110))
            let raw = CGPoint(x: random.range(0...1440), y: random.range(0...875))
            let expected = OrbMagnet.releaseTarget(raw: raw, radius: radius, others: others, visible: Self.visible)
            let shape = FloatingShape(OrbDisc(center: raw, radius: radius))
            let actual = FloatingMagnet.releaseTarget(raw: raw, shape: shape, others: others.map(FloatingShape.init), visible: Self.visible)
            #expect(hypot(actual.x - expected.x, actual.y - expected.y) < 0.5, "raw \(raw)")
            let drag = OrbMagnet.dragTarget(raw: raw, radius: radius, others: others, visible: Self.visible)
            let generalized = FloatingMagnet.dragTarget(raw: raw, shape: shape, others: others.map(FloatingShape.init), visible: Self.visible)
            #expect(hypot(drag.target.x - generalized.target.x, drag.target.y - generalized.target.y) < 0.01)
            #expect(drag.attachedTo == generalized.attachedTo)
        }
    }

    @Test func aBoardTouchesAnotherBoardFlushAlongItsSide() {
        let other = Self.board(500, 400)
        let dragged = Self.board(0, 0)
        let point = FloatingMagnet.touching(CGPoint(x: 845, y: 430), shape: dragged, against: other)
        #expect(abs(point.x - 852) < 0.001 && abs(point.y - 430) < 0.001)
        let result = FloatingMagnet.dragTarget(raw: CGPoint(x: 860, y: 430), shape: dragged, others: [other], visible: Self.visible)
        #expect(result.attachedTo == 0)
        #expect(abs(result.target.x - 852) < 0.001)
    }

    @Test func releasedOverAnOrbABoardSlidesClear() {
        let orbs = [Self.orb(700, 430)]
        let shape = Self.board(760, 420)
        let target = FloatingMagnet.releaseTarget(raw: shape.center, shape: shape, others: orbs, visible: Self.visible)
        let placed = shape.moved(to: target)
        #expect(FloatingPlacement.isFree(placed, others: orbs))
        #expect(FloatingPlacement.fits(placed, in: Self.visible))
        // An orb released over a board slides clear of it as well.
        let board = Self.board(700, 430)
        let orb = Self.orb(720, 440)
        let orbTarget = FloatingMagnet.releaseTarget(raw: orb.center, shape: orb, others: [board], visible: Self.visible)
        #expect(FloatingPlacement.isFree(orb.moved(to: orbTarget), others: [board]))
    }

    @Test func aNewBoardTakesTheFirstFreeTouchingSlotOfItsOrb() {
        let anchor = Self.orb(1000, 500)
        let template = Self.board(0, 0)
        let point = FloatingPlacement.placeNew(template, near: anchor, others: [anchor], visible: Self.visible)
        #expect(point == CGPoint(x: 1000 - 74 - 12 - 170, y: 500))
        // Left taken by a board, and below would overlap that board: right.
        let blocker = Self.board(744, 500)
        let next = FloatingPlacement.placeNew(template, near: anchor, others: [anchor, blocker], visible: Self.visible)
        #expect(FloatingPlacement.isFree(template.moved(to: next), others: [anchor, blocker]))
        #expect(next == CGPoint(x: 1000 + 74 + 12 + 170, y: 500))
    }

    @Test func aFullDisplayCascades() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 400)
        let blocker = Self.board(200, 200)
        let point = FloatingPlacement.placeNew(Self.board(0, 0), near: blocker, others: [blocker], visible: small)
        #expect(FloatingPlacement.fits(Self.board(point.x, point.y), in: small))
    }

    @Test func edgeSnappingUsesTheBoundingSquare() {
        let shape = Self.board(0, 0)
        let target = FloatingMagnet.releaseTarget(raw: CGPoint(x: 1440 - 170 - 20, y: 500), shape: shape, others: [], visible: Self.visible)
        #expect(target == CGPoint(x: 1440 - 170 - 12, y: 500))
    }

    @Test func outlineHelpers() {
        #expect(FloatingShape.outlineSpan(offset: 0, half: 100, corner: 20) == 100)
        #expect(FloatingShape.outlineSpan(offset: 101, half: 100, corner: 20) == nil)
        let span = FloatingShape.outlineSpan(offset: 90, half: 100, corner: 20) ?? 0
        #expect(abs(span - (80 + sqrt(400 - 100))) < 0.0001)
        let inside = FloatingShape.nearestOnOutline(CGPoint(x: 10, y: 2), half: 100, corner: 20)
        #expect(inside == CGPoint(x: 100, y: 2))
        let corner = FloatingShape.nearestOnOutline(CGPoint(x: 200, y: 200), half: 100, corner: 20)
        #expect(abs(hypot(corner.x - 80, corner.y - 80) - 20) < 0.0001)
    }

    @Test func perimeterWalksClockwiseFromTheTopLeftCorner() {
        let outline = BoardPerimeter(width: 340, height: 340, radius: 22)
        #expect(abs(outline.length - (4 * 296 + 2 * .pi * 22)) < 0.0001)
        let start = outline.point(at: 0)
        #expect(start.x == 22 && start.y == 0 && start.tx == 1)
        let right = outline.point(at: 296 + .pi * 11 + 10)
        #expect(abs(right.x - 340) < 0.0001 && abs(right.y - 32) < 0.0001 && right.ty == 1)
        let wrapped = outline.point(at: outline.length + 5)
        #expect(abs(wrapped.x - 27) < 0.0001)
    }
}

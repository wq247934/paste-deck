import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Orb magnet and alignment")
struct MagnetTests {
    static let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let r: CGFloat = 74
    static let other = OrbDisc(center: CGPoint(x: 700, y: 400), radius: r)
    /// Center distance of two touching 148 pt orbs.
    static let touch: CGFloat = 2 * r + 12

    @Test func pullsWithinSixteenPoints() {
        let raw = CGPoint(x: 700 + Self.touch + 16, y: 400)
        let result = OrbMagnet.dragTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(result.target == CGPoint(x: 700 + Self.touch, y: 400))
        #expect(result.attachedTo == 0)
        #expect(result.guides.isEmpty)
    }

    @Test func doesNotPullAtSeventeenPoints() {
        let raw = CGPoint(x: 700 + Self.touch + 17, y: 400 + 20)
        let result = OrbMagnet.dragTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(result.attachedTo == nil)
        #expect(result.target.x == raw.x)
    }

    @Test func pullsAlongTheLineBetweenCenters() {
        let raw = CGPoint(x: 700 + 120, y: 400 + 120)
        let result = OrbMagnet.dragTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        let d = hypot(result.target.x - 700, result.target.y - 400)
        #expect(abs(d - Self.touch) < 0.001)
        #expect(abs(result.target.x - 700 - (result.target.y - 400)) < 0.001, "on the diagonal")
    }

    @Test func alignsWithinEightPointsAndShowsAGuide() {
        let raw = CGPoint(x: 706, y: 400 + Self.touch + 40)
        let result = OrbMagnet.dragTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(result.attachedTo == nil)
        #expect(result.target == CGPoint(x: 700, y: raw.y))
        #expect(result.guides == [OrbGuide(axis: .vertical, position: 700, from: 400 - Self.r, to: raw.y + Self.r)])
        let far = OrbMagnet.dragTarget(raw: CGPoint(x: 709, y: raw.y), radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(far.target.x == 709 && far.guides.isEmpty)
    }

    @Test func alignsOnlyWithinSixtyFourPointsEdgeToEdge() {
        let near = CGPoint(x: 700 + 2 * Self.r + 63, y: 404)
        #expect(OrbMagnet.dragTarget(raw: near, radius: Self.r, others: [Self.other], visible: Self.visible).target.y == 400)
        let away = CGPoint(x: 700 + 2 * Self.r + 66, y: 404)
        #expect(OrbMagnet.dragTarget(raw: away, radius: Self.r, others: [Self.other], visible: Self.visible).target.y == 404)
    }

    @Test func alignmentNeverPullsADiscOffTheEdgeItIsDockedTo() {
        let docked = OrbDisc(center: CGPoint(x: 1440 - 12 - Self.r, y: 300), radius: Self.r)
        let other = OrbDisc(center: CGPoint(x: 1440 - 12 - Self.r - 6, y: 300 + Self.touch + 30), radius: Self.r)
        let result = OrbMagnet.dragTarget(raw: docked.center, radius: Self.r, others: [other], visible: Self.visible)
        #expect(result.target.x == docked.center.x)
        #expect(result.guides.isEmpty)
    }

    @Test func releaseSnapsToTheScreenEdgeFirst() {
        let raw = CGPoint(x: 1440 - Self.r - 20, y: 500)
        let target = OrbMagnet.releaseTarget(raw: raw, radius: Self.r, others: [], visible: Self.visible)
        #expect(target == CGPoint(x: 1440 - 12 - Self.r, y: 500))
    }

    @Test func releaseTouchesAnOrbWhileKeepingTheEdge() {
        let docked = OrbDisc(center: CGPoint(x: 1440 - 12 - Self.r, y: 300), radius: Self.r)
        let raw = CGPoint(x: 1440 - Self.r - 18, y: 300 + Self.touch + 10)
        let target = OrbMagnet.releaseTarget(raw: raw, radius: Self.r, others: [docked], visible: Self.visible)
        #expect(target == CGPoint(x: docked.center.x, y: 300 + Self.touch))
    }

    @Test func releaseTouchesFreely() {
        let raw = CGPoint(x: 700 - Self.touch - 12, y: 410)
        let target = OrbMagnet.releaseTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(abs(hypot(target.x - 700, target.y - 400) - Self.touch) < 0.001)
    }

    @Test func releaseAlignsWhenNotTouching() {
        let raw = CGPoint(x: 703, y: 400 + Self.touch + 50)
        let target = OrbMagnet.releaseTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(target == CGPoint(x: 700, y: raw.y))
    }

    @Test func releaseNeverOverlaps() {
        let raw = CGPoint(x: 720, y: 400)
        let target = OrbMagnet.releaseTarget(raw: raw, radius: Self.r, others: [Self.other], visible: Self.visible)
        #expect(OrbPlacement.isFree(target, radius: Self.r, others: [Self.other]))
        #expect(OrbPlacement.fits(target, radius: Self.r, in: Self.visible))
    }
}

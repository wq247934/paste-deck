import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Name plate width budget and groups")
struct NameplateLayoutTests {
    static let visible = Nameplates.visible

    static func disc(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 148) -> OrbDisc {
        Nameplates.disc(x, y, size: size)
    }

    static func budget(_ index: Int, _ side: NameplateSide, _ discs: [OrbDisc], visible: CGRect = visible) -> CGFloat {
        NameplateLayout.budget(for: index, side: side, discs: discs, visible: visible)
    }

    // MARK: Budget above and below

    @Test(arguments: zip(Nameplates.sizes, [118, 154, 202] as [CGFloat]))
    func equalOrbsAtTheSnapGapGetSPlusSix(_ size: CGFloat, _ expected: CGFloat) {
        let step = size + Nameplates.snap
        let xs = (0..<3).map { 300 + CGFloat($0) * step }
        let discs = xs.map { Self.disc($0, 437.5, size: size) }
        for index in discs.indices {
            #expect(Nameplates.isClose(Self.budget(index, .below, discs), expected), "orb \(index)")
            #expect(Nameplates.isClose(Self.budget(index, .above, discs), expected), "orb \(index)")
        }
        for index in 0..<2 {
            let rightEdge = xs[index] + Self.budget(index, .below, discs) / 2
            let nextLeftEdge = xs[index + 1] - Self.budget(index + 1, .below, discs) / 2
            #expect(nextLeftEdge - rightEdge >= 6 - 1e-9, "plates at full budget stay 6 pt apart")
        }
    }

    @Test func unequalNeighboursSplitTheDistanceInProportionToTheirSizes() {
        // 112 and 196 at the 12 pt gap: centers 56 + 12 + 98 = 166 apart.
        let discs = [Self.disc(500, 437.5, size: 112), Self.disc(666, 437.5, size: 196)]
        let small = Self.budget(0, .below, discs)
        let large = Self.budget(1, .below, discs)
        #expect(Nameplates.isClose(small, 2 * (166 * 112 / 308 - 3)))
        #expect(Nameplates.isClose(large, 2 * (166 * 196 / 308 - 3)))
        #expect(Nameplates.isClose((small / 2 + 3) / (large / 2 + 3), 112 / 196), "the split point divides by size")
        #expect(Nameplates.isClose(166 - small / 2 - large / 2, 6))
        #expect(large < NameplateMetrics(diameter: 196).aloneBudget)
    }

    @Test func theTightestNeighbourInTheBandLimits() {
        let discs = [Self.disc(400, 437.5, size: 112), Self.disc(566, 437.5, size: 196), Self.disc(828, 437.5, size: 148)]
        let left: CGFloat = 2 * (166 * 196 / 308 - 3)
        let right: CGFloat = 2 * (262 * 196 / 344 - 3)
        #expect(left < right)
        #expect(Nameplates.isClose(Self.budget(1, .below, discs), left))
    }

    @Test func onlyDiscsInTheHorizontalBandLimit() {
        // Band: |Δy| < (S + Sn) / 2.
        let edge = [Self.disc(500, 437.5), Self.disc(560, 437.5 + 148)]
        #expect(Self.budget(0, .below, edge) == 222)
        let inside = [Self.disc(500, 437.5), Self.disc(560, 437.5 + 147)]
        #expect(Nameplates.isClose(Self.budget(0, .below, inside), 2 * (30 - 3)))
        let unequalEdge = [Self.disc(500, 437.5, size: 112), Self.disc(540, 437.5 - 154, size: 196)]
        #expect(Self.budget(0, .above, unequalEdge) == 168)
        let unequalInside = [Self.disc(500, 437.5, size: 112), Self.disc(540, 437.5 - 153.5, size: 196)]
        #expect(Nameplates.isClose(Self.budget(0, .above, unequalInside), 2 * (40 * 112 / 308 - 3)))
    }

    @Test func farOrStackedNeighboursLeaveTheAloneBudget() {
        #expect(Self.budget(0, .below, [Self.disc(300, 437.5), Self.disc(900, 437.5)]) == 222)
        #expect(Self.budget(0, .above, [Self.disc(300, 437.5)]) == 222)
        let column = [Self.disc(720, 597.5), Self.disc(720, 437.5), Self.disc(720, 277.5)]
        for index in column.indices {
            #expect(Self.budget(index, .below, column) == 222)
            #expect(Self.budget(index, .above, column) == 222)
        }
    }

    // MARK: Budget on a side

    @Test func sideBudgetsAreLimitedByTheUsableAreaAndOneAndAHalfS() {
        let right = [Self.disc(1440 - 12 - 74, 437.5)]
        #expect(Self.budget(0, .left, right) == 222)
        #expect(Self.budget(0, .right, right) == 4, "12 pt margin less g 5 and the 3 pt inset")
        let left = [Self.disc(12 + 74, 437.5)]
        #expect(Self.budget(0, .right, left) == 222)
        #expect(Self.budget(0, .left, left) == 4)
        let inset = [Self.disc(1440 - 100 - 74, 437.5)]
        #expect(Self.budget(0, .right, inset) == 92)
        let small = [Self.disc(1440 - 12 - 56, 437.5, size: 112)]
        #expect(Self.budget(0, .left, small) == 168)
        #expect(Self.budget(0, .right, small) == 5)
        let touching = [Self.disc(1440 - 74, 437.5)]
        #expect(Self.budget(0, .right, touching) == 0, "never negative")
        let row = [Self.disc(560, 437.5), Self.disc(720, 437.5)]
        #expect(Self.budget(0, .right, row) == 222, "the area limits a side plate instead of a neighbour; fit rejects collisions")
    }

    @Test func sideBudgetsUseTheAreaOfAnOffsetDisplay() {
        let area = CGRect(x: -1920, y: -120, width: 1920, height: 1055)
        #expect(Self.budget(0, .left, [Self.disc(-1920 + 86, 407.5)], visible: area) == 4)
        #expect(Self.budget(0, .right, [Self.disc(-86, 407.5)], visible: area) == 4)
        #expect(Self.budget(0, .left, [Self.disc(-86, 407.5)], visible: area) == 222)
    }

    // MARK: Groups

    @Test func discsWithin16PointsFormAGroup() {
        #expect(NameplateLayout.groups([Self.disc(300, 400), Self.disc(300 + 148 + 16, 400)]) == [[0, 1]])
        #expect(NameplateLayout.groups([Self.disc(300, 400), Self.disc(300 + 148 + 17, 400)]) == [[0], [1]])
        let unequal = { (gap: CGFloat) in [Self.disc(300, 400, size: 112), Self.disc(300 + 56 + 98 + gap, 400, size: 196)] }
        #expect(NameplateLayout.groups(unequal(16)) == [[0, 1]])
        #expect(NameplateLayout.groups(unequal(17)) == [[0], [1]])
    }

    @Test func groupDistanceIsMeasuredEdgeToEdgeAlongTheLineBetweenCenters() {
        // 3-4-5 triangles: centers 160 apart (12 pt gap) and 165 apart (17 pt gap).
        #expect(NameplateLayout.groups([Self.disc(300, 400), Self.disc(396, 528)]) == [[0, 1]])
        #expect(NameplateLayout.groups([Self.disc(300, 400), Self.disc(399, 532)]) == [[0], [1]])
    }

    @Test func groupsAreTransitive() {
        let chain = [Self.disc(100, 400), Self.disc(264, 400), Self.disc(428, 400)]
        #expect(NameplateLayout.groups(chain) == [[0, 1, 2]])
        let cluster = [Self.disc(640, 517.5), Self.disc(800, 517.5), Self.disc(640, 357.5), Self.disc(800, 357.5)]
        #expect(NameplateLayout.groups(cluster) == [[0, 1, 2, 3]], "diagonals are 78 pt apart but joined through the sides")
    }

    @Test func groupsKeepInputOrder() {
        let discs = [Self.disc(100, 400), Self.disc(1000, 400), Self.disc(264, 400), Self.disc(1164, 400), Self.disc(600, 100)]
        #expect(NameplateLayout.groups(discs) == [[0, 2], [1, 3], [4]])
        #expect(NameplateLayout.groups([]) == [])
    }
}

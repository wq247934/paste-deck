import AgentSpeedCore
import CoreGraphics
import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("Name plate placement")
struct NameplatePlacementTests {
    static let visible = Nameplates.visible
    /// Center coordinates of a 148 pt orb snapped 12 pt from each edge.
    static let left: CGFloat = 86, right: CGFloat = 1354, bottom: CGFloat = 86, top: CGFloat = 789, middle: CGFloat = 437.5
    /// Center distance of two 148 pt orbs at the 12 pt snap gap.
    static let step: CGFloat = 160

    static func disc(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 148) -> OrbDisc {
        Nameplates.disc(x, y, size: size)
    }

    /// A plate of a fixed width that cannot be shortened.
    static func fixed(_ id: String, _ disc: OrbDisc, width: CGFloat = 100, wantsPlate: Bool = true) -> NameplateRequest {
        NameplateRequest(id: id, disc: disc, wantsPlate: wantsPlate) { budget in width <= budget ? width : nil }
    }

    static func requests(_ discs: [OrbDisc], width: CGFloat = 100) -> [NameplateRequest] {
        discs.enumerated().map { fixed("o\($0.offset)", $0.element, width: width) }
    }

    static func sides(_ slots: [String: NameplateSlot], _ count: Int) -> [NameplateSide?] {
        (0..<count).map { slots["o\($0)"]?.side }
    }

    /// Every rule a resolved plate must keep (DESIGN 2b, Placement), as readable violations.
    static func violations(_ requests: [NameplateRequest], _ slots: [String: NameplateSlot], visible: CGRect) -> [String] {
        let tolerance: CGFloat = 0.011
        let area = visible.insetBy(dx: 3, dy: 3)
        var problems: [String] = []
        for (index, request) in requests.enumerated() {
            guard let slot = slots[request.id] else { continue }
            let rect = slot.rect
            if !request.wantsPlate { problems.append("\(request.id) has a slot without a plate") }
            if rect.minX < area.minX - tolerance || rect.maxX > area.maxX + tolerance
                || rect.minY < area.minY - tolerance || rect.maxY > area.maxY + tolerance {
                problems.append("\(request.id) leaves the usable area: \(rect)")
            }
            if rect.width > slot.budget + tolerance { problems.append("\(request.id) is wider than its budget") }
            if rect != slot.side.rect(around: request.disc, metrics: request.metrics, width: rect.width) {
                problems.append("\(request.id) is not g from its disc on the \(slot.side) side")
            }
            for (otherIndex, other) in requests.enumerated() where otherIndex != index {
                if Nameplates.distance(other.disc.center, rect) < other.disc.radius + 4 - tolerance {
                    problems.append("\(request.id) is within 4 pt of disc \(other.id)")
                }
                if let otherSlot = slots[other.id], otherIndex > index, Nameplates.distance(rect, otherSlot.rect) < 4 - tolerance {
                    problems.append("\(request.id) is within 4 pt of plate \(other.id)")
                }
            }
        }
        return problems
    }

    static func solve(_ requests: [NameplateRequest], visible: CGRect = visible) -> [String: NameplateSlot] {
        let slots = NameplateLayout.solve(requests, visible: visible)
        let problems = violations(requests, slots, visible: visible)
        #expect(problems.isEmpty, "\(problems)")
        #expect(NameplateLayout.solve(requests, visible: visible) == slots, "deterministic")
        return slots
    }

    // MARK: Geometry

    @Test(arguments: Nameplates.sizes)
    func eachSideSitsGFromTheDisc(_ size: CGFloat) {
        let disc = Self.disc(700, 400, size: size)
        let m = NameplateMetrics(diameter: size)
        let r = size / 2
        let below = NameplateSide.below.rect(around: disc, metrics: m, width: 90)
        #expect(below.maxY == 400 - r - m.gap && below.midX == 700 && below.height == m.height && below.width == 90)
        let above = NameplateSide.above.rect(around: disc, metrics: m, width: 90)
        #expect(above.minY == 400 + r + m.gap && above.midX == 700)
        let left = NameplateSide.left.rect(around: disc, metrics: m, width: 90)
        #expect(left.maxX == 700 - r - m.gap && left.midY == 400)
        let right = NameplateSide.right.rect(around: disc, metrics: m, width: 90)
        #expect(right.minX == 700 + r + m.gap && right.midY == 400)
        #expect(NameplateSide.allCases.filter(\.isSide) == [.left, .right])
    }

    @Test func theOrderTriesBelowAboveThenTheSideFacingTheCenter() {
        #expect(NameplateLayout.order(facingFrom: 1354, visible: Self.visible) == [.below, .above, .left, .right])
        #expect(NameplateLayout.order(facingFrom: 86, visible: Self.visible) == [.below, .above, .right, .left])
        let offset = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        #expect(NameplateLayout.order(facingFrom: -86, visible: offset) == [.below, .above, .left, .right])
        #expect(NameplateLayout.order(facingFrom: -1834, visible: offset) == [.below, .above, .right, .left])
    }

    // MARK: Rows, columns and clusters

    @Test func aRowInTheMiddleHasItsPlatesBelow() {
        let xs = [720 - Self.step, 720, 720 + Self.step]
        let slots = Self.solve(Self.requests(xs.map { Self.disc($0, Self.middle) }))
        #expect(Self.sides(slots, 3) == [.below, .below, .below])
        for (index, x) in xs.enumerated() {
            let slot = slots["o\(index)"]
            #expect(slot?.rect == CGRect(x: x - 50, y: Self.middle - 74 - 5 - 18, width: 100, height: 18))
            #expect(slot.map { Nameplates.isClose($0.budget, 154) } == true)
        }
    }

    @Test func aTopRowHasItsPlatesBelow() {
        let discs = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.top) }
        let slots = Self.solve(Self.requests(discs))
        #expect(Self.sides(slots, 3) == [.below, .below, .below])
        #expect(slots["o1"]?.rect.maxY == Self.top - 74 - 5, "y grows upward: below means a smaller y")
    }

    @Test func aRowDockedToTheBottomEdgeHasItsPlatesAbove() {
        let discs = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.bottom) }
        let slots = Self.solve(Self.requests(discs))
        #expect(Self.sides(slots, 3) == [.above, .above, .above])
        #expect(slots["o0"]?.rect.minY == Self.bottom + 74 + 5)
        #expect(Self.solve(Self.requests([Self.disc(Self.right, Self.bottom)]))["o0"]?.side == .above, "a single docked orb too")
    }

    @Test func aColumnDockedToTheRightEdgeListsItsNamesToTheLeft() {
        let ys = [Self.middle + Self.step, Self.middle, Self.middle - Self.step]
        let slots = Self.solve(Self.requests(ys.map { Self.disc(Self.right, $0) }))
        #expect(Self.sides(slots, 3) == [.left, .left, .left])
        for (index, y) in ys.enumerated() {
            #expect(slots["o\(index)"]?.rect.maxX == Self.right - 74 - 5)
            #expect(slots["o\(index)"]?.rect.midY == y)
        }
    }

    @Test func aColumnDockedToTheLeftEdgeListsItsNamesToTheRight() {
        let ys = [Self.middle + Self.step / 2, Self.middle - Self.step / 2]
        let slots = Self.solve(Self.requests(ys.map { Self.disc(Self.left, $0) }))
        #expect(Self.sides(slots, 2) == [.right, .right])
        #expect(slots["o0"]?.rect.minX == Self.left + 74 + 5)
    }

    @Test func aColumnAwayFromTheEdgesStillFacesTheCenter() {
        let ys = [Self.middle + Self.step / 2, Self.middle - Self.step / 2]
        let rightHalf = Self.solve(Self.requests(ys.map { Self.disc(1000, $0) }))
        #expect(Self.sides(rightHalf, 2) == [.left, .left])
        let leftHalf = Self.solve(Self.requests(ys.map { Self.disc(400, $0) }))
        #expect(Self.sides(leftHalf, 2) == [.right, .right])
    }

    @Test func columnsOnAnOffsetDisplayFaceItsCenter() {
        let area = CGRect(x: -1920, y: -120, width: 1920, height: 1055)
        let ys: [CGFloat] = [487.5, 327.5]
        let rightColumn = Self.solve(Self.requests(ys.map { Self.disc(-86, $0) }), visible: area)
        #expect(Self.sides(rightColumn, 2) == [.left, .left])
        let leftColumn = Self.solve(Self.requests(ys.map { Self.disc(-1920 + 86, $0) }), visible: area)
        #expect(Self.sides(leftColumn, 2) == [.right, .right])
    }

    @Test func aTwoByTwoClusterPutsTheTopPairAboveAndTheBottomPairBelow() {
        let discs = [Self.disc(640, 517.5), Self.disc(800, 517.5), Self.disc(640, 357.5), Self.disc(800, 357.5)]
        let slots = Self.solve(Self.requests(discs))
        #expect(Self.sides(slots, 4) == [.above, .above, .below, .below])
        // Same answer whatever the list order.
        let shuffled = Self.solve([3, 0, 2, 1].map { Self.fixed("o\($0)", discs[$0]) })
        #expect(Self.sides(shuffled, 4) == [.above, .above, .below, .below])
    }

    @Test func aGroupMovesTogetherWhenOneMemberCannotTakeTheFirstPlacement() {
        // Another orb 20 pt under the row's last orb (its own group) blocks only that orb's plate below.
        let row = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.middle) }
        let blocker = Self.disc(720 + Self.step, Self.middle - 148 - 20)
        #expect(NameplateLayout.groups(row + [blocker]) == [[0, 1, 2], [3]])
        let slots = Self.solve(Self.requests(row + [blocker]))
        #expect(Self.sides(slots, 4) == [.above, .above, .above, .below])
    }

    // MARK: Fit

    @Test func aPlateStaysThreePointsInsideTheUsableArea() {
        // A plate below spans y - 97 ... y - 79 for a 148 pt orb.
        #expect(Self.solve(Self.requests([Self.disc(720, 100.5)]))["o0"]?.side == .below, "3.5 pt from the edge")
        #expect(Self.solve(Self.requests([Self.disc(720, 98.5)]))["o0"]?.side == .above, "1.5 pt from the edge")
        #expect(Self.solve(Self.requests([Self.disc(720, Self.middle)], width: 222))["o0"]?.side == .below)
        let nearRight = [Self.disc(1440 - 3 - 111 + 1, Self.middle)]
        #expect(Self.solve(Self.requests(nearRight, width: 222))["o0"]?.side == .left, "a centered plate 1 pt past the inset")
    }

    @Test func aPlateStaysFourPointsFromAnotherDisc() {
        // The plate below spans 340.5 ... 358.5; another orb (its own group) sits under it.
        let orb = Self.disc(720, Self.middle)
        let clear = Self.solve(Self.requests([orb, Self.disc(720, 340.5 - 4.5 - 74)]))
        #expect(clear["o0"]?.side == .below)
        let close = Self.solve(Self.requests([orb, Self.disc(720, 340.5 - 3.5 - 74)]))
        #expect(close["o0"]?.side == .above)
    }

    @Test func aPlateStaysFourPointsFromAnotherPlate() {
        // A bottom row's plates sit above it at 165 ... 183; a lone orb over the row puts its plate below at
        // y - 97 ... y - 79.
        let row = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.bottom) }
        #expect(NameplateLayout.groups(row + [Self.disc(720, 183 + 3.5 + 97)]) == [[0, 1, 2], [3]], "an earlier group")
        let clear = Self.solve(Self.requests(row + [Self.disc(720, 183 + 4.5 + 97)]))
        #expect(Self.sides(clear, 4) == [.above, .above, .above, .below])
        let close = Self.solve(Self.requests(row + [Self.disc(720, 183 + 3.5 + 97)]))
        #expect(Self.sides(close, 4) == [.above, .above, .above, .above])
    }

    // MARK: Hiding and blocking

    @Test func aPlateHidesWhenNothingFits() {
        let tiny = CGRect(x: 0, y: 0, width: 160, height: 160)
        #expect(Self.solve(Self.requests([Self.disc(80, 80)]), visible: tiny).isEmpty)
        let unfit = NameplateRequest(id: "o0", disc: Self.disc(720, Self.middle), wantsPlate: true) { _ in nil }
        #expect(Self.solve([unfit]).isEmpty)
    }

    @Test func aLongNameSqueezedInATightRowHidesWhileItsNeighboursKeepTheirPlates() {
        let discs = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.middle) }
        let requests = [
            Self.fixed("o0", discs[0]), Self.fixed("o1", discs[1], width: 180), Self.fixed("o2", discs[2]),
        ]
        let slots = Self.solve(requests)
        #expect(Self.sides(slots, 3) == [.below, nil, .below])
    }

    @Test func anOrbWithoutAPlateGetsNoSlotButStillBlocks() {
        let top = Self.disc(Self.right, Self.middle + Self.step / 2)
        let plain = Self.disc(Self.right, Self.middle - Self.step / 2)
        #expect(Self.solve([Self.fixed("o0", top)])["o0"]?.side == .below)
        let slots = Self.solve([Self.fixed("o0", top), Self.fixed("o1", plain, wantsPlate: false)])
        #expect(slots["o1"] == nil)
        #expect(slots["o0"]?.side == .above, "the plain orb's disc takes the room below")
        let none = Self.solve([Self.fixed("o0", top, wantsPlate: false), Self.fixed("o1", plain, wantsPlate: false)])
        #expect(none.isEmpty)
    }

    @Test func anOrbWithoutAPlateStillNarrowsItsNeighboursBudget() {
        let discs = [720 - Self.step, 720, 720 + Self.step].map { Self.disc($0, Self.middle) }
        let requests = [Self.fixed("o0", discs[0]), Self.fixed("o1", discs[1], wantsPlate: false), Self.fixed("o2", discs[2])]
        let slots = Self.solve(requests)
        #expect(Self.sides(slots, 3) == [.below, nil, .below])
        #expect(slots["o0"].map { Nameplates.isClose($0.budget, 154) } == true)
        #expect(slots["o2"].map { Nameplates.isClose($0.budget, 154) } == true)
    }

    // MARK: With real shortening

    @Test func aTightRowOfSmallOrbsShortensThePairAndKeepsEveryPlateBelow() {
        let configs = [
            OrbConfig(id: "o0", sources: .explicit([.claudeCode, .claudeDesktop]), size: 112),
            OrbConfig(id: "o1", sources: .explicit([.codex]), size: 112),
            OrbConfig(id: "o2", sources: .explicit([.gemini]), size: 112),
        ]
        let measure = NameplateSpecExampleTests.measure(112)
        let metrics = NameplateMetrics(diameter: 112)
        let labels = configs.map { NameplateLabel.make(config: $0, namer: Nameplates.namer, unavailable: []) }
        let requests = configs.enumerated().map { index, config in
            NameplateRequest(id: config.id, disc: Self.disc(500 + CGFloat(index) * 124, 300, size: 112), wantsPlate: true) { budget in
                let plate = NameplateShortening.plate(labels[index], metrics: metrics, namer: Nameplates.namer, budget: budget, measure: measure)
                return plate.text.fits ? plate.width : nil
            }
        }
        let slots = Self.solve(requests)
        #expect(Self.sides(slots, 3) == [.below, .below, .below])
        let budget = slots["o0"]?.budget ?? 0
        #expect(Nameplates.isClose(budget, 118))
        let text = NameplateShortening.plate(labels[0], metrics: metrics, namer: Nameplates.namer, budget: budget, measure: measure).text
        #expect(text.text == "Claude Code +1")
    }

    // MARK: Rules on random desktops

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Up to eight non-overlapping orbs (≥ 12 pt apart), many snapped to an edge or touching another orb.
    static func randomDesktop(seed: UInt64, visible: CGRect) -> [NameplateRequest] {
        var rng = SplitMix64(state: seed)
        let count = Int.random(in: 1...8, using: &rng)
        var discs: [OrbDisc] = []
        for _ in 0..<200 where discs.count < count {
            let size = [96, 112, 148, 196, 240].randomElement(using: &rng).map { CGFloat($0) } ?? 148
            let r = size / 2
            var center = CGPoint(
                x: CGFloat.random(in: (visible.minX + r)...(visible.maxX - r), using: &rng),
                y: CGFloat.random(in: (visible.minY + r)...(visible.maxY - r), using: &rng)
            )
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: center.x = Bool.random(using: &rng) ? visible.minX + 12 + r : visible.maxX - 12 - r
            case 1: center.y = Bool.random(using: &rng) ? visible.minY + 12 + r : visible.maxY - 12 - r
            case 2:
                if let anchor = discs.randomElement(using: &rng) {
                    let directions: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                    let (dx, dy) = directions.randomElement(using: &rng) ?? (1, 0)
                    let distance: CGFloat = anchor.radius + r + 12
                    center = CGPoint(x: anchor.center.x + dx * distance, y: anchor.center.y + dy * distance)
                }
            default: break
            }
            let disc = OrbDisc(center: center, radius: r)
            guard visible.contains(CGRect(x: center.x - r, y: center.y - r, width: size, height: size).insetBy(dx: 0.5, dy: 0.5)),
                  discs.allSatisfy({ NameplateLayout.edgeDistance($0, disc) >= 12 - 0.01 }) else { continue }
            discs.append(disc)
        }
        return discs.enumerated().map { index, disc in
            let width = CGFloat.random(in: 30...320, using: &rng)
            let wantsPlate = Int.random(in: 0..<8, using: &rng) > 0
            return fixed("o\(index)", disc, width: width, wantsPlate: wantsPlate)
        }
    }

    @Test(arguments: [Nameplates.visible, CGRect(x: -1280, y: 40, width: 1280, height: 760)])
    func everyResolvedPlateKeepsTheRules(_ visible: CGRect) {
        var placed = 0
        for seed in UInt64(1)...300 {
            let requests = Self.randomDesktop(seed: seed, visible: visible)
            let slots = NameplateLayout.solve(requests, visible: visible)
            let problems = Self.violations(requests, slots, visible: visible)
            #expect(problems.isEmpty, "seed \(seed): \(problems)")
            #expect(NameplateLayout.solve(requests, visible: visible) == slots, "seed \(seed) is deterministic")
            placed += slots.count
        }
        #expect(placed > 600, "the random desktops place plenty of plates")
    }
}

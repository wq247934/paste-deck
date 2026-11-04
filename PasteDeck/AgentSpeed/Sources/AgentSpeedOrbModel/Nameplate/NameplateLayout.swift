import CoreGraphics
import Foundation

/// Where a plate sits around its disc.
public enum NameplateSide: String, CaseIterable, Sendable {
    case below, above, left, right

    public var isSide: Bool { self == .left || self == .right }

    /// The rect of a plate `width` wide on this side of `disc` (global points, y up), `metrics.gap` from its edge.
    public func rect(around disc: OrbDisc, metrics: NameplateMetrics, width: CGFloat) -> CGRect {
        let c = disc.center
        let r = disc.radius
        let g = metrics.gap
        let h = metrics.height
        switch self {
        case .below: return CGRect(x: c.x - width / 2, y: c.y - r - g - h, width: width, height: h)
        case .above: return CGRect(x: c.x - width / 2, y: c.y + r + g, width: width, height: h)
        case .left: return CGRect(x: c.x - r - g - width, y: c.y - h / 2, width: width, height: h)
        case .right: return CGRect(x: c.x + r + g, y: c.y - h / 2, width: width, height: h)
        }
    }
}

/// One orb for the placement solver.
public struct NameplateRequest {
    public var id: String
    public var disc: OrbDisc
    /// False for an orb without a plate; its disc still keeps other plates away.
    public var wantsPlate: Bool
    /// The plate's width at rest within a width budget, shortened as needed; nil when even the shortest form is wider.
    public var width: (CGFloat) -> CGFloat?

    public init(id: String, disc: OrbDisc, wantsPlate: Bool, width: @escaping (CGFloat) -> CGFloat?) {
        self.id = id
        self.disc = disc
        self.wantsPlate = wantsPlate
        self.width = width
    }

    public var metrics: NameplateMetrics { NameplateMetrics(diameter: 2 * disc.radius) }
}

/// A resolved plate: its side, its width budget and its rect at rest.
public struct NameplateSlot: Equatable, Sendable {
    public var side: NameplateSide
    public var budget: CGFloat
    public var rect: CGRect

    public init(side: NameplateSide, budget: CGFloat, rect: CGRect) {
        self.side = side
        self.budget = budget
        self.rect = rect
    }
}

/// The placement of every plate on one display (DESIGN 2b, Name plate, Width budget and Placement).
public enum NameplateLayout {
    /// Orbs whose discs are within 16 pt of each other, transitively, in input order.
    public static func groups(_ discs: [OrbDisc]) -> [[Int]] {
        var assigned = Array(repeating: false, count: discs.count)
        var result: [[Int]] = []
        for start in discs.indices where !assigned[start] {
            assigned[start] = true
            var group = [start]
            var cursor = 0
            while cursor < group.count {
                let member = discs[group[cursor]]
                for other in discs.indices where !assigned[other] && edgeDistance(member, discs[other]) <= NameplateMetrics.groupDistance {
                    assigned[other] = true
                    group.append(other)
                }
                cursor += 1
            }
            result.append(group.sorted())
        }
        return result
    }

    /// The width budget of plate `index` on `side`: 1.5 S; above or below, not past the point that divides the
    /// distance to any disc overlapping its horizontal band in proportion to the two sizes, less 3 pt; on a side,
    /// not past the usable area less 3 pt.
    public static func budget(for index: Int, side: NameplateSide, discs: [OrbDisc], visible: CGRect) -> CGFloat {
        let disc = discs[index]
        let metrics = NameplateMetrics(diameter: 2 * disc.radius)
        var budget = metrics.aloneBudget
        if side.isSide {
            let inner = side == .left ? disc.center.x - disc.radius - metrics.gap : disc.center.x + disc.radius + metrics.gap
            let room = side == .left ? inner - (visible.minX + NameplateMetrics.areaInset)
                : visible.maxX - NameplateMetrics.areaInset - inner
            return max(0, min(budget, room))
        }
        var half = budget / 2
        for (other, neighbour) in discs.enumerated() where other != index {
            guard abs(neighbour.center.y - disc.center.y) < disc.radius + neighbour.radius else { continue }
            let share = abs(neighbour.center.x - disc.center.x) * disc.radius / (disc.radius + neighbour.radius)
            half = min(half, share - NameplateMetrics.neighbourMargin)
        }
        budget = 2 * half
        return max(0, budget)
    }

    /// The four placements in the order a group tries them: below, above, the side facing the usable area's center,
    /// the other side.
    public static func order(facingFrom x: CGFloat, visible: CGRect) -> [NameplateSide] {
        let toward: NameplateSide = x > visible.midX ? .left : .right
        return [.below, .above, toward, toward == .left ? .right : .left]
    }

    /// Resolves every plate on one display. A group takes the first placement that fits every member; otherwise each
    /// member takes its own first fit; an orb with no fit is left out (its plate hides).
    public static func solve(_ requests: [NameplateRequest], visible: CGRect) -> [String: NameplateSlot] {
        let discs = requests.map(\.disc)
        var placed: [CGRect] = []
        var result: [String: NameplateSlot] = [:]

        func candidate(_ index: Int, _ side: NameplateSide) -> NameplateSlot? {
            let request = requests[index]
            let budget = budget(for: index, side: side, discs: discs, visible: visible)
            guard budget > 0, let width = request.width(budget), width <= budget + 0.01 else { return nil }
            let rect = side.rect(around: request.disc, metrics: request.metrics, width: width)
            return NameplateSlot(side: side, budget: budget, rect: rect)
        }

        func fits(_ rect: CGRect, owner: Int, others: [CGRect]) -> Bool {
            let area = visible.insetBy(dx: NameplateMetrics.areaInset, dy: NameplateMetrics.areaInset)
            let tolerance: CGFloat = 0.01
            guard rect.minX >= area.minX - tolerance, rect.maxX <= area.maxX + tolerance,
                  rect.minY >= area.minY - tolerance, rect.maxY <= area.maxY + tolerance else { return false }
            for (index, disc) in discs.enumerated() where index != owner {
                if distance(from: disc.center, to: rect) < disc.radius + NameplateMetrics.clearance - tolerance { return false }
            }
            let padded = rect.insetBy(dx: -NameplateMetrics.clearance + tolerance, dy: -NameplateMetrics.clearance + tolerance)
            return !others.contains { padded.intersects($0) }
        }

        for group in groups(discs) {
            let members = group.filter { requests[$0].wantsPlate }
            guard !members.isEmpty else { continue }
            let meanX = group.map { discs[$0].center.x }.reduce(0, +) / CGFloat(group.count)
            let sides = order(facingFrom: meanX, visible: visible)
            var resolved = false
            for side in sides {
                var slots: [(Int, NameplateSlot)] = []
                for member in members {
                    guard let slot = candidate(member, side),
                          fits(slot.rect, owner: member, others: placed + slots.map(\.1.rect)) else { break }
                    slots.append((member, slot))
                }
                guard slots.count == members.count else { continue }
                for (member, slot) in slots { result[requests[member].id] = slot }
                placed += slots.map(\.1.rect)
                resolved = true
                break
            }
            if resolved { continue }
            for member in members {
                for side in sides {
                    guard let slot = candidate(member, side), fits(slot.rect, owner: member, others: placed) else { continue }
                    result[requests[member].id] = slot
                    placed.append(slot.rect)
                    break
                }
            }
        }
        return result
    }

    static func edgeDistance(_ a: OrbDisc, _ b: OrbDisc) -> CGFloat {
        hypot(a.center.x - b.center.x, a.center.y - b.center.y) - a.radius - b.radius
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

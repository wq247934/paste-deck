import Foundation

/// Row heights and the room for rows of one style and size (prototypes `layout()`: `--row`, `--sub`, the more row
/// and the board area of each `board-*.html`).
public struct BoardLayoutMetrics: Equatable, Sendable {
    /// A group row including its gap.
    public var groupHeight: Double
    public var subHeight: Double
    /// `boards.moreSubs` and `boards.moreGroups` rows.
    public var moreHeight: Double
    /// Vertical room for rows.
    public var room: Double
    /// Offset of the first row from the top of the rows area.
    public var top: Double
    /// Most groups the size shows.
    public var groupLimit: Int
    /// Sub rows per group rank (#1 first) when not expanded.
    public var subLimits: [Int]

    public init(groupHeight: Double, subHeight: Double, moreHeight: Double, room: Double, top: Double, groupLimit: Int,
                subLimits: [Int]) {
        self.groupHeight = groupHeight
        self.subHeight = subHeight
        self.moreHeight = moreHeight
        self.room = room
        self.top = top
        self.groupLimit = groupLimit
        self.subLimits = subLimits
    }

    /// DESIGN 2c, Layout per size: S up to 4 groups and no sub rows; M up to 6 groups, two sub rows for #1, one for
    /// #2 and #3; L up to 8 groups, three for #1–#3, two for #4–#5.
    public static func limits(_ size: BoardSize) -> (groups: Int, subs: [Int]) {
        switch size {
        case .small: (4, [])
        case .medium: (6, [2, 1, 1])
        case .large: (8, [3, 3, 3, 2, 2])
        }
    }

    /// The metrics of the board without live metrics; `BoardLayoutMetrics(BoardGeometry)` for a board's switches.
    public static func of(_ style: BoardStyle, _ size: BoardSize, readouts: BoardReadouts = .none) -> BoardLayoutMetrics {
        BoardLayoutMetrics(BoardGeometry(style, size, readouts: readouts))
    }
}

/// What the planner needs of a ranked group.
public struct BoardPlanGroup: Equatable, Sendable {
    public var id: String
    public var live: Double
    /// Sub-agents by live value, latest activity, id.
    public var subs: [BoardPlanSub]

    public init(id: String, live: Double, subs: [BoardPlanSub]) {
        self.id = id
        self.live = live
        self.subs = subs
    }

    public init(_ group: BoardGroup, live: (String) -> Double) {
        self.init(id: group.id, live: group.live, subs: group.subs.map { BoardPlanSub(id: $0.id, live: live($0.id)) })
    }
}

public struct BoardPlanSub: Equatable, Sendable {
    public var id: String
    public var live: Double

    public init(id: String, live: Double) {
        self.id = id
        self.live = live
    }
}

/// One row of the board, at its target place.
public struct BoardPlannedRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Group `group` (index into the ranked groups).
        case group(Int)
        /// Sub-agent `sub` (index into that group's subs).
        case sub(group: Int, sub: Int)
        /// `boards.moreSubs`: the group's other sub-agents and their summed live value.
        case moreSubs(group: Int, count: Int, live: Double)
        /// `boards.moreGroups`: the groups that do not fit and their summed live value.
        case moreGroups(count: Int, live: Double)
    }

    public var kind: Kind
    /// Stable identity across ticks (group id, sub id, `<group id>#more`, `#rest`).
    public var key: String
    /// Top of the row from the top of the rows area, points.
    public var y: Double
    public var height: Double
}

/// The board's rows per size (DESIGN 2c, Layout per size): groups are placed first and sub rows only fill the room
/// that remains, so a sub row never pushes a group out and no row is ever cut. Port of the prototypes' `layout()`.
public enum BoardLayoutPlanner {
    /// An expanded group shows up to this many sub rows.
    public static let expandedLimit = 8

    public static func plan(_ all: [BoardPlanGroup], metrics m: BoardLayoutMetrics, expanded: String? = nil) -> [BoardPlannedRow] {
        var shown = min(all.count, m.groupLimit)
        func restRow() -> Double { all.count > shown ? m.moreHeight : 0 }
        while shown > 1, Double(shown) * m.groupHeight + restRow() > m.room { shown -= 1 }
        var free = m.room - Double(shown) * m.groupHeight - restRow()

        var rows: [BoardPlannedRow] = []
        var y = m.top
        for index in 0..<shown {
            let group = all[index]
            let isExpanded = expanded == group.id
            let wanted = isExpanded ? min(expandedLimit, group.subs.count)
                : (index < m.subLimits.count ? m.subLimits[index] : 0)
            var candidates: [Int] = []
            for (subIndex, sub) in group.subs.enumerated() where candidates.count < wanted {
                if isExpanded || sub.live > BoardGrouping.idle { candidates.append(subIndex) }
            }
            var keep: [Int] = []
            var more = false
            for subIndex in candidates {
                let needMore = group.subs.count - keep.count - 1 > 0 && !more ? m.moreHeight : 0
                guard free >= m.subHeight + needMore else { continue }
                keep.append(subIndex)
                free -= m.subHeight
                if needMore > 0 {
                    more = true
                    free -= m.moreHeight
                }
            }
            if !keep.isEmpty, group.subs.count > keep.count, !more, free >= m.moreHeight {
                more = true
                free -= m.moreHeight
            }
            if more, keep.count == group.subs.count {
                more = false
                free += m.moreHeight
            }

            rows.append(BoardPlannedRow(kind: .group(index), key: group.id, y: y, height: m.groupHeight))
            y += m.groupHeight
            for subIndex in keep {
                rows.append(BoardPlannedRow(kind: .sub(group: index, sub: subIndex), key: group.subs[subIndex].id, y: y,
                                            height: m.subHeight))
                y += m.subHeight
            }
            if more {
                let kept = Set(keep)
                let rest = group.subs.indices.filter { !kept.contains($0) }
                let live = rest.reduce(0) { $0 + max(0, group.subs[$1].live) }
                rows.append(BoardPlannedRow(kind: .moreSubs(group: index, count: rest.count, live: live),
                                            key: group.id + "#more", y: y, height: m.moreHeight))
                y += m.moreHeight
            }
        }
        if all.count > shown {
            let hidden = all[shown...]
            rows.append(BoardPlannedRow(kind: .moreGroups(count: hidden.count, live: hidden.reduce(0) { $0 + max(0, $1.live) }),
                                        key: "#rest", y: y, height: m.moreHeight))
        }
        return rows
    }
}

import Foundation

/// How wide a column would like to be, how narrow it may get, and its share of spare width.
struct ColumnSpec: Equatable, Sendable {
    let natural: Double
    let minimum: Double
    var weight: Double = 0
}

enum HistoryColumnLayout {
    static let gap: Double = 12
    /// Gaps tighten down to this before columns go below their minimums.
    static let minimumGap: Double = 6

    static func spec(_ column: HistoryColumn) -> ColumnSpec {
        switch column {
        case .date: ColumnSpec(natural: 124, minimum: 84)
        case .requests: ColumnSpec(natural: 68, minimum: 56)
        case .output: ColumnSpec(natural: 72, minimum: 46)
        case .input: ColumnSpec(natural: 112, minimum: 56)
        case .cost: ColumnSpec(natural: 84, minimum: 60)
        case .traffic: ColumnSpec(natural: 150, minimum: 136)
        case .cacheHit: ColumnSpec(natural: 72, minimum: 44)
        case .speed: ColumnSpec(natural: 96, minimum: 62)
        case .peak: ColumnSpec(natural: 84, minimum: 56)
        case .agents: ColumnSpec(natural: 56, minimum: 42)
        case .models: ColumnSpec(natural: 150, minimum: 74, weight: 1)
        }
    }

    /// Widths and the gap for `width`: the full gap while the columns fit at their minimums, else a gap tightened
    /// toward `minimumGap`, and only then columns below their minimums (scaled alike), so a narrow window never
    /// clips the table.
    static func layout(_ specs: [ColumnSpec], width: Double) -> (widths: [Double], gap: Double) {
        guard specs.count > 1 else { return (widths(specs, width: width), gap) }
        let gaps = Double(specs.count - 1)
        let minimums = specs.reduce(0) { $0 + max(0, $1.minimum) }
        if minimums + gap * gaps <= width { return (widths(specs, width: width, gap: gap), gap) }
        let tightened = max(minimumGap, (width - minimums) / gaps)
        if minimums + tightened * gaps <= width + 0.001 { return (widths(specs, width: width, gap: tightened), tightened) }
        let scale = max(0, width - tightened * gaps) / max(minimums, 1)
        return (specs.map { max(0, $0.minimum) * scale }, tightened)
    }

    /// Widths left to right with `gap` between them. Spare width goes to weighted columns; when space is short,
    /// columns give up width in proportion to how far they are above their minimum, and never go below it.
    static func widths(_ specs: [ColumnSpec], width: Double, gap: Double = gap) -> [Double] {
        guard !specs.isEmpty else { return [] }
        var widths = specs.map { max(0, max($0.natural, $0.minimum)) }
        let available = max(0, (width.isFinite ? width : 0) - gap * Double(specs.count - 1))
        let natural = widths.reduce(0, +)
        if available >= natural {
            let extra = available - natural
            let weights = specs.reduce(0) { $0 + max(0, $1.weight) }
            for index in widths.indices {
                if weights > 0 {
                    widths[index] += extra * max(0, specs[index].weight) / weights
                } else if index == widths.count - 1 {
                    widths[index] += extra
                }
            }
        } else {
            let slack = specs.indices.map { max(0, widths[$0] - max(0, specs[$0].minimum)) }
            let totalSlack = slack.reduce(0, +)
            let share = totalSlack > 0 ? min(1, (natural - available) / totalSlack) : 0
            for index in widths.indices {
                widths[index] -= slack[index] * share
            }
        }
        return widths
    }
}

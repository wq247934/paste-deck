import AgentSpeedCore

/// Parent groups of an agents list (METRICS 6.7). A row's tree parent is the row its `parentId` names when that row
/// comes earlier in the list; every other row is a root, whatever its `isSubagent`.
struct AgentTree {
    let rows: [AgentStatus]
    /// Index of each row's tree parent.
    let parents: [Int?]
    let children: [[Int]]
    let roots: [Int]

    init(_ rows: [AgentStatus]) {
        self.rows = rows
        var positions: [String: Int] = [:]
        var parents: [Int?] = []
        var children = Array(repeating: [Int](), count: rows.count)
        var roots: [Int] = []
        for (index, row) in rows.enumerated() {
            let parent = row.parentId.flatMap { positions[$0] }
            parents.append(parent)
            if let parent {
                children[parent].append(index)
            } else {
                roots.append(index)
            }
            if positions[row.id] == nil { positions[row.id] = index }
        }
        self.parents = parents
        self.children = children
        self.roots = roots
    }

    /// Nesting depth of each row; 0 for roots.
    var depths: [Int] {
        var depths: [Int] = []
        depths.reserveCapacity(rows.count)
        for parent in parents {
            depths.append(parent.map { depths[$0] + 1 } ?? 0)
        }
        return depths
    }

    /// Row indices depth-first, with the roots and every list of siblings passed through `arrange`.
    func depthFirst(arrange: (_ siblings: [Int], _ areRoots: Bool) -> [Int]) -> [Int] {
        var order: [Int] = []
        order.reserveCapacity(rows.count)
        var stack = Array(arrange(roots, true).reversed())
        while let index = stack.popLast() {
            order.append(index)
            if !children[index].isEmpty {
                stack.append(contentsOf: arrange(children[index], false).reversed())
            }
        }
        return order
    }
}

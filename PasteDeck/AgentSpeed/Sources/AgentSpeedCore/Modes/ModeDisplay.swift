import Foundation

/// How reasoning effort and speed values are drawn and ordered (EXECUTION-MODES, Reasoning effort and speed).
public enum ModeDisplay {
    private static let effortLevels: [String: Int] = [
        "off": 0, "minimal": 1, "low": 1, "medium": 2, "high": 3, "xhigh": 4, "max": 5, "ultra": 5, "ultracode": 5,
    ]
    private static let effortOrder = ["ultracode", "ultra", "max", "xhigh", "high", "medium", "low", "minimal", "off"]
    private static let speedOrder = ["ultrafast", "fast", "highspeed", "standard"]

    /// Meter level 0–5; nil for a token without a level, which shows as its word only.
    public static func effortLevel(_ value: String) -> Int? { effortLevels[value] }

    /// `ultra` (Codex) and `ultracode` (Claude Code): the top rung above `max`.
    public static func isTopRung(_ value: String) -> Bool { value == "ultra" || value == "ultracode" }

    public static func bolts(_ speed: String) -> Int {
        switch speed {
        case "fast", "highspeed": 1
        case "ultrafast": 2
        default: 0
        }
    }

    /// The known ladder first, other tokens in ordinal order, `unknown` last.
    public static func ordered(_ values: [String], kind: ExecutionModeKind) -> [String] {
        let ladder = kind == .effort ? effortOrder : speedOrder
        func rank(_ value: String) -> (Int, Int) {
            (value == "unknown" ? 1 : 0, ladder.firstIndex(of: value) ?? ladder.count)
        }
        return values.sorted { lhs, rhs in
            let (a, b) = (rank(lhs), rank(rhs))
            if a != b { return a < b }
            return lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars)
        }
    }
}

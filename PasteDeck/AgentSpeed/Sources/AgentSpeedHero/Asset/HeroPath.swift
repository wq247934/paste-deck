import Foundation

/// A point of a flattened path; `move` starts a new subpath.
public struct HeroVertex: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var move: Bool

    public init(x: Double, y: Double, move: Bool) {
        self.x = x
        self.y = y
        self.move = move
    }
}

/// The path grammar of the art (DESIGN 4c): absolute `M L C Q Z`, tokens separated by single spaces, numbers with at
/// most two decimals.
public enum HeroPath {
    public enum Command: Sendable, Equatable {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        case close
    }

    public struct SyntaxError: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    public static func parse(_ d: String) throws -> [Command] {
        guard !d.isEmpty, d == d.trimmingCharacters(in: .whitespacesAndNewlines), !d.contains("  ") else {
            throw SyntaxError(description: "path must be a trimmed, single-space separated string")
        }
        let tokens = d.split(separator: " ", omittingEmptySubsequences: false)
        var commands: [Command] = []
        var index = 0
        func numbers(_ count: Int) throws -> [Double] {
            guard index + count < tokens.count else {
                throw SyntaxError(description: "missing arguments near token \(index)")
            }
            return try (1...count).map { offset in
                guard let value = number(tokens[index + offset]) else {
                    throw SyntaxError(description: "bad argument near token \(index)")
                }
                return value
            }
        }
        while index < tokens.count {
            let token = tokens[index]
            if commands.isEmpty, token != "M" { throw SyntaxError(description: "path must start with M") }
            switch token {
            case "M":
                let v = try numbers(2)
                commands.append(.move(v[0], v[1]))
                index += 3
            case "L":
                let v = try numbers(2)
                commands.append(.line(v[0], v[1]))
                index += 3
            case "Q":
                let v = try numbers(4)
                commands.append(.quad(v[0], v[1], v[2], v[3]))
                index += 5
            case "C":
                let v = try numbers(6)
                commands.append(.cubic(v[0], v[1], v[2], v[3], v[4], v[5]))
                index += 7
            case "Z":
                commands.append(.close)
                index += 1
            default:
                throw SyntaxError(description: "unsupported token \(token) (only M L C Q Z)")
            }
        }
        return commands
    }

    /// `-?digits(.d{1,2})?`
    static func number(_ token: Substring) -> Double? {
        var chars = token.utf8[...]
        if chars.first == UInt8(ascii: "-") { chars = chars.dropFirst() }
        guard let first = chars.first, (48...57).contains(first) else { return nil }
        var seenDot = false
        var decimals = 0
        for c in chars {
            if c == UInt8(ascii: ".") {
                guard !seenDot else { return nil }
                seenDot = true
            } else if (48...57).contains(c) {
                if seenDot { decimals += 1 }
            } else {
                return nil
            }
        }
        guard !seenDot || (1...2).contains(decimals) else { return nil }
        return Double(token)
    }

    /// Flattens curves into straight segments no longer than about `step` units; `Z` adds an explicit closing point.
    public static func flatten(_ commands: [Command], step: Double = 1.1) -> [HeroVertex] {
        var out: [HeroVertex] = []
        var current = (x: 0.0, y: 0.0)
        var start = current
        func steps(_ length: Double) -> Int { min(32, max(2, Int((length / step).rounded(.up)))) }
        for command in commands {
            switch command {
            case .move(let x, let y):
                current = (x, y)
                start = current
                out.append(HeroVertex(x: x, y: y, move: true))
            case .line(let x, let y):
                current = (x, y)
                out.append(HeroVertex(x: x, y: y, move: false))
            case .quad(let x1, let y1, let x2, let y2):
                let p0 = current
                let n = steps(hypot(x1 - p0.x, y1 - p0.y) + hypot(x2 - x1, y2 - y1))
                for k in 1...n {
                    let t = Double(k) / Double(n), u = 1 - t
                    out.append(HeroVertex(x: u * u * p0.x + 2 * u * t * x1 + t * t * x2,
                                          y: u * u * p0.y + 2 * u * t * y1 + t * t * y2, move: false))
                }
                current = (x2, y2)
            case .cubic(let x1, let y1, let x2, let y2, let x3, let y3):
                let p0 = current
                let n = steps(hypot(x1 - p0.x, y1 - p0.y) + hypot(x2 - x1, y2 - y1) + hypot(x3 - x2, y3 - y2))
                for k in 1...n {
                    let t = Double(k) / Double(n), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
                    out.append(HeroVertex(x: a * p0.x + b * x1 + c * x2 + e * x3,
                                          y: a * p0.y + b * y1 + c * y2 + e * y3, move: false))
                }
                current = (x3, y3)
            case .close:
                current = start
                out.append(HeroVertex(x: start.x, y: start.y, move: false))
            }
        }
        return out
    }

    /// Points sampled like `spec/tools/vehicles.py` (12 steps per curve), for the containment checks.
    public static func sample(_ commands: [Command]) -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        var current = (x: 0.0, y: 0.0)
        var start = current
        for command in commands {
            switch command {
            case .move(let x, let y):
                current = (x, y)
                start = current
                out.append(current)
            case .line(let x, let y):
                current = (x, y)
                out.append(current)
            case .quad(let x1, let y1, let x2, let y2):
                let p0 = current
                for k in 1...12 {
                    let t = Double(k) / 12, u = 1 - t
                    out.append((u * u * p0.x + 2 * u * t * x1 + t * t * x2, u * u * p0.y + 2 * u * t * y1 + t * t * y2))
                }
                current = (x2, y2)
            case .cubic(let x1, let y1, let x2, let y2, let x3, let y3):
                let p0 = current
                for k in 1...12 {
                    let t = Double(k) / 12, u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
                    out.append((a * p0.x + b * x1 + c * x2 + e * x3, a * p0.y + b * y1 + c * y2 + e * y3))
                }
                current = (x3, y3)
            case .close:
                current = start
                out.append(current)
            }
        }
        return out
    }
}

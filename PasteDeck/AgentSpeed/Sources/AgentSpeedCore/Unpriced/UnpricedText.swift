import Foundation

/// The copied diagnostics text (METRICS 9.10 *Text*, format 1): model ids, providers, rule texts, dates and counts
/// only. Path-like values are redacted, long ones truncated, control characters escaped.
public enum UnpricedText {
    public static let format = 1
    static let maxScalars = 120

    /// The `app` line: the build's version, `macos` or `windows`, and the OS (`macos-26`).
    public struct App: Equatable, Sendable {
        public var version: String
        public var platform: String
        public var os: String

        public init(version: String, platform: String, os: String) {
            self.version = version
            self.platform = platform
            self.os = os
        }

        /// This build on this Mac.
        public static func current(version: String) -> App {
            App(version: version, platform: "macos",
                os: "macos-\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
        }
    }

    public static func render(_ view: UnpricedView, app: App) -> String {
        let range = view.range
        var lines = [
            "Agent Speed unpriced diagnostics \(format)",
            "app version=\(app.version) platform=\(app.platform) os=\(app.os)",
            "prices version=\(view.tableVersion) updated=\(view.tableUpdated)",
            "range view=\(range.view) first=\(range.first) last=\(range.last) days=\(days(range.first, range.last)) "
                + "source=\(range.source?.rawValue ?? "all") excluded=\(excludedText(range.excluded))",
        ]
        var total = (requests: 0, unpriced: 0, pricedNow: 0, noCostData: 0, derived: 0, rows: 0)
        for group in view.groups {
            lines.append("source id=\(group.source.rawValue) requests=\(group.requests) unpriced=\(group.unpriced) "
                + "pricedNow=\(group.pricedNow) noCostData=\(group.noCostData) derived=\(group.derived) rows=\(group.rows.count)")
            for row in group.rows {
                lines.append("row source=\(row.source.rawValue) reason=\(row.diagnosis.reason.rawValue) requests=\(row.requests) "
                    + "first=\(row.first) last=\(row.last) fast=\(row.key.fast) model=\(quoted(row.key.model)) "
                    + "provider=\(quoted(row.key.provider)) canonical=\(quoted(row.diagnosis.canonical)) "
                    + "rule=\(quoted(row.diagnosis.rule, redact: false))")
            }
            total.requests += group.requests
            total.unpriced += group.unpriced
            total.pricedNow += group.pricedNow
            total.noCostData += group.noCostData
            total.derived += group.derived
            total.rows += group.rows.count
        }
        lines.append("total requests=\(total.requests) unpriced=\(total.unpriced) pricedNow=\(total.pricedNow) "
            + "noCostData=\(total.noCostData) derived=\(total.derived) rows=\(total.rows)")
        return lines.map { $0 + "\n" }.joined()
    }

    static func excludedText(_ excluded: Set<SourceKind>) -> String {
        let ids = SourceKind.allCases.filter(excluded.contains).map(\.rawValue)
        return ids.isEmpty ? "none" : ids.joined(separator: ",")
    }

    /// `last − first + 1` of two `YYYY-MM-DD` dates.
    static func days(_ first: String, _ last: String) -> Int64 {
        guard let start = UTCDay.instantMs(first), let end = UTCDay.instantMs(last) else { return 0 }
        return (end - start) / UTCDay.msPerDay + 1
    }

    /// A text value: `null`, else the value in double quotes after redaction (`<path>`), truncation to 120 Unicode
    /// scalars plus `…`, and escaping. `redact` is false only for the table's rule texts.
    public static func quoted(_ text: String?, redact: Bool = true) -> String {
        guard let text else { return "null" }
        var scalars = Array(text.unicodeScalars)
        if redact, isPathLike(scalars) { scalars = Array("<path>".unicodeScalars) }
        if scalars.count > maxScalars { scalars = Array(scalars.prefix(maxScalars)) + ["\u{2026}"] }
        var out = "\""
        for scalar in scalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{8}": out += "\\b"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\u{c}": out += "\\f"
            case "\r": out += "\\r"
            case _ where scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || scalar.value == 0x2028 || scalar.value == 0x2029:
                out += "\\u" + hex4(scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Starts with `/`, `\`, `~` or `file:`, or with a letter, `:` and `/` or `\`, or contains `/users/`,
    /// `\users\` or `/home/` (ASCII letters compared in lower case).
    static func isPathLike(_ scalars: [Unicode.Scalar]) -> Bool {
        let low = scalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 }
        func starts(_ prefix: String) -> Bool { low.starts(with: prefix.unicodeScalars) }
        func contains(_ part: String) -> Bool {
            let needle = Array(part.unicodeScalars)
            guard low.count >= needle.count else { return false }
            return (0...(low.count - needle.count)).contains { low[$0..<($0 + needle.count)].elementsEqual(needle) }
        }
        if starts("/") || starts("\\") || starts("~") || starts("file:") { return true }
        if low.count >= 3, ("a"..."z").contains(low[0]), low[1] == ":", low[2] == "/" || low[2] == "\\" { return true }
        return contains("/users/") || contains("\\users\\") || contains("/home/")
    }

    private static func hex4(_ value: UInt32) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}

import Foundation

/// How paths and file names compare on a platform (METRICS 10.5): `/` and `\` are equivalent, `~` is the home folder,
/// `%VAR%` expands, Windows paths compare case-insensitively; file names drop `.exe` on Windows and keep their case.
struct TrafficPlatform: Sendable {
    enum Kind: String, Sendable {
        case macos, windows
    }

    var kind: Kind
    var home: String
    var environment: [String: String]

    init(kind: Kind, home: String, environment: [String: String] = [:]) {
        self.kind = kind
        self.home = home
        self.environment = environment
    }

    /// This Mac: the current user's home folder.
    static var current: TrafficPlatform {
        TrafficPlatform(kind: .macos, home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    var isWindows: Bool { kind == .windows }

    func normalize(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        var normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("~/") {
            normalized = home.replacingOccurrences(of: "\\", with: "/") + normalized.dropFirst()
        }
        for (key, value) in environment {
            normalized = normalized.replacingOccurrences(of: "%\(key)%", with: value.replacingOccurrences(of: "\\", with: "/"))
        }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return isWindows ? normalized.lowercased() : normalized
    }

    /// The executable's file name: as is on macOS; lower-case without `.exe` on Windows, where an image path has the case the
    /// process was launched with (METRICS 10.5).
    func name(_ executable: String?) -> String {
        let path = (executable ?? "").replacingOccurrences(of: "\\", with: "/")
        let base = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        guard isWindows else { return base }
        let folded = base.lowercased()
        return folded.hasSuffix(".exe") ? String(folded.dropLast(4)) : folded
    }

    /// `path` lies under (or is) one of `prefixes`.
    func isUnder(_ path: String, _ prefixes: [String]) -> Bool {
        let candidate = normalize(path) + "/"
        return prefixes.contains { candidate.hasPrefix(normalize($0) + "/") }
    }
}

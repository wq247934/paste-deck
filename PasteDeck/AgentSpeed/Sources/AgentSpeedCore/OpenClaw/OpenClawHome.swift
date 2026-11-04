import Foundation

/// Where OpenClaw keeps its agent databases (METRICS 2, 4.14): the state folders of this environment and home folder,
/// and the databases a state folder, an agent folder or a database path names.
struct OpenClawHome: Equatable, Sendable {
    static let databaseName = "openclaw-agent.sqlite"

    var environment: [String: String]
    var home: URL

    static var current: OpenClawHome {
        OpenClawHome(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `$OPENCLAW_STATE_DIR` alone when it is set; otherwise `<base>/.openclaw` and every named-profile folder
    /// `<base>/.openclaw-<name>` in ordinal order, with `<base>` = `$OPENCLAW_HOME`, else the home folder. Folders that do
    /// not exist are listed too (discovery skips them); a path listed twice is kept once.
    var stateFolders: [URL] {
        if let override = value("OPENCLAW_STATE_DIR") { return [Self.normalized(expand(override))] }
        let base = value("OPENCLAW_HOME").map(expand) ?? home
        var folders = [base.appendingPathComponent(".openclaw", isDirectory: true)]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        for name in names.sorted(by: { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) })
        where Self.isProfileFolder(name) {
            let folder = base.appendingPathComponent(name, isDirectory: true)
            if FileStat.stat(folder.path)?.isDirectory == true { folders.append(folder) }
        }
        var seen: Set<String> = []
        return folders.map(Self.normalized).filter { seen.insert($0.path).inserted }
    }

    /// `.openclaw-<name>` with `<name>` matching `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` and not `default` in any case.
    static func isProfileFolder(_ name: String) -> Bool {
        let prefix = ".openclaw-"
        guard name.hasPrefix(prefix) else { return false }
        let profile = Array(name.utf8.dropFirst(prefix.utf8.count))
        guard (1...64).contains(profile.count), isAlphanumeric(profile[0]) else { return false }
        guard profile.allSatisfy({ isAlphanumeric($0) || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") }) else { return false }
        return String(decoding: profile, as: UTF8.self).lowercased() != "default"
    }

    /// The agent databases a root names: a file named `openclaw-agent.sqlite` itself, the database of an agent folder,
    /// or `<root>/agents/<agentId>/agent/openclaw-agent.sqlite` for every agent folder of a state folder (not a symlink,
    /// name not starting with `.`), in ordinal order. Only regular files that are not symlinks count.
    static func databases(in root: String) -> [String] {
        if let stat = FileStat.lstat(root), stat.isRegularFile {
            return (root as NSString).lastPathComponent == databaseName ? [root] : []
        }
        let direct = (root as NSString).appendingPathComponent(databaseName)
        if FileStat.lstat(direct)?.isRegularFile == true { return [direct] }
        let agents = (root as NSString).appendingPathComponent("agents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: agents) else { return [] }
        var found: [String] = []
        for name in names.sorted(by: { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }) where !name.hasPrefix(".") {
            let folder = (agents as NSString).appendingPathComponent(name)
            guard FileStat.lstat(folder)?.isDirectory == true else { continue }
            let path = ((folder as NSString).appendingPathComponent("agent") as NSString).appendingPathComponent(databaseName)
            if FileStat.lstat(path)?.isRegularFile == true { found.append(path) }
        }
        return found
    }

    /// The agent-scoped Codex home's `sessions` folder next to an agent database: a Codex root (METRICS 2).
    static func codexRoot(ofDatabase path: String) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("codex-home/sessions")
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    /// A set, trimmed value; a value of only whitespace counts as unset.
    private func value(_ name: String) -> String? {
        guard let raw = environment[name] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A leading `~` is the home folder.
    private func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") || path.hasPrefix("~\\") {
            return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: TranscriptDiscovery.normalizedRoot(url.standardizedFileURL.path), isDirectory: true)
    }
}

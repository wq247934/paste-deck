import Foundation

/// Where Hermes Agent keeps its logs (METRICS 2, 4.15): the Hermes home of this environment and home folder, its log
/// folders (the default profile's and every named profile's), the log files of a folder and a profile's
/// `config.yaml`. Paths follow Python's `posixpath` so agent ids match the reference.
struct HermesHome: Equatable, Sendable {
    static let logFolderName = "logs"
    static let configName = "config.yaml"

    var environment: [String: String]
    var home: URL

    static var current: HermesHome {
        HermesHome(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `$HERMES_HOME` (trimmed, a leading `~` expanded) when it is an absolute path, else `~/.hermes`. Hermes points
    /// it at a profile while it runs one, so the default home or a folder inside it means the default home, and a
    /// value whose parent folder is named `profiles` means that parent's parent.
    var folder: String {
        Self.resolve(hermesHome: environment["HERMES_HOME"], home: TranscriptDiscovery.normalizedRoot(home.path))
    }

    static func resolve(hermesHome: String?, home: String) -> String {
        let defaultHome = join(home, ".hermes")
        var raw = (hermesHome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == "~" || raw.hasPrefix("~/") || raw.hasPrefix("~\\") { raw = home + raw.dropFirst() }
        guard raw.hasPrefix("/") else { return defaultHome }
        let value = normalize(raw)
        let base = normalize(defaultHome)
        let inside = (base.hasSuffix("/") ? base : base + "/")
        if value == base || value.hasPrefix(inside) { return defaultHome }
        let parent = directory(of: value)
        if name(of: parent) == "profiles" { return directory(of: parent) }
        return value
    }

    /// `<home>/logs`, then `<home>/profiles/<name>/logs` for every real folder `<name>` not starting with `.`, in
    /// ordinal order. Folders that do not exist are left out; a path listed twice is kept once.
    static func logFolders(ofHome home: String) -> [String] {
        var folders = [join(home, logFolderName)]
        let profiles = join(home, "profiles")
        if FileStat.stat(profiles)?.isDirectory == true, let names = try? FileManager.default.contentsOfDirectory(atPath: profiles) {
            for name in names.sorted(by: { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) })
            where !name.hasPrefix(".") {
                let profile = join(profiles, name)
                if FileStat.lstat(profile)?.isDirectory == true { folders.append(join(profile, logFolderName)) }
            }
        }
        var seen: Set<String> = []
        return folders.filter { seen.insert($0).inserted && FileStat.stat($0)?.isDirectory == true }
    }

    /// The user setting: a Hermes home (a folder that has a `logs` folder) or one log folder.
    static func settingFolders(_ setting: String) -> [String] {
        if FileStat.stat(join(setting, logFolderName))?.isDirectory == true { return logFolders(ofHome: setting) }
        return FileStat.stat(setting)?.isDirectory == true ? [setting] : []
    }

    /// `agent.log` and `agent.log.<digits>` directly in a log folder, regular files only (never symlinks), by name.
    static func logFiles(in folder: String) -> [String] {
        guard FileStat.stat(folder)?.isDirectory == true,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return names.sorted(by: { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) })
            .filter(isLogFileName)
            .map { join(folder, $0) }
            .filter { FileStat.lstat($0)?.isRegularFile == true }
    }

    static func isLogFileName(_ name: String) -> Bool {
        let base = "agent.log"
        guard name.hasPrefix(base) else { return false }
        let rest = name.utf8.dropFirst(base.utf8.count)
        if rest.isEmpty { return true }
        guard rest.first == UInt8(ascii: "."), rest.count > 1 else { return false }
        return rest.dropFirst().allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    /// The `config.yaml` of a log folder's profile: the parent of a folder named `logs`; none for any other folder.
    static func configPath(ofLogFolder folder: String) -> String? {
        let normalized = normalize(folder)
        guard name(of: normalized) == logFolderName else { return nil }
        return join(directory(of: normalized), configName)
    }

    // MARK: - posixpath

    static func join(_ base: String, _ component: String) -> String {
        if component.hasPrefix("/") { return component }
        if base.isEmpty || base.hasSuffix("/") { return base + component }
        return base + "/" + component
    }

    /// `posixpath.normpath`: no `.`, `..` folded where possible, one slash between components (two leading slashes
    /// kept, as POSIX allows).
    static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "." }
        var leading = path.hasPrefix("/") ? 1 : 0
        if path.hasPrefix("//"), !path.hasPrefix("///") { leading = 2 }
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) where component != "." {
            if component != ".." || (leading == 0 && components.isEmpty) || components.last == ".." {
                components.append(component)
            } else if !components.isEmpty {
                components.removeLast()
            }
        }
        let joined = String(repeating: "/", count: leading) + components.joined(separator: "/")
        return joined.isEmpty ? "." : joined
    }

    /// `posixpath.dirname`.
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        let head = path[...slash]
        if head.allSatisfy({ $0 == "/" }) { return String(head) }
        return String(head.reversed().drop(while: { $0 == "/" }).reversed())
    }

    /// `posixpath.basename`.
    static func name(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

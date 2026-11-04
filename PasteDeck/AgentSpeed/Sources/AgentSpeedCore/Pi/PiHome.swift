import Darwin
import Foundation

/// The environment and home folder Pi's automatic roots derive from (METRICS 2, 4.13): `<agent dir>/sessions`, then
/// the custom session folder of `<agent dir>/settings.json` (`sessionDir`), then `$PI_CODING_AGENT_SESSION_DIR`.
struct PiHome: Equatable, Sendable {
    static let settingsMaxBytes: Int64 = 1 << 20

    var environment: [String: String]
    var home: URL

    static var current: PiHome {
        PiHome(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `$PI_CODING_AGENT_DIR`, else `~/.pi/agent`.
    var agentDirectory: URL {
        value("PI_CODING_AGENT_DIR").map(expand) ?? home.appendingPathComponent(".pi/agent", isDirectory: true)
    }

    /// The automatic roots, without duplicates. The settings file is read, never written.
    var roots: [URL] {
        var roots = [agentDirectory.appendingPathComponent("sessions", isDirectory: true)]
        if let custom = Self.sessionDir(settings: agentDirectory.appendingPathComponent("settings.json").path) {
            roots.append(expand(custom))
        }
        if let custom = value("PI_CODING_AGENT_SESSION_DIR") { roots.append(expand(custom)) }
        var seen: Set<String> = []
        return roots.filter { seen.insert(Self.normalized($0.path)).inserted }
    }

    /// `root` is one of `piRoots` or lies inside one: an omp root there holds Pi's files (METRICS 4.7).
    static func contains(_ piRoots: [String], _ root: String) -> Bool {
        let candidate = normalized(root)
        return piRoots.map(normalized).contains { pi in candidate == pi || candidate.hasPrefix(pi + "/") }
    }

    /// `sessionDir` of Pi's settings when it is a string with visible text, trimmed. A missing, unreadable, oversized
    /// or invalid file has none. The file may be a symlink (dotfile managers link it).
    static func sessionDir(settings path: String) -> String? {
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        guard let stat = FileStat.fstat(descriptor), stat.isRegularFile, stat.size <= settingsMaxBytes else { return nil }
        var data = Data(count: Int(stat.size))
        let read = data.withUnsafeMutableBytes { Darwin.pread(descriptor, $0.baseAddress, $0.count, 0) }
        guard read == data.count, let value = (try? JSONParser.parse(data))?["sessionDir"]?.string else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func value(_ name: String) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }

    private static func normalized(_ path: String) -> String {
        TranscriptDiscovery.normalizedRoot(URL(fileURLWithPath: path).standardizedFileURL.path)
    }
}

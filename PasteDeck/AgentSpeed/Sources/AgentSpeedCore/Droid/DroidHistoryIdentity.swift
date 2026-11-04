import Darwin
import Foundation

/// What the daily history stores to know a Factory Droid session is unchanged (METRICS 8): the transcript's size, and
/// a hash of its modification time with the size and modification time of its sidecar and, for a fork or successor,
/// of its parent's sidecar, whose counters it subtracts. The history rule makes a session's contributions a function of
/// these files alone.
struct DroidHistoryIdentity: Equatable, Sendable {
    var size: Int64
    var modified: Int64

    /// Parent session ids by transcript path, valid while the transcript keeps its identity (droid only appends).
    struct ParentCache: Sendable {
        private var parents: [String: (identity: FileIdentity, parent: String?)] = [:]

        mutating func parent(of path: String, identity: FileIdentity) -> String? {
            if let cached = parents[path], cached.identity == identity { return cached.parent }
            guard let line = DroidHistoryIdentity.firstLine(path) else {
                // Not written completely yet: looked at again next time.
                parents[path] = nil
                return nil
            }
            var parent: String?
            line.withUnsafeBytes { bytes in
                if case .line(.sessionStart(_, let id, _)) = DroidLineExtractor.extract(bytes) { parent = id }
            }
            parents[path] = (identity, parent)
            return parent
        }
    }

    init(path: String, stat: FileStat, parents: inout ParentCache) {
        let transcript = FileStat.lstat(path) ?? stat
        var parts = ["\(transcript.modifiedNs)", Self.part(DroidPaths.sidecarPath(ofTranscript: path))]
        if let parent = parents.parent(of: path, identity: transcript.identity) {
            parts.append(Self.part(DroidPaths.sidecarPath(ofTranscript: DroidPaths.sibling(parent, of: path))))
        }
        size = transcript.size
        modified = Int64(bitPattern: KeyHash.fnv1a(parts.joined(separator: "|")))
    }

    private static func part(_ sidecar: String) -> String {
        guard let stat = FileStat.lstat(sidecar), stat.isRegularFile else { return "-" }
        return "\(stat.size):\(stat.modifiedNs)"
    }

    private static let firstLineLimit = 1 << 20

    /// The transcript's first line without its newline; nil when no complete line is there within 1 MiB.
    static func firstLine(_ path: String) -> [UInt8]? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        guard let stat = FileStat.fstat(descriptor), stat.isRegularFile else { return nil }
        var line: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while line.count < firstLineLimit {
            let offset = off_t(line.count)
            let count = chunk.withUnsafeMutableBytes { Darwin.pread(descriptor, $0.baseAddress, $0.count, offset) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            if let newline = chunk[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                line.append(contentsOf: chunk[0..<newline])
                return line
            }
            line.append(contentsOf: chunk[0..<count])
        }
        return nil
    }
}

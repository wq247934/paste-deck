import Foundation

/// Factory Droid's files (METRICS 4.16): `<session id>.jsonl` transcripts with their `<session id>.settings.json`
/// sidecars, in the sessions root or one folder below it. Read-only, never follows symlinks.
enum DroidPaths {
    static let transcriptSuffix = ".jsonl"
    static let sidecarSuffix = ".settings.json"

    /// The automatic root, `~/.factory/sessions`; Factory documents no environment variable for it.
    static func defaultRoot(home: URL) -> URL {
        home.appendingPathComponent(".factory/sessions", isDirectory: true)
    }

    /// The folder a setting names: its `sessions` folder when it has one (the `.factory` folder), else itself.
    static func sessionsFolder(_ url: URL) -> URL {
        let folder = URL(fileURLWithPath: TranscriptDiscovery.normalizedRoot(url.path), isDirectory: true)
        let nested = folder.appendingPathComponent("sessions", isDirectory: true)
        return FileStat.lstat(nested.path)?.isDirectory == true ? nested : folder
    }

    /// `<folder>/<session id>.settings.json` next to a transcript.
    static func sidecarPath(ofTranscript path: String) -> String {
        guard path.hasSuffix(transcriptSuffix) else { return path + sidecarSuffix }
        return String(path.dropLast(transcriptSuffix.utf8.count)) + sidecarSuffix
    }

    /// The transcript a sidecar belongs to; nil for any other file (a `.bak` copy included).
    static func transcriptPath(ofSidecar path: String) -> String? {
        guard path.hasSuffix(sidecarSuffix), !(path as NSString).lastPathComponent.hasPrefix(".") else { return nil }
        return String(path.dropLast(sidecarSuffix.utf8.count)) + transcriptSuffix
    }

    /// The session file `<folder>/<id>.jsonl` next to a transcript.
    static func sibling(_ id: String, of path: String) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(id + transcriptSuffix)
    }

    /// The session id of a transcript: its file name without `.jsonl`.
    static func sessionId(ofTranscript path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(transcriptSuffix) ? String(name.dropLast(transcriptSuffix.utf8.count)) : name
    }

    /// `^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`: no other file name can be formed from it.
    static func isSessionId(_ value: String) -> Bool {
        let bytes = value.utf8
        guard let first = bytes.first, bytes.count <= 128, isAlphanumeric(first) else { return false }
        return bytes.allSatisfy { isAlphanumeric($0) || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    /// A transcript's stat with the sidecar's modification time folded in (the newer of the two): startup order, the
    /// startup window and the hot window follow the session's latest write. Nil unless the transcript is a regular file.
    static func stat(_ path: String) -> FileStat? {
        guard let stat = FileStat.lstat(path), stat.isRegularFile else { return nil }
        return folding(stat, ofTranscript: path)
    }

    /// A transcript's own stat with its sidecar's modification time folded in.
    static func folding(_ transcript: FileStat, ofTranscript path: String) -> FileStat {
        var stat = transcript
        if let sidecar = FileStat.lstat(sidecarPath(ofTranscript: path)), sidecar.isRegularFile {
            stat.modifiedNs = max(stat.modifiedNs, sidecar.modifiedNs)
        }
        return stat
    }

    /// What identifies one version of a sidecar: size, modification time and identity; nil when nothing is there.
    struct Signature: Equatable, Sendable {
        var size: Int64
        var modifiedNs: Int64
        var identity: FileIdentity
    }

    static func signature(_ path: String) -> Signature? {
        FileStat.lstat(path).map { Signature(size: $0.size, modifiedNs: $0.modifiedNs, identity: $0.identity) }
    }
}

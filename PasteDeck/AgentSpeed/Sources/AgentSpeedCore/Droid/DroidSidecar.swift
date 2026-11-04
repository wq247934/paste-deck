import Darwin
import Foundation

/// A Factory Droid sidecar, `<session id>.settings.json` (METRICS 4.16 Sidecar): read whole, never tailed, never
/// written. Only `model`, `effectiveFactoryRouterModel.modelId` and the five counters of `tokenUsage` are kept.
enum DroidSidecar {
    static let maxBytes = 1 << 20

    /// A readable sidecar: its counters (nil without a `tokenUsage` object) and its session model.
    struct Content: Equatable, Sendable {
        var counters: DroidCounters?
        var model: String?
    }

    /// One look at a sidecar: its signature before reading and what it held (nil when unreadable or missing).
    struct Snapshot: Equatable, Sendable {
        var signature: DroidPaths.Signature?
        var content: Content?
    }

    static func snapshot(_ path: String) -> Snapshot {
        guard let signature = DroidPaths.signature(path) else { return Snapshot(signature: nil, content: nil) }
        return Snapshot(signature: signature, content: read(path))
    }

    /// The whole file when it is a regular file (a symlink is not followed) of at most 1 MiB that holds a JSON object
    /// in valid UTF-8; nil otherwise, so the next read cycle tries again (droid may be replacing it).
    static func read(_ path: String) -> Content? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        guard let stat = FileStat.fstat(descriptor), stat.isRegularFile, stat.size <= Int64(maxBytes) else { return nil }
        let capacity = maxBytes + 1
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }
        var filled = 0
        while filled < capacity {
            let count = Darwin.pread(descriptor, buffer.baseAddress! + filled, capacity - filled, off_t(filled))
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            filled += count
        }
        guard filled <= maxBytes else { return nil }
        return parse(UnsafeRawBufferPointer(rebasing: buffer[0..<filled]))
    }

    /// One leading byte order mark is removed; repeated members resolve like Python's `json.loads` (the last wins).
    static func parse(_ bytes: UnsafeRawBufferPointer) -> Content? {
        var body = bytes
        if body.count >= 3, body[0] == 0xEF, body[1] == 0xBB, body[2] == 0xBF {
            body = UnsafeRawBufferPointer(rebasing: body[3...])
        }
        var scanner = JSONScanner(body)
        var chosen: String?
        var routed: String?
        var counters: DroidCounters?
        do {
            try scanner.beginObject()
            while let key = try scanner.nextMember() {
                if scanner.key(key, is: "model") {
                    chosen = try scanner.readString()
                } else if scanner.key(key, is: "effectiveFactoryRouterModel") {
                    routed = try scanRouter(&scanner)
                } else if scanner.key(key, is: "tokenUsage") {
                    counters = try scanCounters(&scanner)
                } else {
                    try scanner.skipValue()
                }
            }
            try scanner.finish()
        } catch {
            return nil
        }
        return Content(counters: counters, model: sessionModel(routed: routed, chosen: chosen))
    }

    /// The router's pick when it names a model, else `model` unless it is `auto` (ASCII case-insensitive); trimmed.
    static func sessionModel(routed: String?, chosen: String?) -> String? {
        if let routed {
            let trimmed = WorkBuddyLineExtractor.stripped(routed)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let chosen else { return nil }
        let trimmed = WorkBuddyLineExtractor.stripped(chosen)
        guard !trimmed.isEmpty, !trimmed.utf8.elementsEqual("auto".utf8, by: { asciiLowercase($0) == $1 }) else { return nil }
        return trimmed
    }

    private static func asciiLowercase(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func scanRouter(_ scanner: inout JSONScanner) throws(JSONScanError) -> String? {
        guard try scanner.beginObjectIfPresent() else { return nil }
        var modelId: String?
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "modelId") {
                modelId = try scanner.readString()
            } else {
                try scanner.skipValue()
            }
        }
        return modelId
    }

    private static func scanCounters(_ scanner: inout JSONScanner) throws(JSONScanError) -> DroidCounters? {
        guard try scanner.beginObjectIfPresent() else { return nil }
        var counters = DroidCounters()
        while let key = try scanner.nextMember() {
            let field: WritableKeyPath<DroidCounters, Int64>? =
                if scanner.key(key, is: "inputTokens") { \.input }
                else if scanner.key(key, is: "cacheCreationTokens") { \.cacheCreation }
                else if scanner.key(key, is: "cacheReadTokens") { \.cacheRead }
                else if scanner.key(key, is: "outputTokens") { \.output }
                else if scanner.key(key, is: "thinkingTokens") { \.thinking }
                else { nil }
            if let field {
                counters[keyPath: field] = Int64(TokenCount.clamp(try scanner.readNumber()?.truncated))
            } else {
                try scanner.skipValue()
            }
        }
        return counters
    }
}

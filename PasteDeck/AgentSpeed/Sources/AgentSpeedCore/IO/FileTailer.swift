import Darwin
import Foundation

/// Reads complete lines appended to one file (METRICS 5). Read-only, never follows symlinks.
struct FileTailer: Sendable {
    static let defaultMaxLineBytes = 32 << 20
    static let chunkBytes = 4 << 20
    /// Files larger than this are seeded from their last `tailWindowBytes` only.
    static let largeFileBytes: Int64 = 256 << 20
    static let tailWindowBytes: Int64 = 64 << 20

    enum Start: Equatable, Sendable {
        case beginning
        /// Start at the given size; an unterminated last line there is skipped.
        case end(Int64)
        /// Start `bytes` before the end, aligned to the next newline.
        case tail(Int64)
    }

    struct ReadResult: Equatable, Sendable {
        var bytesRead = 0
        /// The file shrank or was replaced; offset and parser state must restart.
        var didReset = false
        var failed = false
        var stat: FileStat?
        /// A whole-document file over its size limit was not read (`partialHistory`).
        var oversized = false
        /// The path names another file than the one expected; nothing was read.
        var otherFile = false
        /// Where reading began, when this read positioned the tailer (its first read since creation or a restart).
        var startOffset: Int64?
    }

    private(set) var path: String
    private(set) var offset: Int64 = 0
    private(set) var identity: FileIdentity?
    private var start: Start?
    private var lines: LineSplitter

    var maxLineBytes: Int { lines.maxLineBytes }
    var oversizedLines: Int { lines.oversizedLines }

    init(path: String, start: Start = .beginning, maxLineBytes: Int = FileTailer.defaultMaxLineBytes) {
        self.path = path
        self.start = start
        lines = LineSplitter(maxLineBytes: maxLineBytes)
    }

    /// Reads every complete line appended since the last call. With `expecting`, a path that now names another file is
    /// not read (a file followed across renames, METRICS 4.15).
    mutating func read(
        expecting expected: FileIdentity? = nil,
        onReset: () -> Void = {},
        onLine: (UnsafeRawBufferPointer) -> Void
    ) -> ReadResult {
        read(expecting: expected, onReset: onReset) { line, _ in onLine(line) }
    }

    /// Like `read(expecting:onReset:onLine:)`, with each line's byte offset in the file.
    mutating func read(
        expecting expected: FileIdentity? = nil,
        onReset: () -> Void = {},
        onLineAt: (UnsafeRawBufferPointer, Int64) -> Void
    ) -> ReadResult {
        var result = ReadResult()
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            result.failed = true
            return result
        }
        defer { Darwin.close(descriptor) }
        guard let stat = FileStat.fstat(descriptor), stat.isRegularFile else {
            result.failed = true
            return result
        }
        result.stat = stat
        if let expected, expected != stat.identity {
            result.otherFile = true
            return result
        }

        if let identity, identity != stat.identity || stat.size < offset {
            restart()
            result.didReset = true
            onReset()
        }
        identity = stat.identity
        if let pending = start {
            position(at: pending, size: stat.size, descriptor: descriptor)
            start = nil
            result.startOffset = offset
        }
        guard offset < stat.size else { return result }

        let capacity = Int(min(Int64(Self.chunkBytes), stat.size - offset))
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }
        while offset < stat.size {
            let wanted = Int(min(Int64(capacity), stat.size - offset))
            let count = Darwin.pread(descriptor, buffer.baseAddress, wanted, off_t(offset))
            if count < 0 {
                if errno == EINTR { continue }
                result.failed = true
                break
            }
            if count == 0 { break }
            lines.consume(UnsafeRawBufferPointer(rebasing: buffer[0..<count]), at: offset, onLine: onLineAt)
            offset += Int64(count)
            result.bytesRead += count
        }
        return result
    }

    /// The followed file now has this path (renamed); offset and buffered line stay.
    mutating func follow(to path: String) {
        self.path = path
    }

    /// Forgets everything; the next read starts at offset 0.
    mutating func restart() {
        offset = 0
        lines.reset()
        start = nil
    }

    private mutating func position(at start: Start, size: Int64, descriptor: Int32) {
        switch start {
        case .beginning:
            offset = 0
        case .end(let recordedSize):
            offset = min(recordedSize, size)
            if offset > 0 {
                var last: UInt8 = 0
                if Darwin.pread(descriptor, &last, 1, off_t(offset - 1)) == 1, last != 0x0A {
                    lines.skipToNextNewline()
                }
            }
        case .tail(let window):
            if size > window {
                offset = size - window
                lines.skipToNextNewline()
            } else {
                offset = 0
            }
        }
    }
}

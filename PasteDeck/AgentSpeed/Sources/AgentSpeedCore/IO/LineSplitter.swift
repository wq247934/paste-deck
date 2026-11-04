import Darwin

/// Splits a byte stream into newline-terminated lines (METRICS 5): an incomplete trailing line is buffered until its
/// newline arrives, and lines longer than `maxLineBytes` are dropped.
struct LineSplitter: Sendable {
    let maxLineBytes: Int
    private(set) var oversizedLines = 0
    private var partial: [UInt8] = []
    /// Stream offset of the first byte of `partial`.
    private var partialStart: Int64 = 0
    /// Skipping bytes until the next newline (oversized or unaligned line).
    private var discarding = false

    init(maxLineBytes: Int) {
        self.maxLineBytes = max(1, maxLineBytes)
    }

    /// Drops everything up to and including the next newline.
    mutating func skipToNextNewline() {
        discarding = true
    }

    /// Forgets the buffered fragment.
    mutating func reset() {
        releasePartial()
        discarding = false
    }

    mutating func consume(_ chunk: UnsafeRawBufferPointer, onLine: (UnsafeRawBufferPointer) -> Void) {
        consume(chunk, at: 0) { line, _ in onLine(line) }
    }

    /// Like `consume(_:onLine:)`, with each line's byte offset in the stream; `chunkOffset` is the chunk's own.
    mutating func consume(_ chunk: UnsafeRawBufferPointer, at chunkOffset: Int64, onLine: (UnsafeRawBufferPointer, Int64) -> Void) {
        guard let base = chunk.baseAddress else { return }
        var lineStart = 0
        while lineStart < chunk.count {
            let remaining = chunk.count - lineStart
            if let newline = memchr(base + lineStart, 0x0A, remaining) {
                let lineEnd = base.distance(to: UnsafeRawPointer(newline))
                let fragment = UnsafeRawBufferPointer(rebasing: chunk[lineStart..<lineEnd])
                if discarding {
                    discarding = false
                } else if partial.isEmpty {
                    if fragment.count > maxLineBytes {
                        oversizedLines += 1
                    } else {
                        onLine(fragment, chunkOffset + Int64(lineStart))
                    }
                } else if partial.count + fragment.count > maxLineBytes {
                    oversizedLines += 1
                    releasePartial()
                } else {
                    partial.append(contentsOf: fragment)
                    let start = partialStart
                    partial.withUnsafeBytes { onLine($0, start) }
                    releasePartial()
                }
                lineStart = lineEnd + 1
            } else {
                let fragment = UnsafeRawBufferPointer(rebasing: chunk[lineStart..<chunk.count])
                if !discarding {
                    if partial.count + fragment.count > maxLineBytes {
                        oversizedLines += 1
                        releasePartial()
                        discarding = true
                    } else {
                        if partial.isEmpty { partialStart = chunkOffset + Int64(lineStart) }
                        partial.append(contentsOf: fragment)
                    }
                }
                lineStart = chunk.count
            }
        }
    }

    private mutating func releasePartial() {
        if partial.capacity > 1 << 20 {
            partial = []
        } else {
            partial.removeAll(keepingCapacity: true)
        }
    }
}

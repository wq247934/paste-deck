import Foundation

/// One record line of Hermes Agent's `agent.log` that Agent Speed reads (METRICS 4.15): a turn start, an API call
/// (well-formed or not), or the end of a turn. Every other line is ignored. Matching works on the UTF-8 bytes: every
/// delimiter of the patterns is ASCII, and an invalid byte sequence (U+FFFD after decoding) never matches one.
struct HermesLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `agent.turn_context`: the turn's model (may be empty) and platform.
        case turn(model: String, platform: String)
        /// `agent.conversation_loop` `API call #…`; nil when the message does not match the grammar (malformed).
        case call(HermesCall?)
        /// A turn end (`Turn ended…`) or a terminal error.
        case end
    }

    var sessionId: String
    /// The line's time in Unix milliseconds (wall clock read in the computer's time zone).
    var timeMs: Int64
    /// The 23-character timestamp text, part of an API call's key.
    var stamp: String
    var kind: Kind

    static let turnLogger = Array("agent.turn_context".utf8)
    static let loopLogger = Array("agent.conversation_loop".utf8)

    /// The line's record, or nil when it is not one of the four kinds (or its time is not a valid wall time).
    static func parse(_ line: UnsafeRawBufferPointer, timeZone: TimeZone) -> HermesLine? {
        var bytes = line.bindMemory(to: UInt8.self)
        if bytes.last == UInt8(ascii: "\r") { bytes = UnsafeBufferPointer(rebasing: bytes.dropLast()) }
        guard let clock = WallClock(bytes) else { return nil }
        var cursor = 23
        guard cursor < bytes.count, bytes[cursor] == space else { return nil }
        cursor += 1
        guard let level = Level(bytes, at: &cursor), cursor < bytes.count, bytes[cursor] == space else { return nil }
        let rest = UnsafeBufferPointer(rebasing: bytes[cursor...])
        var logger = turnLogger
        var split = Self.split(rest, logger: turnLogger)
        if split == nil {
            logger = loopLogger
            split = Self.split(rest, logger: loopLogger)
        }
        guard let (sessionId, message) = split else { return nil }
        let kind: Kind
        if logger == turnLogger {
            guard level == .info, let turn = HermesGrammar.turn(message) else { return nil }
            kind = .turn(model: turn.model, platform: turn.platform)
        } else if level == .info, message.starts(with: callPrefix) {
            kind = .call(HermesGrammar.call(message))
        } else if level == .info || level == .warning, message.starts(with: endedPrefix) || message.starts(with: pendingPrefix) {
            kind = .end
        } else if level == .error, isTerminalError(message) {
            kind = .end
        } else {
            return nil
        }
        guard let timeMs = clock.unixMs(in: timeZone) else { return nil }
        let stamp = String(decoding: UnsafeBufferPointer(rebasing: bytes[0..<23]), as: UTF8.self)
        return HermesLine(sessionId: sessionId, timeMs: timeMs, stamp: stamp, kind: kind)
    }

    /// `(session id, message)` when the text after the level belongs to `logger`: ` <logger>: <message>` (no session)
    /// or ` [<id>] <logger>: <message>` with `<id>` the non-empty text up to the first `] <logger>: `.
    static func split(_ rest: UnsafeBufferPointer<UInt8>, logger: [UInt8]) -> (String, UnsafeBufferPointer<UInt8>)? {
        let head = [space] + logger + [colon, space]
        if rest.starts(with: head) {
            return ("", UnsafeBufferPointer(rebasing: rest[head.count...]))
        }
        guard rest.count > 2, rest[0] == space, rest[1] == UInt8(ascii: "[") else { return nil }
        let closing = [UInt8(ascii: "]"), space] + logger + [colon, space]
        guard let end = HermesGrammar.find(closing, in: rest, from: 2), end > 2 else { return nil }
        let sessionId = String(decoding: UnsafeBufferPointer(rebasing: rest[2..<end]), as: UTF8.self)
        return (sessionId, UnsafeBufferPointer(rebasing: rest[(end + closing.count)...]))
    }

    /// An `ERROR` message that, after an optional leading `[…]` group and spaces, reports a terminal failure.
    static func isTerminalError(_ message: UnsafeBufferPointer<UInt8>) -> Bool {
        var start = 0
        if message.first == UInt8(ascii: "["), let close = message.firstIndex(of: UInt8(ascii: "]")) {
            start = close + 1
            while start < message.count, message[start] == space { start += 1 }
        }
        let text = UnsafeBufferPointer(rebasing: message[start...])
        return text.starts(with: failedPrefix) || text.starts(with: clientErrorPrefix)
    }

    private static let space = UInt8(ascii: " ")
    private static let colon = UInt8(ascii: ":")
    private static let callPrefix = Array("API call #".utf8)
    private static let endedPrefix = Array("Turn ended: ".utf8)
    private static let pendingPrefix = Array("Turn ended with pending tool result".utf8)
    private static let failedPrefix = Array("API call failed after ".utf8)
    private static let clientErrorPrefix = Array("Non-retryable client error: ".utf8)

    private enum Level {
        case debug, info, warning, error, critical

        private static let names: [(Level, [UInt8])] = [
            (.debug, Array("DEBUG".utf8)), (.info, Array("INFO".utf8)), (.warning, Array("WARNING".utf8)),
            (.error, Array("ERROR".utf8)), (.critical, Array("CRITICAL".utf8)),
        ]

        init?(_ bytes: UnsafeBufferPointer<UInt8>, at cursor: inout Int) {
            let rest = UnsafeBufferPointer(rebasing: bytes[cursor...])
            guard let (level, name) = Self.names.first(where: { rest.starts(with: $0.1) }) else { return nil }
            self = level
            cursor += name.count
        }
    }
}

/// The fields of a well-formed API-call message (METRICS 4.15), as written.
struct HermesCall: Equatable, Sendable {
    var number: String
    var model: String
    var provider: String
    /// nil for `?` (no usage).
    var input: String?
    var output: String?
    var latency: String
    var cacheRead: String?
    var cacheWrite: String?
}

/// The message grammars of METRICS 4.15, written out as the regular expressions backtrack: a lazy model group ends at
/// the first ` provider=` after which the rest of the pattern matches.
enum HermesGrammar {
    struct Turn {
        var model: String
        var platform: String
    }

    /// `^conversation turn: session=[^ ]* model=(.*?) provider=[^ ]* platform=([^ ]*) history=-?[0-9]+ msg=`.
    static func turn(_ message: UnsafeBufferPointer<UInt8>) -> Turn? {
        var scanner = Scanner(message)
        guard scanner.literal("conversation turn: session=") else { return nil }
        scanner.skipNonSpaces()
        guard scanner.literal(" model=") else { return nil }
        let modelStart = scanner.position
        var from = modelStart
        while let candidate = find(providerKey, in: message, from: from) {
            var rest = Scanner(message, at: candidate + providerKey.count)
            rest.skipNonSpaces()
            if rest.literal(" platform=") {
                let platformStart = rest.position
                rest.skipNonSpaces()
                let platformEnd = rest.position
                if rest.literal(" history="), rest.integer(), rest.literal(" msg=") {
                    return Turn(model: text(message, modelStart, candidate), platform: text(message, platformStart, platformEnd))
                }
            }
            from = candidate + 1
        }
        return nil
    }

    /// The whole message must match `^API call #([0-9]+): model=(.*?) provider=([^ ]*) in=(-?[0-9]+|\?)
    /// out=(-?[0-9]+|\?) total=(-?[0-9]+|\?) latency=(-?[0-9]+(?:\.[0-9]+)?)s(?: cache=(-?[0-9]+)/-?[0-9]+
    /// \(-?[0-9]+%\))?(?: write=(-?[0-9]+))?(?: .*)?$`; nil otherwise.
    static func call(_ message: UnsafeBufferPointer<UInt8>) -> HermesCall? {
        var scanner = Scanner(message)
        guard scanner.literal("API call #") else { return nil }
        let numberStart = scanner.position
        guard scanner.digits() else { return nil }
        let number = text(message, numberStart, scanner.position)
        guard scanner.literal(": model=") else { return nil }
        let modelStart = scanner.position
        var from = modelStart
        while let candidate = find(providerKey, in: message, from: from) {
            if var call = tail(message, at: candidate + providerKey.count) {
                call.number = number
                call.model = text(message, modelStart, candidate)
                return call
            }
            from = candidate + 1
        }
        return nil
    }

    /// Everything after ` provider=`.
    private static func tail(_ message: UnsafeBufferPointer<UInt8>, at start: Int) -> HermesCall? {
        var scanner = Scanner(message, at: start)
        scanner.skipNonSpaces()
        let provider = text(message, start, scanner.position)
        guard scanner.literal(" in="), let input = scanner.count(),
              scanner.literal(" out="), let output = scanner.count(),
              scanner.literal(" total="), scanner.count() != nil,
              scanner.literal(" latency=") else { return nil }
        let latencyStart = scanner.position
        _ = scanner.literal("-")
        guard scanner.digits() else { return nil }
        if scanner.peek(".") {
            var fraction = scanner
            fraction.position += 1
            if fraction.digits() { scanner = fraction }
        }
        let latency = text(message, latencyStart, scanner.position)
        guard scanner.literal("s") else { return nil }
        guard scanner.atEnd || scanner.peek(" ") else { return nil }
        var call = HermesCall(number: "", model: "", provider: provider, input: input.number, output: output.number,
                              latency: latency)
        // The optional groups count only when what follows them is the end or a space (` .*`).
        var cache = scanner
        if cache.literal(" cache="), let read = cache.signedInteger(), cache.literal("/"), cache.signedInteger() != nil,
           cache.literal(" ("), cache.signedInteger() != nil, cache.literal("%)"), cache.atEnd || cache.peek(" ") {
            call.cacheRead = read
            scanner = cache
        }
        var write = scanner
        if write.literal(" write="), let written = write.signedInteger(), write.atEnd || write.peek(" ") {
            call.cacheWrite = written
        }
        return call
    }

    private static let providerKey = Array(" provider=".utf8)

    /// The first occurrence of `needle` in `haystack` at or after `from`.
    static func find(_ needle: [UInt8], in haystack: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard from <= haystack.count, let base = haystack.baseAddress, !needle.isEmpty else { return nil }
        return needle.withUnsafeBytes { pattern -> Int? in
            guard let found = memmem(base + from, haystack.count - from, pattern.baseAddress, needle.count) else { return nil }
            return UnsafeRawPointer(base).distance(to: UnsafeRawPointer(found))
        }
    }

    static func text(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
    }

    /// A cursor over the message bytes.
    struct Scanner {
        let bytes: UnsafeBufferPointer<UInt8>
        var position: Int

        init(_ bytes: UnsafeBufferPointer<UInt8>, at position: Int = 0) {
            self.bytes = bytes
            self.position = position
        }

        var atEnd: Bool { position >= bytes.count }

        func peek(_ character: Unicode.Scalar) -> Bool {
            position < bytes.count && bytes[position] == UInt8(ascii: character)
        }

        mutating func literal(_ text: StaticString) -> Bool {
            let count = text.utf8CodeUnitCount
            guard position + count <= bytes.count else { return false }
            let pointer = text.utf8Start
            for offset in 0..<count where bytes[position + offset] != pointer[offset] { return false }
            position += count
            return true
        }

        mutating func skipNonSpaces() {
            while position < bytes.count, bytes[position] != UInt8(ascii: " ") { position += 1 }
        }

        /// One or more ASCII digits (as many as there are).
        mutating func digits() -> Bool {
            let start = position
            while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) { position += 1 }
            return position > start
        }

        /// `-?[0-9]+`.
        mutating func integer() -> Bool {
            var probe = self
            _ = probe.literal("-")
            guard probe.digits() else { return false }
            self = probe
            return true
        }

        /// `-?[0-9]+` as written.
        mutating func signedInteger() -> String? {
            let start = position
            guard integer() else { return nil }
            return HermesGrammar.text(bytes, start, position)
        }

        /// A token count: `-?[0-9]+` as written, or `?` (no usage, `number` nil).
        struct Count {
            var number: String?
        }

        mutating func count() -> Count? {
            if peek("?") {
                position += 1
                return Count(number: nil)
            }
            return signedInteger().map { Count(number: $0) }
        }
    }
}

/// The 23-character timestamp of a record line: `YYYY-MM-DD HH:MM:SS,mmm` in ASCII digits.
struct WallClock: Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int
    var millisecond: Int

    init?(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard bytes.count >= 23 else { return nil }
        func number(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for index in start..<(start + count) {
                let byte = bytes[index]
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        let separators: [(Int, Unicode.Scalar)] = [(4, "-"), (7, "-"), (10, " "), (13, ":"), (16, ":"), (19, ",")]
        guard separators.allSatisfy({ bytes[$0.0] == UInt8(ascii: $0.1) }),
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2), let hour = number(11, 2),
              let minute = number(14, 2), let second = number(17, 2), let millisecond = number(20, 3) else { return nil }
        self.init(year: year, month: month, day: day, hour: hour, minute: minute, second: second, millisecond: millisecond)
    }

    init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, millisecond: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
    }

    /// The instant this wall time names in `zone`, as Python's `datetime.timestamp()` of a naive local time with
    /// `fold = 0`: a time that occurs twice is the earlier instant, a skipped time uses the offset in force before the
    /// change. Nil outside 1970–9999 or for an impossible date or clock.
    func unixMs(in zone: TimeZone) -> Int64? {
        guard (1970...9999).contains(year), (1...12).contains(month), (1...Self.days(year, month)).contains(day),
              hour <= 23, minute <= 59, second <= 59 else { return nil }
        let wall = Self.daysSinceEpoch(year, month, day) * 86_400 + Int64(hour * 3600 + minute * 60 + second)
        func offset(_ seconds: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
        }
        let before = offset(wall - 14 * 3600)
        let after = offset(wall + 14 * 3600)
        let solutions = [before, after].filter { offset(wall - $0) == $0 }.map { wall - $0 }
        let seconds = solutions.min() ?? wall - before
        return seconds * 1000 + Int64(millisecond)
    }

    static func days(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from 1970-01-01 in the proleptic Gregorian calendar.
    static func daysSinceEpoch(_ year: Int, _ month: Int, _ day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let m = Int64(month)
        let dayOfYear = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

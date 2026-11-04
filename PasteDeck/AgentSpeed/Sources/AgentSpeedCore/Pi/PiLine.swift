import Foundation

/// A `usage` object of Pi's normalized `Usage` (METRICS 4.13); missing, non-numeric and negative fields are 0.
struct PiUsage: Equatable, Sendable {
    var tokens: TokenUsage
    /// One of `input`, `output`, `cacheRead`, `cacheWrite` is above 0.
    var hasUsage: Bool
}

/// `message.stopReason`; a missing or non-string value counts as `aborted`.
enum PiStop: Equatable, Sendable {
    case aborted
    case error
    case pending
    case deferred
    case stop
    case toolUse
    case length
    case other

    /// No timing and phase `idle`: `pending` and `deferred` fetch their result later, without it.
    var isFailure: Bool { self == .aborted || self == .error || self == .pending || self == .deferred }

    /// Pi runs the tool calls of the message.
    var runsTools: Bool { self == .toolUse || self == .stop || self == .length }
}

/// An assistant message past the statistics guard: `model`, `provider` and `api` are strings and `usage` is an object.
struct PiAssistant: Equatable, Sendable {
    var model: String
    /// The `provider` string; nil when it is empty (METRICS 3.2).
    var provider: String?
    var usage: PiUsage
    /// `message.timestamp` truncated, when it is a finite number above 0.
    var startedMs: Int64?
    /// `message.durationMs` truncated, when it is a finite number of at least 0 (pi-ai 0.99+).
    var durationMs: Int64?
    var stop: PiStop
    /// String ids of the `toolCall` blocks of `message.content`.
    var toolCallIds: Set<String> = []
    /// `message.thinkingLevel` as a recorded request effort (EXECUTION-MODES, Pi).
    var effort: ExecutionModeFact?
}

enum PiRecord: Equatable, Sendable {
    /// A `user` or `developer` message.
    case input
    case assistant(PiAssistant)
    /// The `usage` of a tool's own model calls, when it is an object.
    case toolResult(callId: String?, usage: PiUsage?)
    /// A `usage` entry whose `provider` and `model` are strings.
    case usageEntry(model: String, provider: String?, usage: PiUsage?)
    /// The summary call of a `compaction` or `branch_summary` entry.
    case summary(PiUsage?)
    /// A `thinking_level_change` entry as a selected session effort; nil when its level is no effort token.
    case thinkingLevel(ExecutionModeFact?)
    /// Anything else, including assistant messages that fail the guard: only `lastLineMs`.
    case other
}

/// One classified line of a Pi session file (METRICS 4.13).
enum PiLine: Equatable, Sendable {
    /// A `session` line; Pi's header has the omp shape.
    case header(OmpSession)
    /// An entry with a string `id` and a parseable `timestamp`.
    case entry(id: String, timestampMs: Int64, record: PiRecord)
    /// Entries without a string `id` or a parseable `timestamp`.
    case ignored
}

/// Decodes Pi session lines. Conversation content is skipped (only validated). Repeated members resolve like
/// Python's `json.loads`: the last one wins.
enum PiLineExtractor {
    private static let types: [StaticString] = [
        "session", "message", "usage", "compaction", "branch_summary", "thinking_level_change",
    ]
    private static let roles: [StaticString] = ["user", "developer", "assistant", "toolResult"]
    private static let stopReasons: [StaticString] = ["aborted", "error", "pending", "deferred", "stop", "toolUse", "length"]

    static func extract(_ bytes: UnsafeRawBufferPointer) -> LineExtraction<PiLine> {
        if bytes.allSatisfy({ $0 == UInt8(ascii: " ") || (0x09...0x0D).contains($0) }) { return .blank }
        var scanner = JSONScanner(bytes)
        do {
            try scanner.beginObject()
            let top = try scanTopLevel(&scanner)
            try scanner.finish()
            return .line(top.classified())
        } catch {
            return .malformed
        }
    }

    // MARK: - Members

    private struct Usage {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var cacheWrite1h = 0
        var reasoning = 0

        var normalized: PiUsage {
            let tokens = TokenUsage(
                input: TokenCount.sum(input, cacheRead, cacheWrite),
                cachedInput: cacheRead,
                cacheWriteInput: cacheWrite,
                cacheWrite1hInput: min(cacheWrite1h, cacheWrite),
                output: output,
                reasoning: reasoning
            )
            return PiUsage(tokens: tokens, hasUsage: input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0)
        }
    }

    /// `provider`: absent, not a string, or the string (nil when it is longer than the scanner captures).
    private struct Provider {
        var isString = false
        var value: String?
    }

    private struct MessageMembers {
        var role: Int?
        var model: String?
        var provider = Provider()
        var hasApi = false
        var usage: Usage?
        var timestamp: JSONNumber?
        var duration: JSONNumber?
        var stopReason: Int?
        var toolCallIds: Set<String> = []
        var toolCallId: String?
        var thinkingLevel: String?

        func record() -> PiRecord {
            switch role {
            case 0, 1:
                return .input
            case 2:
                guard let model, provider.isString, hasApi, let usage else { return .other }
                return .assistant(PiAssistant(
                    model: model,
                    provider: provider.value.flatMap { $0.isEmpty ? nil : $0 },
                    usage: usage.normalized,
                    startedMs: timestamp.flatMap { $0.isFinite && $0.isPositive ? $0.truncated : nil },
                    durationMs: duration.flatMap { $0.isFinite && $0.isNonNegative ? $0.truncated : nil },
                    stop: stop,
                    toolCallIds: toolCallIds,
                    effort: ExecutionModeAdapters.effort(thinkingLevel, evidence: .recorded, scope: .request)
                ))
            case 3:
                return .toolResult(callId: toolCallId, usage: usage?.normalized)
            default:
                return .other
            }
        }

        private var stop: PiStop {
            switch stopReason {
            case nil, 0: .aborted
            case 1: .error
            case 2: .pending
            case 3: .deferred
            case 4: .stop
            case 5: .toolUse
            case 6: .length
            default: .other
            }
        }
    }

    private struct TopLevel {
        var type: Int?
        var id: String?
        var timestampMs: Int64?
        var cwd: String?
        var message: MessageMembers?
        var model: String?
        var provider = Provider()
        var usage: Usage?
        var thinkingLevel: String?

        func classified() -> PiLine {
            if type == 0 { return .header(OmpSession(id: id, timestampMs: timestampMs, cwd: cwd)) }
            guard let id, let timestampMs else { return .ignored }
            let record: PiRecord = switch type {
            case 1: message?.record() ?? .other
            case 2:
                if let model, provider.isString {
                    .usageEntry(model: model, provider: provider.value.flatMap { $0.isEmpty ? nil : $0 }, usage: usage?.normalized)
                } else {
                    .other
                }
            case 3, 4: .summary(usage?.normalized)
            case 5: .thinkingLevel(ExecutionModeAdapters.effort(thinkingLevel, evidence: .selected, scope: .session))
            default: .other
            }
            return .entry(id: id, timestampMs: timestampMs, record: record)
        }
    }

    // MARK: - Scanning

    private static func scanTopLevel(_ scanner: inout JSONScanner) throws(JSONScanError) -> TopLevel {
        var top = TopLevel()
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "type") {
                top.type = try scanner.readStringMatch(types)
            } else if scanner.key(key, is: "id") {
                top.id = try scanner.readString()
            } else if scanner.key(key, is: "timestamp") {
                top.timestampMs = try scanner.readTimestamp()
            } else if scanner.key(key, is: "cwd") {
                top.cwd = try scanner.readString()
            } else if scanner.key(key, is: "message") {
                top.message = try scanMessage(&scanner)
            } else if scanner.key(key, is: "model") {
                top.model = try scanner.readString()
            } else if scanner.key(key, is: "provider") {
                top.provider = try scanProvider(&scanner)
            } else if scanner.key(key, is: "usage") {
                top.usage = try scanUsage(&scanner)
            } else if scanner.key(key, is: "thinkingLevel") {
                top.thinkingLevel = try scanner.readString()
            } else {
                try scanner.skipValue()
            }
        }
        return top
    }

    private static func scanMessage(_ scanner: inout JSONScanner) throws(JSONScanError) -> MessageMembers? {
        guard try scanner.beginObjectIfPresent() else { return nil }
        var message = MessageMembers()
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "role") {
                message.role = try scanner.readStringMatch(roles)
            } else if scanner.key(key, is: "model") {
                message.model = try scanner.readString()
            } else if scanner.key(key, is: "provider") {
                message.provider = try scanProvider(&scanner)
            } else if scanner.key(key, is: "api") {
                message.hasApi = try scanner.readStringIsNonEmpty() != nil
            } else if scanner.key(key, is: "usage") {
                message.usage = try scanUsage(&scanner)
            } else if scanner.key(key, is: "timestamp") {
                message.timestamp = try scanner.readNumber()
            } else if scanner.key(key, is: "durationMs") {
                message.duration = try scanner.readNumber()
            } else if scanner.key(key, is: "stopReason") {
                message.stopReason = try scanner.readStringMatch(stopReasons)
            } else if scanner.key(key, is: "content") {
                message.toolCallIds = try OmpLineExtractor.scanToolCallIds(&scanner)
            } else if scanner.key(key, is: "toolCallId") {
                message.toolCallId = try scanner.readString()
            } else if scanner.key(key, is: "thinkingLevel") {
                message.thinkingLevel = try scanner.readString()
            } else {
                try scanner.skipValue()
            }
        }
        return message
    }

    private static func scanProvider(_ scanner: inout JSONScanner) throws(JSONScanError) -> Provider {
        let value = try scanner.readStringValue()
        return Provider(isString: value != nil, value: value.flatMap { $0 })
    }

    private static func scanUsage(_ scanner: inout JSONScanner) throws(JSONScanError) -> Usage? {
        guard try scanner.beginObjectIfPresent() else { return nil }
        var usage = Usage()
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "input") {
                usage.input = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "output") {
                usage.output = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "cacheRead") {
                usage.cacheRead = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "cacheWrite") {
                usage.cacheWrite = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "cacheWrite1h") {
                usage.cacheWrite1h = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "reasoning") {
                usage.reasoning = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else {
                try scanner.skipValue()
            }
        }
        return usage
    }
}

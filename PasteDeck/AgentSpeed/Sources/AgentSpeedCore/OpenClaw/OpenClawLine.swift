import Foundation

/// An assistant message of an OpenClaw transcript past the statistics guard: `model`, `provider` and `api` are strings
/// and `usage` is an object (METRICS 4.14, the guard of 4.7).
struct OpenClawAssistant: Equatable, Sendable {
    var model: String
    /// The `provider` string; nil when it is empty (METRICS 3.2).
    var provider: String?
    var tokens: TokenUsage
    /// One of `input`, `output`, `cacheRead`, `cacheWrite` is above 0.
    var hasUsage: Bool
    /// `usage.usageReport.state == "unavailable"`: provisional stream counters that emit no response.
    var usageUnavailable: Bool
    /// `message.timestamp` truncated, when it is a finite number above 0.
    var startedMs: Int64?
    /// `stop`, `length` or `toolUse`; any other or missing stop reason counts as `aborted`, a failure.
    var stopRunsTools: Bool
    var stopIsFailure: Bool
    /// `message.api == "cli"`: a CLI backend turn.
    var isCLI: Bool
    /// The message mirrors a turn another runtime ran (mirror origin, `claude-cli` or an `acp-` provider).
    var isMirror: Bool
    /// String ids of the `toolCall` blocks of `message.content`.
    var toolCallIds: Set<String> = []
}

enum OpenClawRecord: Equatable, Sendable {
    /// A `user` or `developer` message.
    case input
    case assistant(OpenClawAssistant)
    case toolResult(callId: String?)
    /// Anything else, including assistant messages that fail the guard: only `lastLineMs`.
    case other
}

/// One classified transcript entry of an OpenClaw window: Pi's session entry format (METRICS 4.13, 4.14).
enum OpenClawLine: Equatable, Sendable {
    /// A `session` entry; the header has the omp shape.
    case header(OmpSession)
    /// An entry with a string `id` and a parseable `timestamp`.
    case entry(id: String, timestampMs: Int64, record: OpenClawRecord)
    /// Entries without a string `id` or a parseable `timestamp`.
    case ignored
}

/// Decodes OpenClaw transcript entries. Conversation content is skipped (only validated). Repeated members resolve like
/// Python's `json.loads`: the last one wins.
enum OpenClawLineExtractor {
    private static let types: [StaticString] = ["session", "message"]
    private static let roles: [StaticString] = ["user", "developer", "assistant", "toolResult"]
    private static let stopReasons: [StaticString] = ["stop", "length", "toolUse", "error", "aborted"]

    static func extract(_ bytes: UnsafeRawBufferPointer) -> LineExtraction<OpenClawLine> {
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
        var unavailable = false

        var tokens: TokenUsage {
            TokenUsage(
                input: TokenCount.sum(input, cacheRead, cacheWrite),
                cachedInput: cacheRead,
                cacheWriteInput: cacheWrite,
                cacheWrite1hInput: min(cacheWrite1h, cacheWrite),
                output: output,
                reasoning: reasoning
            )
        }

        var hasUsage: Bool { input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0 }
    }

    private struct MessageMembers {
        var role: Int?
        var model: String?
        var isProviderString = false
        var provider: String?
        var providerIsACP = false
        var api: String?
        var isApiString = false
        var usage: Usage?
        var timestamp: JSONNumber?
        var stopReason: Int?
        var toolCallIds: Set<String> = []
        var toolCallId: String?
        var hasMirrorOrigin = false

        func record() -> OpenClawRecord {
            switch role {
            case 0, 1:
                return .input
            case 2:
                guard let model, isProviderString, isApiString, let usage else { return .other }
                let isCLI = api == "cli"
                let stop = stopReason ?? -1
                return .assistant(OpenClawAssistant(
                    model: model,
                    provider: provider.flatMap { $0.isEmpty ? nil : $0 },
                    tokens: usage.tokens,
                    hasUsage: usage.hasUsage,
                    usageUnavailable: usage.unavailable,
                    startedMs: timestamp.flatMap { $0.isFinite && $0.isPositive ? $0.truncated : nil },
                    stopRunsTools: (0...2).contains(stop),
                    stopIsFailure: !(0...2).contains(stop),
                    isCLI: isCLI,
                    isMirror: hasMirrorOrigin || (isCLI && provider == "claude-cli") || providerIsACP,
                    toolCallIds: toolCallIds
                ))
            case 3:
                return .toolResult(callId: toolCallId)
            default:
                return .other
            }
        }
    }

    private struct TopLevel {
        var type: Int?
        var id: String?
        var timestampMs: Int64?
        var cwd: String?
        var message: MessageMembers?

        func classified() -> OpenClawLine {
            if type == 0 { return .header(OmpSession(id: id, timestampMs: timestampMs, cwd: cwd)) }
            guard let id, let timestampMs else { return .ignored }
            let record: OpenClawRecord = type == 1 ? message?.record() ?? .other : .other
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
                let value = try scanner.readStringValue()
                message.isProviderString = value != nil
                message.provider = value.flatMap { $0 }
                message.providerIsACP = message.provider?.hasPrefix("acp-") == true
            } else if scanner.key(key, is: "api") {
                let value = try scanner.readStringValue()
                message.isApiString = value != nil
                message.api = value.flatMap { $0 }
            } else if scanner.key(key, is: "usage") {
                message.usage = try scanUsage(&scanner)
            } else if scanner.key(key, is: "timestamp") {
                message.timestamp = try scanner.readNumber()
            } else if scanner.key(key, is: "stopReason") {
                message.stopReason = try scanner.readStringMatch(stopReasons)
            } else if scanner.key(key, is: "content") {
                message.toolCallIds = try OmpLineExtractor.scanToolCallIds(&scanner)
            } else if scanner.key(key, is: "toolCallId") {
                message.toolCallId = try scanner.readString()
            } else if scanner.key(key, is: "__openclaw") {
                message.hasMirrorOrigin = try scanMirrorOrigin(&scanner)
            } else {
                try scanner.skipValue()
            }
        }
        return message
    }

    /// `__openclaw.mirrorOrigin` is a non-empty string.
    private static func scanMirrorOrigin(_ scanner: inout JSONScanner) throws(JSONScanError) -> Bool {
        guard try scanner.beginObjectIfPresent() else { return false }
        var found = false
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "mirrorOrigin") {
                found = try scanner.readStringIsNonEmpty() == true
            } else {
                try scanner.skipValue()
            }
        }
        return found
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
            } else if scanner.key(key, is: "reasoningTokens") {
                usage.reasoning = TokenCount.clamp(try scanner.readNumber()?.truncated)
            } else if scanner.key(key, is: "usageReport") {
                usage.unavailable = try scanUsageReport(&scanner)
            } else {
                try scanner.skipValue()
            }
        }
        return usage
    }

    /// `usageReport.state == "unavailable"`.
    private static func scanUsageReport(_ scanner: inout JSONScanner) throws(JSONScanError) -> Bool {
        guard try scanner.beginObjectIfPresent() else { return false }
        var unavailable = false
        while let key = try scanner.nextMember() {
            if scanner.key(key, is: "state") {
                unavailable = try scanner.readStringMatch(["unavailable"]) == 0
            } else {
                try scanner.skipValue()
            }
        }
        return unavailable
    }
}

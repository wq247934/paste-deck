import Foundation
import Testing
@testable import AgentSpeedCore

/// Work signals inside the monitor (METRICS 6.10): actions start with a file's live lines and reach the agents list.
@Suite("Work signals in the monitor")
struct WorkSignalSessionTests {
    static let relative = "claude/projects/-w-loop/s-loop.jsonl"

    static func line(_ ms: Int64, _ type: String, _ message: String) -> String {
        let time = Date(timeIntervalSince1970: TimeInterval(ms) / 1000).ISO8601Format()
        return #"{"type":"\#(type)","entrypoint":"cli","cwd":"/w/loop","timestamp":"\#(time)","message":\#(message)}"#
    }

    /// A failing `Bash` run of the same command, as one assistant and one user line.
    static func failingRun(_ index: Int, at ms: Int64) -> [String] {
        let call = #"{"type":"tool_use","id":"t\#(index)","name":"Bash","input":{"command":"swift test"}}"#
        return [
            line(ms, "assistant", #"{"id":"m\#(index)","model":"claude-opus-5-5","stop_reason":"tool_use","content":[\#(call)],"usage":{"output_tokens":5}}"#),
            line(ms + 500, "user", #"{"content":[{"type":"tool_result","tool_use_id":"t\#(index)","is_error":true,"content":"failed"}]}"#),
        ]
    }

    @Test func seededLinesAddNoActionsAndLiveOnesLoop() throws {
        let directory = try TempDirectory()
        let now = Clock.milliseconds(Date())
        _ = try directory.write(Self.relative, (0..<3).flatMap { Self.failingRun($0, at: now - 60_000 + Int64($0) * 2000) }
            .joined(separator: "\n") + "\n")
        let configuration = MonitorConfiguration(enabledSources: [.claudeCode], claudeRoot: directory.file("claude/projects"))
        let session = TranscriptSession(configuration: configuration)
        _ = session.seed(todayStartMs: SessionTests.startOfToday())
        let seeded = session.advance(nowMs: now, todayStartMs: SessionTests.startOfToday(), emitsEvents: true).output
        #expect(seeded.agents.count == 1)
        #expect(seeded.agents.first?.signals == WorkSignals.none)

        try directory.append(Self.relative, (3..<6).flatMap { Self.failingRun($0, at: now - 20_000 + Int64($0) * 2000) }
            .joined(separator: "\n") + "\n")
        #expect(session.rediscover(todayStartMs: SessionTests.startOfToday()))
        let live = session.advance(nowMs: now, todayStartMs: SessionTests.startOfToday(), emitsEvents: true).output
        let signals = try #require(live.agents.first?.signals)
        #expect(signals.looping == 3)
        #expect(signals.failed == 3 && signals.recovered == 0)
        _ = directory
    }

    /// Pi lines (METRICS 4.13) through the shared omp-format reader: a tool call, then its failed result.
    static let piLines = [
        #"{"type":"session","version":3,"id":"s1","timestamp":"2026-10-20T12:00:00.000Z","cwd":"/w/halo"}"#,
        #"{"type":"message","id":"a1","timestamp":"2026-10-20T12:00:03.000Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"c1","name":"read","arguments":{"path":"src/queue.ts"}}],"api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":{"input":1,"output":5,"cacheRead":0,"cacheWrite":0},"stopReason":"toolUse","timestamp":1792497601005}}"#,
        #"{"type":"message","id":"t1","timestamp":"2026-10-20T12:00:03.500Z","message":{"role":"toolResult","toolCallId":"c1","toolName":"read","isError":true,"content":[],"timestamp":1792497603500}}"#,
    ]

    @Test func piToolCallsAndResultsBecomeActions() {
        var deduper = Deduper()
        let (parser, _) = ParserBehaviorTests.run(.pi, Self.piLines, path: "/w/pi/s1.jsonl", deduper: &deduper)
        #expect(parser.state.actions.actions.map(\.call.tool) == ["read"])
        #expect(parser.state.actions.actions.map(\.failed) == [true])
    }

    @Test func copiedHistoryAddsNoActions() {
        var deduper = Deduper()
        let lines = Self.failingRun(0, at: 1_000_000)
        _ = ParserBehaviorTests.run(.claude, lines, path: "/a/s1.jsonl", deduper: &deduper, fileID: 0)
        let (copy, _) = ParserBehaviorTests.run(.claude, lines, path: "/a/s2.jsonl", deduper: &deduper, fileID: 1)
        #expect(copy.state.actions.actions.isEmpty)
    }
}

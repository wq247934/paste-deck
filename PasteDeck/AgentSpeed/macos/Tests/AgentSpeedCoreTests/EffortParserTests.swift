import Foundation
import Testing
@testable import AgentSpeedCore

/// Reasoning effort and speed per native source (EXECUTION-MODES, Native rules).
@Suite("Reasoning effort parsing")
struct EffortParserTests {
    private static func assistant(_ ts: String, id: String, effort: String? = nil, perTurn: String? = nil,
                                  speed: String? = nil, stop: String = #""end_turn""#) -> String {
        var line = ParserBehaviorTests.claudeAssistant(ts, id: id, output: 10, stop: stop)
        if let speed {
            line = line.replacingOccurrences(of: #""output_tokens":10"#, with: #""output_tokens":10,"speed":"\#(speed)""#)
        }
        let fields = [effort.map { #""effort":"\#($0)""# }, perTurn.map { #""perTurnEffort":"\#($0)""# }].compactMap { $0 }
        return fields.isEmpty ? line : line.replacingOccurrences(of: #"{"type":"assistant","#,
                                                                 with: "{" + fields.joined(separator: ",") + #","type":"assistant","#)
    }

    private static func attachment(_ ts: String, _ type: String) -> String {
        #"{"type":"attachment","attachment":{"type":"\#(type)"},"timestamp":"\#(ts)"}"#
    }

    private static func prompt(_ ts: String) -> String {
        ParserBehaviorTests.claudeUser(ts, content: #""go""#)
    }

    private static func meta(_ ts: String) -> String {
        #"{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"x"}]},"timestamp":"\#(ts)"}"#
    }

    private static func toolResult(_ ts: String) -> String {
        ParserBehaviorTests.claudeUser(ts, content: #"[{"type":"tool_result","tool_use_id":"t","content":"x"}]"#)
    }

    private func efforts(_ upserts: [ResponseUpsert]) -> [String?] {
        upserts.filter(\.isCompletion).map { $0.record.modes.effortAndSpeed.effort?.mode }
    }

    @Test func claudeRecordedEffortPrefersPerTurnEffort() {
        var deduper = Deduper()
        let (parser, upserts) = ParserBehaviorTests.run(.claude, [
            Self.prompt("2026-10-24T10:00:00Z"),
            Self.assistant("2026-10-24T10:00:01Z", id: "a", effort: "xhigh", perTurn: "max", speed: "fast"),
            Self.assistant("2026-10-24T10:00:02Z", id: "b", effort: "HIGH"),
            Self.assistant("2026-10-24T10:00:03Z", id: "c"),
            Self.assistant("2026-10-24T10:00:04Z", id: "d", effort: "xhigh", perTurn: "default"),
        ], deduper: &deduper)
        #expect(efforts(upserts) == ["max", "high", nil, nil])
        let first = upserts[0].record.modes.effortAndSpeed
        #expect(first.speed == ExecutionModeAttribution(kind: .speed, mode: "fast", evidence: "served", provider: "anthropic"))
        #expect(first.effort?.evidence == "recorded" && first.bolts == 1)
        // The current effort keeps the latest recorded one; the speed is the latest response's (unknown here).
        #expect(parser.state.modes.effortAndSpeed == .init(effort: .init(kind: .effort, mode: "high", evidence: "recorded"), speed: nil))
    }

    @Test func claudeUltracodeSessionFollowsEnterAndExit() {
        var deduper = Deduper()
        var lines = [
            Self.prompt("2026-10-24T10:00:00Z"),
            Self.attachment("2026-10-24T10:00:00.500Z", "ultra_effort_enter"),
            Self.assistant("2026-10-24T10:00:01Z", id: "a", effort: "xhigh"),
            Self.prompt("2026-10-24T10:00:02Z"),
            Self.attachment("2026-10-24T10:00:02.500Z", "ultra_effort_enter"),
            Self.assistant("2026-10-24T10:00:03Z", id: "b", effort: "xhigh"),
        ]
        let (on, onUpserts) = ParserBehaviorTests.run(.claude, lines, deduper: &deduper)
        #expect(efforts(onUpserts) == ["ultracode", "ultracode"])
        #expect(on.state.modes.effortAndSpeed.effort?.mode == "ultracode")
        lines += [Self.attachment("2026-10-24T10:00:04Z", "ultra_effort_exit")]
        var second = Deduper()
        let (off, _) = ParserBehaviorTests.run(.claude, lines, deduper: &second)
        #expect(off.state.modes.effortAndSpeed.effort?.mode == "xhigh")
        lines += [Self.prompt("2026-10-24T10:00:05Z"), Self.assistant("2026-10-24T10:00:06Z", id: "c", effort: "medium")]
        var third = Deduper()
        let (_, afterUpserts) = ParserBehaviorTests.run(.claude, lines, deduper: &third)
        #expect(efforts(afterUpserts) == ["ultracode", "ultracode", "medium"])
    }

    @Test func claudeKeywordTurnLastsUntilTheNextPrompt() {
        var deduper = Deduper()
        let (parser, upserts) = ParserBehaviorTests.run(.claude, [
            Self.prompt("2026-10-24T10:00:00Z"),
            Self.attachment("2026-10-24T10:00:00.100Z", "workflow_keyword_request"),
            Self.meta("2026-10-24T10:00:00.200Z"),
            Self.assistant("2026-10-24T10:00:01Z", id: "a", effort: "high", stop: #""tool_use""#),
            Self.toolResult("2026-10-24T10:00:02Z"),
            Self.assistant("2026-10-24T10:00:03Z", id: "b", effort: "high"),
        ], deduper: &deduper)
        // Meta lines and tool results are not prompts, so the turn stays ultracode.
        #expect(efforts(upserts) == ["ultracode", "ultracode"])
        #expect(parser.state.modes.effortAndSpeed.effort?.mode == "ultracode")
        var next = Deduper()
        let (ended, endedUpserts) = ParserBehaviorTests.run(.claude, [
            Self.attachment("2026-10-24T10:00:00Z", "workflow_keyword_request"),
            Self.assistant("2026-10-24T10:00:01Z", id: "a", effort: "high"),
            ParserBehaviorTests.claudeUser("2026-10-24T10:00:02Z", content: #"[{"type":"text","text":"[Request interrupted by user]"}]"#),
        ], deduper: &next)
        #expect(efforts(endedUpserts) == ["ultracode"])
        // An interrupt is a prompt line: the turn ends and the current effort is the recorded one again.
        #expect(ended.state.modes.effortAndSpeed.effort?.mode == "high")
    }

    @Test func claudeUltracodeNeverReachesSubAgents() {
        var deduper = Deduper()
        let main = [
            Self.attachment("2026-10-24T10:00:00Z", "ultra_effort_enter"),
            Self.assistant("2026-10-24T10:00:01Z", id: "main", effort: "xhigh"),
        ]
        let child = [
            #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"task"},"timestamp":"2026-10-24T10:00:02Z"}"#,
            Self.assistant("2026-10-24T10:00:03Z", id: "child", effort: "medium"),
        ]
        let (parent, _) = ParserBehaviorTests.run(.claude, main, path: "/p/s.jsonl", deduper: &deduper)
        let (sub, upserts) = ParserBehaviorTests.run(.claude, child, path: "/p/s/subagents/agent-1.jsonl", deduper: &deduper, fileID: 1)
        #expect(parent.state.modes.effortAndSpeed.effort?.mode == "ultracode")
        #expect(efforts(upserts) == ["medium"])
        #expect(sub.state.modes.effortAndSpeed.effort?.mode == "medium")
    }

    private static func settings(_ ts: String, _ body: String) -> String {
        #"{"type":"event_msg","timestamp":"\#(ts)","payload":{"type":"thread_settings_applied","thread_settings":{\#(body)}}}"#
    }

    private static func turn(_ ts: String, _ body: String = "") -> String {
        #"{"type":"turn_context","timestamp":"\#(ts)","payload":{"model":"m"\#(body.isEmpty ? "" : "," + body)}}"#
    }

    private static func usage(_ ts: String, _ id: String, tier: String? = nil) -> String {
        let field = tier.map { #","service_tier":"\#($0)""# } ?? ""
        return #"{"type":"token_usage_record","timestamp":"\#(ts)","payload":{"response_id":"\#(id)"\#(field),"usage":{"input_tokens":3,"output_tokens":40,"total_tokens":43}}}"#
    }

    private func views(_ upserts: [ResponseUpsert]) -> [EffortAndSpeed] { upserts.map { $0.record.modes.effortAndSpeed } }

    @Test func codexThreadSettingsLastUntilChangedOrCleared() {
        var deduper = Deduper()
        let (parser, upserts) = ParserBehaviorTests.run(.codex, [
            Self.settings("2026-10-24T10:00:00Z", #""service_tier":"priority","reasoning_effort":"xhigh""#),
            Self.usage("2026-10-24T10:00:01Z", "r1"),
            Self.settings("2026-10-24T10:00:02Z", #""service_tier":"ultrafast""#),
            Self.usage("2026-10-24T10:00:03Z", "r2"),
            Self.settings("2026-10-24T10:00:04Z", #""service_tier":null,"reasoning_effort":"ultra""#),
            Self.usage("2026-10-24T10:00:05Z", "r3"),
        ], deduper: &deduper)
        let selected = { (mode: String) in ExecutionModeAttribution(kind: .speed, mode: mode, evidence: "selected", provider: "openai") }
        #expect(views(upserts).map(\.speed) == [selected("fast"), selected("ultrafast"), nil])
        #expect(views(upserts).map { $0.effort?.mode } == ["xhigh", "xhigh", "ultra"])
        #expect(views(upserts).map { $0.effort?.evidence } == ["selected", "selected", "selected"])
        #expect(parser.state.modes.effortAndSpeed.effort?.mode == "ultra")
        #expect(parser.state.modes.effortAndSpeed.speed == nil)
    }

    @Test func codexTurnFactsAreReplacedAtEveryTurnContext() {
        var deduper = Deduper()
        let (parser, upserts) = ParserBehaviorTests.run(.codex, [
            Self.settings("2026-10-24T10:00:00Z", #""reasoning_effort":"high""#),
            Self.turn("2026-10-24T10:00:01Z", #""effort":"max","service_tier":"priority""#),
            Self.usage("2026-10-24T10:00:02Z", "r1"),
            Self.usage("2026-10-24T10:00:03Z", "r2"),
            Self.turn("2026-10-24T10:00:04Z", #""collaboration_mode":{"mode":"default","settings":{"reasoning_effort":"medium"}}"#),
            Self.usage("2026-10-24T10:00:05Z", "r3"),
            Self.turn("2026-10-24T10:00:06Z"),
            Self.usage("2026-10-24T10:00:07Z", "r4"),
        ], deduper: &deduper)
        // Responding never clears turn facts; a new turn replaces them; without any the session setting shows again.
        #expect(views(upserts).map { $0.effort?.mode } == ["max", "max", "medium", "high"])
        #expect(views(upserts).map { $0.effort?.evidence } == ["recorded", "recorded", "recorded", "selected"])
        #expect(views(upserts).map { $0.speed?.mode } == ["fast", "fast", nil, nil])
        #expect(parser.state.modes.effortAndSpeed.effort == .init(kind: .effort, mode: "high", evidence: "selected"))
    }

    @Test func codexRequestTierStaysInItsResponse() {
        var deduper = Deduper()
        let (parser, upserts) = ParserBehaviorTests.run(.codex, [
            Self.settings("2026-10-24T10:00:00Z", #""service_tier":"default""#),
            Self.usage("2026-10-24T10:00:01Z", "r1", tier: "priority"),
            Self.usage("2026-10-24T10:00:02Z", "r2"),
        ], deduper: &deduper)
        #expect(views(upserts).map(\.speed) == [
            .init(kind: .speed, mode: "fast", evidence: "recorded", provider: "openai"),
            .init(kind: .speed, mode: "standard", evidence: "selected", provider: "openai"),
        ])
        #expect(parser.state.modes.facts.allSatisfy { $0.scope != .request })
        #expect(parser.state.modes.effortAndSpeed.speed?.mode == "standard")
        // A sub-agent rollout starts with its own empty context.
        var other = Deduper()
        let (_, child) = ParserBehaviorTests.run(.codex, [Self.usage("2026-10-24T10:00:03Z", "r3")], deduper: &other, fileID: 2)
        #expect(child.first?.record.modes.facts.isEmpty == true)
    }

    @Test func opencodeVariantIsTheRecordedEffort() throws {
        func parse(_ model: String) throws -> OpencodeMessageData {
            let json = #"{"model":\#(model),"tokens":{"input":1,"output":12}}"#
            return try #require(Data(json.utf8).withUnsafeBytes(OpencodeDataExtractor.extract))
        }
        let row = try parse(#"{"id":"m","providerID":"anthropic","variant":"xhigh"}"#)
        #expect(row.modes.effortAndSpeed.effort == .init(kind: .effort, mode: "xhigh", evidence: "recorded"))
        #expect(try parse(#"{"id":"m","providerID":"openai","variant":"default"}"#).modes.facts.isEmpty)
        #expect(try parse(#"{"id":"m","variant":"none"}"#).modes.effortAndSpeed.effort?.mode == "off")
        #expect(try parse(#""m""#).modes.facts.isEmpty)
    }
}

import Darwin
import Foundation
import Testing
@testable import AgentSpeedCore

/// Factory Droid inside the live session and the daily history (METRICS 4.16): both write orders, a restored lower
/// sidecar, a replaced transcript, sessions older than the startup window, Task-tool workers and forks, the folder
/// setting, history by the session's files and the live monitor's watcher.
@Suite("Factory Droid session")
struct DroidSessionTests {
    static let base: Int64 = 1_792_497_600_000

    static func iso(_ ms: Int64) -> String { OmpSessionTests.iso(ms) }

    static func start(_ id: String, cwd: String = "/w/forge", parent: String? = nil, calling: String? = nil) -> String {
        var line = #"{"type":"session_start","id":"\#(id)","title":"t","owner":"dev","version":2,"cwd":"\#(cwd)""#
        if let parent { line += #","parent":"\#(parent)""# }
        if let calling { line += #","callingSessionId":"\#(calling)","callingToolUseId":"toolu_x""# }
        return line + "}\n"
    }

    static func user(_ id: String, _ ms: Int64, visibility: String? = nil) -> String {
        let extra = visibility.map { #","visibility":"\#($0)""# } ?? ""
        return #"{"type":"message","id":"\#(id)","timestamp":"\#(iso(ms))","parentId":null,"message":{"role":"user","content":[{"type":"text","text":"(omitted)"}]\#(extra)}}"# + "\n"
    }

    static func assistant(_ id: String, _ ms: Int64, tools: Bool = false, model: String = "claude-opus-5-5") -> String {
        let block = tools ? #"{"type":"tool_use","id":"toolu_\#(id)","name":"Read","input":{}}"# : #"{"type":"text","text":"(omitted)"}"#
        return #"{"type":"message","id":"\#(id)","timestamp":"\#(iso(ms))","parentId":null,"message":{"role":"assistant","content":[\#(block)],"modelId":"\#(model)","reasoningEffort":"high"}}"# + "\n"
    }

    static let outcome = #"{"type":"agent_turn_outcome","turnId":"t","reason":"completed","resultKind":"text"}"# + "\n"

    static func sidecar(_ input: Int, _ cacheWrite: Int, _ cacheRead: Int, _ output: Int, _ thinking: Int,
                        model: String = "claude-opus-5-5") -> String {
        #"{"model":"\#(model)","reasoningEffort":"high","tokenUsage":{"inputTokens":\#(input),"outputTokens":\#(output),"cacheCreationTokens":\#(cacheWrite),"cacheReadTokens":\#(cacheRead),"thinkingTokens":\#(thinking),"factoryCredits":0}}"#
    }

    struct Home {
        let directory = try! TempDirectory()
        var configuration: MonitorConfiguration

        init() {
            try? FileManager.default.createDirectory(at: directory.file(".factory/sessions"), withIntermediateDirectories: true)
            configuration = MonitorConfiguration(enabledSources: [.droid], droidRoot: directory.file(".factory"))
        }

        func path(_ relative: String) -> String { directory.file(".factory/sessions/" + relative).path }

        func write(_ relative: String, _ text: String, modified: Date? = nil) throws {
            try directory.write(".factory/sessions/" + relative, text, modified: modified)
        }

        func append(_ relative: String, _ text: String) throws {
            try directory.append(".factory/sessions/" + relative, text)
        }

        /// Writes `relative` through a new file renamed over it (a new identity), as droid replaces its sidecar.
        func replace(_ relative: String, _ text: String, modified: Date? = nil) throws {
            try write(relative + ".new", text, modified: modified)
            #expect(Darwin.rename(path(relative + ".new"), path(relative)) == 0)
        }

        /// The path the file watcher reports.
        func canonical(_ relative: String) -> String {
            let path = path(relative)
            guard let resolved = realpath((path as NSString).deletingLastPathComponent, nil) else { return path }
            defer { free(resolved) }
            return (String(cString: resolved) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        }
    }

    static func responses(_ session: TranscriptSession) -> [String: ResponseRecord] {
        Dictionary(uniqueKeysWithValues: session.responses.map { ($0.key, $0) })
    }

    static func usage(_ input: Int, cached: Int, write: Int, output: Int, reasoning: Int) -> TokenUsage {
        TokenUsage(input: input, cachedInput: cached, cacheWriteInput: write, output: output, reasoning: reasoning)
    }

    @Test func callsGetTheirTokensWhicheverFileDroidWritesFirst() throws {
        let home = Home()
        try home.write("-w-forge/s1.jsonl", Self.start("s1") + Self.user("u1", Self.base + 1000)
            + Self.assistant("m1", Self.base + 4000, tools: true))
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        #expect(session.seed(todayStartMs: Self.base).filesRead == 1)
        #expect(session.responses.isEmpty, "no counters yet: the call waits")
        #expect(session.watchedPaths == [(home.canonical("-w-forge/s1.jsonl") as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/-w-forge", with: "")])

        // The sidecar after the line: the call takes the whole rewrite.
        try home.write("-w-forge/s1.settings.json", Self.sidecar(1000, 4000, 0, 120, 30))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.settings.json")]))
        var responses = Self.responses(session)
        #expect(responses["droid:m1"]?.usage == Self.usage(5000, cached: 0, write: 4000, output: 120, reasoning: 30))
        #expect(responses["droid:m1"]?.startMs == Self.base + 1000 && responses["droid:m1"]?.endMs == Self.base + 4000)
        #expect(responses["droid:m1"]?.modes.effortAndSpeed.effort?.mode == "high")

        // The sidecar before the line: its growth waits for the call.
        try home.replace("-w-forge/s1.settings.json", Self.sidecar(1200, 4000, 4800, 200, 30))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.settings.json")]))
        #expect(session.responses.count == 1)
        try home.append("-w-forge/s1.jsonl", Self.user("r1", Self.base + 4200) + Self.assistant("m2", Self.base + 6000) + Self.outcome)
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.jsonl")]))
        responses = Self.responses(session)
        #expect(responses["droid:m2"]?.usage == Self.usage(5000, cached: 4800, write: 0, output: 80, reasoning: 0))
        #expect(responses["droid:m2"]?.startMs == Self.base + 4200)

        let (output, events) = session.advance(nowMs: Self.base + 10_000, todayStartMs: Self.base, emitsEvents: true)
        let completions = events.filter { if case .responseCompleted = $0 { true } else { false } }
        #expect(completions.count == 2)
        #expect(output.todayBySource[.droid]?.output == 200 && output.todayBySource[.droid]?.requests == 2)
        #expect(output.agents.first?.agent.project == "forge" && output.agents.first?.phase == .idle)
        #expect(!session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.settings.json.bak")]), "never read")
    }

    @Test func aRestoredLowerSidecarAddsNothingAndGrowthAboveItCounts() throws {
        let home = Home()
        try home.write("-w-forge/s1.jsonl", Self.start("s1") + Self.user("u1", Self.base + 1000) + Self.assistant("m1", Self.base + 4000))
        try home.write("-w-forge/s1.settings.json", Self.sidecar(1000, 4000, 0, 120, 30))
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(Self.responses(session)["droid:m1"]?.usage.output == 120)

        // droid's `.bak` renamed back: older than the transcript, so only the sidecar's own identity tells.
        try home.write("-w-forge/s1.settings.json.bak", Self.sidecar(500, 0, 0, 60, 0),
                       modified: Date(timeIntervalSince1970: TimeInterval(Self.base) / 1000))
        #expect(Darwin.rename(home.path("-w-forge/s1.settings.json.bak"), home.path("-w-forge/s1.settings.json")) == 0)
        #expect(session.pollRecentFiles(nowMs: Clock.milliseconds(Date())), "the 1-second fallback notices the sidecar")
        #expect(session.responses.count == 1 && Self.responses(session)["droid:m1"]?.usage.output == 120)
        #expect(!session.pollRecentFiles(nowMs: Clock.milliseconds(Date())), "nothing changed since")

        try home.append("-w-forge/s1.jsonl", Self.user("u2", Self.base + 5000) + Self.assistant("m2", Self.base + 7000))
        try home.replace("-w-forge/s1.settings.json", Self.sidecar(1100, 4000, 0, 150, 30))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.jsonl"), home.canonical("-w-forge/s1.settings.json")]))
        #expect(Self.responses(session)["droid:m2"]?.usage == Self.usage(100, cached: 0, write: 0, output: 30, reasoning: 0))
    }

    @Test func aReplacedTranscriptIsReadAgainFromTheStart() throws {
        let home = Home()
        let lines = Self.start("s1") + Self.user("u1", Self.base + 1000) + Self.assistant("m1", Self.base + 4000)
        try home.write("-w-forge/s1.jsonl", lines)
        try home.write("-w-forge/s1.settings.json", Self.sidecar(1000, 0, 9000, 100, 10))
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        _ = session.seed(todayStartMs: Self.base)
        try home.append("-w-forge/s1.jsonl", Self.user("u2", Self.base + 5000) + Self.assistant("m2", Self.base + 7000))
        try home.replace("-w-forge/s1.settings.json", Self.sidecar(1500, 0, 13000, 160, 10))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.jsonl")]))
        #expect(Self.responses(session)["droid:m2"]?.usage.output == 60)

        try home.replace("-w-forge/s1.jsonl", lines + Self.user("u2", Self.base + 5000) + Self.assistant("m2", Self.base + 7000)
            + Self.user("u3", Self.base + 8000) + Self.assistant("m3", Self.base + 9000))
        try home.replace("-w-forge/s1.settings.json", Self.sidecar(1800, 0, 16000, 200, 10))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-forge/s1.jsonl")]))
        let records = session.responses
        #expect(Set(records.map(\.key)) == ["droid:m1", "droid:m2", "droid:m3"])
        #expect(records.reduce(0) { $0 + $1.usage.input } == 17_800 && records.reduce(0) { $0 + $1.usage.output } == 200,
                "the whole own counters, split again by weight")
        #expect(records.reduce(0) { $0 + $1.usage.reasoning } == 10)
    }

    @Test func anOlderSessionStartsAtItsEndWithItsCountersAsBaseline() throws {
        let home = Home()
        let yesterday = Date(timeIntervalSince1970: TimeInterval(Self.base - 86_400_000) / 1000)
        try home.write("-w-old/s2.jsonl", Self.start("s2", cwd: "/w/old") + Self.user("v1", Self.base - 86_400_000)
            + Self.assistant("o1", Self.base - 86_396_000) + Self.outcome, modified: yesterday)
        try home.write("-w-old/s2.settings.json", Self.sidecar(50_000, 0, 200_000, 9000, 1000, model: "gpt-5.5"),
                       modified: yesterday)
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        let summary = session.seed(todayStartMs: Self.base)
        #expect(summary.filesDiscovered == 1 && summary.filesRead == 0 && session.responses.isEmpty)

        try home.append("-w-old/s2.jsonl", Self.user("v2", Self.base + 5000) + Self.assistant("o2", Self.base + 7000, model: "gpt-5.5"))
        try home.replace("-w-old/s2.settings.json", Self.sidecar(50_400, 0, 210_000, 9080, 1010, model: "gpt-5.5"))
        #expect(session.handleChanges(atCanonicalPaths: [home.canonical("-w-old/s2.settings.json")]))
        #expect(session.responses.map(\.key) == ["droid:o2"])
        #expect(session.responses.first?.usage == Self.usage(10_400, cached: 10_000, write: 0, output: 80, reasoning: 10))
        #expect(session.responses.first?.model == "gpt-5.5")
    }

    /// The main session, its Task-tool worker, a fork that copies the main session's first call, and a session whose
    /// counters belong to no call; written in that order.
    static func family(in home: Home) throws {
        let now = Date()
        try home.write("-w-forge/s-main.jsonl", Self.start("s-main") + Self.user("u1", Self.base + 1000)
            + Self.assistant("m1", Self.base + 4000, tools: true), modified: now.addingTimeInterval(-40))
        try home.write("-w-forge/s-main.settings.json", Self.sidecar(1000, 0, 0, 100, 0), modified: now.addingTimeInterval(-41))
        try home.write("-w-forge/s-work.jsonl", Self.start("s-work", calling: "s-main") + Self.user("w0", Self.base + 4100)
            + Self.assistant("w1", Self.base + 5000), modified: now.addingTimeInterval(-30))
        try home.write("-w-forge/s-work.settings.json", Self.sidecar(300, 0, 0, 30, 0), modified: now.addingTimeInterval(-31))
        try home.write("-w-forge/s-fork.jsonl", Self.start("s-fork", parent: "s-main") + Self.user("u1", Self.base + 1000)
            + Self.assistant("m1", Self.base + 4000, tools: true) + Self.user("f0", Self.base + 6000)
            + Self.assistant("f1", Self.base + 8000), modified: now.addingTimeInterval(-20))
        try home.write("-w-forge/s-fork.settings.json", Self.sidecar(1500, 0, 0, 160, 0), modified: now.addingTimeInterval(-21))
        try home.write("s-none.jsonl", Self.start("s-none") + Self.user("n0", Self.base + 9000, visibility: "user_only"),
                       modified: now.addingTimeInterval(-10))
        try home.write("s-none.settings.json", Self.sidecar(70, 0, 0, 5, 0), modified: now.addingTimeInterval(-11))
    }

    @Test func workersLinkToTheirCallerAndForksStartFromTheirParent() throws {
        let home = Home()
        try Self.family(in: home)
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        #expect(session.seed(todayStartMs: Self.base).filesRead == 4)
        let responses = Self.responses(session)
        #expect(Set(responses.keys) == ["droid:m1", "droid:w1", "droid:f1"], "the fork's copy is the main session's; no call, no response")
        #expect(responses["droid:m1"]?.agentId == home.path("-w-forge/s-main.jsonl") && responses["droid:m1"]?.usage.output == 100)
        #expect(responses["droid:w1"]?.usage == Self.usage(300, cached: 0, write: 0, output: 30, reasoning: 0))
        #expect(responses["droid:f1"]?.usage == Self.usage(500, cached: 0, write: 0, output: 60, reasoning: 0), "own counters only")
        let (output, _) = session.advance(nowMs: Self.base + 10_000, todayStartMs: Self.base, emitsEvents: false)
        let agents = Dictionary(uniqueKeysWithValues: output.agents.map { ($0.agent.id, $0) })
        #expect(agents[home.path("-w-forge/s-work.jsonl")]?.parentId == home.path("-w-forge/s-main.jsonl"))
        #expect(agents[home.path("-w-forge/s-work.jsonl")]?.agent.isSubagent == true)
        #expect(agents[home.path("-w-forge/s-fork.jsonl")]?.parentId == nil, "a fork is a root agent")
        #expect(session.sessionCounts(todayStartMs: Self.base)[.droid] == 3, "the worker is not a session")
        #expect(session.root(for: .droid).path == home.directory.file(".factory/sessions").path)
    }

    @Test func theHistoryKeepsEachSessionByItsFiles() throws {
        let home = Home()
        try Self.family(in: home)
        let store = home.directory.file("history.sqlite").path
        func run() throws -> HistoryScanReport {
            try HistoryScan.run(configuration: home.configuration, timeZone: HistoryTests.utc, storePath: store)
        }
        var report = try run()
        #expect(report.filesAnalyzed == 4)
        #expect(report.days.map(\.totals.requests) == [4] && report.days.map(\.totals.output) == [195],
                "three calls and the session without one")
        #expect(try run().filesAnalyzed == 0)

        try home.replace("-w-forge/s-work.settings.json", Self.sidecar(400, 0, 0, 40, 0))
        report = try run()
        #expect(report.filesAnalyzed == 1 && report.days.map(\.totals.output) == [205])

        // The fork subtracts its parent's counters, so a new parent sidecar analyses both again.
        try home.replace("-w-forge/s-main.settings.json", Self.sidecar(1200, 0, 0, 120, 0))
        report = try run()
        #expect(report.filesAnalyzed == 2 && report.days.map(\.totals.output) == [120 + 40 + 40 + 5])
        #expect(try run().filesAnalyzed == 0)
    }

    @Test func anUnreadableParentSidecarIsRetriedByTheNextReadCycle() throws {
        let home = Home()
        let cutOff = #"{"model":"claude-opus-5-5","tokenUsage":{"inputTokens":4"#
        for (parent, fork) in [("p-1", "k-1"), ("p-2", "k-2")] {
            try home.write("-w-forge/\(parent).jsonl", Self.start(parent) + Self.user("u-\(parent)", Self.base + 1000)
                + Self.assistant("m-\(parent)", Self.base + 4000))
            try home.write("-w-forge/\(parent).settings.json", cutOff)
            try home.write("-w-forge/\(fork).jsonl", Self.start(fork, parent: parent) + Self.user("u-\(fork)", Self.base + 6000)
                + Self.assistant("m-\(fork)", Self.base + 8000))
            try home.write("-w-forge/\(fork).settings.json", Self.sidecar(1500, 0, 0, 160, 0))
        }
        let session = TranscriptSession(configuration: home.configuration, clock: { Self.base + 10_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(session.responses.isEmpty, "the parents' counters are unknown, so neither fork counts yet")

        // p-1 is written out: k-1 counts its own share. p-2 stays cut off: the second attempt counts it as 0.
        try home.replace("-w-forge/p-1.settings.json", Self.sidecar(1000, 0, 0, 100, 0))
        #expect(session.pollRecentFiles(nowMs: Clock.milliseconds(Date())))
        let responses = Self.responses(session)
        #expect(responses["droid:m-k-1"]?.usage == Self.usage(500, cached: 0, write: 0, output: 60, reasoning: 0))
        #expect(responses["droid:m-k-2"]?.usage == Self.usage(1500, cached: 0, write: 0, output: 160, reasoning: 0))
        #expect(responses["droid:m-p-1"]?.usage.output == 100 && responses["droid:m-p-2"] == nil)
        #expect(!session.pollRecentFiles(nowMs: Clock.milliseconds(Date())), "known now: nothing more to read")
    }

    @Test func aFolderSettingReadsItsSessionsFolder() throws {
        let directory = try TempDirectory()
        try directory.write("moved/sessions/-w-p/s1.jsonl", Self.start("s1", cwd: "/w/p") + Self.user("u1", Self.base + 1000)
            + Self.assistant("m1", Self.base + 2000))
        try directory.write("moved/sessions/-w-p/s1.settings.json", Self.sidecar(10, 0, 0, 5, 0))
        for setting in ["moved", "moved/sessions"] {
            let configuration = MonitorConfiguration(enabledSources: [.droid], droidRoot: directory.file(setting))
            let session = TranscriptSession(configuration: configuration, clock: { Self.base + 10_000 })
            _ = session.seed(todayStartMs: Self.base)
            #expect(session.responses.map(\.key) == ["droid:m1"], "\(setting)")
            #expect(session.root(for: .droid).path == directory.file("moved/sessions").path)
        }
    }

    @MainActor
    @Test func theLiveMonitorFollowsBothFiles() async throws {
        let home = Home()
        let now = Clock.milliseconds(Date())
        try home.write("-w-forge/s1.jsonl", Self.start("s1") + Self.user("u1", now - 9000) + Self.assistant("m1", now - 6000, tools: true))
        try home.write("-w-forge/s1.settings.json", Self.sidecar(1000, 0, 0, 100, 10))
        let store = SpeedStore()
        let monitor = LiveMonitor(store: store, configuration: home.configuration)
        monitor.start()
        defer { monitor.stop() }
        func today() -> TokenTotals? { store.snapshot.sources.first { $0.kind == .droid }?.today }
        #expect(await LiveMonitorTests.waitUntil { store.snapshot.state == .running && today()?.requests == 1 })
        #expect(store.snapshot.agents.first { $0.source == .droid }?.phase == .tools)

        try home.append("-w-forge/s1.jsonl", Self.user("r1", now - 5000) + Self.assistant("m2", now - 3000) + Self.outcome)
        #expect(await LiveMonitorTests.waitUntil { store.snapshot.agents.first { $0.source == .droid }?.phase == .idle })
        #expect(today()?.requests == 1, "the call waits for its counters")
        try home.replace("-w-forge/s1.settings.json", Self.sidecar(1400, 0, 0, 160, 10))
        #expect(await LiveMonitorTests.waitUntil { today()?.requests == 2 && today()?.output == 160 })
        #expect(store.snapshot.sources.first { $0.kind == .droid }?.sessionCount == 1)
    }
}

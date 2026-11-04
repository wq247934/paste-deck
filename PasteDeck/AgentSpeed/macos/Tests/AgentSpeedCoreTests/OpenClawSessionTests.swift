import Foundation
import Testing
@testable import AgentSpeedCore

/// OpenClaw inside the live session and the daily history (METRICS 4.14): a Gateway writing its agent databases while
/// they are read, rewritten and pruned windows, older windows read from their end, databases and profiles that appear
/// while running, the agent-scoped Codex homes and the warning for a database without session tables.
@Suite("OpenClaw session")
struct OpenClawSessionTests {
    static let base: Int64 = 1_792_497_600_000

    // MARK: - Entries

    static func header(_ id: String, _ ms: Int64, cwd: String = "/w/claw") -> String {
        #"{"type":"session","version":4,"id":"\#(id)","timestamp":"\#(OmpSessionTests.iso(ms))","cwd":"\#(cwd)"}"#
    }

    static func user(_ id: String, _ ms: Int64) -> String {
        #"{"type":"message","id":"\#(id)","timestamp":"\#(OmpSessionTests.iso(ms))","message":{"role":"user","content":"(omitted)","timestamp":\#(ms)}}"#
    }

    static func assistant(_ id: String, start: Int64, end: Int64, output: Int = 40, stop: String = "stop",
                          calls: [String] = []) -> String {
        let blocks = calls.map { #"{"type":"toolCall","id":"\#($0)","name":"read","arguments":{"path":"src/\#($0).ts"}}"# }
        let content = ([#"{"type":"text","text":"(omitted)"}"#] + blocks).joined(separator: ",")
        return #"{"type":"message","id":"\#(id)","timestamp":"\#(OmpSessionTests.iso(end))","message":{"role":"assistant","content":[\#(content)],"api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":{"input":3,"output":\#(output),"cacheRead":100,"cacheWrite":0},"stopReason":"\#(stop)","timestamp":\#(start)}}"#
    }

    static func toolResult(_ id: String, call: String, _ ms: Int64) -> String {
        #"{"type":"message","id":"\#(id)","timestamp":"\#(OmpSessionTests.iso(ms))","message":{"role":"toolResult","toolCallId":"\#(call)","toolName":"read","content":[],"isError":false,"timestamp":\#(ms)}}"#
    }

    // MARK: - A Gateway

    /// A home folder whose OpenClaw Gateway writes its agent databases the way 2026.10 does (WAL, one row per entry),
    /// reduced to the columns Agent Speed reads. `<home>/.codex/sessions` is the automatic Codex root.
    final class Gateway {
        let directory = try! TempDirectory()
        private var writers: [String: SQLiteConnection] = [:]

        var home: OpenClawHome { OpenClawHome(environment: [:], home: directory.url) }

        func configuration(codexRoot: URL? = nil) -> MonitorConfiguration {
            var configuration = MonitorConfiguration(enabledSources: [.openclaw, .codex], codexRoot: codexRoot)
            configuration.openclawHome = home
            configuration.automaticRoots = [.codex: [directory.file(".codex/sessions")]]
            return configuration
        }

        func database(_ agent: String, state: String = ".openclaw") -> String {
            directory.file("\(state)/agents/\(agent)/agent/openclaw-agent.sqlite").path
        }

        /// The path the file watcher reports for a database (or its `-wal`).
        func canonical(_ path: String) -> String {
            let folder = (path as NSString).deletingLastPathComponent
            guard let resolved = realpath(folder, nil) else { return path }
            defer { free(resolved) }
            return (String(cString: resolved) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        }

        func writer(_ agent: String, state: String = ".openclaw") throws -> SQLiteConnection {
            let path = database(agent, state: state)
            if let writer = writers[path] { return writer }
            let fresh = FileManager.default.fileExists(atPath: path)
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            let writer = try SQLiteConnection(path: path, mode: .readWriteCreate)
            if !fresh {
                try writer.execute("PRAGMA journal_mode = WAL")
                try writer.execute("""
                    CREATE TABLE session_nodes (session_key TEXT NOT NULL PRIMARY KEY, current_session_id TEXT NOT NULL,
                      entry_json TEXT NOT NULL, updated_at INTEGER NOT NULL, spawned_by TEXT) STRICT;
                    CREATE TABLE session_windows (session_id TEXT NOT NULL PRIMARY KEY, session_key TEXT NOT NULL,
                      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, transcript_updated_at INTEGER DEFAULT NULL,
                      acp_owned INTEGER NOT NULL DEFAULT 0, agent_harness_id TEXT, spawned_by TEXT) STRICT;
                    CREATE TABLE transcript_events (session_id TEXT NOT NULL, seq INTEGER NOT NULL, event_json TEXT,
                      created_at INTEGER NOT NULL, event_zstd BLOB, event_utf8_bytes INTEGER,
                      PRIMARY KEY (session_id, seq)) STRICT;
                    CREATE TABLE transcript_rewrite_watermarks (session_id TEXT NOT NULL PRIMARY KEY,
                      generation TEXT NOT NULL, updated_at INTEGER NOT NULL) STRICT;
                    CREATE TABLE auth_profile_store (store_key TEXT NOT NULL PRIMARY KEY, value_json TEXT NOT NULL) STRICT;
                    """)
            }
            writers[path] = writer
            return writer
        }

        /// A new window of the session `key` (which it becomes the current window of), with its header row.
        func addWindow(_ id: String, agent: String = "main", state: String = ".openclaw", key: String? = nil, at ms: Int64,
                       runtime: String = "openclaw", spawnedBy: String? = nil, cwd: String = "/w/claw") throws {
            let writer = try writer(agent, state: state)
            let window = try writer.prepare("INSERT INTO session_windows VALUES (?1, ?2, ?3, ?3, ?3, 0, ?4, ?5)")
            window.bind(1, id)
            window.bind(2, key ?? "agent:\(agent):\(id)")
            window.bind(3, ms)
            window.bind(4, runtime)
            if let spawnedBy { window.bind(5, spawnedBy) }
            try window.run()
            let node = try writer.prepare("""
                INSERT INTO session_nodes VALUES (?1, ?2, '{}', ?3, ?4)
                ON CONFLICT(session_key) DO UPDATE SET current_session_id = excluded.current_session_id
                """)
            node.bind(1, key ?? "agent:\(agent):\(id)")
            node.bind(2, id)
            node.bind(3, ms)
            if let spawnedBy { node.bind(4, spawnedBy) }
            try node.run()
            try append(id, agent: agent, state: state, [Gateway.headerRow(id, ms, cwd: cwd)], at: ms)
        }

        private static func headerRow(_ id: String, _ ms: Int64, cwd: String) -> String {
            OpenClawSessionTests.header(id, ms, cwd: cwd)
        }

        /// Appends entries in one transaction and advances the window's `transcript_updated_at`.
        func append(_ window: String, agent: String = "main", state: String = ".openclaw", _ entries: [String], at ms: Int64) throws {
            let writer = try writer(agent, state: state)
            try writer.transaction {
                var seq = try maxSeq(window, writer: writer)
                for entry in entries {
                    seq += 1
                    let insert = try writer.prepare("INSERT INTO transcript_events VALUES (?1, ?2, ?3, ?4, NULL, NULL)")
                    insert.bind(1, window)
                    insert.bind(2, seq)
                    insert.bind(3, entry)
                    insert.bind(4, ms)
                    try insert.run()
                }
                let touch = try writer.prepare("UPDATE session_windows SET transcript_updated_at = ?2, updated_at = ?2 WHERE session_id = ?1")
                touch.bind(1, window)
                touch.bind(2, ms)
                try touch.run()
            }
        }

        /// Replaces a window's rows (a transcript rewrite); `generation` nil leaves the watermark alone.
        func rewrite(_ window: String, agent: String = "main", _ entries: [String], generation: String?, at ms: Int64) throws {
            let writer = try writer(agent)
            try writer.transaction {
                let delete = try writer.prepare("DELETE FROM transcript_events WHERE session_id = ?1")
                delete.bind(1, window)
                try delete.run()
                if let generation {
                    let mark = try writer.prepare("""
                        INSERT INTO transcript_rewrite_watermarks VALUES (?1, ?2, ?3)
                        ON CONFLICT(session_id) DO UPDATE SET generation = excluded.generation
                        """)
                    mark.bind(1, window)
                    mark.bind(2, generation)
                    mark.bind(3, ms)
                    try mark.run()
                }
            }
            try append(window, agent: agent, entries, at: ms)
        }

        func deleteWindow(_ window: String, agent: String = "main") throws {
            let writer = try writer(agent)
            for table in ["transcript_events", "session_windows"] {
                let delete = try writer.prepare("DELETE FROM \(table) WHERE session_id = ?1")
                delete.bind(1, window)
                try delete.run()
            }
        }

        /// Closes like the Gateway does when it stops: checkpoints and removes `-wal` and `-shm`.
        func close(_ agent: String = "main") throws {
            let path = database(agent)
            guard let writer = writers.removeValue(forKey: path) else { return }
            try writer.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            writer.close()
            for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }

        private func maxSeq(_ window: String, writer: SQLiteConnection) throws -> Int64 {
            let statement = try writer.prepare("SELECT coalesce(max(seq), 0) FROM transcript_events WHERE session_id = ?1")
            statement.bind(1, window)
            var value: Int64 = 0
            try statement.forEachRow { value = $0.int64(0) }
            return value
        }
    }

    static func agents(_ session: TranscriptSession, at ms: Int64 = base + 60_000) -> [String: EngineAgentStatus] {
        let output = session.advance(nowMs: ms, todayStartMs: base, emitsEvents: false).output
        return Dictionary(uniqueKeysWithValues: output.agents.map { ($0.agent.id, $0) })
    }

    // MARK: - Live reading

    @Test func aGrowingDatabaseStreamsItsRows() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        try gateway.append("w1", [Self.user("u1", Self.base + 1000),
                                  Self.assistant("a1", start: Self.base + 1005, end: Self.base + 3000)], at: Self.base + 3000)
        let path = gateway.database("main")
        let id = OpenClawSource.agentId(path, "w1")

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        let summary = session.seed(todayStartMs: Self.base)
        #expect(summary.filesDiscovered == 1 && summary.filesRead == 1, "one database counts as one file")
        #expect(session.responses.map(\.key) == ["openclaw:a1:\(Self.base + 1005)"])
        #expect(session.responses.first?.startMs == Self.base + 1005 && session.responses.first?.endMs == Self.base + 3000)
        var agent = try #require(Self.agents(session, at: Self.base + 10_000)[id])
        #expect(agent.agent.project == "claw" && agent.agent.cwdPath == "/w/claw" && agent.phase == .idle)
        #expect(agent.agent.actions.isEmpty, "seeding adds no actions")
        #expect(session.watchedPaths.contains(gateway.canonical(gateway.directory.file(".openclaw/agents").path)))
        #expect(session.sessionCounts(todayStartMs: Self.base)[.openclaw] == 1)

        // The watcher reports the -wal: the user's message starts the in-flight estimate.
        try gateway.append("w1", [Self.user("u2", Self.base + 20_000)], at: Self.base + 20_000)
        #expect(session.handleChanges(atCanonicalPaths: [gateway.canonical(path) + "-wal"]))
        agent = try #require(Self.agents(session, at: Self.base + 21_000)[id])
        #expect(agent.phase == .generating && agent.agent.inFlightStartMs == Self.base + 20_000)

        // The 1-second fallback finds the next rows without a watcher event.
        try gateway.append("w1", [Self.assistant("a2", start: Self.base + 20_005, end: Self.base + 24_000, output: 80,
                                                 stop: "toolUse", calls: ["c1", "c2"])], at: Self.base + 24_000)
        #expect(session.pollRecentFiles(nowMs: Self.base + 25_000))
        let (output, events) = session.advance(nowMs: Self.base + 25_000, todayStartMs: Self.base, emitsEvents: true)
        #expect(events.count == 1, "a live response is a completion")
        agent = try #require(output.agents.first { $0.agent.id == id })
        #expect(agent.phase == .tools && agent.agent.actions.map(\.call.tool) == ["read", "read"])
        #expect(session.responses.count == 2 && output.todayBySource[.openclaw]?.output == 120)

        try gateway.append("w1", [Self.toolResult("r1", call: "c1", Self.base + 26_000),
                                  Self.toolResult("r2", call: "c2", Self.base + 26_500)], at: Self.base + 26_500)
        #expect(session.pollRecentFiles(nowMs: Self.base + 27_000))
        agent = try #require(Self.agents(session, at: Self.base + 27_000)[id])
        #expect(agent.phase == .generating && agent.agent.inFlightStartMs == Self.base + 26_500)
        #expect(!session.pollRecentFiles(nowMs: Self.base + 28_000), "nothing changed")
    }

    @Test func subagentWindowsLinkToTheCurrentWindowOfTheirSession() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", key: "agent:main:main", at: Self.base)
        try gateway.addWindow("w2", key: "agent:main:main", at: Self.base + 5000)
        try gateway.addWindow("child", key: "agent:main:subagent:9f", at: Self.base + 6000, spawnedBy: "agent:main:main")
        try gateway.append("child", [Self.assistant("c1", start: Self.base + 6100, end: Self.base + 7000)], at: Self.base + 7000)
        let path = gateway.database("main")

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: Self.base)
        let agents = Self.agents(session)
        let child = try #require(agents[OpenClawSource.agentId(path, "child")])
        #expect(child.agent.isSubagent && child.parentId == OpenClawSource.agentId(path, "w2"),
                "the parent is the session's current window")
        #expect(session.sessionCounts(todayStartMs: Self.base)[.openclaw] == 2, "sub-agent windows are not sessions")
    }

    @Test func aRewrittenWindowIsReadAgainWithoutCountingTwice() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        let a1 = Self.assistant("a1", start: Self.base + 1005, end: Self.base + 3000)
        try gateway.append("w1", [Self.user("u1", Self.base + 1000), a1, Self.user("u2", Self.base + 4000),
                                  Self.assistant("a2", start: Self.base + 4005, end: Self.base + 6000)], at: Self.base + 6000)
        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(session.responses.count == 2)

        // A new generation: the window is read again from its first row, the same keys merge.
        try gateway.rewrite("w1", [Self.header("w1", Self.base), Self.user("u1", Self.base + 1000), a1,
                                   Self.user("u3", Self.base + 8000)], generation: "g2", at: Self.base + 8000)
        #expect(session.pollRecentFiles(nowMs: Self.base + 9000))
        #expect(session.responses.count == 2, "a1 merges and a2 stays recorded")
        var output = session.advance(nowMs: Self.base + 9000, todayStartMs: Self.base, emitsEvents: false).output
        #expect(output.today.requests == 2)
        #expect(output.agents.first?.phase == .generating && output.agents.first?.agent.inFlightStartMs == Self.base + 8000)

        // Fewer rows without a watermark change: the highest seq dropped, so the window was rewritten too.
        try gateway.rewrite("w1", [Self.header("w1", Self.base), a1], generation: nil, at: Self.base + 10_000)
        #expect(session.pollRecentFiles(nowMs: Self.base + 11_000))
        output = session.advance(nowMs: Self.base + 11_000, todayStartMs: Self.base, emitsEvents: false).output
        #expect(output.today.requests == 2 && output.agents.first?.phase == .idle)
    }

    @Test func prunedWindowsAndRemovedDatabasesLeave() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        try gateway.addWindow("w2", at: Self.base + 1000)
        try gateway.append("w2", [Self.assistant("a1", start: Self.base + 1100, end: Self.base + 2000)], at: Self.base + 2000)
        let path = gateway.database("main")
        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(Set(Self.agents(session).keys) == [OpenClawSource.agentId(path, "w1"), OpenClawSource.agentId(path, "w2")])

        try gateway.deleteWindow("w2")
        #expect(session.pollRecentFiles(nowMs: Self.base + 31_000))
        #expect(Set(Self.agents(session).keys) == [OpenClawSource.agentId(path, "w1")])
        #expect(session.responses.count == 1, "a pruned window's responses stay recorded")

        try gateway.close()
        try FileManager.default.removeItem(atPath: path)
        #expect(session.pollRecentFiles(nowMs: Self.base + 32_000))
        #expect(Self.agents(session).isEmpty)
        _ = session.rediscover(todayStartMs: Self.base)
        #expect(session.sessionCounts(todayStartMs: Self.base)[.openclaw] == 0)
    }

    @Test func olderWindowsStartAfterTheirLastRow() throws {
        let gateway = Gateway()
        let yesterday = Self.base - 86_400_000
        try gateway.addWindow("old", at: yesterday, cwd: "/w/nova")
        try gateway.append("old", [Self.user("u1", yesterday + 1000),
                                   Self.assistant("a1", start: yesterday + 1005, end: yesterday + 3000)], at: yesterday + 3000)
        try gateway.addWindow("new", at: Self.base + 1000)
        try gateway.append("new", [Self.assistant("n1", start: Self.base + 1100, end: Self.base + 2000)], at: Self.base + 2000)
        let path = gateway.database("main")
        let old = OpenClawSource.agentId(path, "old")

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 60_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(session.responses.map(\.key) == ["openclaw:n1:\(Self.base + 1100)"])
        #expect(Self.agents(session)[old] == nil)

        try gateway.append("old", [Self.user("u2", Self.base + 50_000),
                                   Self.assistant("a2", start: Self.base + 50_005, end: Self.base + 54_000, output: 80)],
                           at: Self.base + 54_000)
        #expect(session.handleChanges(atCanonicalPaths: [gateway.canonical(path) + "-wal"]))
        #expect(session.responses.map(\.key).sorted() == ["openclaw:a2:\(Self.base + 50_005)", "openclaw:n1:\(Self.base + 1100)"])
        let agent = try #require(Self.agents(session)[old])
        #expect(agent.agent.project == "nova", "the header is read before the new rows")
        #expect(agent.phase == .idle && agent.agent.lastLineMs == Self.base + 54_000)
    }

    @Test func aClosedDatabaseIsReadWithoutCreatingFilesUntilTheGatewayWritesAgain() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        try gateway.append("w1", [Self.assistant("a1", start: Self.base + 100, end: Self.base + 900)], at: Self.base + 900)
        try gateway.close()
        let path = gateway.database("main")
        let folder = (path as NSString).deletingLastPathComponent
        let before = try FileManager.default.contentsOfDirectory(atPath: folder).sorted()

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(session.responses.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).sorted() == before, "reading creates no file")

        // The Gateway starts again: the immutable connection is dropped once a -wal appears.
        try gateway.append("w1", [Self.assistant("a2", start: Self.base + 2000, end: Self.base + 2900)], at: Self.base + 2900)
        #expect(FileManager.default.fileExists(atPath: path + "-wal"))
        #expect(session.pollRecentFiles(nowMs: Self.base + 31_000))
        #expect(session.responses.count == 2)
    }

    // MARK: - Roots

    @Test func databasesAndProfilesThatAppearWhileRunning() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        // A chosen Codex folder keeps the Codex roots fixed, so only the OpenClaw source looks for new databases.
        let fixed = gateway.configuration(codexRoot: gateway.directory.file("codex"))
        let session = TranscriptSession(configuration: fixed, clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: Self.base)
        #expect(!session.openclawRootsChanged)

        try gateway.addWindow("o1", agent: "ops", at: Self.base + 1000)
        try gateway.append("o1", agent: "ops", [Self.assistant("o1a", start: Self.base + 1100, end: Self.base + 1900)],
                           at: Self.base + 1900)
        #expect(!session.openclawRootsChanged)
        #expect(session.rediscover(todayStartMs: Self.base))
        #expect(session.responses.map(\.key) == ["openclaw:o1a:\(Self.base + 1100)"])

        // With automatic Codex roots a new agent brings its Codex home: the monitor restarts the session.
        let automatic = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = automatic.seed(todayStartMs: Self.base)
        #expect(!automatic.openclawRootsChanged)
        try gateway.addWindow("x1", agent: "extra", at: Self.base + 2000)
        #expect(automatic.openclawRootsChanged, "a new agent-scoped Codex home")
        let restarted = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        #expect(!restarted.openclawRootsChanged)
        try FileManager.default.createDirectory(at: gateway.directory.file(".openclaw-work"), withIntermediateDirectories: true)
        #expect(restarted.openclawRootsChanged, "a new profile folder")
    }

    @Test func codexRunsInAnAgentScopedHomeCountUnderCodex() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        let rollout = "openclaw/.openclaw/agents/main/agent/codex-home/sessions/2026/10/20/"
            + "rollout-2026-10-20T13-10-00-019a0b1c-2d3e-7f40-8a51-c2d3e4f5a6b7.jsonl"
        let target = gateway.directory.file(".openclaw/agents/main/agent/codex-home/sessions/2026/10/20")
            .appendingPathComponent((rollout as NSString).lastPathComponent)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixtures.root.appendingPathComponent(rollout), to: target)

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base + 30_000 })
        _ = session.seed(todayStartMs: 0)
        let codex = session.responses.filter { $0.source == .codex }
        #expect(codex.count == 2 && codex.allSatisfy { $0.agentId.hasSuffix("/agent/codex-home/sessions/2026/10/20/" + target.lastPathComponent) })
        #expect(session.responses.allSatisfy { $0.source == .codex }, "the window has no responses of its own")

        var off = gateway.configuration()
        off.enabledSources = [.codex]
        let codexOnly = TranscriptSession(configuration: off, clock: { Self.base + 30_000 })
        _ = codexOnly.seed(todayStartMs: 0)
        #expect(codexOnly.responses.count == 2, "the Codex home is a Codex root while OpenClaw is off")
    }

    @Test func aDatabaseWithoutSessionTablesIsDetectedAndWarned() throws {
        let gateway = Gateway()
        let path = gateway.database("legacy")
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let writer = try SQLiteConnection(path: path, mode: .readWriteCreate)
        try writer.execute("CREATE TABLE auth_profile_store (store_key TEXT PRIMARY KEY, value_json TEXT)")
        writer.close()

        let session = TranscriptSession(configuration: gateway.configuration(), clock: { Self.base })
        #expect(session.hasAvailableRoot)
        _ = session.seed(todayStartMs: Self.base)
        let context = SnapshotContext(session: session, todayStartMs: Self.base)
        #expect(context.warnings.contains(.unsupportedFormat(.openclaw)))
        #expect(context.sources[.openclaw]?.available == true)
        #expect(context.sources[.openclaw]?.rootPath == gateway.directory.file(".openclaw").path)
        #expect(context.sources[.openclaw]?.sessionCount == 0)

        let missing = TranscriptSession(configuration: MonitorConfiguration(
            enabledSources: [.openclaw], openclawRoot: gateway.directory.file("nowhere")), clock: { Self.base })
        #expect(!missing.hasAvailableRoot && SnapshotContext(session: missing, todayStartMs: Self.base).sources[.openclaw]?.available == false)
    }

    // MARK: - History

    @Test func historyAnalysesOnlyTheWindowsThatChanged() throws {
        let gateway = Gateway()
        try gateway.addWindow("w1", at: Self.base)
        try gateway.append("w1", [Self.assistant("a1", start: Self.base + 100, end: Self.base + 900)], at: Self.base + 900)
        try gateway.addWindow("w2", at: Self.base + 1000)
        try gateway.append("w2", [Self.assistant("b1", start: Self.base + 1100, end: Self.base + 1900, output: 60)],
                           at: Self.base + 1900)
        let store = gateway.directory.file("history.sqlite").path
        let configuration = gateway.configuration()

        var report = try HistoryScan.run(configuration: configuration, timeZone: HistoryTests.utc, storePath: store)
        #expect(report.sessionsAnalyzed == 2)
        #expect(report.days.first { $0.source == .openclaw }?.totals.requests == 2)

        report = try HistoryScan.run(configuration: configuration, timeZone: HistoryTests.utc, storePath: store)
        #expect(report.sessionsAnalyzed == 0, "an unchanged database is not opened again")

        try gateway.append("w2", [Self.assistant("b2", start: Self.base + 3000, end: Self.base + 3900, output: 70)],
                           at: Self.base + 3900)
        report = try HistoryScan.run(configuration: configuration, timeZone: HistoryTests.utc, storePath: store)
        #expect(report.sessionsAnalyzed == 1, "only the window that grew")
        let day = try #require(report.days.first { $0.source == .openclaw })
        #expect(day.totals.requests == 3 && day.totals.output == 170)
    }
}

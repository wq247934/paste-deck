import Foundation
import Testing
@testable import AgentSpeedCore

/// METRICS 11.9 against report-vectors.json `websocket.scheduler`: the simulator's timelines with instant writes.
@Suite struct ReportStreamSchedulerTests {
    typealias Scheduler = ReportStreamScheduler

    static var vectors: [String: Any] {
        ((try? Fixtures.json("report-vectors.json"))?["websocket"] as? [String: Any]) ?? [:]
    }

    static func settings(_ basis: ReportStreamSettings, _ overrides: Any?) -> ReportStreamSettings {
        var settings = basis
        let given = overrides as? [String: Any] ?? [:]
        for field in ReportStreamSettings.fields {
            if let value = given[field.name] as? Int { settings[keyPath: field.key] = value }
        }
        return settings
    }

    /// Ticks with `until` repeat every `step` (500 ms) through `until`; events then run in time order, stable.
    static func expand(_ events: [[String: Any]]) -> [[String: Any]] {
        var expanded: [[String: Any]] = []
        for event in events {
            guard event.string("type") == "tick", let until = event.int64("until") else {
                expanded.append(event)
                continue
            }
            var copy = event
            copy["until"] = nil
            copy["step"] = nil
            for at in stride(from: event.int64("at")!, through: until, by: Int64.Stride(event.int64("step") ?? 500)) {
                copy["at"] = Int(at)
                expanded.append(copy)
            }
        }
        return expanded.enumerated().sorted { ($0.element.int64("at")!, $0.offset) < ($1.element.int64("at")!, $1.offset) }
            .map(\.element)
    }

    /// Runs one case like `simulate_stream`: wake-ups the scheduler asks for become ticks without new data.
    static func simulate(_ item: [String: Any]) -> (log: [String], scheduler: Scheduler) {
        let config = item["config"] as? [String: Any] ?? [:]
        let available = config["available"] as? Bool ?? true
        var scheduler = Scheduler(settings: available ? settings(.standard, config) : nil,
                                  heartbeatSeconds: config["heartbeatSeconds"] as? Int ?? 60, jitter: { 1 })
        var log: [String] = []
        let events = expand(item["events"] as? [[String: Any]] ?? [])
        let tickTimes = Set(events.filter { $0.string("type") == "tick" }.compactMap { $0.int64("at") })
        var lastActive = false

        func record(_ t: Int64, _ actions: [Scheduler.Action]) {
            log += actions.compactMap(\.text).map { "\(t) \($0)" }
        }

        func wake(until limit: Int64) {
            while let at = scheduler.wakeAt, at < limit {
                scheduler.clearWake()
                if !tickTimes.contains(at) { record(at, scheduler.tick(at: at, active: lastActive)) }
            }
        }

        for event in events {
            let t = event.int64("at")!
            let kind = event.string("type")!
            wake(until: t)
            if scheduler.wakeAt == t, kind == "tick" { scheduler.clearWake() }
            let actions: [Scheduler.Action]
            switch kind {
            case "tick":
                lastActive = event["active"] as? Bool ?? false
                let userEvents: [ReportScheduler.Event] = (event["events"] as? [String] ?? []).map {
                    switch $0 {
                    case "pause": .pause
                    case "resume": .resume
                    case "networkOff": .networkOff
                    case "networkOn": .networkOn
                    default: .stop
                    }
                }
                actions = scheduler.tick(at: t, active: lastActive, changed: event["changed"] as? Bool ?? false,
                                         observed: event.int64("observedAgo").map { t - $0 }, events: userEvents)
            case "open":
                actions = scheduler.opened(at: t)
            case "ready":
                actions = scheduler.ready(at: t, limits: settings(scheduler.settings, event["limits"]))
            case "ack":
                actions = scheduler.ack(at: t, seq: event.int("seq"),
                                        status: event.string("status") == "duplicate" ? .duplicate : .accepted,
                                        matches: (event.string("sha") ?? "match") == "match")
            case "error":
                actions = scheduler.error(at: t, seq: event["seq"] as? Int, code: event.string("code")!,
                                          httpStatus: event.int("httpStatus"), retryAfterSeconds: event["retryAfter"] as? Int,
                                          fatal: event["fatal"] as? Bool ?? false)
            case "close":
                actions = scheduler.closed(at: t, code: event.int("code"))
            case "reject":
                actions = scheduler.rejected(at: t, status: event.int("status"), code: event.string("code"),
                                             retryAfterSeconds: event["retryAfter"] as? Int)
            case "settings":
                let given = event["settings"] as? [String: Any]
                actions = scheduler.settingsChanged(at: t, given.map { settings(.standard, $0) })
            case "retry":
                actions = scheduler.retry(at: t)
            default:
                Issue.record("unknown event \(kind)")
                actions = []
            }
            record(t, actions)
        }
        wake(until: .max)
        return (log, scheduler)
    }

    @Test func vectorTimelines() throws {
        let cases = try #require(Self.vectors["scheduler"] as? [[String: Any]])
        #expect(cases.count == 22)
        for item in cases {
            let name = item.string("name") ?? "?"
            let expect = try #require(item["expect"] as? [String: Any])
            let (log, scheduler) = Self.simulate(item)
            let wanted = expect["log"] as? [String] ?? []
            #expect(log == wanted, "\(name)\nexpected: \(wanted.joined(separator: " | "))\ngot:      \(log.joined(separator: " | "))")
            if let counters = expect["counters"] as? [String: Int] {
                let got = Dictionary(uniqueKeysWithValues: scheduler.counters.all.filter { $0.value != 0 }.map { ($0.name, $0.value) })
                #expect(got == counters, "\(name) counters")
            }
            if let latency = expect["latency"] as? [Int] {
                #expect(scheduler.latency.samples == latency.map(Int64.init), "\(name) latency")
            }
            if let state = expect["state"] as? [String: Any] {
                #expect(scheduler.connection.rawValue == state.string("connection"), "\(name) connection")
                #expect(scheduler.seq == state.int("seq"), "\(name) seq")
                #expect(scheduler.failures == state.int("failures"), "\(name) failures")
                #expect(scheduler.stop?.rawValue == state.string("stop"), "\(name) stop")
                #expect(scheduler.lastDelivered == state.int64("lastDelivered"), "\(name) lastDelivered")
            }
        }
    }

    @Test func backoffVector() throws {
        let expected = try #require(Self.vectors["backoff"] as? [Int]).map(Int64.init)
        let delays = (1...9).map { Scheduler.backoffMs[min($0, Scheduler.backoffMs.count) - 1] }
        #expect(delays == expected)
    }

    /// Opens a connection at 0 → 20 with one dirty tick before it.
    static func opened() -> Scheduler {
        var scheduler = Scheduler(settings: .standard, heartbeatSeconds: 60, jitter: { 1 })
        _ = scheduler.tick(at: 0, active: true, changed: true)
        _ = scheduler.opened(at: 10)
        _ = scheduler.ready(at: 20, limits: .standard)
        return scheduler
    }

    /// Nothing connects or is built while blocked (not confirmed, not registered, an error that needs the user).
    @Test func blockedConnectsNothing() {
        var scheduler = Scheduler(settings: .standard, heartbeatSeconds: 60, jitter: { 1 })
        var actions: [Scheduler.Action] = []
        for t in stride(from: Int64(0), through: 30_000, by: 500) {
            actions += scheduler.tick(at: t, active: true, changed: true, observed: t, blocked: true)
        }
        #expect(actions.allSatisfy { $0 == .discard(beforeIncrements: false) })
        #expect(scheduler.connection == .closed)
    }

    /// A message too large for the connection is dropped as stale; a closing connection then closes.
    @Test func unwritableIsStale() throws {
        var scheduler = Self.opened()
        let seq = try #require(scheduler.tick(at: 100, active: true, changed: true).compactMap { action -> Int? in
            if case .write(let seq) = action { return seq }
            return nil
        }.first)
        #expect(scheduler.unwritable(seq: seq) == [.dropped(seq: seq, .stale)])
        #expect(scheduler.counters.stale == 1)
        #expect(scheduler.awaitingCount == 0)
        #expect(scheduler.unwritable(seq: seq).isEmpty)
    }

    /// A pending wake-up is consumed by any tick at or after it, so a timer that fires late adds nothing.
    @Test func wakeIsConsumedByALaterTick() {
        var scheduler = Self.opened()
        _ = scheduler.tick(at: 100, active: true, changed: true)
        #expect(scheduler.tick(at: 110, active: true, changed: true).contains(.wake(at: 150)))
        #expect(scheduler.tick(at: 160, active: true).contains { if case .build = $0 { true } else { false } })
        #expect(scheduler.wakeAt == nil)
    }

    /// An observation exactly 1 s old is still written; one millisecond more is stale.
    @Test func staleIsAboveOneSecond() {
        var scheduler = Self.opened()
        #expect(scheduler.tick(at: 100, active: true, changed: true, observed: -900).contains(.write(seq: 1)))
        #expect(scheduler.tick(at: 200, active: true, changed: true, observed: -801).contains(.dropped(seq: 2, .stale)))
    }

    /// The reconnect delay carries the jitter, rounded to the millisecond.
    @Test func backoffCarriesTheJitter() {
        var scheduler = Scheduler(settings: .standard, heartbeatSeconds: 60, jitter: { 1.2 })
        _ = scheduler.tick(at: 0, active: true, changed: true)
        #expect(scheduler.closed(at: 5, code: 1006) == [.backoff(reconnectAt: 605)])
    }

    /// The latency ring keeps the last 512 samples; a delivery's rank is kept until another one carries one.
    @Test func latencyRingAndRank() {
        var latency = ReportLatency()
        for sample in 1...600 { latency.add(Int64(sample)) }
        #expect(latency.samples.count == 512)
        #expect(latency.samples.first == 89)
        #expect(latency.p50 == 344)
        var scheduler = Self.opened()
        _ = scheduler.tick(at: 100, active: true, changed: true, observed: 90)
        _ = scheduler.ack(at: 130, seq: 1, status: .accepted, rank: 3)
        #expect(scheduler.rank == 3)
        #expect(scheduler.latency.samples == [40])
    }
}

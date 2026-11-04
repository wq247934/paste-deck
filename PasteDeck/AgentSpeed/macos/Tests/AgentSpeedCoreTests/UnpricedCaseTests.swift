import Foundation
import Testing
@testable import AgentSpeedCore

/// `spec/fixtures/unpriced-cases.json` (METRICS 9.10): every case group, the copied text byte for byte.
@Suite("Unpriced diagnostics cases")
struct UnpricedCaseTests {
    static func cases() throws -> [String: Any] { try Fixtures.json("unpriced-cases.json") }

    static func table() throws -> PriceTable {
        try PriceTableTests.table(try #require(try cases().string("table")))
    }

    static func facts(_ list: Any?) throws -> [UnpricedFact] {
        try #require(list as? [[String: Any]]).map { fact in
            UnpricedFact(key: UnpricedFactKey(model: fact.string("model"), provider: fact.string("provider"),
                                              fast: fact["fast"] as? Bool ?? false, noDate: fact["noDate"] as? Bool ?? false),
                         requests: fact.int("requests"))
        }
    }

    static func reading(_ stored: [String: Any]) throws -> UnpricedReading {
        let side = try #require(stored["side"] as? [[String: Any]]).map { row in
            UnpricedSideRow(model: row.string("model") ?? "", provider: row.string("provider"),
                            fast: row["fast"] as? Bool ?? false, requests: row.int64("requests") ?? 0,
                            version: row.int64("version") ?? 0)
        }
        let models = (stored["models"] as? [String: NSNumber] ?? [:]).mapValues(\.intValue)
        return UnpricedReading.read(requests: stored.int("requests"), unpriced: (stored["unpriced"] as? NSNumber)?.intValue,
                                    models: models, side: side, fileVersion: stored.int64("fileVersion") ?? 0)
    }

    /// The live case's responses through the engine's day ledger (METRICS 9.10 *Live*).
    static func liveParts(_ spec: [String: Any]) throws -> [UnpricedPart] {
        let today = try #require(spec.string("today"))
        let todayStart = try #require(UTCDay.instantMs(today))
        var engine = SpeedEngine()
        for (index, response) in try #require(spec["responses"] as? [[String: Any]]).enumerated() {
            let record = ResponseRecord(
                key: "r\(index)", source: try #require(SourceKind(rawValue: response.string("source") ?? "")), agentId: "a\(index)",
                model: response.string("model"), startMs: nil, endMs: try #require(response.int64("endMs")),
                usage: TokenUsage(input: 10, output: 1), provider: response.string("provider"),
                fast: response["fast"] as? Bool ?? false, costMicroUsd: response.int64("costMicroUsd"),
                requestCount: response.int("requestCount"))
            engine.upsert(record, project: "p", isCompletion: true, emitsEvents: false)
        }
        let output = engine.advance(nowMs: todayStart + 43_200_000, todayStartMs: todayStart, emitsEvents: false)
        return UnpricedPart.live(day: today, requests: output.todayBySource.mapValues(\.requests), facts: output.todayUnpricedFacts)
    }

    static func json(_ part: UnpricedPart) -> NSDictionary {
        [
            "day": part.day, "source": part.source.rawValue, "requests": part.requests, "noCostData": part.noCostData,
            "derived": part.derived, "facts": part.facts.map(json),
        ]
    }

    static func json(_ fact: UnpricedFact) -> [String: Any] {
        var object: [String: Any] = ["model": fact.model, "provider": fact.provider ?? NSNull(), "fast": fact.fast,
                                     "requests": fact.requests]
        if fact.noDate { object["noDate"] = true }
        return object
    }

    @Test func diagnoseCases() throws {
        let table = try Self.table()
        let cases = try #require(try Self.cases()["diagnose"] as? [[String: Any]])
        #expect(cases.count >= 20)
        for (index, spec) in cases.enumerated() {
            let model = spec.string("model"), provider = spec.string("provider")
            let fast = spec["fast"] as? Bool ?? false
            let got = table.resolver.diagnose(model: model, provider: provider, fast: fast)
            let priced = table.cost(model: model, provider: provider, usage: TokenUsage(input: 1000, output: 100), endMs: nil, fast: fast)
            #expect((got == nil) == (priced != nil), "diagnose[\(index)] \(model ?? "nil") agrees with the price")
            var expected: UnpricedDiagnosis?
            if let want = spec["expect"] as? [String: Any] {
                expected = UnpricedDiagnosis(reason: try #require(UnpricedReason(rawValue: want.string("reason") ?? "")),
                                             canonical: want.string("canonical"), rule: want.string("rule"))
            }
            #expect(got == expected, "diagnose[\(index)] \(model ?? "nil")")
        }
    }

    @Test func readCases() throws {
        for spec in try #require(try Self.cases()["read"] as? [[String: Any]]) {
            let name = spec.string("name") ?? ""
            let want = try #require(spec["expect"] as? [String: Any])
            let got = try Self.reading(try #require(spec["stored"] as? [String: Any]))
            #expect(got.requests == want.int("requests"), "\(name) requests")
            #expect(got.noCostData == want.int("noCostData"), "\(name) noCostData")
            #expect(got.derived == want.int("derived"), "\(name) derived")
            #expect(got.facts == (try Self.facts(want["facts"])), "\(name) facts")
        }
    }

    @Test func quoteCases() throws {
        for spec in try #require(try Self.cases()["quote"] as? [[String: Any]]) {
            let text = try #require(spec.string("text"))
            #expect(UnpricedText.quoted(text, redact: spec["redact"] as? Bool ?? true) == spec.string("expect"), "\(text)")
        }
        #expect(UnpricedText.quoted(nil) == "null")
    }

    @Test func liveCases() throws {
        for spec in try #require(try Self.cases()["live"] as? [[String: Any]]) {
            let got = try Self.liveParts(spec).map(Self.json)
            let want = try #require(spec["expect"] as? [[String: Any]])
            #expect(got.count == want.count)
            for (part, expected) in zip(got, want) {
                #expect(part.isEqual(to: expected), "\(spec.string("name") ?? ""): \(part) != \(expected)")
            }
        }
    }

    @Test func reportCases() throws {
        let cases = try Self.cases()
        let current = try Self.table()
        var stored: [UnpricedPart] = []
        for entry in try #require(cases["stored"] as? [[String: Any]]) {
            let reading = try Self.reading(try #require(entry["stored"] as? [String: Any]))
            stored.append(UnpricedPart(day: try #require(entry.string("day")),
                                       source: try #require(SourceKind(rawValue: entry.string("source") ?? "")),
                                       requests: reading.requests, noCostData: reading.noCostData, derived: reading.derived,
                                       facts: reading.facts))
        }
        stored = UnpricedPart.merged(stored)
        let live = try #require(cases["live"] as? [[String: Any]])
        let reports = try #require(cases["reports"] as? [[String: Any]])
        #expect(reports.count >= 6)
        for report in reports {
            let name = report.string("name") ?? ""
            let table = try report.string("table").map(PriceTableTests.table) ?? current
            let app = try #require(report["app"] as? [String: String])
            let view = try #require(report["view"] as? [String: Any])
            let range = UnpricedRange(
                view: try #require(view.string("view")), first: try #require(view.string("first")),
                last: try #require(view.string("last")), source: view.string("source").flatMap(SourceKind.init(rawValue:)),
                excluded: Set((view["excluded"] as? [String] ?? []).compactMap(SourceKind.init(rawValue:))))
            let parts = range.view == "live"
                ? try Self.liveParts(try #require(live.first { $0.string("name") == report.string("input") }))
                : stored
            let result = UnpricedView(parts: parts, table: table, range: range)
            let text = UnpricedText.render(result, app: UnpricedText.App(version: app["version"] ?? "", platform: app["platform"] ?? "",
                                                                        os: app["os"] ?? ""))
            #expect(text == report.string("expect"), "report \(name)")
            #expect(Array(text.utf8) == Array((report.string("expect") ?? "").utf8), "report \(name) bytes")
            for group in result.groups {
                #expect(group.rowRequests + group.pricedNow == group.unpriced, "report \(name) \(group.source)")
            }
        }
    }
}

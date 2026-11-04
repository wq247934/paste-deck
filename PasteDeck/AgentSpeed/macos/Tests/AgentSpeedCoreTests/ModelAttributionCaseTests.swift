import Foundation
import Testing
@testable import AgentSpeedCore

/// `spec/fixtures/model-attribution-cases.json` (METRICS 4.1 step 4, 11.3, 11.4 Attribution), as
/// `spec/tools/reference.py --check-fixtures` checks it: every response and every report ledger increment keeps the
/// model of its own message, never a session's earlier one.
@Suite("Model attribution cases")
struct ModelAttributionCaseTests {
    struct Response: Equatable {
        var key: String
        var model: String?
        var output: Int
        var reportModelId: String
    }

    struct Agent: Equatable {
        var source: String
        var isSubagent: Bool
        var model: String?
        var reportModelId: String
        var responses: [Response]
    }

    struct LedgerRow: Hashable {
        var modelId: String
        var source: String
        var requests: Int64
        var output: Int64
    }

    static func document() throws -> [String: Any] { try Fixtures.json("model-attribution-cases.json") }

    @Test func casesKeepEachResponsesOwnModel() throws {
        let table = PriceBook.bundled
        let cases = try #require(Self.document()["cases"] as? [[String: Any]])
        #expect(cases.count == 4)
        for spec in cases {
            let name = spec.string("name") ?? ""
            let files = try #require(spec["files"] as? [[String: Any]])
            let expected = try #require(spec["expect"] as? [String: [String: Any]])
            var deduper = Deduper()
            var engine = SpeedEngine(pricing: PriceBook())
            var lastEnd: Int64 = 0
            for (index, file) in files.enumerated() {
                let path = try #require(file.string("path"))
                var parser = TranscriptParser(family: .claude, agentId: "/fixture/" + path, fileID: FileID(index))
                var order: [String] = []
                var latest: [String: ResponseRecord] = [:]
                for text in try #require(file["lines"] as? [String]) {
                    Array(text.utf8).withUnsafeBytes { bytes in
                        parser.consume(rawLine: bytes, deduper: &deduper) { upsert in
                            let record = upsert.record
                            if latest[record.key] == nil { order.append(record.key) }
                            latest[record.key] = record
                            lastEnd = max(lastEnd, record.endMs)
                            engine.upsert(record, project: "nova", isCompletion: upsert.isCompletion, emitsEvents: true,
                                          nowMs: record.endMs)
                        }
                    }
                }
                let state = parser.state
                let got = Agent(
                    source: state.source.rawValue, isSubagent: state.isSubagent, model: state.model,
                    reportModelId: table.reportModelId(model: state.model, provider: nil),
                    responses: order.compactMap { latest[$0] }.map {
                        Response(key: $0.key, model: $0.model, output: $0.usage.output,
                                 reportModelId: table.reportModelId(model: $0.model, provider: $0.provider))
                    }
                )
                #expect(got == Self.agent(try #require(expected[path])), "\(name) / \(path)")
            }
            let counters = engine.advance(nowMs: lastEnd, todayStartMs: lastEnd - 3_600_000, emitsEvents: true)
                .report.counters
            let ledger = Set(counters.byModel.map { key, usage in
                LedgerRow(modelId: key.modelId, source: key.source.rawValue, requests: usage.requests, output: usage.output)
            })
            let wanted = Set(try #require(spec["ledger"] as? [[String: Any]]).map {
                LedgerRow(modelId: $0.string("modelId") ?? "", source: $0.string("source") ?? "",
                          requests: Int64($0.int("requests")), output: Int64($0.int("output")))
            })
            #expect(ledger == wanted, "\(name) ledger")
        }
    }

    @Test func opusFiveFiveSpellingsNeverReportOpusFive() throws {
        let table = PriceBook.bundled
        let pairs = try #require(Self.document()["reportIds"] as? [[String]])
        #expect(!pairs.isEmpty)
        for pair in pairs {
            #expect(table.reportModelId(model: pair[0], provider: nil) == pair[1], "\(pair[0])")
        }
    }

    static func agent(_ json: [String: Any]) -> Agent {
        Agent(
            source: json.string("source") ?? "", isSubagent: json["isSubagent"] as? Bool ?? false,
            model: json.string("model"), reportModelId: json.string("reportModelId") ?? "",
            responses: (json["responses"] as? [[String: Any]] ?? []).map {
                Response(key: $0.string("key") ?? "", model: $0.string("model"), output: $0.int("output"),
                         reportModelId: $0.string("reportModelId") ?? "")
            }
        )
    }
}

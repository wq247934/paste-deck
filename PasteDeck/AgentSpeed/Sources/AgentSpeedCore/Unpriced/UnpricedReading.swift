import Foundation

/// One row of the history store's side table `contribution_unpriced` (METRICS 9.10), as stored.
public struct UnpricedSideRow: Equatable, Sendable {
    public var model: String
    /// Nil for the stored empty string.
    public var provider: String?
    public var fast: Bool
    public var requests: Int64
    /// The analysis version that wrote it.
    public var version: Int64

    public init(model: String, provider: String?, fast: Bool, requests: Int64, version: Int64) {
        self.model = model
        self.provider = provider
        self.fast = fast
        self.requests = requests
        self.version = version
    }
}

/// One stored contribution (file or session, day, source) read for the diagnostics: its requests, the requests
/// stored without cost data, the facts, and how many of them were derived from the per-model counts.
public struct UnpricedReading: Equatable, Sendable {
    public var requests: Int
    public var noCostData: Int
    public var facts: [UnpricedFact]
    public var derived: Int

    public init(requests: Int, noCostData: Int = 0, facts: [UnpricedFact] = [], derived: Int = 0) {
        self.requests = requests
        self.noCostData = noCostData
        self.facts = facts
        self.derived = derived
    }

    /// *Reading* of METRICS 9.10 for one contribution: `unpriced` nil = stored before costs existed; `models` the
    /// per-model unpriced counts by raw model; `side` its side rows; `fileVersion` the file's analysis version.
    public static func read(requests: Int, unpriced: Int?, models: [String: Int], side: [UnpricedSideRow],
                            fileVersion: Int64) -> UnpricedReading {
        read(requests: requests, unpriced: unpriced, models: models, facts: validFacts(side, fileVersion: fileVersion))
    }

    /// The facts of a contribution's side rows when every row was written by the file's analysis version and counts
    /// at least one request (rows equal after trimming add up); nil otherwise or without rows.
    static func validFacts(_ side: [UnpricedSideRow], fileVersion: Int64) -> [UnpricedFactKey: Int]? {
        guard !side.isEmpty, side.allSatisfy({ $0.version == fileVersion && $0.requests >= 1 }) else { return nil }
        var tally: [UnpricedFactKey: Int] = [:]
        for row in side {
            let key = UnpricedFactKey(model: row.model, provider: row.provider, fast: row.fast)
            tally[key] = (tally[key] ?? 0).saturatingAdd(Int(clamping: row.requests))
        }
        return tally
    }

    /// The rest of *Reading* once the side rows are checked: they are the facts when they add up to `unpriced`,
    /// else the facts are derived from the per-model counts in the order of the models' UTF-8 bytes.
    static func read(requests: Int, unpriced: Int?, models: [String: Int], facts: [UnpricedFactKey: Int]?) -> UnpricedReading {
        guard let unpriced else { return UnpricedReading(requests: requests, noCostData: requests) }
        guard unpriced > 0 else { return UnpricedReading(requests: requests) }
        if let facts, facts.values.reduce(0, { $0.saturatingAdd($1) }) == unpriced {
            return UnpricedReading(requests: requests, facts: UnpricedFact.list(facts))
        }
        var tally: [UnpricedFactKey: Int] = [:]
        var left = unpriced
        for (model, count) in models.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
            let take = min(max(count, 0), left)
            guard take > 0 else { continue }
            tally[UnpricedFactKey(model: model, provider: nil, fast: false), default: 0] += take
            left -= take
        }
        if left > 0 { tally[UnpricedFactKey(model: "", provider: nil, fast: false), default: 0] += left }
        return UnpricedReading(requests: requests, facts: UnpricedFact.list(tally), derived: unpriced)
    }
}

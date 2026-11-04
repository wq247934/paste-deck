import Foundation

/// The side table of the unpriced facts (METRICS 9.10). Created on every open rather than by a schema version step,
/// like `day_traffic`: older builds keep opening the store and ignore it; readers check each row's `version` against
/// its file's.
extension HistoryDatabase {
    static let unpricedTableSQL = """
        CREATE TABLE IF NOT EXISTS contribution_unpriced (
            file_id INTEGER NOT NULL,
            day TEXT NOT NULL,
            source TEXT NOT NULL,
            model TEXT NOT NULL,
            provider TEXT NOT NULL,
            fast INTEGER NOT NULL,
            requests INTEGER NOT NULL,
            version INTEGER NOT NULL,
            PRIMARY KEY (file_id, day, source, model, provider, fast)
        ) WITHOUT ROWID;
        """

    /// Sets each contribution's facts from its side rows when they are valid for the file's version; rows without a
    /// contribution are ignored.
    func loadUnpriced(into entries: inout [String: Entry], paths: [Int64: String]) throws {
        var rows: [String: [UsageKey: [UnpricedSideRow]]] = [:]
        let statement = try connection.prepare("""
            SELECT file_id, day, source, model, provider, fast, requests, version FROM contribution_unpriced
            """)
        try statement.forEachRow { row in
            guard let path = paths[row.int64(0)], let day = row.string(1),
                  let source = row.string(2).flatMap(SourceKind.init(rawValue:)), let model = row.string(3) else { return }
            let key = UsageKey(day: day, source: source)
            guard entries[path]?.days[key] != nil else { return }
            let provider = row.string(4) ?? ""
            rows[path, default: [:]][key, default: []].append(UnpricedSideRow(
                model: model, provider: provider.isEmpty ? nil : provider, fast: row.int64(5) != 0,
                requests: row.int64(6), version: row.int64(7)))
        }
        for (path, days) in rows {
            guard let version = entries[path]?.version else { continue }
            for (key, side) in days {
                entries[path]?.days[key]?.unpricedFacts = UnpricedReading.validFacts(side, fileVersion: version) ?? [:]
            }
        }
    }

    func deleteUnpriced(fileId: Int64) throws {
        let statement = try connection.prepare("DELETE FROM contribution_unpriced WHERE file_id = ?1")
        statement.bind(1, fileId)
        try statement.run()
    }

    /// One row per fact of a contribution; nothing when it has no unpriced responses.
    func saveUnpriced(_ facts: [UnpricedFactKey: Int], fileId: Int64, day: String, source: SourceKind, version: Int64) throws {
        guard !facts.isEmpty else { return }
        let statement = try connection.prepare("""
            INSERT INTO contribution_unpriced (file_id, day, source, model, provider, fast, requests, version)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            """)
        for (fact, requests) in facts where requests > 0 {
            statement.bind(1, fileId)
            statement.bind(2, day)
            statement.bind(3, source.rawValue)
            statement.bind(4, fact.model)
            statement.bind(5, fact.provider ?? "")
            statement.bind(6, fact.fast ? 1 : 0)
            statement.bind(7, requests)
            statement.bind(8, version)
            try statement.run()
        }
    }
}

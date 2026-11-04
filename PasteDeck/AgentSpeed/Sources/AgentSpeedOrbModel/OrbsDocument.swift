import Foundation

/// An orb's position on one display of an arrangement (DESIGN 2b `layouts`), encoded flat:
/// `{"display": "<display key>", "xAnchor": "high", "x": 12, "yAnchor": "fraction", "y": 0.31}`.
public struct OrbLayoutEntry: Equatable, Hashable, Sendable {
    public var display: String
    public var record: OrbPositionRecord

    public init(display: String, record: OrbPositionRecord) {
        self.display = display
        self.record = record
    }
}

extension OrbLayoutEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case display
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        display = try container.decode(String.self, forKey: .display)
        record = try OrbPositionRecord(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(display, forKey: .display)
        try record.encode(to: encoder)
    }
}

/// Every floating orb and where each one sits (DESIGN 2b, persisted as the settings value `orbs`).
///
/// Besides the spec's `layouts` (per display arrangement), the document keeps `layoutOrder` (least recently used
/// first, at most 16 arrangements) and `displayRecords`: the last position of each orb on each display, used as a
/// fallback when an arrangement is new.
public struct OrbsDocument: Equatable, Sendable {
    public static let maxOrbs = 8
    public static let maxArrangements = 16
    public static let currentVersion = 1

    public var version: Int
    public var orbs: [OrbConfig]
    /// Arrangement key → orb id → position.
    public var layouts: [String: [String: OrbLayoutEntry]]
    /// Arrangement keys, least recently used first.
    public var layoutOrder: [String]
    /// Orb id → display key → the orb's last position on that display.
    public var displayRecords: [String: [String: OrbPositionRecord]]

    public init(
        orbs: [OrbConfig],
        layouts: [String: [String: OrbLayoutEntry]] = [:],
        layoutOrder: [String] = [],
        displayRecords: [String: [String: OrbPositionRecord]] = [:]
    ) {
        version = Self.currentVersion
        self.orbs = orbs
        self.layouts = layouts
        self.layoutOrder = layoutOrder
        self.displayRecords = displayRecords
        normalize()
    }

    /// A fresh install: one orb tracking all sources.
    public static func fresh(id: String) -> OrbsDocument {
        OrbsDocument(orbs: [.makeDefault(id: id)])
    }

    /// The key of a display arrangement: the connected display keys, sorted, joined with `+`.
    public static func arrangementKey(_ displayKeys: [String]) -> String {
        displayKeys.sorted().joined(separator: "+")
    }

    // MARK: Orbs

    public func orb(_ id: String) -> OrbConfig? {
        orbs.first { $0.id == id }
    }

    public func index(of id: String) -> Int? {
        orbs.firstIndex { $0.id == id }
    }

    public var canAdd: Bool { orbs.count < Self.maxOrbs }

    /// Removes an orb and every position it had.
    public mutating func removeOrb(_ id: String) {
        orbs.removeAll { $0.id == id }
        for key in Array(layouts.keys) {
            layouts[key]?[id] = nil
            if layouts[key]?.isEmpty == true {
                layouts[key] = nil
                layoutOrder.removeAll { $0 == key }
            }
        }
        displayRecords[id] = nil
    }

    // MARK: Layouts

    public func entry(orb: String, arrangement: String) -> OrbLayoutEntry? {
        layouts[arrangement]?[orb]
    }

    /// Stores an orb's position in an arrangement, marks the arrangement as most recently used (dropping the least
    /// recently used beyond 16) and remembers the position as the orb's fallback on that display.
    public mutating func setEntry(_ entry: OrbLayoutEntry, orb: String, arrangement: String) {
        layouts[arrangement, default: [:]][orb] = entry
        displayRecords[orb, default: [:]][entry.display] = entry.record
        touchArrangement(arrangement)
    }

    /// Forgets an orb's position in an arrangement (Reset Position).
    public mutating func clearEntry(orb: String, arrangement: String) {
        layouts[arrangement]?[orb] = nil
    }

    /// Marks an arrangement as the most recently used.
    public mutating func touchArrangement(_ arrangement: String) {
        guard layouts[arrangement] != nil else { return }
        layoutOrder.removeAll { $0 == arrangement }
        layoutOrder.append(arrangement)
        while layoutOrder.count > Self.maxArrangements {
            let dropped = layoutOrder.removeFirst()
            layouts[dropped] = nil
        }
    }

    /// The orb's last position on `display`, from any arrangement.
    public func fallbackRecord(orb: String, display: String) -> OrbPositionRecord? {
        displayRecords[orb]?[display]
    }

    // MARK: Serialization

    /// Stable JSON (sorted keys).
    public func data() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Tolerant decoding: invalid orbs and entries are skipped, duplicate ids keep the first, more than eight orbs
    /// are cut. Nil when the data is not a document or has no valid orb, so the caller falls back to the defaults
    /// (or the migration).
    public init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(OrbsDocument.self, from: data), !decoded.orbs.isEmpty else {
            return nil
        }
        self = decoded
    }

    /// Drops duplicate ids, extra orbs and positions of orbs that no longer exist, and reconciles the LRU order.
    mutating func normalize() {
        var seen: Set<String> = []
        orbs = Array(orbs.filter { seen.insert($0.id).inserted }.prefix(Self.maxOrbs))
        let ids = Set(orbs.map(\.id))
        for key in Array(layouts.keys) {
            let kept = (layouts[key] ?? [:]).filter { ids.contains($0.key) }
            layouts[key] = kept.isEmpty ? nil : kept
        }
        displayRecords = displayRecords.filter { ids.contains($0.key) && !$0.value.isEmpty }
        var order: [String] = []
        for key in layoutOrder where layouts[key] != nil && !order.contains(key) { order.append(key) }
        let missing = layouts.keys.filter { !order.contains($0) }.sorted()
        layoutOrder = missing + order
        while layoutOrder.count > Self.maxArrangements {
            layouts[layoutOrder.removeFirst()] = nil
        }
    }
}

extension OrbsDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case version, orbs, layouts, layoutOrder, displayRecords
    }

    /// Decodes a value or nothing, so one bad element never fails the whole document.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let orbs = try container.decode([Lossy<OrbConfig>].self, forKey: .orbs).compactMap(\.value)
        let rawLayouts = try? container.decodeIfPresent([String: [String: Lossy<OrbLayoutEntry>]].self, forKey: .layouts)
        let layouts = (rawLayouts ?? [:]).mapValues { $0.compactMapValues(\.value) }
        let order = try? container.decodeIfPresent([String].self, forKey: .layoutOrder)
        let rawRecords = try? container.decodeIfPresent([String: [String: Lossy<OrbPositionRecord>]].self, forKey: .displayRecords)
        let records = (rawRecords ?? [:]).mapValues { $0.compactMapValues(\.value) }
        self.init(orbs: orbs, layouts: layouts, layoutOrder: order ?? [], displayRecords: records)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(orbs, forKey: .orbs)
        try container.encode(layouts, forKey: .layouts)
        try container.encode(layoutOrder, forKey: .layoutOrder)
        try container.encode(displayRecords, forKey: .displayRecords)
    }
}

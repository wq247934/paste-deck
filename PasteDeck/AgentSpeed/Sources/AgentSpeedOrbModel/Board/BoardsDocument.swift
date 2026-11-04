import Foundation

/// Every leaderboard board and where each one sits (DESIGN 2c, persisted as the settings value `boards`).
///
/// Layouts work as the orbs' (`OrbsDocument`): positions per display arrangement (at most 16, least recently used
/// dropped), plus `layoutOrder` and `displayRecords` as fallbacks. `lastStyle` remembers the style of the board last
/// added or restyled, so the next `boards.add` starts from it.
public struct BoardsDocument: Equatable, Sendable {
    public static let maxBoards = 4
    public static let maxArrangements = OrbsDocument.maxArrangements
    public static let currentVersion = 1

    public var version: Int
    public var boards: [BoardConfig]
    /// Arrangement key → board id → position.
    public var layouts: [String: [String: OrbLayoutEntry]]
    /// Arrangement keys, least recently used first.
    public var layoutOrder: [String]
    /// Board id → display key → the board's last position on that display.
    public var displayRecords: [String: [String: OrbPositionRecord]]
    /// The style `add` uses; nil = `neon`.
    public var lastStyle: BoardStyle?

    public init(
        boards: [BoardConfig] = [],
        layouts: [String: [String: OrbLayoutEntry]] = [:],
        layoutOrder: [String] = [],
        displayRecords: [String: [String: OrbPositionRecord]] = [:],
        lastStyle: BoardStyle? = nil
    ) {
        version = Self.currentVersion
        self.boards = boards
        self.layouts = layouts
        self.layoutOrder = layoutOrder
        self.displayRecords = displayRecords
        self.lastStyle = lastStyle
        normalize()
    }

    /// A fresh install and an upgrade have no board.
    public static let empty = BoardsDocument()

    // MARK: Boards

    public func board(_ id: String) -> BoardConfig? {
        boards.first { $0.id == id }
    }

    public func index(of id: String) -> Int? {
        boards.firstIndex { $0.id == id }
    }

    public var canAdd: Bool { boards.count < Self.maxBoards }

    /// `boards.add`: the last used style (else `neon`), `M`, all sources, every readout on (nothing is copied). Nil at
    /// the limit.
    @discardableResult
    public mutating func add(id: String) -> BoardConfig? {
        guard canAdd, board(id) == nil else { return nil }
        let board = BoardConfig(id: id, style: lastStyle ?? .neon, size: .medium, sources: .all)
        boards.append(board)
        return board
    }

    /// Replaces the board with the same id; a style change becomes the last used style.
    public mutating func update(_ board: BoardConfig) {
        guard let index = index(of: board.id) else { return }
        if boards[index].style != board.style { lastStyle = board.style }
        boards[index] = board
    }

    /// Removes a board and every position it had.
    public mutating func remove(_ id: String) {
        boards.removeAll { $0.id == id }
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

    public func entry(board: String, arrangement: String) -> OrbLayoutEntry? {
        layouts[arrangement]?[board]
    }

    /// Stores a board's position in an arrangement, marks the arrangement as most recently used (dropping the least
    /// recently used beyond 16) and remembers the position as the board's fallback on that display.
    public mutating func setEntry(_ entry: OrbLayoutEntry, board: String, arrangement: String) {
        guard self.board(board) != nil else { return }
        layouts[arrangement, default: [:]][board] = entry
        displayRecords[board, default: [:]][entry.display] = entry.record
        touchArrangement(arrangement)
    }

    public mutating func clearEntry(board: String, arrangement: String) {
        layouts[arrangement]?[board] = nil
        if layouts[arrangement]?.isEmpty == true {
            layouts[arrangement] = nil
            layoutOrder.removeAll { $0 == arrangement }
        }
    }

    public mutating func touchArrangement(_ arrangement: String) {
        guard layouts[arrangement] != nil else { return }
        layoutOrder.removeAll { $0 == arrangement }
        layoutOrder.append(arrangement)
        while layoutOrder.count > Self.maxArrangements {
            layouts[layoutOrder.removeFirst()] = nil
        }
    }

    // MARK: Serialization

    /// Stable JSON (sorted keys).
    public func data() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Tolerant decoding: invalid boards and entries are skipped, duplicate ids keep the first, boards beyond four
    /// are cut. Nil when the data is not a document at all (the caller starts from `empty`).
    public init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(BoardsDocument.self, from: data) else { return nil }
        self = decoded
    }

    mutating func normalize() {
        var seen: Set<String> = []
        boards = Array(boards.filter { seen.insert($0.id).inserted }.prefix(Self.maxBoards))
        let ids = Set(boards.map(\.id))
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

extension BoardsDocument: OrbLayoutProviding {
    public var layoutIDs: [String] { boards.map(\.id) }

    public func layoutEntry(_ id: String, arrangement: String) -> OrbLayoutEntry? {
        entry(board: id, arrangement: arrangement)
    }

    public func layoutRecords(_ id: String) -> [String: OrbPositionRecord] {
        displayRecords[id] ?? [:]
    }
}

extension BoardsDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case version, boards, layouts, layoutOrder, displayRecords, lastStyle
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let boards = (try? container.decodeIfPresent([Lossy<BoardConfig>].self, forKey: .boards))?.compactMap(\.value) ?? []
        let rawLayouts = try? container.decodeIfPresent([String: [String: Lossy<OrbLayoutEntry>]].self, forKey: .layouts)
        let layouts = (rawLayouts ?? [:]).mapValues { $0.compactMapValues(\.value) }
        let order = try? container.decodeIfPresent([String].self, forKey: .layoutOrder)
        let rawRecords = try? container.decodeIfPresent([String: [String: Lossy<OrbPositionRecord>]].self, forKey: .displayRecords)
        let records = (rawRecords ?? [:]).mapValues { $0.compactMapValues(\.value) }
        let lastStyle = try? container.decodeIfPresent(BoardStyle.self, forKey: .lastStyle)
        self.init(boards: boards, layouts: layouts, layoutOrder: order ?? [], displayRecords: records, lastStyle: lastStyle)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(boards, forKey: .boards)
        try container.encode(layouts, forKey: .layouts)
        try container.encode(layoutOrder, forKey: .layoutOrder)
        try container.encode(displayRecords, forKey: .displayRecords)
        try container.encodeIfPresent(lastStyle, forKey: .lastStyle)
    }
}

import Foundation

/// A user's copy of a theme: a literal name, the preset it is based on, and 13 titles plus an idle label where an empty
/// field means "the base's title in the current language" (DESIGN 1, Custom title sets).
public struct CustomTitleSet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public static let nameLimit = 32

    public var id: String
    public var name: String
    public var base: TitlePreset
    public var idle: String
    /// Exactly 13 strings, level 1 first; "" = the base's title.
    public var titles: [String]

    public init(id: String, name: String, base: TitlePreset, idle: String = "", titles: [String] = []) {
        self.id = id
        self.name = Self.cleanName(name) ?? ""
        self.base = base
        self.idle = TitleText.sanitize(idle).text
        self.titles = Self.normalized(titles)
    }

    /// The field of level 0 (idle) or 1...13.
    public func field(level: Int) -> String {
        level == 0 ? idle : titles[min(max(level, 1), TitlePreset.levelCount) - 1]
    }

    public mutating func setField(level: Int, _ text: String) {
        if level == 0 { idle = text } else { titles[min(max(level, 1), TitlePreset.levelCount) - 1] = text }
    }

    /// 1–32 characters, trimmed; nil when empty (committing an empty name keeps the previous one).
    public static func cleanName(_ name: String) -> String? {
        let text = TitleText.sanitize(name, limit: nameLimit).text
        guard !text.isEmpty else { return nil }
        return text.count > nameLimit ? String(text.prefix(nameLimit)).trimmingCharacters(in: .whitespaces) : text
    }

    /// Padded with "" or cut to 13, each re-normalized by the text rules (not the length cut).
    static func normalized(_ titles: [String]) -> [String] {
        var result = titles.prefix(TitlePreset.levelCount).map { TitleText.sanitize($0).text }
        while result.count < TitlePreset.levelCount { result.append("") }
        return result
    }

    enum CodingKeys: String, CodingKey { case id, name, base, idle, titles }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "empty id")
        }
        let base = ((try? container.decodeIfPresent(String.self, forKey: .base)) ?? nil).flatMap(TitlePreset.init(id:)) ?? .vehicles
        self.init(
            id: id,
            name: ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "",
            base: base,
            idle: ((try? container.decodeIfPresent(String.self, forKey: .idle)) ?? nil) ?? "",
            titles: ((try? container.decodeIfPresent([String].self, forKey: .titles)) ?? nil) ?? []
        )
    }
}

/// A title theme in use: a preset or a custom set.
public enum TitleTheme: Equatable, Hashable, Sendable {
    case preset(TitlePreset)
    case custom(CustomTitleSet)

    public var id: String {
        switch self {
        case .preset(let preset): preset.rawValue
        case .custom(let set): set.id
        }
    }

    /// The preset that fills its empty fields (itself for a preset).
    public var base: TitlePreset {
        switch self {
        case .preset(let preset): preset
        case .custom(let set): set.base
        }
    }

    /// The dashboard hero keeps the vehicle for Vehicles and sets based on it (DESIGN 4c).
    public var showsVehicleArt: Bool { base.showsVehicleArt }

    /// The text of level 0 (idle) or 1...13; `localized` looks up a string key in the current language.
    public func text(level: Int, localized: (String) -> String) -> String {
        if case .custom(let set) = self {
            let field = set.field(level: level)
            if !field.isEmpty { return field }
        }
        return localized(level == 0 ? base.idleKey : base.titleKey(level: level))
    }

    /// The name shown in pickers.
    public func name(localized: (String) -> String) -> String {
        switch self {
        case .preset(let preset): localized(preset.nameKey)
        case .custom(let set): set.name
        }
    }
}

/// The title themes setting (DESIGN 1, Persistence; settings key `titleThemes`).
public struct TitleThemesDocument: Codable, Equatable, Sendable {
    public static let maxCustom = 8
    public static let defaultsKey = "titleThemes"

    public var version = 1
    /// A preset id or a custom set id; default and fallback `vehicles`.
    public var selected: String
    public var custom: [CustomTitleSet]

    public init(selected: String = TitlePreset.vehicles.rawValue, custom: [CustomTitleSet] = []) {
        self.selected = selected
        self.custom = custom
    }

    public var canAddCustom: Bool { custom.count < Self.maxCustom }

    public func customSet(_ id: String) -> CustomTitleSet? { custom.first { $0.id == id } }

    /// The theme an id names, or nil when it names nothing known (a newer version's preset, a deleted set).
    public func theme(id: String?) -> TitleTheme? {
        guard let id else { return nil }
        if let preset = TitlePreset(id: id) { return .preset(preset) }
        return customSet(id).map(TitleTheme.custom)
    }

    /// The General theme; an unknown selection falls back to Vehicles.
    public var general: TitleTheme { theme(id: selected) ?? .preset(.vehicles) }

    /// An orb's theme: its own when it names a known theme, else the General theme.
    public func orbTheme(_ id: String?) -> TitleTheme { theme(id: id) ?? general }

    /// Every theme in picker order: the presets, then the custom sets in creation order.
    public var allThemes: [TitleTheme] { TitlePreset.allCases.map(TitleTheme.preset) + custom.map(TitleTheme.custom) }

    // MARK: Coding

    enum CodingKeys: String, CodingKey { case version, selected, custom }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = ((try? container.decodeIfPresent(Int.self, forKey: .version)) ?? nil) ?? 1
        var sets: [CustomTitleSet] = []
        let entries = ((try? container.decodeIfPresent([Failable].self, forKey: .custom)) ?? nil) ?? []
        for entry in entries {
            guard let set = entry.set, !sets.contains(where: { $0.id == set.id }), sets.count < Self.maxCustom else { continue }
            sets.append(set)
        }
        custom = sets
        let stored = ((try? container.decodeIfPresent(String.self, forKey: .selected)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        selected = stored.flatMap { $0.isEmpty ? nil : $0 } ?? TitlePreset.vehicles.rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(selected, forKey: .selected)
        try container.encode(custom, forKey: .custom)
    }

    public func data() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Nil for absent or unreadable data (a fresh install: Vehicles, no custom sets).
    public init?(data: Data?) {
        guard let data, let document = try? JSONDecoder().decode(TitleThemesDocument.self, from: data) else { return nil }
        self = document
    }

    /// Decodes any element; an invalid set becomes nil instead of failing the document.
    private struct Failable: Decodable {
        let set: CustomTitleSet?

        init(from decoder: Decoder) throws {
            set = try? CustomTitleSet(from: decoder)
        }
    }
}

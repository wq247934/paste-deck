import AgentSpeedCore
import Foundation

/// The sources an orb tracks (DESIGN 2b `sources`): every enabled source, including ones detected or added later, or
/// an explicit list of METRICS 1 keys. Keys this version does not know are kept (and ignored) so a newer version's
/// choice survives a downgrade.
public enum OrbSourceSelection: Equatable, Hashable, Sendable {
    case all
    /// Raw keys: known ones in source order first, then unknown ones in their original order; never empty.
    case explicit([String])

    /// Normalizes a set of known sources (source order, no duplicates); an empty list means `.all`.
    public static func explicit(_ kinds: [SourceKind]) -> OrbSourceSelection {
        normalized(kinds.map(\.rawValue))
    }

    /// Source order first, unknown keys after them, duplicates dropped; empty → `.all`.
    public static func normalized(_ keys: [String]) -> OrbSourceSelection {
        var seen: Set<String> = []
        let unique = keys.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return .all }
        let present = Set(unique)
        let known = SourceKind.allCases.map(\.rawValue).filter(present.contains)
        let unknown = unique.filter { SourceKind(rawValue: $0) == nil }
        return .explicit(known + unknown)
    }

    public var isAll: Bool { self == .all }

    /// The known sources of an explicit list, in source order; empty for `.all`.
    public var knownSources: [SourceKind] {
        guard case let .explicit(keys) = self else { return [] }
        return keys.compactMap(SourceKind.init(rawValue:))
    }

    /// The engine's source set; nil for `.all`.
    public var sourceSet: SourceSet? {
        guard case .explicit = self else { return nil }
        return SourceSet(knownSources)
    }

    public func tracks(_ kind: SourceKind) -> Bool {
        switch self {
        case .all: true
        case let .explicit(keys): keys.contains(kind.rawValue)
        }
    }

    /// The selection after the user toggles `kind` in the orb's sources menu (DESIGN 2b): on an all-sources orb it
    /// becomes that single source; otherwise the source is added or removed. Removing the last known source is
    /// refused (nil).
    public func toggling(_ kind: SourceKind) -> OrbSourceSelection? {
        guard case let .explicit(keys) = self else { return .explicit([kind.rawValue]) }
        if keys.contains(kind.rawValue) {
            let remaining = keys.filter { $0 != kind.rawValue }
            guard remaining.contains(where: { SourceKind(rawValue: $0) != nil }) else { return nil }
            return .normalized(remaining)
        }
        return .normalized(keys + [kind.rawValue])
    }
}

extension OrbSourceSelection: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = text == "all" ? .all : .normalized([text])
            return
        }
        let keys = (try? container.decode([String].self)) ?? []
        self = .normalized(keys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case let .explicit(keys): try container.encode(keys)
        }
    }
}

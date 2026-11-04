import Foundation

/// The unit an orb shows (DESIGN 2b `unit`, 9): token speed or the API-equivalent cost per second. Heat, tiers and
/// titles always follow tokens. Unknown values from a newer version decode as `tokens`.
public enum OrbUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case tokens, cost

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrbUnit(rawValue: raw) ?? .tokens
    }

    public var toggled: OrbUnit { self == .tokens ? .cost : .tokens }
}

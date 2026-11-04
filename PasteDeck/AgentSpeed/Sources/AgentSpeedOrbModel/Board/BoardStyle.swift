import Foundation

/// The look of a leaderboard board (DESIGN 2c). Unknown values from a newer version decode as `glass`.
public enum BoardStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case glass, timing, neon

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BoardStyle(rawValue: raw) ?? .glass
    }

    public var titleKey: String { "boards.style.\(rawValue)" }

    /// Corner radius of the rounded square (prototypes `.panel { border-radius }`).
    public var cornerRadius: Double {
        switch self {
        case .glass: 26
        case .timing: 20
        case .neon: 22
        }
    }
}

/// The three board sizes (DESIGN 2c): `S` 280, `M` 340 (default), `L` 420 pt square. Unknown values decode as `M`.
public enum BoardSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small = "S"
    case medium = "M"
    case large = "L"

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BoardSize(rawValue: raw) ?? .medium
    }

    /// Side of the rounded square in points.
    public var side: Double {
        switch self {
        case .small: 280
        case .medium: 340
        case .large: 420
        }
    }
}

import Foundation

/// What an orb's two-line readout shows (DESIGN 2b `traffic`, 10): the traffic of its own sources, the whole computer,
/// the live intelligence of its sources, or nothing. Absent (orbs saved by older builds) decodes as `sources` in
/// `OrbConfig`; an unknown value as `off`.
public enum OrbTraffic: String, CaseIterable, Codable, Sendable, Identifiable {
    case sources, machine, intelligence, off

    /// Network speed, which needs traffic measuring.
    public var isNetwork: Bool { self == .sources || self == .machine }

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrbTraffic(rawValue: raw) ?? .off
    }
}

/// The global name plate setting (DESIGN 2b, Name plate, `orbNames`).
public enum OrbNamesMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto, always, never

    public var id: String { rawValue }
}

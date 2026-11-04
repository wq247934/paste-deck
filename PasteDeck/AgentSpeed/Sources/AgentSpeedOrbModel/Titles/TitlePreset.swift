import Foundation

/// The nine preset title themes in picker order (DESIGN 1, Title themes). Every theme names the same 13 levels on the
/// same thresholds plus an idle label; only Vehicles keeps the vehicle art in the dashboard hero.
public enum TitlePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case vehicles, animals, wind, space, cultivation, wuxia, mage, gameRank, engineer

    public static let levelCount = 13

    public var id: String { rawValue }

    /// The dashboard hero shows the vehicle (else the title badge, DESIGN 4c).
    public var showsVehicleArt: Bool { self == .vehicles }

    public var nameKey: String { "titles.\(rawValue).name" }

    /// The idle label's string key (Vehicles keeps `tier.idle`).
    public var idleKey: String { self == .vehicles ? "tier.idle" : "titles.\(rawValue).idle" }

    /// The string key of level 1...13 (Vehicles keeps its `title.*` keys).
    public func titleKey(level: Int) -> String {
        let level = min(max(level, 1), Self.levelCount)
        guard self == .vehicles else { return "titles.\(rawValue).\(level)" }
        return "title." + Self.vehicleKeys[level - 1]
    }

    /// The vehicle keys of levels 1...13 (also the hero art keys of `spec/assets/vehicles.json`).
    public static let vehicleKeys = [
        "walk", "bicycle", "ebike", "motorcycle", "car", "sportsCar", "bulletTrain", "raceCar", "maglev", "jetliner",
        "fighterJet", "hypersonic", "rocket",
    ]

    /// Decodes an unknown id as nil instead of failing.
    public init?(id: String) {
        self.init(rawValue: id)
    }
}

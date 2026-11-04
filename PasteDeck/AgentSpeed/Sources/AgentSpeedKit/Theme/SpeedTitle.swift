import Foundation

/// The visible speed label: a vehicle title from a 13-step ladder (DESIGN section 1, "Speed titles"). Thresholds are
/// fractions of the redline so every metric and redline reads the same; walking starts at an absolute 0.5 tok/s.
public enum SpeedTitle: Int, SpeedLadder {
    case idle
    case walk, bicycle, ebike, motorcycle, car, sportsCar, bulletTrain, raceCar, maglev, jetliner, fighterJet, hypersonic, rocket

    static var firstActive: SpeedTitle { .walk }

    /// Every title the label can show, slowest first.
    static var ladder: [SpeedTitle] { allCases.filter { $0 != .idle } }

    /// The titles whose thresholds scale with the redline (walking starts at a fixed 0.5 tok/s), as listed and
    /// ticked under the redline slider.
    static var scaledLadder: [SpeedTitle] { ladder.filter { $0 != .walk } }

    /// Entry threshold as a fraction of the redline (walking uses an absolute 0.5 tok/s).
    var threshold: Double {
        switch self {
        case .idle, .walk: 0
        case .bicycle: 0.02
        case .ebike: 0.03
        case .motorcycle: 0.04
        case .car: 0.06
        case .sportsCar: 0.08
        case .bulletTrain: 0.12
        case .raceCar: 0.17
        case .maglev: 0.24
        case .jetliner: 0.34
        case .fighterJet: 0.5
        case .hypersonic: 0.7
        case .rocket: 1
        }
    }

    public func enterSpeed(redline: Double) -> Double {
        switch self {
        case .idle: 0
        case .walk: SpeedTier.cruiseSpeed
        default: threshold * redline
        }
    }

    public var titleKey: String {
        switch self {
        case .idle: "tier.idle"
        case .walk: "title.walk"
        case .bicycle: "title.bicycle"
        case .ebike: "title.ebike"
        case .motorcycle: "title.motorcycle"
        case .car: "title.car"
        case .sportsCar: "title.sportsCar"
        case .bulletTrain: "title.bulletTrain"
        case .raceCar: "title.raceCar"
        case .maglev: "title.maglev"
        case .jetliner: "title.jetliner"
        case .fighterJet: "title.fighterJet"
        case .hypersonic: "title.hypersonic"
        case .rocket: "title.rocket"
        }
    }

    var next: SpeedTitle? { SpeedTitle(rawValue: rawValue + 1) }
    var previous: SpeedTitle? { SpeedTitle(rawValue: rawValue - 1) }

    /// The hero vehicle's key in `spec/assets/vehicles.json` (DESIGN 4c); nil while idle.
    var vehicleKey: String? {
        guard self != .idle else { return nil }
        return String(titleKey.dropFirst("title.".count))
    }

    init?(vehicleKey: String) {
        guard let title = SpeedTitle.ladder.first(where: { $0.vehicleKey == vehicleKey }) else { return nil }
        self = title
    }

    public static func < (lhs: SpeedTitle, rhs: SpeedTitle) -> Bool { lhs.rawValue < rhs.rawValue }
}

typealias TitleTracker = LadderTracker<SpeedTitle>

/// How a speed title fits a label of fixed width: it shrinks, down to 80 % of the label size, and is never truncated.
enum TitleFit {
    static let minimumScale: CGFloat = 0.8

    /// Scale for text `width` points wide in a label `limit` points wide.
    static func scale(width: CGFloat, limit: CGFloat) -> CGFloat {
        guard width > 0, limit > 0, width > limit else { return 1 }
        return max(minimumScale, limit / width)
    }
}

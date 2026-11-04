import AgentSpeedOrbModel
import AppKit

/// Reads the single orb's per-display positions of earlier versions (`orb.positions`, `orb.lastDisplay`) for the
/// migration to multiple orbs (DESIGN 2b). Never writes: a downgrade finds them as they were.
@MainActor
struct LegacyOrbPositions {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The display the user last placed the orb on.
    var lastDisplay: String? {
        defaults.string(forKey: Key.lastDisplay)
    }

    /// Every saved record, keyed by display UUID.
    var records: [String: OrbPositionRecord] {
        var result: [String: OrbPositionRecord] = [:]
        for (display, value) in defaults.dictionary(forKey: Key.positions) ?? [:] {
            guard let entry = value as? [String: Any], let x = Self.decode(entry, prefix: "x"), let y = Self.decode(entry, prefix: "y") else {
                continue
            }
            result[display] = OrbPositionRecord(x: x, y: y)
        }
        return result
    }

    private static func decode(_ entry: [String: Any], prefix: String) -> OrbPositionRecord.Axis? {
        guard let anchor = entry[prefix + "Anchor"] as? String,
              let raw = (entry[prefix] as? NSNumber)?.doubleValue, raw.isFinite
        else { return nil }
        return OrbPositionRecord.Axis(anchor: anchor, value: raw)
    }

    private enum Key {
        static let positions = "orb.positions"
        static let lastDisplay = "orb.lastDisplay"
    }
}

extension NSScreen {
    /// Stable identifier of the physical display, surviving reconnects and resolution changes.
    var orbDisplayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = number.uint32Value
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid)
        else { return "display-\(displayID)" }
        return string as String
    }

    var orbSnapScreen: OrbSnapScreen {
        OrbSnapScreen(frame: frame, visibleFrame: visibleFrame)
    }
}

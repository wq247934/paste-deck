import CoreGraphics

/// When an orb carries a name plate (DESIGN 2b, Name plate, When it shows).
public enum NameplateVisibility {
    /// What the global `orbNames` setting gives this orb: `auto` shows a plate when two or more orbs are visible or
    /// when the orb tracks some (not all) sources, so a single all-sources orb looks exactly as before.
    public static func automatic(mode: OrbNamesMode, shownOrbs: Int, tracksAll: Bool) -> Bool {
        switch mode {
        case .auto: shownOrbs >= 2 || !tracksAll
        case .always: true
        case .never: false
        }
    }

    /// The orb's effective setting: its own `showName`, else the global result. The menus check this state.
    public static func isOn(_ orb: OrbConfig, mode: OrbNamesMode, shownOrbs: Int) -> Bool {
        orb.showName ?? automatic(mode: mode, shownOrbs: shownOrbs, tracksAll: tracksAll(orb))
    }

    /// Whether the plate is drawn: the effective setting, the orb shown, and a diameter of at least 80 pt.
    public static func isDrawn(_ orb: OrbConfig, mode: OrbNamesMode, shownOrbs: Int, isShown: Bool) -> Bool {
        isShown && CGFloat(orb.size) >= NameplateMetrics.minimumDiameter && isOn(orb, mode: mode, shownOrbs: shownOrbs)
    }

    /// An explicit list without a known source reads as all sources (DESIGN 2b `name`).
    public static func tracksAll(_ orb: OrbConfig) -> Bool {
        orb.sources.knownSources.isEmpty
    }
}

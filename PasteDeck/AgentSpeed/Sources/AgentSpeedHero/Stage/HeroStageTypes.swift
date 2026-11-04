import Foundation

/// Effects intensity of the vehicle layer (DESIGN 4c, Effects intensity), after the Reduce Motion cap.
public enum HeroLevel: Int, Comparable, Sendable, CaseIterable {
    case off, soft, standard, max

    public static func < (lhs: HeroLevel, rhs: HeroLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the stage reads each frame.
public struct HeroInput: Sendable {
    /// Seconds on a monotonic time base.
    public var time: Double
    /// Vehicle index of the displayed speed title; nil while idle.
    public var title: Int?
    /// When the displayed title last changed (same time base); the transition starts there.
    public var titleChangedAt: Double
    /// Entry speed `T_k` of the displayed title (tok/s).
    public var threshold: Double
    /// Entry speed of the next title; nil for the last one (rocket).
    public var nextThreshold: Double?
    public var redline: Double
    /// Smoothed heat `h_s` and overdrive `o_s` (DESIGN section 1).
    public var heat: Double
    public var overdrive: Double
    /// Effect tier: 0 idle, 1 cruise, 2 boost, 3 overdrive, 4 redline.
    public var tier: Int
    public var level: HeroLevel
    public var reduceMotion: Bool
    /// Start of a 6 s idle-sweep cycle, shared with the gauge's idle sweep.
    public var sweepEpoch: Double

    public init(time: Double, title: Int?, titleChangedAt: Double, threshold: Double, nextThreshold: Double?, redline: Double,
                heat: Double, overdrive: Double, tier: Int, level: HeroLevel, reduceMotion: Bool, sweepEpoch: Double = 0) {
        self.time = time
        self.title = title
        self.titleChangedAt = titleChangedAt
        self.threshold = threshold
        self.nextThreshold = nextThreshold
        self.redline = redline
        self.heat = heat
        self.overdrive = overdrive
        self.tier = tier
        self.level = level
        self.reduceMotion = reduceMotion
        self.sweepEpoch = sweepEpoch
    }
}

/// How a vehicle enters or leaves (DESIGN 4c, Title transitions and Start-up).
public enum HeroTransition: Sendable, Equatable {
    /// Already in place (or a parked vehicle starting where it stands).
    case stay
    case upgrade
    case downgrade
    /// Reduce Motion crossfade.
    case fade
    /// Off: no animation.
    case cut
    /// Start-up onto another vehicle: the parked one fades out, the new one fades in on the spot.
    case wake
}

/// A vehicle on stage: the current one or the one leaving.
public struct HeroActor: Sendable, Equatable {
    public var vehicle: Int
    public var start: Double
    public var transition: HeroTransition
    /// Titles climbed or dropped by the change that brought it in.
    public var levels: Int
    /// Offset along the heading the actor had when it started leaving.
    public var base: Double

    public init(vehicle: Int, start: Double, transition: HeroTransition, levels: Int = 0, base: Double = 0) {
        self.vehicle = vehicle
        self.start = start
        self.transition = transition
        self.levels = levels
        self.base = base
    }
}

/// Where an actor is drawn this frame.
public struct HeroPlacement: Sendable, Equatable {
    /// Offset in canvas units.
    public var offset: SIMD2<Double>
    public var alpha: Double
    /// Speed (units/s) the motion ghosts trail by.
    public var ghostSpeed: Double
    /// Unit vector of the heading.
    public var direction: SIMD2<Double>
}

/// The upgrade flash on the incoming vehicle.
public struct HeroFlash: Sendable, Equatable {
    public var start: Double
    public var strength: Double
}

/// How often the layer needs a new frame.
public enum HeroFrameDemand: Sendable, Equatable {
    /// Nothing moves: redraw only when an input changes.
    case still
    /// Parked: breathing (10 fps) or the light band (30 fps).
    case idle(fps: Int)
    /// Something moves: display rate.
    case full
}

/// Modifiers a running start-up applies to the current vehicle (DESIGN 4c, Start-up table).
public struct HeroStartupEffects: Sendable, Equatable {
    public var lurch = 0.0
    public var pitch = 0.0
    public var lift = 0.0
    public var hipLift = 0.0
    public var lights = 0.0
    public var flame = 1.0
    public var contrail = 1.0
    public var shock = 1.0
    public var hover = 1.0
    public var shake = 0.0
    public var glow = 0.0

    public init() {}
}

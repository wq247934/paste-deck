import Foundation

/// A spark or streak particle in board points (fx.js `parts`).
public struct BoardParticle: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var age: Double
    public var life: Double
    public var size: Double
    public var color: BoardFXColor
    public var gravity: Double
    public var drag: Double
    /// Drawn as a short line along its velocity, else as a dot.
    public var streak: Bool

    public var fade: Double { max(0, 1 - age / life) }
}

/// An expanding ring (fx.js `waves`): radius `4 + (maxRadius − 4) · easeOutCubic(t)`, alpha `(1 − t) · 0.85`.
public struct BoardWave: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var maxRadius: Double
    public var age: Double
    public var life: Double
    public var color: BoardFXColor

    public var progress: Double { min(1, age / life) }
    public var radius: Double { 4 + (maxRadius - 4) * (1 - pow(1 - progress, 3)) }
    public var alpha: Double { (1 - progress) * 0.85 }
    public var width: Double { 2.5 * (1 - progress) + 0.5 }
}

/// A lightning bolt (fx.js `bolts`): a main path and up to three branches, flickering out over `life`.
public struct BoardBolt: Equatable, Sendable {
    public static let maxPaths = 4
    public static let maxPoints = 12

    public var alive = false
    public var age = 0.0
    public var life = 0.32
    public var color = BoardFXColor.fxWhite
    public var pathCount = 0
    /// Points per path; path `k` starts at `k × maxPoints` in the bolt's slot of `BoardEffects.boltPoints`.
    public var lengths = SIMD4<Int32>(repeating: 0)

    /// `(1 − age / life) · (0.65 + 0.35 sin(90 age))`.
    public var flicker: Double { max(0, 1 - age / life) * (0.65 + 0.35 * sin(age * 90)) }
}

/// A hyperspace streak (fx.js `warp.stars`): angle and distance from the warp center.
public struct BoardStar: Equatable, Sendable {
    public var angle: Double
    public var distance: Double
}

/// One perimeter comet: where its head is along the outline (fraction, wrapping) and how visible it is.
public struct BoardComet: Equatable, Sendable {
    /// Position relative to the shared phase (fraction of the outline); eases to `targetOffset` so the visible comets
    /// stay evenly spaced when their count changes.
    public var offset = 0.0
    public var targetOffset = 0.0
    public var opacity = 0.0
    public var targetOpacity = 0.0
}

/// The inputs of a settled effects frame (see `BoardEffects.still`).
public struct BoardEffectsStill: Equatable, Sendable {
    var style: BoardStyle
    var side: Double
    var intensity: BoardEffectsIntensity
    var reduceMotion: Bool
    var heat: Double
    var overdrive: Double
    var phase: Double
    var gold: Double
    var comets: ContiguousArray<BoardComet>
}

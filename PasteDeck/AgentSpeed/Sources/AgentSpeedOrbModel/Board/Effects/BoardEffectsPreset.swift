import Foundation

/// A straight-alpha sRGB color of the board effects (r, g, b, a in 0...1).
public typealias BoardFXColor = SIMD4<Float>

public extension BoardFXColor {
    /// `0xRRGGBB` with `alpha`.
    static func hex(_ value: UInt32, alpha: Float = 1) -> BoardFXColor {
        BoardFXColor(Float((value >> 16) & 0xFF) / 255, Float((value >> 8) & 0xFF) / 255, Float(value & 0xFF) / 255, alpha)
    }

    func opacity(_ factor: Float) -> BoardFXColor { BoardFXColor(x, y, z, w * factor) }

    static let fxGold = BoardFXColor.hex(0xFACC15)
    static let fxGoldHead = BoardFXColor.hex(0xFFE58A)
    static let fxGoldPale = BoardFXColor.hex(0xFFF1A8)
    static let fxOrange = BoardFXColor.hex(0xFB923C)
    static let fxWhiteHot = BoardFXColor.hex(0xFFF7D6)
    static let fxWhite = BoardFXColor.hex(0xFFFFFF)
    static let fxGreen = BoardFXColor.hex(0x22C55E)
}

/// Up to four colors a burst cycles through (no array, so emitting never allocates).
public struct BoardFXPalette: Equatable, Sendable {
    public var colors: (BoardFXColor, BoardFXColor, BoardFXColor, BoardFXColor)
    public var count: Int

    public init(_ a: BoardFXColor, _ b: BoardFXColor? = nil, _ c: BoardFXColor? = nil, _ d: BoardFXColor? = nil) {
        colors = (a, b ?? a, c ?? a, d ?? a)
        count = d != nil ? 4 : c != nil ? 3 : b != nil ? 2 : 1
    }

    public subscript(index: Int) -> BoardFXColor {
        switch index % count {
        case 0: colors.0
        case 1: colors.1
        case 2: colors.2
        default: colors.3
        }
    }

    public static func == (lhs: BoardFXPalette, rhs: BoardFXPalette) -> Bool {
        lhs.count == rhs.count && (0..<lhs.count).allSatisfy { lhs[$0] == rhs[$0] }
    }
}

/// One particle burst (fx.js `burst` options): `count` particles at a random angle within `spread` radians around
/// `angle` (nil: any direction), speed `speed × U(0.35, 1.1)`, life `life × U(0.6, 1.2)`, size `size × U(0.6, 1.4)`.
public struct BoardBurst: Equatable, Sendable {
    public var count: Int
    public var speed: Double
    public var angle: Double?
    public var spread: Double
    public var life: Double
    public var colors: BoardFXPalette
    public var size: Double
    public var gravity: Double
    public var drag: Double
    public var streak: Bool

    public init(count: Int = 20, speed: Double = 160, angle: Double? = nil, spread: Double = .pi * 2, life: Double = 0.9,
                colors: BoardFXPalette, size: Double = 1.8, gravity: Double = 90, drag: Double = 1.6, streak: Bool = true) {
        self.count = count
        self.speed = speed
        self.angle = angle
        self.spread = spread
        self.life = life
        self.colors = colors
        self.size = size
        self.gravity = gravity
        self.drag = drag
        self.streak = streak
    }
}

/// The effect tier of a heat (fx.js `setHeat`), which picks the comet count.
public enum BoardHeatTier: Int, Comparable, Sendable, CaseIterable {
    case idle, cruise, boost, overdrive, redline

    public init(heat h: Double) {
        self = h < 0.05 ? .idle : h < 0.32 ? .cruise : h < 0.56 ? .boost : h < 0.78 ? .overdrive : .redline
    }

    public static func < (lhs: BoardHeatTier, rhs: BoardHeatTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Effects intensity (DESIGN 2c): Off — nothing; Soft — one comet at most, no particles or warp; Standard; Max — 1.5×
/// particles and warp density.
public enum BoardEffectsIntensity: String, CaseIterable, Sendable {
    case off, soft, standard, max

    var particleScale: Double {
        switch self {
        case .off, .soft: 0
        case .standard: 1
        case .max: 1.5
        }
    }
}

/// What differs between the three styles' effects (the prototypes' `BoardFX.create` options and panel CSS).
public struct BoardEffectsPreset: Equatable, Sendable {
    public var style: BoardStyle
    public var cornerRadius: Double
    /// Comets per tier: idle, cruise, boost, overdrive, redline.
    public var comets: [Int]
    public var ringWidth: Double
    /// Neon's hyperspace streaks behind the content.
    public var warp: Bool
    /// The outside bloom: CSS blur and spread per unit of `--bloom`.
    public var bloomBlur: Double
    public var bloomSpread: Double
    public var overtakeBurst: BoardBurst
    /// The overtake burst takes the climber's source color (else the burst's own colors, timing's green).
    public var overtakeBurstInSourceColor: Bool
    /// Neon: lightning from the climber's rank to the row it passed, a strike from the top edge on a new leader and a
    /// flash of the board.
    public var lightning: Bool

    public static func of(_ style: BoardStyle) -> BoardEffectsPreset {
        switch style {
        case .glass:
            BoardEffectsPreset(style: style, cornerRadius: style.cornerRadius, comets: [1, 1, 2, 3, 4], ringWidth: 1.6,
                               warp: false, bloomBlur: 70, bloomSpread: 6,
                               overtakeBurst: BoardBurst(count: 14, speed: 120, life: 0.7, colors: BoardFXPalette(.fxWhite),
                                                         size: 1.5, gravity: 60),
                               overtakeBurstInSourceColor: true, lightning: false)
        case .timing:
            BoardEffectsPreset(style: style, cornerRadius: style.cornerRadius, comets: [1, 1, 2, 2, 3], ringWidth: 1.2,
                               warp: false, bloomBlur: 70, bloomSpread: 6,
                               overtakeBurst: BoardBurst(count: 12, speed: 130, life: 0.6,
                                                         colors: BoardFXPalette(.fxGreen, .fxWhite), size: 1.4, gravity: 50),
                               overtakeBurstInSourceColor: false, lightning: false)
        case .neon:
            BoardEffectsPreset(style: style, cornerRadius: style.cornerRadius, comets: [1, 2, 3, 4, 4], ringWidth: 1.4,
                               warp: true, bloomBlur: 80, bloomSpread: 8,
                               overtakeBurst: BoardBurst(count: 16, speed: 140, life: 0.7, colors: BoardFXPalette(.fxWhite),
                                                         size: 1.5, gravity: 60),
                               overtakeBurstInSourceColor: true, lightning: true)
        }
    }
}

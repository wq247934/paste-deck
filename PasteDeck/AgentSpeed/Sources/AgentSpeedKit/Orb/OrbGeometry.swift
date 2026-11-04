import SwiftUI

/// Fixed geometry of one orb size (DESIGN section 2, layer 3). Angles are degrees in screen space (y down).
struct OrbGeometry {
    static let segmentCount = 36
    static let startAngle = 135.0
    static let sweep = 270.0
    static let segmentGap = 2.2

    let diameter: CGFloat
    let center: CGPoint
    let gaugeRadius: CGFloat
    /// Radial length of a segment.
    let segmentLength: CGFloat
    /// Tangential width of a segment at the gauge radius.
    let segmentWidth: CGFloat
    let segmentCorner: CGFloat
    let tickRadius: CGFloat
    let cometRadius: CGFloat

    init(diameter: CGFloat, canvasSide: CGFloat) {
        self.diameter = diameter
        center = CGPoint(x: canvasSide / 2, y: canvasSide / 2)
        gaugeRadius = 0.41 * diameter
        segmentLength = 0.045 * diameter
        let slot = Self.sweep / Double(Self.segmentCount)
        segmentWidth = gaugeRadius * (slot - Self.segmentGap) * .pi / 180
        segmentCorner = min(segmentWidth, segmentLength) * 0.24
        tickRadius = 0.455 * diameter
        cometRadius = 0.472 * diameter
    }

    /// Center angle of a segment.
    static func segmentAngle(_ index: Int) -> Double {
        startAngle + sweep / Double(segmentCount) * (Double(index) + 0.5)
    }

    /// Angle of a gauge fraction (0 = start of the arc, 1 = end).
    static func angle(forFraction fraction: Double) -> Double {
        startAngle + sweep * fraction
    }

    func point(angle degrees: Double, radius: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }
}

/// Small, fast, seedable generator for particles.
struct OrbRandom {
    private var state: UInt64

    init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func range(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }
}

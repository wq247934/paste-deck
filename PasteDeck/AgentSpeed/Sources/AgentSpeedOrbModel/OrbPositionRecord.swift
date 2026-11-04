import CoreGraphics
import Foundation

/// Where the disc sits on one display, independent of that display's resolution: each axis is either docked to an
/// edge at a fixed distance or a fraction of the usable area.
///
/// JSON form (DESIGN 2b): `{"xAnchor": "low|high|fraction", "x": n, "yAnchor": …, "y": n}`.
public struct OrbPositionRecord: Equatable, Hashable, Sendable {
    public enum Axis: Equatable, Hashable, Sendable {
        /// Distance from the disc edge to the low (left/bottom) usable edge.
        case low(CGFloat)
        /// Distance from the disc edge to the high (right/top) usable edge.
        case high(CGFloat)
        /// Disc center as a fraction of the usable span.
        case fraction(CGFloat)
    }

    public var x: Axis
    public var y: Axis

    public init(x: Axis, y: Axis) {
        self.x = x
        self.y = y
    }

    public init(center: CGPoint, radius: CGFloat, visible: CGRect) {
        x = Self.axis(center.x, radius: radius, low: visible.minX, high: visible.maxX)
        y = Self.axis(center.y, radius: radius, low: visible.minY, high: visible.maxY)
    }

    public func center(radius: CGFloat, visible: CGRect) -> CGPoint {
        CGPoint(
            x: Self.resolve(x, radius: radius, low: visible.minX, high: visible.maxX),
            y: Self.resolve(y, radius: radius, low: visible.minY, high: visible.maxY)
        )
    }

    private static func axis(_ value: CGFloat, radius: CGFloat, low: CGFloat, high: CGFloat) -> Axis {
        let toLow = value - radius - low
        let toHigh = high - (value + radius)
        if toLow <= OrbSnap.threshold, toLow <= toHigh { return .low(max(0, toLow)) }
        if toHigh <= OrbSnap.threshold { return .high(max(0, toHigh)) }
        let span = high - low
        return .fraction(span > 0 ? ((value - low) / span).clampedToRange(0...1) : 0.5)
    }

    private static func resolve(_ axis: Axis, radius: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        let value: CGFloat = switch axis {
        case let .low(distance): low + distance + radius
        case let .high(distance): high - distance - radius
        case let .fraction(fraction): low + fraction * (high - low)
        }
        return OrbSnap.clampAxis(value, radius: radius, low: low, high: high)
    }
}

extension OrbPositionRecord {
    /// The default corner (top right, `OrbSnap.defaultInset` from both usable edges) as a record: on any display it
    /// resolves to `OrbSnap.defaultCenter`.
    public static let defaultCorner = OrbPositionRecord(x: .high(OrbSnap.defaultInset), y: .high(OrbSnap.defaultInset))
}

extension OrbPositionRecord.Axis {
    /// The anchor name and value stored in JSON and in the legacy defaults dictionary.
    public var encoded: (anchor: String, value: Double) {
        switch self {
        case let .low(distance): ("low", Double(distance))
        case let .high(distance): ("high", Double(distance))
        case let .fraction(fraction): ("fraction", Double(fraction))
        }
    }

    /// Decodes an anchor and value with the clamping of the legacy store; nil for an unknown anchor or a
    /// non-finite value.
    public init?(anchor: String, value: Double) {
        guard value.isFinite else { return nil }
        let value = CGFloat(value)
        switch anchor {
        case "low": self = .low(value.clampedToRange(0...OrbSnap.threshold))
        case "high": self = .high(value.clampedToRange(0...OrbSnap.threshold))
        case "fraction": self = .fraction(value.clampedToRange(0...1))
        default: return nil
        }
    }
}

extension OrbPositionRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case xAnchor, x, yAnchor, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let x = Axis(anchor: try container.decode(String.self, forKey: .xAnchor),
                           value: try container.decode(Double.self, forKey: .x)),
              let y = Axis(anchor: try container.decode(String.self, forKey: .yAnchor),
                           value: try container.decode(Double.self, forKey: .y))
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid position"))
        }
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x.encoded.anchor, forKey: .xAnchor)
        try container.encode(x.encoded.value, forKey: .x)
        try container.encode(y.encoded.anchor, forKey: .yAnchor)
        try container.encode(y.encoded.value, forKey: .y)
    }
}

extension Comparable {
    func clampedToRange(_ range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

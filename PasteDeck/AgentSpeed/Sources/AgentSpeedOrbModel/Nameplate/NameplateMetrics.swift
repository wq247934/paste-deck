import CoreGraphics
import Foundation

/// The name plate's measures for one orb size (DESIGN 2b, Name plate, Geometry), in points.
public struct NameplateMetrics: Equatable, Sendable {
    /// No plate below this diameter (only `minimal` goes that small).
    public static let minimumDiameter: CGFloat = 80
    /// A plate stays this far inside the usable area.
    public static let areaInset: CGFloat = 3
    /// …and this far from every other disc and plate.
    public static let clearance: CGFloat = 4
    /// Discs this close (edge to edge) form a group.
    public static let groupDistance: CGFloat = 16
    /// A plate above or below stops this short of the proportional split point toward a neighbour.
    public static let neighbourMargin: CGFloat = 3

    public let diameter: CGFloat
    /// Text size `f`.
    public let fontSize: CGFloat
    /// Plate height `h`; the corner radius is `h / 2`.
    public let height: CGFloat
    /// Gap to the disc `g`.
    public let gap: CGFloat
    /// Dot diameter `d`.
    public let dot: CGFloat

    public init(diameter: CGFloat) {
        self.diameter = diameter
        let f = min(max((0.066 * diameter * 2).rounded() / 2, 9), 12)
        fontSize = f
        height = (1.78 * f).rounded()
        gap = min(max((0.034 * diameter).rounded(), 4), 7)
        dot = max(5, 0.6 * f)
    }

    public var cornerRadius: CGFloat { height / 2 }
    /// The width budget of a plate with nothing beside it: 1.5 S.
    public var aloneBudget: CGFloat { 1.5 * diameter }
    /// Each dot overlaps the previous one by a third.
    public var dotStep: CGFloat { dot * 2 / 3 }
    /// The first dot is concentric with the left end cap.
    public var leading: CGFloat { (height - dot) / 2 }
    /// From the last dot to the text.
    public var textGap: CGFloat { 0.42 * fontSize }
    public var trailing: CGFloat { 0.52 * height }
    /// Between two items of the expanded (chip) content.
    public var itemGap: CGFloat { 0.9 * fontSize }
    /// Stroke of an unavailable source's hollow ring.
    public var ringWidth: CGFloat { max(1, 0.18 * dot) }

    public func dotsWidth(_ count: Int) -> CGFloat {
        count > 0 ? dot + CGFloat(count - 1) * dotStep : 0
    }

    /// Width of the plate's fixed parts: padding, dots and the gap before the text.
    public func chrome(dots: Int) -> CGFloat {
        let dotsWidth = dotsWidth(dots)
        return (dots > 0 ? leading + dotsWidth + textGap : height / 2) + trailing
    }

    public func plateWidth(dots: Int, textWidth: CGFloat) -> CGFloat {
        chrome(dots: dots) + textWidth
    }

    /// The widest text a plate of `width` can carry.
    public func textBudget(plateWidth width: CGFloat, dots: Int) -> CGFloat {
        width - chrome(dots: dots)
    }

    /// Center of dot `index` from the plate's left edge.
    public func dotCenter(_ index: Int) -> CGFloat {
        leading + dot / 2 + CGFloat(index) * dotStep
    }

    /// Where the text starts from the plate's left edge.
    public func textStart(dots: Int) -> CGFloat {
        dots > 0 ? leading + dotsWidth(dots) + textGap : height / 2
    }

    /// Width of expanded (chip) content: each item a dot and its text, `itemGap` apart.
    public func chipWidth(_ items: [(hasDot: Bool, textWidth: CGFloat)]) -> CGFloat {
        guard !items.isEmpty else { return height }
        var width = leading + trailing + CGFloat(items.count - 1) * itemGap
        for item in items {
            width += (item.hasDot ? dot + textGap : 0) + item.textWidth
        }
        return width
    }
}

/// Text rules of the plate (DESIGN 2b, Name plate, Type).
public enum NameplateText {
    /// Letter spacing in points: +0.012 em, or +0.04 em when the text contains CJK.
    public static func tracking(for text: String, fontSize: CGFloat) -> CGFloat {
        (containsCJK(text) ? 0.04 : 0.012) * fontSize
    }

    /// Kana, CJK ideographs, Hangul syllables and full-width forms.
    public static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF,
                 0x20000...0x2FA1F:
                true
            default:
                false
            }
        }
    }
}

import AgentSpeedOrbModel
import AppKit
import CoreText

/// How the badge sets one title (DESIGN 4c, Hero title badge, Title layout), in units of the 100 × 100 badge canvas:
/// the pure layout of `TitleBadgeLayout`, measured with the system font at its heaviest weight up to Heavy, and the
/// ink box of all lines so the block is centered optically on (50, 50).
struct HeroBadgeTitle {
    let layout: TitleBadgeLayout
    /// Baseline of each line, in canvas units (y down).
    let baselines: [Double]
    /// Width of each line without its trailing tracking, in canvas units.
    let widths: [Double]
    /// The ink box of all lines, in canvas units.
    let inkTop: Double
    let inkBottom: Double
    let inkWidth: Double

    var inkHeight: Double { inkBottom - inkTop }
}

/// Layouts are computed once per text and language, then cached (DESIGN 4c).
@MainActor
final class HeroBadgeTextCache {
    private struct Key: Hashable {
        let text: String
        let language: AppLanguage
    }

    private var entries: [Key: HeroBadgeTitle] = [:]

    func title(_ text: String, language: AppLanguage) -> HeroBadgeTitle {
        let key = Key(text: text, language: language)
        if let cached = entries[key] { return cached }
        let title = Self.make(text, language: language)
        if entries.count > 128 { entries.removeAll(keepingCapacity: true) }
        entries[key] = title
        return title
    }

    /// The heaviest weight the system font offers up to Heavy (CJK fallbacks take their own heaviest).
    static let weight = NSFont.Weight.heavy

    static func font(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: weight) }

    static func line(_ text: String, size: Double, trackingEm: Double, language: AppLanguage) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: CGFloat(size)),
            .kern: CGFloat(trackingEm * size),
            NSAttributedString.Key(kCTLanguageAttributeName as String): language.rawValue,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// Advance width without the trailing tracking.
    static func width(_ text: String, size: Double, trackingEm: Double, language: AppLanguage) -> Double {
        let line = line(text, size: size, trackingEm: trackingEm, language: language)
        return CTLineGetTypographicBounds(line, nil, nil, nil) - trackingEm * size
    }

    private static func make(_ text: String, language: AppLanguage) -> HeroBadgeTitle {
        let layout = TitleBadgeLayout.layout(text, language: language.rawValue) { line, size, tracking in
            width(line, size: size, trackingEm: tracking, language: language)
        }
        var top = Double.infinity
        var bottom = -Double.infinity
        var widths: [Double] = []
        var offsets: [Double] = []
        for (index, text) in layout.lines.enumerated() {
            let line = line(text, size: layout.size, trackingEm: layout.tracking, language: language)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let base = Double(index) * layout.lineAdvance * layout.size
            top = min(top, base - Double(ink.maxY))
            bottom = max(bottom, base - Double(ink.minY))
            widths.append(CTLineGetTypographicBounds(line, nil, nil, nil) - layout.tracking * layout.size)
            offsets.append(base)
        }
        if !top.isFinite || !bottom.isFinite || bottom <= top {
            top = -layout.size * 0.72
            bottom = 0
        }
        let shift = 50 - (top + bottom) / 2
        return HeroBadgeTitle(
            layout: layout,
            baselines: offsets.map { $0 + shift },
            widths: widths,
            inkTop: top + shift,
            inkBottom: bottom + shift,
            inkWidth: widths.max() ?? 0
        )
    }
}

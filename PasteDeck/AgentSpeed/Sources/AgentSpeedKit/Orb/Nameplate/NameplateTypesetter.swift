import AgentSpeedOrbModel
import AppKit
import CoreText

/// Sets the plate's text with Core Text (DESIGN 2b, Name plate, Type): the system font, semibold, tabular digits, one
/// line, tracking +0.012 em (+0.04 em with CJK), centered by cap height or, with CJK, by the ideographic center.
/// Widths and vertical metrics are cached per size.
@MainActor
final class NameplateTypesetter {
    static let shared = NameplateTypesetter()

    private var fonts: [CGFloat: CTFont] = [:]
    private var widths: [WidthKey: CGFloat] = [:]
    private var ideographicCenters: [CGFloat: CGFloat] = [:]

    private struct WidthKey: Hashable {
        let text: String
        let size: CGFloat
        let tracking: CGFloat
    }

    func font(size: CGFloat) -> CTFont {
        if let font = fonts[size] { return font }
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold) as CTFont
        fonts[size] = font
        return font
    }

    /// The width of `text` as the plate sets it; `tracking` is the label's (from its full name).
    func width(_ text: String, size: CGFloat, tracking: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = WidthKey(text: text, size: size, tracking: tracking)
        if let width = widths[key] { return width }
        if widths.count > 2048 { widths.removeAll() }
        let line = self.line(text, size: size, tracking: tracking, color: .black)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        widths[key] = width
        return width
    }

    /// A measure for the shortening rules, with the tracking of `fullText`.
    func measure(size: CGFloat, fullText: String) -> (String) -> CGFloat {
        let tracking = NameplateText.tracking(for: fullText, fontSize: size)
        return { [unowned self] text in self.width(text, size: size, tracking: tracking) }
    }

    func line(_ text: String, size: CGFloat, tracking: CGFloat, color: RGBColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: size),
            .kern: tracking,
            .foregroundColor: color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// The baseline below the plate's vertical center (y up: subtract from the center).
    func baselineDrop(ideographic: Bool, size: CGFloat) -> CGFloat {
        ideographic ? ideographicCenter(size: size) : CTFontGetCapHeight(font(size: size)) / 2
    }

    /// Half the height of an ideograph's face above the baseline, from the font the system falls back to for CJK.
    private func ideographicCenter(size: CGFloat) -> CGFloat {
        if let center = ideographicCenters[size] { return center }
        let base = font(size: size)
        let sample = "中" as CFString
        let fallback = CTFontCreateForString(base, sample, CFRange(location: 0, length: 1))
        var characters: [UniChar] = Array("中".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var center = CTFontGetCapHeight(base) / 2
        if CTFontGetGlyphsForCharacters(fallback, &characters, &glyphs, characters.count) {
            var rect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(fallback, .horizontal, &glyphs, &rect, 1)
            if rect.height > 0 { center = rect.midY }
        }
        ideographicCenters[size] = center
        return center
    }
}

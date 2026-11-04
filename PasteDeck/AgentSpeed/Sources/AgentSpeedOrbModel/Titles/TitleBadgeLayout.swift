import Foundation

/// How the hero title badge sets a title (DESIGN 4c, Hero title badge, Title layout), in canvas units of the 100 ×
/// 100 badge canvas. Pure: the caller measures text with its own fonts.
public struct TitleBadgeLayout: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case seal
        case twoLines
        case oneLine
    }

    public var kind: Kind
    public var lines: [String]
    /// Font size in canvas units.
    public var size: Double
    /// Tracking in em.
    public var tracking: Double
    /// Line advance in em.
    public var lineAdvance: Double

    /// The width the title block may take.
    public static let maxWidth = 72.0
    static let smallest = 9.0

    /// `measure(text, size, trackingEm)` returns the advance width of one line in canvas units.
    public static func layout(_ text: String, language: String, measure: (String, Double, Double) -> Double) -> TitleBadgeLayout {
        let characters = Array(text)
        let cjk = text.unicodeScalars.contains(where: isCJK)
        let chinese = language.hasPrefix("zh")
        let tracking: (Double) -> Double = { size in cjk ? 0.04 : (size < 14 ? 0 : 0.05) }

        if chinese, characters.count == 4, text.unicodeScalars.allSatisfy(isHan) {
            return TitleBadgeLayout(kind: .seal, lines: [String(characters[0..<2]), String(characters[2..<4])], size: 21,
                                    tracking: 0.04, lineAdvance: 1.04)
        }

        let maximum: Double = characters.count == 1 ? 34 : (cjk ? 28 : (characters.count == 2 ? 26 : 22))
        var oneLine = smallest
        var size = maximum
        while size >= smallest {
            if measure(text, size, tracking(size)) <= maxWidth {
                oneLine = size
                break
            }
            size -= 0.5
        }

        let breaks = breakCandidates(characters, hanOnly: text.unicodeScalars.allSatisfy(isHan))
        if !breaks.isEmpty {
            var size = cjk ? 22.0 : 20.0
            while size >= 13 {
                if size >= 1.15 * oneLine {
                    let options = breaks.compactMap { index -> (lines: [String], widest: Double, balance: Double)? in
                        let first = String(characters[0..<index]).trimmingCharacters(in: .whitespaces)
                        let second = String(characters[index...]).trimmingCharacters(in: .whitespaces)
                        guard !first.isEmpty, !second.isEmpty else { return nil }
                        let widths = (measure(first, size, tracking(size)), measure(second, size, tracking(size)))
                        guard max(widths.0, widths.1) <= maxWidth else { return nil }
                        return ([first, second], max(widths.0, widths.1), abs(widths.0 - widths.1))
                    }
                    if let best = options.min(by: { $0.balance < $1.balance }) {
                        return TitleBadgeLayout(kind: .twoLines, lines: best.lines, size: size, tracking: tracking(size), lineAdvance: 1.1)
                    }
                }
                size -= 0.5
            }
        }
        return TitleBadgeLayout(kind: .oneLine, lines: [text], size: oneLine, tracking: tracking(oneLine), lineAdvance: 1.1)
    }

    /// Break opportunities: after every space; in Han-only text of five or more characters after the second (five) or
    /// at the middle (six or more). Runs of kana or Latin letters never break.
    static func breakCandidates(_ characters: [Character], hanOnly: Bool) -> [Int] {
        var result: [Int] = []
        for (index, character) in characters.enumerated() where character == " " && index > 0 && index < characters.count - 1 {
            result.append(index)
        }
        if result.isEmpty, hanOnly, characters.count >= 5 {
            result.append(characters.count == 5 ? 2 : characters.count / 2)
        }
        return result
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true
        default: false
        }
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xAC00...0xD7AF, 0xFF66...0xFF9F: true
        default: isHan(scalar)
        }
    }
}

import AgentSpeedCore
import Foundation

/// The name a plate carries, kept structured so it can be shortened by the rules of DESIGN 2b (Name plate, Content).
public enum NameplateName: Equatable, Hashable, Sendable {
    case custom(String)
    case allSources(String)
    case single(String)
    case pair(String, String)
    /// The first source and the number of the others.
    case more(String, Int)
}

/// One colour dot of a plate.
public enum NameplateDot: Equatable, Hashable, Sendable {
    /// Filled in the source color.
    case source(SourceKind)
    /// An unavailable source: a hollow ring in the secondary color.
    case unavailable(SourceKind)
    /// All sources: a conic gradient through every source color.
    case spectrum
}

/// What a plate shows at rest: its dots and its name.
public struct NameplateLabel: Equatable, Hashable, Sendable {
    public static let maxDots = 3

    public var name: NameplateName
    public var dots: [NameplateDot]

    public init(name: NameplateName, dots: [NameplateDot]) {
        self.name = name
        self.dots = dots
    }

    /// The custom name, else the automatic one, with one dot per tracked source (at most three, unavailable ones hollow)
    /// or the spectrum dot for all sources.
    public static func make(config: OrbConfig, namer: OrbNamer, unavailable: Set<SourceKind>) -> NameplateLabel {
        let known = config.sources.knownSources
        let dots: [NameplateDot] = known.isEmpty
            ? [.spectrum]
            : known.prefix(maxDots).map { unavailable.contains($0) ? .unavailable($0) : .source($0) }
        if let custom = config.name { return NameplateLabel(name: .custom(custom), dots: dots) }
        let name: NameplateName = switch known.count {
        case 0: .allSources(namer.allSources)
        case 1: .single(namer.sourceName(known[0]))
        case 2: .pair(namer.sourceName(known[0]), namer.sourceName(known[1]))
        default: .more(namer.sourceName(known[0]), known.count - 1)
        }
        return NameplateLabel(name: name, dots: dots)
    }
}

/// Shortening within a width budget; the type never shrinks (DESIGN 2b, Name plate): `A + B` → `A +1` → `A… +1`;
/// `A +n` → `A… +n`; one source, all sources or a custom name → a tail ellipsis on a grapheme boundary.
public enum NameplateShortening {
    public static let ellipsis = "…"

    public struct Result: Equatable, Sendable {
        public var text: String
        public var width: CGFloat
        /// False when even the shortest form is wider than the budget.
        public var fits: Bool
        /// Whether the text differs from the full name.
        public var isShortened: Bool
    }

    /// The full text of a name.
    public static func fullText(_ name: NameplateName, namer: OrbNamer) -> String {
        switch name {
        case let .custom(text), let .allSources(text), let .single(text): text
        case let .pair(first, second): namer.pair(first, second)
        case let .more(first, count): namer.more(first, count)
        }
    }

    /// The longest form of `name` whose measured width is at most `budget`.
    public static func fit(_ name: NameplateName, namer: OrbNamer, budget: CGFloat, measure: (String) -> CGFloat) -> Result {
        let full = fullText(name, namer: namer)
        let fullWidth = measure(full)
        if fullWidth <= budget { return Result(text: full, width: fullWidth, fits: true, isShortened: false) }
        switch name {
        case let .custom(text), let .allSources(text), let .single(text):
            return ellipsized(text, budget: budget, measure: measure) { $0 }
        case let .pair(first, _):
            let more = namer.more(first, 1)
            let width = measure(more)
            if width <= budget { return Result(text: more, width: width, fits: true, isShortened: true) }
            return ellipsized(first, budget: budget, measure: measure) { namer.more($0, 1) }
        case let .more(first, count):
            return ellipsized(first, budget: budget, measure: measure) { namer.more($0, count) }
        }
    }

    /// The plate for `label` within a width `budget`: the shortened text and the plate's width.
    public static func plate(
        _ label: NameplateLabel, metrics: NameplateMetrics, namer: OrbNamer, budget: CGFloat, measure: (String) -> CGFloat
    ) -> (text: Result, width: CGFloat) {
        let dots = label.dots.count
        let text = fit(label.name, namer: namer, budget: metrics.textBudget(plateWidth: budget, dots: dots), measure: measure)
        return (text, metrics.plateWidth(dots: dots, textWidth: text.width))
    }

    /// The longest grapheme prefix of `text` (at least one), trimmed and followed by `…`, that fits once wrapped by
    /// `compose`.
    public static func ellipsized(
        _ text: String, budget: CGFloat, measure: (String) -> CGFloat, compose: (String) -> String
    ) -> Result {
        let characters = Array(text)
        func candidate(_ count: Int) -> String {
            let head = String(characters.prefix(count)).trimmingCharacters(in: .whitespaces)
            return compose(head + ellipsis)
        }
        var low = 1
        var high = max(1, characters.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if measure(candidate(middle)) <= budget { low = middle } else { high = middle - 1 }
        }
        let text = candidate(low)
        let width = measure(text)
        return Result(text: text, width: width, fits: width <= budget, isShortened: true)
    }
}

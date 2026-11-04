import AgentSpeedCore
import AgentSpeedOrbModel
import Foundation

/// What one orb's plate says (DESIGN 2b, Name plate, Content): its label in the plate's metrics, shortened to a width
/// budget, and the chip content it widens to.
@MainActor
struct OrbNameplateContent: Equatable {
    let label: NameplateLabel
    let metrics: NameplateMetrics
    let fullText: String
    private let namer: OrbNamer

    init(label: NameplateLabel, metrics: NameplateMetrics, namer: OrbNamer) {
        self.label = label
        self.metrics = metrics
        self.namer = namer
        fullText = NameplateShortening.fullText(label.name, namer: namer)
    }

    nonisolated static func == (lhs: OrbNameplateContent, rhs: OrbNameplateContent) -> Bool {
        lhs.label == rhs.label && lhs.metrics == rhs.metrics && lhs.fullText == rhs.fullText
    }

    private var tracking: CGFloat { NameplateText.tracking(for: fullText, fontSize: metrics.fontSize) }

    /// The plate at rest within `budget`, and whether it fits.
    func collapsed(budget: CGFloat) -> (face: NameplateFace, fits: Bool) {
        let typesetter = NameplateTypesetter.shared
        let measure = typesetter.measure(size: metrics.fontSize, fullText: fullText)
        let plate = NameplateShortening.plate(label, metrics: metrics, namer: namer, budget: budget, measure: measure)
        let face = NameplateFace.collapsed(dots: label.dots, text: plate.text.text, metrics: metrics, tracking: tracking,
                                           textWidth: plate.text.width, ideographic: NameplateText.containsCJK(fullText))
        return (face, plate.text.fits && plate.width <= budget + 0.01)
    }

    /// The width at rest within `budget` for the placement solver; nil when even the shortest form does not fit.
    func restWidth(budget: CGFloat) -> CGFloat? {
        let result = collapsed(budget: budget)
        return result.fits ? result.face.width : nil
    }

    /// The chip content in the plate's metrics; nil when it would read the same as `face` (nothing moves).
    func expanded(_ items: [NameplateFace.Item], comparedTo face: NameplateFace) -> NameplateFace? {
        guard !items.isEmpty else { return nil }
        if items.count == 1, face.runs.count == 1, items[0].text == face.runs[0].text, items[0].role == .text,
           face.dots.map(\.dot) == [items[0].dot].compactMap({ $0 }) {
            return nil
        }
        let typesetter = NameplateTypesetter.shared
        let size = metrics.fontSize
        return NameplateFace.expanded(items, metrics: metrics) { text, tracking in
            typesetter.width(text, size: size, tracking: tracking)
        }
    }
}

/// Builds plate content from the app's state.
@MainActor
enum OrbNameplateContentBuilder {
    static func content(model: AgentSpeedModel, config: OrbConfig) -> OrbNameplateContent {
        let namer = model.orbs.namer(model.l10n)
        let unavailable = Set(model.orbs.dots(of: config.id).filter { !$0.available }.map(\.source))
        let label = NameplateLabel.make(config: config, namer: namer, unavailable: unavailable)
        return OrbNameplateContent(label: label, metrics: NameplateMetrics(diameter: CGFloat(config.size)), namer: namer)
    }

    /// The source chip's content (DESIGN 2b, Identity at a glance), one item per source, unavailable ones with their
    /// status (`Gemini CLI · 未偵測到`); all sources: the spectrum dot and `orbs.sources.all`.
    static func items(model: AgentSpeedModel, config: OrbConfig) -> [NameplateFace.Item] {
        let l10n = model.l10n
        let dots = model.orbs.dots(of: config.id)
        guard !dots.isEmpty else {
            return [NameplateFace.Item(dot: .spectrum, text: l10n("orbs.sources.all"), role: .text)]
        }
        let statuses = Dictionary(model.snapshot.sources.map { ($0.kind, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        let fallback = model.orbs.runtime(config.id)?.feed.unavailableTitleKey ?? "source.notFound"
        return dots.map { dot in
            let name = l10n(dot.source.titleKey)
            guard !dot.available else { return NameplateFace.Item(dot: .source(dot.source), text: name, role: .text) }
            let reason = statuses[dot.source].map { $0 ? "source.notFound" : "source.disabled" } ?? fallback
            return NameplateFace.Item(dot: .unavailable(dot.source), text: name + " · " + l10n(reason), role: .secondary)
        }
    }
}

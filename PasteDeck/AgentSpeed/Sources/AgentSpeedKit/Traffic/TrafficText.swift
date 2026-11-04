import AgentSpeedCore
import AppKit

/// Traffic wording shared by the dashboard, the menu bar, history and accessibility (DESIGN 10, Formatting): rates in
/// the chosen unit, totals always in bytes, pairs as `↓ 48.2 MB · ↑ 3.10 MB`, and the spoken forms without arrows.
@MainActor
struct TrafficText {
    let l10n: Localizer
    let bits: Bool

    init(model: AgentSpeedModel) {
        l10n = model.l10n
        bits = model.settings.trafficUnit == .bits
    }

    init(l10n: Localizer, bits: Bool) {
        self.l10n = l10n
        self.bits = bits
    }

    func rate(_ bytesPerSecond: Double) -> TrafficFormat.Parts { TrafficFormat.rateParts(bytesPerSecond, bits: bits) }

    /// `↓ 48.2 MB · ↑ 3.10 MB`.
    func pair(_ bytes: TrafficBytes) -> String {
        l10n("traffic.pair", TrafficFormat.total(bytes.rx), TrafficFormat.total(bytes.tx))
    }

    /// `今天下載 48.2 MB，上傳 3.10 MB` (`traffic.a11y.totals`).
    func spokenTotals(_ bytes: TrafficBytes) -> String {
        l10n("traffic.a11y.totals", TrafficFormat.total(bytes.rx), TrafficFormat.total(bytes.tx))
    }

    /// `下載 48.2 MB，上傳 3.10 MB` (`traffic.a11y.pair`): a day's or range's bytes read aloud, where the context names it.
    func spokenPair(_ bytes: TrafficBytes) -> String {
        l10n("traffic.a11y.pair", TrafficFormat.total(bytes.rx), TrafficFormat.total(bytes.tx))
    }

    /// `下載每秒 12.4 MB，上傳每秒 186 KB` (`a11y.orb.traffic`): rates read as words, units as written.
    func spokenRates(_ rate: TrafficRate) -> String {
        l10n("a11y.orb.traffic", Self.spoken(self.rate(rate.rx)), Self.spoken(self.rate(rate.tx)))
    }

    static func spoken(_ parts: TrafficFormat.Parts) -> String {
        let unit = parts.unit.hasSuffix("/s") ? String(parts.unit.dropLast(2)) : parts.unit
        return parts.number + " " + unit
    }

    /// The reason per-agent traffic is unavailable, for captions.
    func reason(_ reason: TrafficUnavailableReason) -> String {
        switch reason {
        case .sampler: l10n("traffic.unavailable.sampler")
        case .helperMissing: l10n("traffic.unavailable.helperMissing")
        case .helperStopped: l10n("traffic.unavailable.helperStopped")
        case .helperOutdated: l10n("traffic.unavailable.helperOutdated")
        case .denied: l10n("traffic.unavailable.denied")
        }
    }
}

/// Widths of the fixed cells a rate updates in (DESIGN 10): the number as wide as `8.88` in tabular digits, the unit as
/// wide as `MB/s` (bits: `Mb/s`), so a readout never changes width or position.
@MainActor
enum TrafficCells {
    private struct Key: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var unitSize: CGFloat
        var bits: Bool
    }

    private static var cache: [Key: (number: CGFloat, unit: CGFloat)] = [:]

    static func widths(size: CGFloat, weight: NSFont.Weight, unitSize: CGFloat? = nil, unitWeight: NSFont.Weight? = nil,
                       bits: Bool) -> (number: CGFloat, unit: CGFloat) {
        let unitSize = unitSize ?? size
        let key = Key(size: size, weight: weight.rawValue, unitSize: unitSize, bits: bits)
        if let cached = cache[key] { return cached }
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        }
        let value = (width("8.88", .monospacedDigitSystemFont(ofSize: size, weight: weight)),
                     width(bits ? "Mb/s" : "MB/s", .systemFont(ofSize: unitSize, weight: unitWeight ?? weight)))
        cache[key] = value
        return value
    }
}

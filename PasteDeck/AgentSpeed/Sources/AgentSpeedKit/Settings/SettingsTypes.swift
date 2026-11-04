import AgentSpeedCore
import Foundation

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark

    public var id: String { rawValue }
    public var titleKey: String { "appearance.\(rawValue)" }
}

public enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"
    case en
    case ja

    public var id: String { rawValue }

    public var resolved: AppLanguage {
        switch self {
        case .system: AppLanguage.system
        case .zhHant: .zhHant
        case .zhHans: .zhHans
        case .en: .en
        case .ja: .ja
        }
    }

    public var titleKey: String {
        switch self {
        case .system: "settings.language.system"
        case .zhHant: "language.zhHant"
        case .zhHans: "language.zhHans"
        case .en: "language.en"
        case .ja: "language.ja"
        }
    }
}

public enum BarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case glyphValue, value, glyph

    public var id: String { rawValue }
    public var titleKey: String { "settings.bar.mode.\(rawValue)" }
    public var showsGlyph: Bool { self != .value }
    public var showsValue: Bool { self != .glyph }
}

/// The unit of traffic rates (DESIGN 10): bytes (default) or bits; totals are always bytes.
public enum TrafficUnit: String, CaseIterable, Identifiable, Sendable {
    case bytes, bits

    public var id: String { rawValue }
    public var titleKey: String { "settings.traffic.unit.\(rawValue)" }
}

/// The menu bar's network block after the value (DESIGN 10, Menu bar and taskbar): network speed of this computer or
/// of the agents. An unknown stored value reads as `off`; 性能 has a switch of its own (`AgentSpeedSettings.barIntelligence`).
public enum BarTraffic: String, CaseIterable, Identifiable, Sendable {
    case off, machine, agents

    public var id: String { rawValue }
    public var titleKey: String { "settings.bar.traffic.\(rawValue)" }
    /// The two network choices, which need traffic measuring.
    public var isNetwork: Bool { self == .machine || self == .agents }
}

/// The live value's unit (DESIGN 9): token speed or the API-equivalent cost per second.
public enum LiveUnit: String, CaseIterable, Identifiable, Sendable {
    case tokens, cost

    public var id: String { rawValue }
}

public enum EffectsLevel: String, CaseIterable, Identifiable, Comparable, Sendable {
    case off, soft, standard, max

    public var id: String { rawValue }
    public var titleKey: String { "effects.\(rawValue)" }

    private var rank: Int {
        switch self {
        case .off: 0
        case .soft: 1
        case .standard: 2
        case .max: 3
        }
    }

    public static func < (lhs: EffectsLevel, rhs: EffectsLevel) -> Bool { lhs.rank < rhs.rank }
}

enum OrbSizePreset: CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: Self { self }

    var diameter: Double {
        switch self {
        case .small: 112
        case .medium: 148
        case .large: 196
        }
    }

    var titleKey: String {
        switch self {
        case .small: "menu.size.small"
        case .medium: "menu.size.medium"
        case .large: "menu.size.large"
        }
    }
}

extension SpeedMetric: Identifiable {
    public var id: String { rawValue }

    public var titleKey: String { self == .output ? "metric.output" : "metric.total" }
}

extension SourceKind {
    public var titleKey: String { "source.\(rawValue)" }
}

public enum SettingsLimits {
    /// Output-speed redline range; kept for callers that predate per-metric redlines.
    static let redline: ClosedRange<Double> = 50...2000
    static let redlineStep: Double = 50
    static let redlineTotal: ClosedRange<Double> = 20_000...2_000_000

    public static func redlineRange(for metric: SpeedMetric) -> ClosedRange<Double> {
        metric == .output ? redline : redlineTotal
    }

    /// The slider's maximum (DESIGN 1).
    public static func defaultRedline(for metric: SpeedMetric) -> Double {
        metric == .output ? 2000 : 2_000_000
    }

    /// The default before it moved to the maximum: a stored value equal to it counts as never set (DESIGN 1).
    public static func formerDefaultRedline(for metric: SpeedMetric) -> Double {
        metric == .output ? 400 : 200_000
    }

    /// The redline to start from: a stored former default moves to the new default once (when `migrated` is false);
    /// any other stored value is kept.
    public static func startingRedline(stored: Double?, metric: SpeedMetric, migrated: Bool) -> Double {
        guard let stored else { return defaultRedline(for: metric) }
        if !migrated, stored == formerDefaultRedline(for: metric) { return defaultRedline(for: metric) }
        return stored
    }

    /// Slider increment at a value: 50 tok/s for output; two significant digits for total throughput
    /// (1k steps below 100k, 10k below 1M, 100k above), so the slider feels logarithmic.
    public static func redlineStep(at value: Double, metric: SpeedMetric) -> Double {
        guard metric == .total else { return redlineStep }
        let magnitude = floor(log10(max(value, 1)))
        return pow(10, max(3, magnitude - 1))
    }

    public static func snapRedline(_ value: Double, metric: SpeedMetric) -> Double {
        let range = redlineRange(for: metric)
        let value = value.isFinite ? value.clamped(to: range) : defaultRedline(for: metric)
        let step = redlineStep(at: value, metric: metric)
        return ((value / step).rounded() * step).clamped(to: range)
    }

    /// Maps a slider position (0...1) to a redline: linear for output, logarithmic for total throughput.
    public static func redline(atPosition position: Double, metric: SpeedMetric) -> Double {
        let range = redlineRange(for: metric)
        let p = position.clamped(to: 0...1)
        let raw = metric == .output
            ? range.lowerBound + (range.upperBound - range.lowerBound) * p
            : range.lowerBound * pow(range.upperBound / range.lowerBound, p)
        return snapRedline(raw, metric: metric)
    }

    public static func position(ofRedline value: Double, metric: SpeedMetric) -> Double {
        let range = redlineRange(for: metric)
        let value = value.clamped(to: range)
        if metric == .output {
            return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        }
        return log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }
}

/// 菜单栏速度显示模式（PasteDeck 集成新增，DESIGN 2b 菜单栏块）：
/// 仅额度保持 PasteDeck 升级前的默认行为，两者都关时状态栏只显示图标。
public enum SpeedBarDisplay: String, CaseIterable, Identifiable, Hashable, Sendable {
    public var id: String { rawValue }
    /// 仅显示额度。
    case quotaOnly
    /// 仅显示实时速度。
    case speedOnly
    /// 额度 + 实时速度。
    case both
    /// 都不显示。
    case off

    /// 设置菜单与界面用的展示名。
    public var title: String {
        switch self {
        case .quotaOnly: "仅显示额度"
        case .speedOnly: "仅显示实时速度"
        case .both: "额度＋实时速度"
        case .off: "不显示额外数据"
        }
    }
}

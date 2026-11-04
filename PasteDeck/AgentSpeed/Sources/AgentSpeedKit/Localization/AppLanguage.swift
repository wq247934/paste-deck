import Foundation

/// A language the app ships strings for.
public enum AppLanguage: String, CaseIterable, Sendable {
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"
    case en
    case ja

    /// Locale used for text shaping (Han glyph variants) and number formatting.
    public var locale: Locale {
        switch self {
        case .zhHant: Locale(identifier: "zh-Hant-TW")
        case .zhHans: Locale(identifier: "zh-Hans-CN")
        case .en: Locale(identifier: "en-US")
        case .ja: Locale(identifier: "ja-JP")
        }
    }

    public var usesLatinCase: Bool { self == .en }

    /// DESIGN section 0: zh-HK/zh-MO/zh-TW → zh-Hant, other zh → zh-Hans, ja → ja, everything else → en.
    public static func resolve(identifier: String) -> AppLanguage {
        let language = Locale.Language(identifier: identifier)
        switch language.languageCode?.identifier {
        case "zh":
            if let script = language.script?.identifier {
                return script == "Hant" ? .zhHant : .zhHans
            }
            let region = language.region?.identifier
            return ["TW", "HK", "MO"].contains(region ?? "") ? .zhHant : .zhHans
        case "ja":
            return .ja
        default:
            return .en
        }
    }

    public static var system: AppLanguage {
        resolve(identifier: Locale.preferredLanguages.first ?? "en")
    }
}

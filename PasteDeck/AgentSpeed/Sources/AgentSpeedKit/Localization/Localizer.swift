import Foundation
import Observation

/// Looks up UI strings in the generated table for the active language. Observable so views re-render on switch.
@MainActor
@Observable
public final class Localizer {
    public private(set) var language: AppLanguage

    @ObservationIgnored private var preference: LanguagePreference
    @ObservationIgnored private var localeObserver: NSObjectProtocol?

    public init(preference: LanguagePreference) {
        self.preference = preference
        language = preference.resolved
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public var locale: Locale { language.locale }

    public func apply(_ preference: LanguagePreference) {
        self.preference = preference
        refresh()
    }

    public func callAsFunction(_ key: String) -> String {
        Self.string(key, language: language)
    }

    public func callAsFunction(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: Self.string(key, language: language), locale: language.locale, arguments: arguments)
    }

    public nonisolated static func string(_ key: String, language: AppLanguage) -> String {
        guard let entry = StringTable.entries[key] else {
            assertionFailure("Missing string key \(key)")
            return key
        }
        switch language {
        case .zhHant: return entry.zhHant
        case .zhHans: return entry.zhHans
        case .en: return entry.en
        case .ja: return entry.ja
        }
    }

    private func refresh() {
        let resolved = preference.resolved
        if resolved != language { language = resolved }
    }
}

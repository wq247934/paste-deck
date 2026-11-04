import AgentSpeedCore
import AgentSpeedOrbModel
import AppKit
import Observation

/// An undo offered for 8 s after a custom title set is deleted or reset (DESIGN 5, Title themes).
struct TitleThemesUndo: Identifiable, Equatable {
    enum Kind: Equatable {
        case delete(name: String)
        case reset(name: String)
    }

    let id = UUID()
    let kind: Kind
    let previous: TitleThemesDocument
    /// The orbs document before a delete replaced its references.
    let previousOrbs: OrbsDocument?
    let expires: Date

    static func == (lhs: TitleThemesUndo, rhs: TitleThemesUndo) -> Bool { lhs.id == rhs.id }
}

/// Uncommitted text of one custom title field (the editor's live preview).
struct TitleDraft: Equatable {
    var setID: String
    var level: Int
    var text: String
}

/// What committing a custom title field did (DESIGN 1, text rules and length).
struct TitleCommit: Equatable {
    var text: String
    var removedEmoji: Bool
    var cut: Bool
}

/// The title themes setting (DESIGN 1): the General theme, the custom sets and their editing, persisted as one JSON
/// value (`titleThemes`), and the titles every surface shows.
@MainActor
@Observable
public final class TitleThemesController {
    static let undoDuration: TimeInterval = 8

    private(set) var document: TitleThemesDocument
    private(set) var undoBanner: TitleThemesUndo?
    /// Text being typed in the custom set editor and not committed yet: every surface already shows it, so the editor's
    /// previews follow the typing without a transition (DESIGN 5, Live preview).
    private(set) var draft: TitleDraft?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var model: AgentSpeedModel?
    @ObservationIgnored private var undoTimer: Timer?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        document = TitleThemesDocument(data: defaults.data(forKey: TitleThemesDocument.defaultsKey)) ?? TitleThemesDocument()
    }

    public func activate(model: AgentSpeedModel) {
        self.model = model
    }

    // MARK: Resolution

    /// The General theme (dashboard, Settings → General, menu bar accessibility).
    var general: TitleTheme { applyingDraft(document.general) }

    /// A floating orb's theme: its own, else General (DESIGN 2b `titleTheme`).
    func theme(forOrb config: OrbConfig?) -> TitleTheme { applyingDraft(document.orbTheme(config?.titleTheme)) }

    /// Shows uncommitted text of a field everywhere until it is committed or abandoned.
    func setDraft(level: Int, of id: String, text: String) {
        let next = TitleDraft(setID: id, level: level, text: text)
        if draft != next { draft = next }
    }

    func clearDraft() {
        if draft != nil { draft = nil }
    }

    private func applyingDraft(_ theme: TitleTheme) -> TitleTheme {
        guard let draft, case .custom(var set) = theme, set.id == draft.setID else { return theme }
        set.setField(level: draft.level, TitleText.sanitize(draft.text).text)
        return .custom(set)
    }

    /// The text of a speed title in a theme, as typed (editor, title list, accessibility).
    func text(_ title: SpeedTitle, in theme: TitleTheme, l10n: Localizer) -> String {
        theme.text(level: title.rawValue, localized: { l10n($0) })
    }

    /// The text as the readout and the badge draw it: Latin uppercase when the app language is English.
    func label(_ title: SpeedTitle, in theme: TitleTheme, l10n: Localizer) -> String {
        TitleText.displayCase(text(title, in: theme, l10n: l10n), english: l10n.language == .en)
    }

    func name(of theme: TitleTheme, l10n: Localizer) -> String { theme.name(localized: { l10n($0) }) }

    // MARK: Editing

    func select(_ id: String) {
        setDocument(TitleThemeEditing.select(id, in: document))
    }

    /// Duplicates `sourceID` into a new selected custom set; nil at eight sets.
    @discardableResult
    func copy(_ sourceID: String) -> String? {
        guard let model, let source = document.theme(id: sourceID) else { return nil }
        let l10n = model.l10n
        let id = UUID().uuidString
        guard let next = TitleThemeEditing.copy(sourceID, in: document, newID: id, sourceName: name(of: source, l10n: l10n),
                                                copyName: { l10n("titles.custom.copyName", $0) }) else { return nil }
        setDocument(next)
        return id
    }

    /// Deletes a custom set without confirmation; General and orb references fall back to its base; 8 s undo.
    func delete(_ id: String) {
        guard let set = document.customSet(id), let result = TitleThemeEditing.delete(id, in: document) else { return }
        let previous = document
        let previousOrbs = model?.orbs.replaceTitleTheme(id, with: result.base.rawValue)
        setDocument(result.document)
        offerUndo(.delete(name: set.name), previous: previous, previousOrbs: previousOrbs)
    }

    func rename(_ id: String, to name: String) {
        setDocument(TitleThemeEditing.rename(id, to: name, in: document))
    }

    func setBase(_ base: TitlePreset, of id: String) {
        setDocument(TitleThemeEditing.setBase(base, of: id, in: document))
    }

    /// Applies the text rules and the length budget of the current language, then stores the field.
    @discardableResult
    func commitField(level: Int, of id: String, text: String) -> TitleCommit {
        let clean = TitleText.sanitize(text)
        let language = model?.l10n.language ?? .en
        let fitted = TitleText.fitted(clean.text, maxWidth: TitleText.maximumWidth) { TitleMeasure.w7($0, language: language) }
        setDocument(TitleThemeEditing.setField(level: level, of: id, to: fitted.text, in: document))
        clearDraft()
        return TitleCommit(text: fitted.text, removedEmoji: clean.removedEmoji, cut: fitted.cut)
    }

    func resetAll(_ id: String) {
        guard let set = document.customSet(id) else { return }
        let previous = document
        setDocument(TitleThemeEditing.resetAll(id, in: document))
        offerUndo(.reset(name: set.name), previous: previous, previousOrbs: nil)
    }

    // MARK: Undo

    func undo() {
        guard let banner = undoBanner else { return }
        dismissUndo()
        setDocument(banner.previous)
        if let orbs = banner.previousOrbs { model?.orbs.restoreTitleThemes(from: orbs) }
    }

    func dismissUndo() {
        undoTimer?.invalidate()
        undoTimer = nil
        undoBanner = nil
    }

    func undoMessage(_ l10n: Localizer) -> String {
        switch undoBanner?.kind {
        case .delete(let name)?: l10n("titles.custom.didDelete", name)
        case .reset(let name)?: l10n("titles.custom.didReset", name)
        case nil: ""
        }
    }

    private func offerUndo(_ kind: TitleThemesUndo.Kind, previous: TitleThemesDocument, previousOrbs: OrbsDocument?) {
        undoTimer?.invalidate()
        let banner = TitleThemesUndo(kind: kind, previous: previous, previousOrbs: previousOrbs,
                                     expires: Date().addingTimeInterval(Self.undoDuration))
        undoBanner = banner
        let timer = Timer(timeInterval: Self.undoDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.undoBanner?.id == banner.id else { return }
                self.undoBanner = nil
                self.undoTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        undoTimer = timer
    }

    private func setDocument(_ next: TitleThemesDocument) {
        guard next != document else { return }
        document = next
        defaults.set(next.data(), forKey: TitleThemesDocument.defaultsKey)
    }
}

/// Title widths in the readout's title style (DESIGN 1, Title length).
enum TitleMeasure {
    /// `w7`: semibold system font at the 7 pt floor, tracking 0, uppercase when English.
    static func w7(_ text: String, language: AppLanguage) -> Double {
        width(TitleText.displayCase(text, english: language == .en), size: 7, weight: .semibold, language: language)
    }

    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0, language: AppLanguage) -> Double {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .kern: tracking,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language.rawValue,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}

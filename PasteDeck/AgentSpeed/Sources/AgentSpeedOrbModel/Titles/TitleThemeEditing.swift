import Foundation

/// Operations on the title themes setting (DESIGN 1, Custom title sets). Each is pure; the app keeps the previous
/// document (and the orbs document) to undo a delete or a reset for 8 s.
public enum TitleThemeEditing {
    /// A new custom set copied from `sourceID` (a preset or a custom set), appended and selected. Its base is the
    /// preset the source is (or is based on); a custom source also passes on its texts. Nil at eight sets or for an
    /// unknown source. `copyName` formats `titles.custom.copyName` with the source's name.
    public static func copy(
        _ sourceID: String,
        in doc: TitleThemesDocument,
        newID: String,
        sourceName: String,
        copyName: (String) -> String
    ) -> TitleThemesDocument? {
        guard doc.canAddCustom, let source = doc.theme(id: sourceID) else { return nil }
        var set = CustomTitleSet(id: newID, name: uniqueName(copyName(sourceName), in: doc), base: source.base)
        if case .custom(let original) = source {
            set.idle = original.idle
            set.titles = original.titles
        }
        var next = doc
        next.custom.append(set)
        next.selected = newID
        return next
    }

    /// `name`, else `name 2`, `name 3` … whichever no custom set has yet (cut to fit 32 characters).
    public static func uniqueName(_ name: String, in doc: TitleThemesDocument) -> String {
        let taken = Set(doc.custom.map(\.name))
        let base = CustomTitleSet.cleanName(name) ?? name
        guard taken.contains(base) else { return base }
        var number = 2
        while true {
            let suffix = " \(number)"
            let stem = String(base.prefix(CustomTitleSet.nameLimit - suffix.count)).trimmingCharacters(in: .whitespaces)
            let candidate = stem + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// Removes a custom set; the General selection naming it falls back to its base preset. Returns the base (orbs
    /// naming the set take it too: `OrbEditing.replacingTitleTheme`). Nil for an unknown id.
    public static func delete(_ id: String, in doc: TitleThemesDocument) -> (document: TitleThemesDocument, base: TitlePreset)? {
        guard let set = doc.customSet(id) else { return nil }
        var next = doc
        next.custom.removeAll { $0.id == id }
        if next.selected == id { next.selected = set.base.rawValue }
        return (next, set.base)
    }

    public static func select(_ id: String, in doc: TitleThemesDocument) -> TitleThemesDocument {
        guard doc.theme(id: id) != nil else { return doc }
        var next = doc
        next.selected = id
        return next
    }

    /// Committing an empty name keeps the previous one.
    public static func rename(_ id: String, to name: String, in doc: TitleThemesDocument) -> TitleThemesDocument {
        guard let index = doc.custom.firstIndex(where: { $0.id == id }), let clean = CustomTitleSet.cleanName(name) else { return doc }
        var next = doc
        next.custom[index].name = clean
        return next
    }

    /// Filled fields stay; empty ones follow the new base at once.
    public static func setBase(_ base: TitlePreset, of id: String, in doc: TitleThemesDocument) -> TitleThemesDocument {
        guard let index = doc.custom.firstIndex(where: { $0.id == id }) else { return doc }
        var next = doc
        next.custom[index].base = base
        return next
    }

    /// Stores a committed field (already sanitized and fitted by the caller); "" uses the base's title.
    public static func setField(level: Int, of id: String, to text: String, in doc: TitleThemesDocument) -> TitleThemesDocument {
        guard let index = doc.custom.firstIndex(where: { $0.id == id }) else { return doc }
        var next = doc
        next.custom[index].setField(level: level, TitleText.sanitize(text).text)
        return next
    }

    /// Empties all 14 fields.
    public static func resetAll(_ id: String, in doc: TitleThemesDocument) -> TitleThemesDocument {
        guard let index = doc.custom.firstIndex(where: { $0.id == id }) else { return doc }
        var next = doc
        next.custom[index].idle = ""
        next.custom[index].titles = Array(repeating: "", count: TitlePreset.levelCount)
        return next
    }
}

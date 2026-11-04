import AgentSpeedCore
import Foundation

/// The boards' menus as values (DESIGN 2c Interaction and window), so their content is testable; the app turns
/// them into native menus.
public enum BoardMenuModel {
    public struct SourceEntry: Equatable, Sendable {
        public var source: SourceKind
        public var checked: Bool
        /// False for the last tracked source (`orbs.sources.lastOne`).
        public var enabled: Bool
        /// `source.notFound` / `source.disabled` for an unavailable source (it stays selectable).
        public var statusKey: String?
    }

    public enum Toggle: String, Equatable, Sendable {
        case alwaysOnTop = "menu.alwaysOnTop"
        case clickThrough = "menu.clickThrough"
    }

    public enum Item: Equatable, Sendable {
        /// Disabled: the style name and the board's sources.
        case header(style: BoardStyle, sources: OrbSourceSelection)
        /// `boards.style` ▸ the three styles, check on `selected`.
        case styles(selected: BoardStyle)
        /// `orbs.sources` ▸ `orbs.sources.all`, separator, every source.
        case sources(all: Bool, entries: [SourceEntry])
        /// `boards.readouts` ▸ the three live metrics switches, each with its check.
        case readouts(BoardReadouts)
        /// `menu.size` ▸ S / M / L.
        case sizes(selected: BoardSize)
        /// `menu.effects` ▸ the global effects level.
        case effects
        case toggle(Toggle, on: Bool)
        /// `boards.add`; disabled at the limit with `boards.limit`.
        case add(enabled: Bool)
        /// `boards.remove`, asking `boards.remove.confirm`.
        case remove
        case dashboard
        /// `boards.settings` (Settings → 懸浮窗, Boards).
        case settings
        case separator
    }

    /// The context menu of `board`. `status` maps unavailable sources to their status key.
    public static func context(_ board: BoardConfig, document: BoardsDocument,
                               status: [SourceKind: String] = [:]) -> [Item] {
        let entries = SourceKind.allCases.map { source in
            let checked = !board.sources.isAll && board.sources.tracks(source)
            return SourceEntry(source: source, checked: checked,
                               enabled: !checked || board.sources.toggling(source) != nil,
                               statusKey: status[source])
        }
        return [
            .header(style: board.style, sources: board.sources),
            .separator,
            .styles(selected: board.style),
            .sources(all: board.sources.isAll, entries: entries),
            .readouts(board.readouts),
            .sizes(selected: board.size),
            .effects,
            .separator,
            .toggle(.alwaysOnTop, on: board.alwaysOnTop),
            .toggle(.clickThrough, on: board.clickThrough),
            .separator,
            .add(enabled: document.canAdd),
            .remove,
            .separator,
            .dashboard,
            .settings,
        ]
    }

    public enum QuickItem: Equatable, Sendable {
        /// `boards.show` (false) or `boards.hide` (true) for every board.
        case visibility(anyVisible: Bool)
        case add(enabled: Bool)
    }

    /// The quick menu's board items: show / hide while boards exist, then add.
    public static func quick(_ document: BoardsDocument) -> [QuickItem] {
        var items: [QuickItem] = []
        if !document.boards.isEmpty { items.append(.visibility(anyVisible: document.anyVisible)) }
        items.append(.add(enabled: document.canAdd))
        return items
    }
}

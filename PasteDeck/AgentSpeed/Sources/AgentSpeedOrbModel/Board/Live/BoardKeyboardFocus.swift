import Foundation

/// A key a focused board handles (DESIGN 12 *Keyboard*).
public enum BoardKey: Equatable, Sendable {
    case tab(backward: Bool)
    case up
    case down
    case space
    case escape

    /// The key of a key-down event (`keyCode` as AppKit reports it); nil for every other key.
    public init?(keyCode: UInt16, shift: Bool) {
        switch keyCode {
        case 48: self = .tab(backward: shift)
        case 126: self = .up
        case 125: self = .down
        case 49: self = .space
        case 53: self = .escape
        default: return nil
        }
    }
}

/// Keyboard focus on a board's score rows (DESIGN 12 *Keyboard*): while keyboard navigation is on, the group and sub
/// rows that show a score (the board's `intelligence` readout on) take focus in visual order. Tab and Shift-Tab wrap
/// around like the window's key view loop; the arrow keys stop at the ends like a list. Space shows the focused row's
/// card, a focus move keeps an open card on the focused row, Esc closes it. The focus stays on its row (its key)
/// across ticks; a row that leaves passes it to the row now in its place.
public struct BoardKeyboardFocus: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        /// The focus moved to this row (an open card follows it).
        case moved(String)
        case showCard(String)
        case closeCard
        /// Handled, nothing changes (an arrow at the end of the list, Esc without a card).
        case none
    }

    public private(set) var keys: [String] = []
    public private(set) var key: String?

    public init() {}

    /// The rows that take focus, in visual order: group and sub rows while `intelligence` is on and keyboard
    /// navigation is on; none otherwise.
    public static func keys(_ rows: [BoardPlannedRow], intelligence: Bool, keyboardNavigation: Bool) -> [String] {
        guard intelligence, keyboardNavigation else { return [] }
        return rows.compactMap { row in
            switch row.kind {
            case .group, .sub: row.key
            case .moreSubs, .moreGroups: nil
            }
        }
    }

    public var isEnabled: Bool { !keys.isEmpty }

    /// New rows: the focus keeps its row, else takes the row now at its place (the last when the list got shorter).
    public mutating func update(_ keys: [String]) {
        defer { self.keys = keys }
        guard let key, !keys.contains(key) else { return }
        guard let index = self.keys.firstIndex(of: key), !keys.isEmpty else {
            self.key = nil
            return
        }
        self.key = keys[min(index, keys.count - 1)]
    }

    /// Focuses `key` when it takes focus; true when the focus moved.
    @discardableResult
    public mutating func focus(_ key: String) -> Bool {
        guard keys.contains(key), self.key != key else { return false }
        self.key = key
        return true
    }

    /// The focus enters the board (its window became key): the focused row stays, else the first row takes it.
    @discardableResult
    public mutating func enter() -> String? {
        if key == nil { key = keys.first }
        return key
    }

    public mutating func clear() {
        key = nil
    }

    /// Handles `pressed`; nil when the board does not take it (no row takes focus).
    public mutating func handle(_ pressed: BoardKey, cardShown: Bool) -> Effect? {
        guard isEnabled else { return nil }
        switch pressed {
        case .tab(let backward): return move(by: backward ? -1 : 1, wraps: true)
        case .up: return move(by: -1, wraps: false)
        case .down: return move(by: 1, wraps: false)
        case .space:
            guard let key = key ?? enter() else { return nil }
            return .showCard(key)
        case .escape:
            return cardShown ? .closeCard : Effect.none
        }
    }

    private mutating func move(by step: Int, wraps: Bool) -> Effect {
        guard let key, let index = keys.firstIndex(of: key) else {
            let entered = step > 0 ? keys.first : keys.last
            self.key = entered
            return entered.map(Effect.moved) ?? .none
        }
        var next = index + step
        if wraps {
            next = (next % keys.count + keys.count) % keys.count
        } else if !keys.indices.contains(next) {
            return .none
        }
        guard next != index else { return .none }
        self.key = keys[next]
        return .moved(keys[next])
    }
}

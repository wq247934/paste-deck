import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedOrbModel

/// DESIGN 2c Data model `readouts` and Live metrics *Switches*: three independent switches, all on for a new board and
/// for a board saved by an earlier version, persisted with the board, in the context menu after the sources.
@Suite("Board readouts")
struct BoardReadoutsTests {
    static func decode(_ json: String) throws -> BoardConfig {
        try JSONDecoder().decode(BoardConfig.self, from: Data(json.utf8))
    }

    @Test func aBoardFromAnEarlierVersionHasEverySwitchOn() throws {
        let board = try Self.decode(#"{"id":"b","style":"neon","size":"M"}"#)
        #expect(board.readouts == .all)
    }

    @Test func missingKeysAndNonBooleansReadAsOn() throws {
        let partial = try Self.decode(#"{"id":"b","readouts":{"intelligence":false,"thinking":"no"}}"#)
        #expect(partial.readouts == BoardReadouts(intelligence: false, thinking: true, cost: true))
        let wrong = try Self.decode(#"{"id":"b","readouts":"off"}"#)
        #expect(wrong.readouts == .all)
        let numbers = try Self.decode(#"{"id":"b","readouts":{"thinking":0,"cost":false}}"#)
        #expect(numbers.readouts == BoardReadouts(intelligence: true, thinking: true, cost: false))
    }

    @Test func aStoredRowCostKeyIsIgnoredAndNotWrittenAgain() throws {
        let stored = #"{"version":1,"boards":[{"id":"b","readouts":{"intelligence":true,"thinking":false,"cost":true,"rowCost":false}}]}"#
        let document = try #require(BoardsDocument(data: Data(stored.utf8)))
        #expect(document.board("b")?.readouts == BoardReadouts(intelligence: true, thinking: false, cost: true))
        let json = try #require(String(data: document.data(), encoding: .utf8))
        #expect(json.contains(#""readouts":{"cost":true,"intelligence":true,"thinking":false}"#) && !json.contains("rowCost"))
    }

    @Test func theSwitchesPersistWithTheBoard() throws {
        var document = BoardsDocument()
        document.add(id: "b")
        document.setReadouts(BoardReadouts(intelligence: true, thinking: false, cost: true), of: "b")
        let data = document.data()
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""readouts":{"cost":true,"intelligence":true,"thinking":false}"#))
        let restored = try #require(BoardsDocument(data: data))
        #expect(restored.board("b")?.readouts == BoardReadouts(intelligence: true, thinking: false, cost: true))
    }

    @Test func addCopiesNothingAndTheSwitchesAreIndependent() throws {
        var document = BoardsDocument()
        document.add(id: "a")
        document.setReadouts(.none, of: "a")
        document.add(id: "b")
        #expect(document.board("b")?.readouts == .all)
        document.toggleReadout(.cost, of: "b")
        #expect(document.board("b")?.readouts == BoardReadouts(intelligence: true, thinking: true, cost: false))
        document.toggleReadout(.thinking, of: "b")
        document.toggleReadout(.cost, of: "b")
        #expect(document.board("b")?.readouts == BoardReadouts(intelligence: true, thinking: false, cost: true))
        #expect(document.board("a")?.readouts == BoardReadouts.none)
    }

    @Test func theContextMenuOffersTheSwitchesAfterTheSources() throws {
        var document = BoardsDocument()
        document.add(id: "b")
        document.toggleReadout(.thinking, of: "b")
        let board = try #require(document.board("b"))
        let items = BoardMenuModel.context(board, document: document)
        let sources = try #require(items.firstIndex { if case .sources = $0 { true } else { false } })
        #expect(items[sources + 1] == .readouts(BoardReadouts(intelligence: true, thinking: false, cost: true)))
        #expect(items[sources + 2] == .sizes(selected: .medium))
        #expect(BoardReadout.allCases.map(\.titleKey) == ["boards.readouts.intel", "boards.readouts.thinking", "boards.readouts.cost"])
    }

    @Test func thinkingMayHideOnlyBesideAnotherHeroReadout() {
        #expect(BoardReadouts.all.thinkingMayHide)
        #expect(!BoardReadouts(intelligence: false, thinking: true, cost: false).thinkingMayHide)
        #expect(BoardReadouts(intelligence: false, thinking: true, cost: true).thinkingMayHide)
    }
}

/// DESIGN 2c Live metrics, *Thinking hidden at zero*.
@Suite("Board thinking fold")
struct BoardThinkingFoldTests {
    @Test func zeroForThreeSecondsHidesAndAValueBringsItBack() {
        var fold = BoardThinkingFold()
        let hidden1 = fold.update(eligible: true, quiet: false, shown: "0", at: 10)
        #expect(!hidden1)
        #expect(fold.holdEnd(after: 10) == 13)
        let hidden2 = fold.update(eligible: true, quiet: false, shown: "0.0", at: 12.5)
        #expect(!hidden2)
        let hidden3 = fold.update(eligible: true, quiet: false, shown: "0", at: 13)
        #expect(hidden3)
        #expect(fold.holdEnd(after: 13) == nil)
        let hidden4 = fold.update(eligible: true, quiet: false, shown: "0.1", at: 13.5)
        #expect(!hidden4)
    }

    @Test func aValueWithinTheHoldRestartsIt() {
        var fold = BoardThinkingFold()
        fold.update(eligible: true, quiet: false, shown: "0", at: 0)
        fold.update(eligible: true, quiet: false, shown: "12", at: 2)
        fold.update(eligible: true, quiet: false, shown: "0", at: 2.5)
        let hidden5 = fold.update(eligible: true, quiet: false, shown: "0", at: 5)
        #expect(!hidden5)
        let hidden6 = fold.update(eligible: true, quiet: false, shown: "0", at: 5.5)
        #expect(hidden6)
    }

    @Test func quietKeepsTheVisibilityAndRestartsTheHold() {
        var fold = BoardThinkingFold()
        fold.update(eligible: true, quiet: false, shown: "0", at: 0)
        let hidden7 = fold.update(eligible: true, quiet: false, shown: "0", at: 3)
        #expect(hidden7)
        let hidden8 = fold.update(eligible: true, quiet: true, shown: "0", at: 4)
        #expect(hidden8, "a hidden 思考 stays hidden while quiet")
        var shown = BoardThinkingFold()
        shown.update(eligible: true, quiet: false, shown: "0", at: 0)
        shown.update(eligible: true, quiet: true, shown: "0", at: 2)
        let hidden9 = shown.update(eligible: true, quiet: false, shown: "0", at: 4)
        #expect(!hidden9, "the hold starts over after the quiet")
        let hidden10 = shown.update(eligible: true, quiet: false, shown: "0", at: 7)
        #expect(hidden10)
    }

    @Test func aloneOrSwitchedOffItNeverHides() {
        var fold = BoardThinkingFold()
        fold.update(eligible: true, quiet: false, shown: "0", at: 0)
        fold.update(eligible: true, quiet: false, shown: "0", at: 3)
        let hidden11 = fold.update(eligible: false, quiet: false, shown: "0", at: 4)
        #expect(!hidden11)
        let hidden12 = fold.update(eligible: false, quiet: false, shown: "0", at: 10)
        #expect(!hidden12)
    }
}

/// DESIGN 2c Live metrics, *Table cells*: a wider text widens a cell at once, it narrows 6 s later.
@Suite("Board cell width")
struct BoardCellWidthTests {
    @Test func widensAtOnceAndNarrowsSixSecondsAfterTheLastWideValue() {
        var cell = BoardCellWidth(base: 40)
        let width13 = cell.fit(30, at: 0)
        #expect(width13 == 40)
        let width14 = cell.fit(52, at: 1)
        #expect(width14 == 52)
        #expect(cell.narrowsAt == 7)
        let width15 = cell.fit(45, at: 4)
        #expect(width15 == 52, "still wider than the base: the hold restarts")
        let width16 = cell.fit(30, at: 9.9)
        #expect(width16 == 52)
        let width17 = cell.fit(30, at: 10)
        #expect(width17 == 40)
        #expect(cell.narrowsAt == nil)
        cell.reset(base: 44)
        #expect(cell.current == 44)
    }
}

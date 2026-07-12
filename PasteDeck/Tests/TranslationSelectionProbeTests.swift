import AppKit
import XCTest
@testable import PasteDeck

final class TranslationSelectionProbeTests: XCTestCase {
    func testPasteboardSnapshotRestoresMultipleFormatsAndItems() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteDeckTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let firstItem = NSPasteboardItem()
        firstItem.setString("原剪贴板文本", forType: .string)
        firstItem.setData(Data("rich-content".utf8), forType: .rtf)
        let secondItem = NSPasteboardItem()
        secondItem.setString("第二项", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([firstItem, secondItem]))

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("临时选区", forType: .string)
        snapshot.restore(to: pasteboard)

        let restoredItems = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restoredItems.count, 2)
        XCTAssertEqual(restoredItems[0].string(forType: .string), "原剪贴板文本")
        XCTAssertEqual(restoredItems[0].data(forType: .rtf), Data("rich-content".utf8))
        XCTAssertEqual(restoredItems[1].string(forType: .string), "第二项")
    }

    func testPasteboardSnapshotNeverIntroducesSelectionProbeMarker() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteDeckTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("用户内容", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "用户内容")
        XCTAssertFalse(pasteboard.string(forType: .string)?.hasPrefix("PasteDeck.SelectionProbe.") ?? true)
    }

    func testLeakedLegacyProbeMarkerIsNotConsideredSafeToRestore() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteDeckTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("PasteDeck.SelectionProbe.legacy", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        XCTAssertFalse(snapshot.isSafeToRestore)
    }
}

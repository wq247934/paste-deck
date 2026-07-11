import AppKit
import XCTest
@testable import PasteDeck

@MainActor
final class KeyboardFocusPanelTests: XCTestCase {
    func testPanelCanReceiveKeyboardInputWithoutApplicationActivation() {
        _ = NSApplication.shared
        let panel = KeyboardFocusPanel(
            keyboardContentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.worksWhenModal)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }
}

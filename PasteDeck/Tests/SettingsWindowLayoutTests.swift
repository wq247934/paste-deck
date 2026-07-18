import AppKit
import XCTest
@testable import PasteDeck

final class SettingsWindowLayoutTests: XCTestCase {
    func testSettingsWindowProvidesSpaciousDefaultAndSafeMinimumSizes() {
        XCTAssertEqual(SettingsWindowLayout.defaultContentSize, NSSize(width: 920, height: 680))
        XCTAssertEqual(SettingsWindowLayout.minimumContentSize, NSSize(width: 760, height: 520))
    }
}


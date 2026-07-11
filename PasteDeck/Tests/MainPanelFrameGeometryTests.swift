import AppKit
import XCTest
@testable import PasteDeck

final class MainPanelFrameGeometryTests: XCTestCase {
    func testLayoutUsesSpecifiedDefaultAndMinimumContentSizes() {
        XCTAssertEqual(MainPanelWindowLayout.horizontalDefaultContentSize, NSSize(width: 800, height: 400))
        XCTAssertEqual(MainPanelWindowLayout.verticalDefaultContentSize, NSSize(width: 480, height: 680))
        XCTAssertEqual(MainPanelWindowLayout.horizontalMinimumContentSize, NSSize(width: 520, height: 260))
        XCTAssertEqual(MainPanelWindowLayout.verticalMinimumContentSize, NSSize(width: 360, height: 420))
    }

    func testFrameInsideVisibleScreenIsPreservedExactly() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let requestedFrame = NSRect(x: 120, y: 140, width: 800, height: 400)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [visibleFrame]
        )

        XCTAssertEqual(constrainedFrame, requestedFrame)
    }

    func testFrameSpanningAdjacentConnectedDisplaysIsPreservedExactly() {
        let leftVisibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rightVisibleFrame = NSRect(x: 1000, y: 0, width: 1000, height: 800)
        let requestedFrame = NSRect(x: 820, y: 180, width: 420, height: 500)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [leftVisibleFrame, rightVisibleFrame]
        )

        XCTAssertEqual(constrainedFrame, requestedFrame)
    }

    func testFrameCrossingGapBetweenOffsetDisplaysMovesOntoVisibleArea() {
        let leftVisibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rightVisibleFrame = NSRect(x: 1000, y: 200, width: 1000, height: 600)
        let requestedFrame = NSRect(x: 820, y: 100, width: 420, height: 500)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [leftVisibleFrame, rightVisibleFrame]
        )

        XCTAssertEqual(constrainedFrame, NSRect(x: 1000, y: 200, width: 420, height: 500))
    }

    func testFrameFromDisconnectedDisplayMovesFullyOntoNearestScreen() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let requestedFrame = NSRect(x: 1800, y: 100, width: 600, height: 500)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [visibleFrame]
        )

        XCTAssertEqual(constrainedFrame, NSRect(x: 840, y: 100, width: 600, height: 500))
    }

    func testOversizedFrameShrinksToVisibleScreenBounds() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let requestedFrame = NSRect(x: -200, y: -100, width: 1800, height: 1100)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [visibleFrame]
        )

        XCTAssertEqual(constrainedFrame, visibleFrame)
    }

    func testStoredFrameBelowMinimumSizeIsExpanded() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let requestedFrame = NSRect(x: 200, y: 200, width: 300, height: 180)

        let constrainedFrame = MainPanelFrameGeometry.constrainedFrame(
            requestedFrame,
            visibleFrames: [visibleFrame],
            minimumSize: NSSize(width: 520, height: 260)
        )

        XCTAssertEqual(constrainedFrame, NSRect(x: 200, y: 200, width: 520, height: 260))
    }

    func testDefaultFrameIsCenteredInVisibleScreen() {
        let visibleFrame = NSRect(x: -1200, y: 24, width: 1200, height: 776)

        let centeredFrame = MainPanelFrameGeometry.centeredFrame(
            size: NSSize(width: 480, height: 680),
            in: visibleFrame
        )

        XCTAssertEqual(centeredFrame, NSRect(x: -840, y: 72, width: 480, height: 680))
    }
}

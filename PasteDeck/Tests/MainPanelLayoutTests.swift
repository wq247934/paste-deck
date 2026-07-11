import AppKit
import XCTest
@testable import PasteDeck

final class MainPanelLayoutTests: XCTestCase {
    func testHorizontalCardsAdaptWithinReadablePreviewBounds() {
        let compactMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .horizontal,
            viewportSize: NSSize(width: 800, height: 120)
        )
        let expandedMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .horizontal,
            viewportSize: NSSize(width: 800, height: 420)
        )

        XCTAssertEqual(compactMetrics.cardMetrics?.previewHeight, 100)
        XCTAssertEqual(compactMetrics.cardMetrics?.width, 125)
        XCTAssertEqual(expandedMetrics.cardMetrics?.previewHeight, 200)
        XCTAssertEqual(expandedMetrics.cardMetrics?.width, 250)
        XCTAssertEqual(expandedMetrics.itemSize.height, 404)
        XCTAssertEqual(expandedMetrics.horizontalPageCardCount, 3)

        let widerMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .horizontal,
            viewportSize: NSSize(width: 1_080, height: 420)
        )
        XCTAssertEqual(widerMetrics.horizontalPageCardCount, 4)
    }

    func testVerticalLayoutsUseStableHeightsAndAdaptiveGridColumns() {
        let compactListMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .verticalCompactList,
            viewportSize: NSSize(width: 480, height: 600)
        )
        let largeCardMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .verticalLargeCards,
            viewportSize: NSSize(width: 480, height: 600)
        )
        let oneColumnMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .verticalAdaptiveGrid,
            viewportSize: NSSize(width: 443, height: 600)
        )
        let twoColumnMetrics = VirtualizedCardList.CollectionLayoutMetrics.make(
            layout: .verticalAdaptiveGrid,
            viewportSize: NSSize(width: 444, height: 600)
        )

        XCTAssertEqual(compactListMetrics.itemSize.height, 72)
        XCTAssertEqual(largeCardMetrics.cardMetrics?.previewHeight, 180)
        XCTAssertEqual(largeCardMetrics.itemSize.height, 208)
        XCTAssertEqual(oneColumnMetrics.gridColumnCount, 1)
        XCTAssertEqual(twoColumnMetrics.gridColumnCount, 2)
        XCTAssertEqual(twoColumnMetrics.cardMetrics?.previewHeight, 140)
        XCTAssertEqual(twoColumnMetrics.itemSize.height, 168)
    }

    func testVerticalListNavigationStopsAtBoundaries() {
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 0,
                itemCount: 5,
                layout: .verticalCompactList,
                gridColumnCount: 1,
                direction: .up
            ),
            0
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 2,
                itemCount: 5,
                layout: .verticalLargeCards,
                gridColumnCount: 1,
                direction: .down
            ),
            3
        )
    }

    func testKeyboardNavigationRequiresSelectedCardToBeFullyVisible() {
        let horizontalViewport = NSRect(x: 0, y: 0, width: 800, height: 320)
        XCTAssertTrue(
            MainPanelCollectionViewport.contains(
                itemFrame: NSRect(x: 544, y: 8, width: 250, height: 304),
                viewport: horizontalViewport,
                isHorizontal: true
            )
        )
        XCTAssertFalse(
            MainPanelCollectionViewport.contains(
                itemFrame: NSRect(x: 794, y: 8, width: 250, height: 304),
                viewport: horizontalViewport,
                isHorizontal: true
            )
        )

        let verticalViewport = NSRect(x: 0, y: 0, width: 480, height: 600)
        XCTAssertFalse(
            MainPanelCollectionViewport.contains(
                itemFrame: NSRect(x: 16, y: 520, width: 448, height: 120),
                viewport: verticalViewport,
                isHorizontal: false
            )
        )
    }

    func testGridNavigationHandlesIncompleteFinalRow() {
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 2,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .left
            ),
            2
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 3,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .left
            ),
            2
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 0,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .right
            ),
            1
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 1,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .right
            ),
            1
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 1,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .up
            ),
            1
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 3,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .down
            ),
            4
        )
        XCTAssertEqual(
            MainPanelNavigation.nextIndex(
                currentIndex: 4,
                itemCount: 5,
                layout: .verticalAdaptiveGrid,
                gridColumnCount: 2,
                direction: .down
            ),
            4
        )
    }
}

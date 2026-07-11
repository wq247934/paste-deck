import XCTest
@testable import PasteDeck

final class LinkTitleServiceTests: XCTestCase {
    func testWebsiteFallbackUsesCompleteHost() {
        XCTAssertEqual(
            ClipboardItem.makeLinkWebsiteName(from: "https://docs.google.com/document/d/123"),
            "docs.google.com"
        )
        XCTAssertEqual(
            ClipboardItem.makeLinkWebsiteName(from: "https://example.com.tr/path"),
            "example.com.tr"
        )
        XCTAssertEqual(
            ClipboardItem.makeLinkWebsiteName(from: "https://192.168.1.1/admin"),
            "192.168.1.1"
        )
    }

    func testLinkTitleEligibilitySkipsNonPublicCandidates() {
        XCTAssertTrue(LinkTitleService.isEligible(URL(string: "https://example.com")!))
        XCTAssertTrue(LinkTitleService.isEligible(URL(string: "http://example.com/path")!))
        XCTAssertFalse(LinkTitleService.isEligible(URL(string: "ftp://example.com/file")!))
        XCTAssertFalse(LinkTitleService.isEligible(URL(string: "https://localhost:8080")!))
        XCTAssertFalse(LinkTitleService.isEligible(URL(string: "https://192.168.1.1/admin")!))
        XCTAssertFalse(LinkTitleService.isEligible(URL(string: "https://user:password@example.com")!))
    }

    func testNewClipboardItemStartsWithoutTitleFetchState() {
        let item = ClipboardItem(contentType: .link, textContent: "https://example.com")

        XCTAssertNil(item.linkPageTitle)
        XCTAssertNil(item.linkTitleRequestedAt)
        XCTAssertNil(item.linkTitleFetchedAt)
        XCTAssertEqual(item.linkWebsiteName, "example.com")
    }
}

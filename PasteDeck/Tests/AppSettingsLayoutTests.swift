import Foundation
import SwiftData
import XCTest
@testable import PasteDeck

@MainActor
final class AppSettingsLayoutTests: XCTestCase {
    func testLayoutEnumsKeepStableRawValues() {
        XCTAssertEqual(PanelOrientation.horizontal.rawValue, 0)
        XCTAssertEqual(PanelOrientation.vertical.rawValue, 1)
        XCTAssertEqual(VerticalPanelStyle.compactList.rawValue, 0)
        XCTAssertEqual(VerticalPanelStyle.largeCards.rawValue, 1)
        XCTAssertEqual(VerticalPanelStyle.adaptiveGrid.rawValue, 2)
    }

    func testLayoutFacadeFallsBackForMissingAndUnknownValues() {
        let settings = AppSettings()

        XCTAssertNil(settings.panelOrientationRawValue)
        XCTAssertNil(settings.verticalPanelStyleRawValue)
        XCTAssertEqual(settings.panelOrientation, .horizontal)
        XCTAssertEqual(settings.verticalPanelStyle, .compactList)

        settings.panelOrientationRawValue = 99
        settings.verticalPanelStyleRawValue = 99

        XCTAssertEqual(settings.panelOrientation, .horizontal)
        XCTAssertEqual(settings.verticalPanelStyle, .compactList)
    }

    func testLayoutSettingsRoundTripThroughPersistentStore() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeck-AppSettingsLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("settings.store")
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)
        let writingContext = ModelContext(container)
        let settings = AppSettings()
        settings.panelOrientation = .vertical
        settings.verticalPanelStyle = .adaptiveGrid
        writingContext.insert(settings)
        try writingContext.save()

        let readingContext = ModelContext(container)
        let persistedSettings = try XCTUnwrap(readingContext.fetch(FetchDescriptor<AppSettings>()).first)

        XCTAssertEqual(persistedSettings.panelOrientationRawValue, PanelOrientation.vertical.rawValue)
        XCTAssertEqual(persistedSettings.verticalPanelStyleRawValue, VerticalPanelStyle.adaptiveGrid.rawValue)
        XCTAssertEqual(persistedSettings.panelOrientation, .vertical)
        XCTAssertEqual(persistedSettings.verticalPanelStyle, .adaptiveGrid)
    }
}

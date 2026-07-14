import AppKit
import SwiftData
import XCTest
@testable import PasteDeck

final class ClipboardAssetLifecycleTests: XCTestCase {
    private var temporaryCacheRoot: URL!

    override func setUpWithError() throws {
        temporaryCacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDeckAssetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryCacheRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryCacheRoot {
            try? FileManager.default.removeItem(at: temporaryCacheRoot)
        }
        temporaryCacheRoot = nil
    }

    func testSaveImageUsesSHA256PathAndReusesIdenticalContent() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let image = makeImage(redComponent: 230, greenComponent: 26, blueComponent: 26)

        let firstPath = try XCTUnwrap(cacheManager.saveImage(image))
        let secondPath = try XCTUnwrap(cacheManager.saveImage(image))
        let cachedFiles = try FileManager.default.contentsOfDirectory(
            at: temporaryCacheRoot.appendingPathComponent("images"),
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(firstPath, secondPath)
        XCTAssertEqual(cachedFiles.count, 1)
        XCTAssertEqual(URL(fileURLWithPath: firstPath).deletingPathExtension().lastPathComponent.count, 64)
    }

    func testClearUnreferencedCachePreservesReferencedImage() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let referencedPath = try XCTUnwrap(cacheManager.saveImage(
            makeImage(redComponent: 26, greenComponent: 51, blueComponent: 230)
        ))
        let orphanURL = temporaryCacheRoot
            .appendingPathComponent("images")
            .appendingPathComponent("legacy-orphan.png")
        try Data(repeating: 7, count: 128).write(to: orphanURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: orphanURL.path
        )

        let removedCount = cacheManager.clearUnreferencedCache(
            referencedImagePaths: [referencedPath]
        )

        XCTAssertEqual(removedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testCapacityCleanupDeletesOnlyOldUnreferencedFiles() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let referencedPath = try XCTUnwrap(cacheManager.saveImage(
            makeImage(redComponent: 102, greenComponent: 51, blueComponent: 179)
        ))
        let orphanURL = temporaryCacheRoot
            .appendingPathComponent("images")
            .appendingPathComponent("oversized-orphan.png")
        try Data(repeating: 3, count: 2 * 1024 * 1024).write(to: orphanURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: orphanURL.path
        )

        let removedCount = cacheManager.cleanCacheIfNeeded(
            limitMB: 1,
            referencedImagePaths: [referencedPath]
        )

        XCTAssertEqual(removedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testUnreferencedImageCleanupIgnoresReservedFileCacheDirectory() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let fileCacheDirectory = temporaryCacheRoot.appendingPathComponent("files")
        let cachedFileURL = fileCacheDirectory.appendingPathComponent("reserved-file.txt")
        try Data("reserved".utf8).write(to: cachedFileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: cachedFileURL.path
        )

        let removedCount = cacheManager.clearUnreferencedCache(referencedImagePaths: [])

        XCTAssertEqual(removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedFileURL.path))
        XCTAssertEqual(cacheManager.getTotalCacheSize(), 0)
    }

    func testPendingAdoptionSurvivesDeletionOfPreviousFinalReference() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let imageAssetStore = ClipboardImageAssetStore()
        let image = makeImage(redComponent: 77, greenComponent: 128, blueComponent: 230)
        let imagePath = try XCTUnwrap(cacheManager.saveImage(image))
        let schema = Schema([
            ClipboardItem.self,
            FavoriteCollection.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let previousItem = ClipboardItem(contentType: .image, imagePath: imagePath)
        context.insert(previousItem)
        try context.save()

        let pendingPath = try XCTUnwrap(imageAssetStore.prepareImageForAdoption(
            image,
            cacheManager: cacheManager
        ))
        XCTAssertEqual(pendingPath, imagePath)

        XCTAssertEqual(
            ClipboardItemLifecycleService.deleteItems(
                [previousItem],
                in: context,
                cacheManager: cacheManager,
                imageAssetStore: imageAssetStore
            ),
            1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        let replacementItem = ClipboardItem(contentType: .image, imagePath: pendingPath)
        context.insert(replacementItem)
        try context.save()
        imageAssetStore.commitAdoption(at: pendingPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))
    }

    func testMaintenancePreservesOldAssetWhileAdoptionIsPending() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let imageAssetStore = ClipboardImageAssetStore()
        let image = makeImage(redComponent: 179, greenComponent: 77, blueComponent: 204)
        let imagePath = try XCTUnwrap(cacheManager.saveImage(image))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: imagePath
        )
        let schema = Schema([
            ClipboardItem.self,
            FavoriteCollection.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let pendingPath = try XCTUnwrap(imageAssetStore.prepareImageForAdoption(
            image,
            cacheManager: cacheManager
        ))
        let removedCount = ClipboardItemLifecycleService.clearUnreferencedCache(
            in: context,
            cacheManager: cacheManager,
            imageAssetStore: imageAssetStore
        )

        XCTAssertEqual(removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingPath))

        ClipboardItemLifecycleService.discardUnadoptedImage(
            at: pendingPath,
            in: context,
            cacheManager: cacheManager,
            imageAssetStore: imageAssetStore
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingPath))
    }

    func testDeletingSharedImageRemovesFileOnlyAfterFinalReference() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let imagePath = try XCTUnwrap(cacheManager.saveImage(
            makeImage(redComponent: 26, greenComponent: 204, blueComponent: 51)
        ))
        let schema = Schema([
            ClipboardItem.self,
            FavoriteCollection.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let firstItem = ClipboardItem(contentType: .image, imagePath: imagePath)
        let secondItem = ClipboardItem(contentType: .image, imagePath: imagePath)
        context.insert(firstItem)
        context.insert(secondItem)
        try context.save()

        XCTAssertEqual(
            ClipboardItemLifecycleService.deleteItems(
                [firstItem],
                in: context,
                cacheManager: cacheManager
            ),
            1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        XCTAssertEqual(
            ClipboardItemLifecycleService.deleteItems(
                [secondItem],
                in: context,
                cacheManager: cacheManager
            ),
            1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
    }

    func testDiscardUnadoptedImagePreservesExistingReference() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let imagePath = try XCTUnwrap(cacheManager.saveImage(
            makeImage(redComponent: 242, greenComponent: 128, blueComponent: 26)
        ))
        let schema = Schema([
            ClipboardItem.self,
            FavoriteCollection.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let persistedItem = ClipboardItem(contentType: .image, imagePath: imagePath)
        context.insert(persistedItem)
        try context.save()

        ClipboardItemLifecycleService.discardUnadoptedImage(
            at: imagePath,
            in: context,
            cacheManager: cacheManager
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))
    }

    func testDiscardUnadoptedImageRemovesUnreferencedFileImmediately() throws {
        let cacheManager = CacheManager(cacheRootDirectory: temporaryCacheRoot)
        let imagePath = try XCTUnwrap(cacheManager.saveImage(
            makeImage(redComponent: 51, greenComponent: 179, blueComponent: 179)
        ))
        let schema = Schema([
            ClipboardItem.self,
            FavoriteCollection.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        ClipboardItemLifecycleService.discardUnadoptedImage(
            at: imagePath,
            in: context,
            cacheManager: cacheManager
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
    }

    private func makeImage(
        redComponent: UInt8,
        greenComponent: UInt8,
        blueComponent: UInt8,
        alphaComponent: UInt8 = 255
    ) -> NSImage {
        let pixelWidth = 4
        let pixelHeight = 4
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let bitmapData = bitmap.bitmapData!
        for verticalIndex in 0..<pixelHeight {
            for horizontalIndex in 0..<pixelWidth {
                let pixelOffset = verticalIndex * bitmap.bytesPerRow + horizontalIndex * 4
                bitmapData[pixelOffset] = redComponent
                bitmapData[pixelOffset + 1] = greenComponent
                bitmapData[pixelOffset + 2] = blueComponent
                bitmapData[pixelOffset + 3] = alphaComponent
            }
        }

        let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
        image.addRepresentation(bitmap)
        return image
    }
}

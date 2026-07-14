//
//  ClipboardItemLifecycleService.swift
//  PasteDeck
//
//  Keeps SwiftData clipboard records and content-addressed image assets in sync.
//

import Foundation
import SwiftData

/// Unified deletion and cache-maintenance boundary for ClipboardItem-owned image assets.
enum ClipboardItemLifecycleService {
    /// Deletes records first, then releases image files that no remaining record references.
    /// Shared SHA-256 assets remain on disk until their final ClipboardItem reference is deleted.
    @discardableResult
    static func deleteItems(
        _ items: [ClipboardItem],
        in context: ModelContext,
        cacheManager: CacheManager = CacheManager(),
        imageAssetStore: ClipboardImageAssetStore = .shared
    ) -> Int {
        var seenItemIDs = Set<UUID>()
        let uniqueItems = items.filter { seenItemIDs.insert($0.id).inserted }
        guard !uniqueItems.isEmpty else { return 0 }

        let candidateImagePaths = Set(uniqueItems.compactMap(\.imagePath))
        uniqueItems.forEach(context.delete)

        do {
            try context.save()
        } catch {
            context.rollback()
            NSLog("[PasteDeck] Failed to delete clipboard items: \(error.localizedDescription)")
            return 0
        }

        imageAssetStore.removeImagesIfUnreferenced(
            candidateImagePaths,
            in: context.container,
            cacheManager: cacheManager
        )
        return uniqueItems.count
    }

    /// Releases a newly written image when its temporary ClipboardItem was rejected before insertion.
    /// The file is retained when an existing record already owns the same content-addressed path.
    static func discardUnadoptedImage(
        at path: String?,
        in context: ModelContext,
        cacheManager: CacheManager = CacheManager(),
        imageAssetStore: ClipboardImageAssetStore = .shared
    ) {
        imageAssetStore.discardAdoption(
            at: path,
            in: context.container,
            cacheManager: cacheManager
        )
    }

    /// Applies the configured soft cache limit without deleting assets referenced by history records.
    @discardableResult
    static func cleanCacheIfNeeded(
        limitMB: Int,
        in context: ModelContext,
        cacheManager: CacheManager = CacheManager(),
        imageAssetStore: ClipboardImageAssetStore = .shared
    ) -> Int {
        imageAssetStore.cleanCacheIfNeeded(
            limitMB: limitMB,
            in: context.container,
            cacheManager: cacheManager
        )
    }

    /// Removes all legacy or otherwise orphaned cache files while preserving every referenced image.
    @discardableResult
    static func clearUnreferencedCache(
        in context: ModelContext,
        cacheManager: CacheManager = CacheManager(),
        imageAssetStore: ClipboardImageAssetStore = .shared
    ) -> Int {
        imageAssetStore.clearUnreferencedCache(
            in: context.container,
            cacheManager: cacheManager
        )
    }
}

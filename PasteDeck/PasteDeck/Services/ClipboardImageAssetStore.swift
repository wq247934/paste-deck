//
//  ClipboardImageAssetStore.swift
//  PasteDeck
//
//  Serializes image adoption, final-reference deletion, and cache maintenance.
//

import AppKit
import Foundation
import SwiftData

/// Coordinates the filesystem and SwiftData sides of content-addressed clipboard image ownership.
///
/// A newly written image is registered as pending until its ClipboardItem save either commits or rolls back.
/// Final-reference deletion and cache maintenance share the same lock, so they can never remove a path while
/// another clipboard insertion is between writing that path and persisting its database reference.
final class ClipboardImageAssetStore {
    static let shared = ClipboardImageAssetStore()

    /// Small mutations use indexed path lookups; larger batches fetch image references once to avoid query fan-out.
    private static let targetedReferenceLookupLimit: Int = 8

    private let lock = NSLock()
    private var pendingAdoptionCounts: [String: Int] = [:]

    /// Writes or reuses an image asset and protects its path until adoption is committed or discarded.
    func prepareImageForAdoption(
        _ image: NSImage,
        cacheManager: CacheManager
    ) -> String? {
        withLock {
            guard let path = cacheManager.saveImage(image) else { return nil }

            let normalizedPath = normalize(path)
            pendingAdoptionCounts[normalizedPath, default: 0] += 1
            return normalizedPath
        }
    }

    /// Releases the temporary protection after the ClipboardItem reference has been saved successfully.
    func commitAdoption(at path: String?) {
        guard let path else { return }

        withLock {
            releasePendingAdoption(at: normalize(path))
        }
    }

    /// Releases a rejected adoption and removes its file only when no pending or persisted owner remains.
    func discardAdoption(
        at path: String?,
        in container: ModelContainer,
        cacheManager: CacheManager
    ) {
        guard let path else { return }

        withLock {
            let normalizedPath = normalize(path)
            releasePendingAdoption(at: normalizedPath)
            guard pendingAdoptionCounts[normalizedPath] == nil,
                  isImageReferenced(at: normalizedPath, in: container) == false else {
                return
            }

            cacheManager.removeCachedImage(at: normalizedPath)
        }
    }

    /// Removes candidate files only after a fresh reference lookup inside the shared serialization boundary.
    func removeImagesIfUnreferenced(
        _ candidateImagePaths: Set<String>,
        in container: ModelContainer,
        cacheManager: CacheManager
    ) {
        guard !candidateImagePaths.isEmpty else { return }

        withLock {
            let normalizedPaths = Set(candidateImagePaths.map(normalize))
            let removablePaths: Set<String>

            if normalizedPaths.count <= Self.targetedReferenceLookupLimit {
                removablePaths = Set(normalizedPaths.filter { path in
                    pendingAdoptionCounts[path] == nil
                        && isImageReferenced(at: path, in: container) == false
                })
            } else {
                guard let referencedPaths = referencedImagePaths(in: container) else { return }

                let pendingPaths = Set(pendingAdoptionCounts.keys)
                removablePaths = normalizedPaths.subtracting(
                    referencedPaths.union(pendingPaths)
                )
            }

            removablePaths.forEach { path in
                cacheManager.removeCachedImage(at: path)
            }
        }
    }

    /// Applies the image-cache soft limit while treating every pending adoption as a live reference.
    @discardableResult
    func cleanCacheIfNeeded(
        limitMB: Int,
        in container: ModelContainer,
        cacheManager: CacheManager
    ) -> Int {
        withLock {
            guard let referencedPaths = referencedImagePaths(in: container) else { return 0 }
            let pendingPaths = Set(pendingAdoptionCounts.keys)

            return cacheManager.cleanCacheIfNeeded(
                limitMB: limitMB,
                referencedImagePaths: referencedPaths.union(pendingPaths)
            )
        }
    }

    /// Removes orphaned image-cache files while treating every pending adoption as a live reference.
    @discardableResult
    func clearUnreferencedCache(
        in container: ModelContainer,
        cacheManager: CacheManager
    ) -> Int {
        withLock {
            guard let referencedPaths = referencedImagePaths(in: container) else { return 0 }
            let pendingPaths = Set(pendingAdoptionCounts.keys)

            return cacheManager.clearUnreferencedCache(
                referencedImagePaths: referencedPaths.union(pendingPaths)
            )
        }
    }

    private func referencedImagePaths(in container: ModelContainer) -> Set<String>? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.imagePath != nil
            }
        )
        guard let imageItems = try? context.fetch(descriptor) else { return nil }

        return Set(imageItems.compactMap(\.imagePath).map(normalize))
    }

    /// Returns nil on fetch failure so callers preserve the file rather than risk breaking a live record.
    private func isImageReferenced(at path: String, in container: ModelContainer) -> Bool? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.imagePath == path
            }
        )
        descriptor.fetchLimit = 1

        guard let matchingItems = try? context.fetch(descriptor) else { return nil }
        return !matchingItems.isEmpty
    }

    private func releasePendingAdoption(at path: String) {
        guard let adoptionCount = pendingAdoptionCounts[path] else { return }

        if adoptionCount > 1 {
            pendingAdoptionCounts[path] = adoptionCount - 1
        } else {
            pendingAdoptionCounts.removeValue(forKey: path)
        }
    }

    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

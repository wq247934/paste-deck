//
//  CacheManager.swift
//  PasteDeck
//
//  Manages local file cache for clipboard images and files.
//  Cache directory: ~/Library/Caches/PasteDeck/
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import CryptoKit

/// Manages local cache storage for clipboard images and files
final class CacheManager {
    /// Orphan scans ignore very recent files so a concurrent clipboard insert can finish adopting its asset.
    private static let orphanSafetyInterval: TimeInterval = 60

    private let fileManager = FileManager.default
    private let imageCacheDirectory: URL
    private let fileCacheDirectory: URL

    init(cacheRootDirectory: URL? = nil) {
        let appCacheURL = cacheRootDirectory ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("PasteDeck")

        imageCacheDirectory = appCacheURL.appendingPathComponent("images")
        fileCacheDirectory = appCacheURL.appendingPathComponent("files")

        createDirectoriesIfNeeded()
    }

    // MARK: - Public Methods

    /// Saves an NSImage to the cache as PNG
    /// - Parameter image: The image to save
    /// - Returns: The content-addressed file path of the saved image, or nil on failure
    func saveImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        // 图片文件名是规范 PNG 数据的 SHA-256。相同内容复用同一资产，避免重复复制时先制造孤儿文件。
        let contentIdentifier = contentIdentifier(for: pngData)
        let fileURL = imageCacheDirectory.appendingPathComponent("\(contentIdentifier).png")
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL.path
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            // 并发写入同一内容时，另一个写入者可能已经完成；此时仍采用已存在的内容寻址资产。
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL.path
            }

            return nil
        }
    }

    /// Returns a stable SHA-256 identifier for a cached image. Legacy UUID-named files are hashed lazily.
    func imageContentIdentifier(at path: String?) -> String? {
        guard let path else { return nil }

        let fileURL = URL(fileURLWithPath: path)
        let fileNameIdentifier = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        if fileNameIdentifier.count == 64,
           fileNameIdentifier.unicodeScalars.allSatisfy({
               CharacterSet(charactersIn: "0123456789abcdef").contains($0)
           }) {
            return fileNameIdentifier
        }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return nil
        }

        return contentIdentifier(for: data)
    }

    /// Returns the file size in bytes at the given path
    func getFileSize(at path: String) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int else {
            return 0
        }
        return fileSize
    }

    /// Calculates image cache size in bytes. The reserved files directory is excluded until it has ownership tracking.
    func getTotalCacheSize() -> Int {
        var totalSize = 0

        if let enumerator = fileManager.enumerator(
            at: imageCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += fileSize
                }
            }
        }

        return totalSize
    }

    /// Removes only unreferenced cache files when total cache size exceeds the configured soft limit.
    /// Referenced images are never deleted, so the resulting size may remain above the limit.
    @discardableResult
    func cleanCacheIfNeeded(limitMB: Int, referencedImagePaths: Set<String>) -> Int {
        guard limitMB > 0 else { return 0 }

        let limitBytes = limitMB * 1024 * 1024
        let currentSize = getTotalCacheSize()

        guard currentSize > limitBytes else { return 0 }

        let referencedPaths = normalizedPaths(referencedImagePaths)
        let sortedCandidates = unreferencedCacheFiles(referencedImagePaths: referencedPaths)
            .sorted { first, second in first.date < second.date }
        var remainingSize = currentSize
        var removedCount = 0

        for candidate in sortedCandidates {
            guard remainingSize > limitBytes else { break }

            do {
                try fileManager.removeItem(at: candidate.url)
                remainingSize -= candidate.size
                removedCount += 1
            } catch {
                continue
            }
        }

        return removedCount
    }

    /// Removes every cache file that is not referenced by a persisted clipboard image.
    @discardableResult
    func clearUnreferencedCache(referencedImagePaths: Set<String>) -> Int {
        let referencedPaths = normalizedPaths(referencedImagePaths)
        var removedCount = 0

        for candidate in unreferencedCacheFiles(referencedImagePaths: referencedPaths) {
            do {
                try fileManager.removeItem(at: candidate.url)
                removedCount += 1
            } catch {
                continue
            }
        }

        return removedCount
    }

    /// Removes one image asset only when the path belongs to PasteDeck's image cache.
    @discardableResult
    func removeCachedImage(at path: String) -> Bool {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        guard fileURL.deletingLastPathComponent() == imageCacheDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    private func createDirectoriesIfNeeded() {
        for directory in [imageCacheDirectory, fileCacheDirectory] {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    private func contentIdentifier(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedPaths(_ paths: Set<String>) -> Set<String> {
        Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private func unreferencedCacheFiles(
        referencedImagePaths: Set<String>
    ) -> [(url: URL, size: Int, date: Date)] {
        var candidates: [(url: URL, size: Int, date: Date)] = []

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: imageCacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        ) else {
            return candidates
        }

        for fileURL in fileURLs {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else { continue }

            let isReferencedImage = referencedImagePaths.contains(fileURL.standardizedFileURL.path)
            let modificationDate = values?.contentModificationDate ?? Date.distantPast
            let isSafeToRemove = Date().timeIntervalSince(modificationDate) >= Self.orphanSafetyInterval
            guard !isReferencedImage, isSafeToRemove else { continue }

            candidates.append((
                url: fileURL,
                size: values?.fileSize ?? 0,
                date: modificationDate
            ))
        }

        return candidates
    }
}

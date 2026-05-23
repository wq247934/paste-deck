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

/// Manages local cache storage for clipboard images and files
class CacheManager {
    private let fileManager = FileManager.default
    private let imageCacheDirectory: URL
    private let fileCacheDirectory: URL

    init() {
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCacheURL = cacheURL.appendingPathComponent("PasteDeck")

        imageCacheDirectory = appCacheURL.appendingPathComponent("images")
        fileCacheDirectory = appCacheURL.appendingPathComponent("files")

        createDirectoriesIfNeeded()
    }

    // MARK: - Public Methods

    /// Saves an NSImage to the cache as PNG
    /// - Parameter image: The image to save
    /// - Returns: The file path of the saved image, or nil on failure
    func saveImage(_ image: NSImage) -> String? {
        let fileName = UUID().uuidString + ".png"
        let fileURL = imageCacheDirectory.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// Returns the file size in bytes at the given path
    func getFileSize(at path: String) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int else {
            return 0
        }
        return fileSize
    }

    /// Calculates total cache size in bytes
    func getTotalCacheSize() -> Int {
        var totalSize = 0

        for directory in [imageCacheDirectory, fileCacheDirectory] {
            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += fileSize
                    }
                }
            }
        }

        return totalSize
    }

    /// Removes all cached files
    func clearAllCache() {
        for directory in [imageCacheDirectory, fileCacheDirectory] {
            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
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
}
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

    /// Removes old cache files when cache size exceeds the limit
    func cleanCacheIfNeeded(limitMB: Int) async {
        let limitBytes = limitMB * 1024 * 1024
        let currentSize = getTotalCacheSize()

        guard currentSize > limitBytes else { return }

        print("Cache size (\(currentSize) bytes) exceeds limit (\(limitBytes) bytes), cleaning...")

        // 清理图片缓存（按文件修改时间从旧到新）
        await cleanDirectoryByAge(directory: imageCacheDirectory, targetSize: limitBytes / 2)
        await cleanDirectoryByAge(directory: fileCacheDirectory, targetSize: limitBytes / 2)
    }

    /// Clean files in directory by age (oldest first) until size is under target
    private func cleanDirectoryByAge(directory: URL, targetSize: Int) async {
        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            // 获取目录下所有文件
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])

            // 按修改时间排序（最旧的在前）
            let sortedFiles = fileURLs.sorted { (url1, url2) -> Bool in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 < date2
            }

            var currentSize = sortedFiles.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + size
            }

            // 删除旧文件直到大小低于目标
            for fileURL in sortedFiles {
                guard currentSize > targetSize else { break }

                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                try? fileManager.removeItem(at: fileURL)
                currentSize -= fileSize
            }

            print("Cleaned \(directory.lastPathComponent) to \(currentSize) bytes (target: \(targetSize))")
        } catch {
            print("Error cleaning directory \(directory.lastPathComponent): \(error)")
        }
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
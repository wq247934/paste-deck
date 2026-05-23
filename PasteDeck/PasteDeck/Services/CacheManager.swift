//
//  CacheManager.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit

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
            print("Failed to save image: \(error)")
            return nil
        }
    }

    func getFileSize(at path: String) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int else {
            return 0
        }
        return fileSize
    }

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

    func clearAllCache() {
        for directory in [imageCacheDirectory, fileCacheDirectory] {
            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }

    private func createDirectoriesIfNeeded() {
        for directory in [imageCacheDirectory, fileCacheDirectory] {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
}

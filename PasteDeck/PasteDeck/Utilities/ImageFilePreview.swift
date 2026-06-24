//
//  ImageFilePreview.swift
//  PasteDeck
//
//  Created on 2026-06-21.
//

import AppKit
import Foundation

enum ImageFilePreview {
    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "tif", "bmp"
    ]

    static func isSupportedImageFile(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    static func loadImageIfSupported(path: String) -> NSImage? {
        guard isSupportedImageFile(path: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

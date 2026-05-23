//
//  PasteService.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit

class PasteService {
    static let shared = PasteService()
    private var clipboardMonitor: ClipboardMonitor?

    private init() {}

    func setClipboardMonitor(_ monitor: ClipboardMonitor) {
        self.clipboardMonitor = monitor
    }

    func paste(_ item: ClipboardItem) {
        // 暂停监听，避免记录粘贴的内容
        clipboardMonitor?.pause()

        copyToPasteboard(item)
        simulatePaste()

        // 延迟恢复监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.clipboardMonitor?.resume()
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .link:
            if let urlString = item.textContent {
                pasteboard.setString(urlString, forType: .string)
                if let url = URL(string: urlString) {
                    pasteboard.setData(url.absoluteString.data(using: .utf8) ?? Data(), forType: .URL)
                }
            }

        case .image:
            if let imagePath = item.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                pasteboard.writeObjects([image])
            }

        case .file:
            if let filePath = item.filePath {
                let fileURL = URL(fileURLWithPath: filePath)
                pasteboard.writeObjects([fileURL as NSURL])
            }

        case .color:
            if let hex = item.colorHex,
               let nsColor = NSColor(hex: hex) {
                pasteboard.writeObjects([nsColor])
                pasteboard.setString(hex, forType: .string)
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDownEvent?.flags = .maskCommand
        keyUpEvent?.flags = .maskCommand

        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if length == 8 {
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}

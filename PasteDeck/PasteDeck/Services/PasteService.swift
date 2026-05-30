//
//  PasteService.swift
//  PasteDeck
//
//  Handles clipboard operations and simulated paste keystrokes.
//  Coordinates with ClipboardMonitor to avoid recording self-pasted content.
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit

/// Handles clipboard copy and paste operations
class PasteService {
    static let shared = PasteService()
    private var clipboardMonitor: ClipboardMonitor?

    private init() {}

    /// Sets the clipboard monitor reference for pause/resume during paste
    func setClipboardMonitor(_ monitor: ClipboardMonitor) {
        self.clipboardMonitor = monitor
    }

    /// Copies item to clipboard (call before hiding panel)
    func preparePaste(_ item: ClipboardItem) {
        clipboardMonitor?.pause()
        copyToPasteboard(item)
    }

    /// Simulates Cmd+V after panel is hidden and previous app has focus
    func performPaste() {
        simulatePaste()

        // Resume monitoring after paste completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.clipboardMonitor?.resume()
        }
    }

    /// Legacy: Copies item to clipboard and simulates Cmd+V keystroke
    /// ⚠️ Should not be used when panel is visible — use preparePaste + performPaste instead
    func paste(_ item: ClipboardItem) {
        clipboardMonitor?.pause()
        copyToPasteboard(item)
        simulatePaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.clipboardMonitor?.resume()
        }
    }

    /// 批量粘贴：暂停监控 → 依次粘贴 → 恢复监控
    /// - Parameters:
    ///   - items: 要粘贴的项目列表（按显示顺序）
    ///   - interval: 每次粘贴间隔（秒），默认 0.15
    func batchPaste(_ items: [ClipboardItem], interval: TimeInterval = 0.15) {
        guard !items.isEmpty else { return }

        clipboardMonitor?.pause()

        for (i, item) in items.enumerated() {
            let delay = Double(i) * interval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.copyToPasteboard(item)
                self?.simulatePaste()
            }
        }

        // 恢复监控（在最后一次粘贴完成后）
        let totalDelay = Double(items.count) * interval + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) { [weak self] in
            self?.clipboardMonitor?.resume()
        }
    }

    /// Copies clipboard item content to the system pasteboard
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

    // MARK: - Private Methods

    /// Simulates Cmd+V keystroke using CGEvent
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

// MARK: - NSColor Hex Extension

extension NSColor {
    /// Creates NSColor from hex string (e.g., "#FF5733" or "#FF573388")
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

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
    private var activeSelectionCopyProbe: SelectionCopyProbe?

    private init() {}

    /// Sets the clipboard monitor reference for pause/resume during paste
    func setClipboardMonitor(_ monitor: ClipboardMonitor) {
        self.clipboardMonitor = monitor
    }

    /// 在不永久改变用户剪贴板的前提下，通过 Command+C 读取不支持 AXSelectedText 的应用选区。
    /// 浏览器、Electron、PDF 阅读器等经常只在执行复制命令时提供选中文本，因此这是辅助功能读取的兜底通道。
    func readSelectedTextBySimulatingCopy(
        maximumWait: TimeInterval = 0.4,
        completion: @escaping (String?) -> Void
    ) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }

        if var activeSelectionCopyProbe {
            activeSelectionCopyProbe.completions.append(completion)
            self.activeSelectionCopyProbe = activeSelectionCopyProbe
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        clipboardMonitor?.pause()
        activeSelectionCopyProbe = SelectionCopyProbe(
            snapshot: snapshot,
            originalChangeCount: pasteboard.changeCount,
            completions: [completion]
        )
        simulateCopy()
        let pollingInterval: TimeInterval = 0.02
        let remainingAttempts = max(1, Int(ceil(maximumWait / pollingInterval)))
        pollForCopiedSelection(
            pollingInterval: pollingInterval,
            remainingAttempts: remainingAttempts
        )
    }

    /// Copies item to clipboard (call before hiding panel)
    func preparePaste(_ item: ClipboardItem, plainText: Bool = false) {
        clipboardMonitor?.pause()
        copyToPasteboard(item, plainText: plainText)
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
    func paste(_ item: ClipboardItem, plainText: Bool = false) {
        clipboardMonitor?.pause()
        copyToPasteboard(item, plainText: plainText)
        simulatePaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.clipboardMonitor?.resume()
        }
    }

    /// 批量粘贴：暂停监控 → 依次粘贴 → 恢复监控
    /// - Parameters:
    ///   - items: 要粘贴的项目列表（按显示顺序）
    ///   - interval: 每次粘贴间隔（秒），默认 0.15
    func batchPaste(_ items: [ClipboardItem], interval: TimeInterval = 0.15, plainText: Bool = false) {
        guard !items.isEmpty else { return }

        clipboardMonitor?.pause()

        for (i, item) in items.enumerated() {
            let delay = Double(i) * interval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.copyToPasteboard(item, plainText: plainText)
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
    func copyToPasteboard(_ item: ClipboardItem, plainText: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text, .markdown, .json:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
                // 带格式粘贴：同时写入 RTF 数据
                if item.contentType == .text, !plainText, let rtfData = item.rtfData {
                    pasteboard.setData(rtfData, forType: .rtf)
                }
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

    /// 向当前前台应用发送一次 Command+C，用于读取无法通过辅助功能 API 获取的选区。
    private func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDownEvent?.flags = .maskCommand
        keyUpEvent?.flags = .maskCommand
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
    }

    /// 短时轮询复制结果，兼容浏览器和大型文档在主线程繁忙时延迟写入剪贴板。
    private func pollForCopiedSelection(
        pollingInterval: TimeInterval,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + pollingInterval) { [weak self] in
            guard let self, let probe = self.activeSelectionCopyProbe else { return }
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != probe.originalChangeCount else {
                if remainingAttempts > 1 {
                    self.pollForCopiedSelection(
                        pollingInterval: pollingInterval,
                        remainingAttempts: remainingAttempts - 1
                    )
                } else {
                    self.finishSelectionCopyProbe(text: nil, restoresClipboard: false)
                }
                return
            }

            let plainText = pasteboard.string(forType: .string)
            let richText = pasteboard.data(forType: .rtf).flatMap {
                try? NSAttributedString(data: $0, options: [:], documentAttributes: nil).string
            }
            let selectedText = plainText ?? richText
            let trimmed = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let validText: String?
            if let trimmed,
               !trimmed.isEmpty,
               !trimmed.hasPrefix("PasteDeck.SelectionProbe.") {
                validText = trimmed
            } else {
                validText = nil
            }
            self.finishSelectionCopyProbe(text: validText, restoresClipboard: true)
        }
    }

    /// 完成唯一的选区探测，先恢复用户剪贴板，再向所有等待方返回同一份选区结果。
    private func finishSelectionCopyProbe(text: String?, restoresClipboard: Bool) {
        guard let probe = activeSelectionCopyProbe else { return }
        activeSelectionCopyProbe = nil
        if restoresClipboard, probe.snapshot.isSafeToRestore {
            probe.snapshot.restore(to: .general)
        }
        clipboardMonitor?.resumeImmediatelyAfterSelectionProbe()
        for completion in probe.completions {
            completion(text)
        }
    }
}

/// 一次全局唯一的模拟复制探测；并发调用会加入 completions，而不会再次改写剪贴板。
private struct SelectionCopyProbe {
    /// 探测开始前用户剪贴板的完整快照，仅在 Command+C 确实改写剪贴板后恢复。
    let snapshot: PasteboardSnapshot
    /// 探测开始前的 NSPasteboard changeCount，用于在不写入标记的情况下判断复制是否成功。
    let originalChangeCount: Int
    /// 等待同一选区结果的回调列表，包含自动划词和快捷键入口。
    var completions: [(String?) -> Void]
}

/// 剪贴板中一个 item 的完整数据快照，用于选区探测完成后恢复多类型内容。
struct PasteboardItemSnapshot {
    /// 该 item 按 pasteboard type 保存的全部可读取二进制表示，例如文本、RTF、图片或文件 URL。
    let representations: [NSPasteboard.PasteboardType: Data]
}

/// 用户剪贴板的多 item 快照，确保模拟 Command+C 不会破坏原有剪贴板内容。
struct PasteboardSnapshot {
    /// 按原顺序保存的剪贴板 items；空数组表示探测前剪贴板为空。
    let items: [PasteboardItemSnapshot]
    /// 某些应用只暴露字符串而不提供 pasteboardItems 时的恢复兜底文本。
    let fallbackString: String?

    /// 旧版本若已泄漏内部探测标记，不再把该标记恢复回系统剪贴板；成功复制的真实选区将自然替换它。
    var isSafeToRestore: Bool {
        fallbackString?.hasPrefix("PasteDeck.SelectionProbe.") != true
    }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> PasteboardItemSnapshot? in
            let representations = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
            return representations.isEmpty ? nil : PasteboardItemSnapshot(representations: representations)
        }
        return PasteboardSnapshot(items: items, fallbackString: pasteboard.string(forType: .string))
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            if let fallbackString {
                pasteboard.setString(fallbackString, forType: .string)
            }
            return
        }
        let restoredItems = items.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.representations {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
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

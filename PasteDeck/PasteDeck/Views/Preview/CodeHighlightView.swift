//
//  CodeHighlightView.swift
//  PasteDeck
//
//  Renders syntax-highlighted code using Highlightr with line numbers.
//  Created on 2026-05-24.
//

import SwiftUI
import Highlightr

struct CodeHighlightView: NSViewRepresentable {
    let code: String
    let language: String?
    let showLineNumbers: Bool

    init(code: String, language: String? = nil, showLineNumbers: Bool = true) {
        self.code = code
        self.language = language
        self.showLineNumbers = showLineNumbers
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = true
        textView.allowsUndo = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true

        applyHighlight(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyHighlight(to: textView)
    }

    private func applyHighlight(to textView: NSTextView) {
        let highlightr = Highlightr()

        let result: NSAttributedString?

        if let lang = language {
            result = highlightr?.highlight(code, as: lang)
        } else {
            result = highlightr?.highlight(code)
        }

        if let attributed = result {
            let fullText = showLineNumbers ? addLineNumbers(to: attributed) : attributed
            textView.textStorage?.setAttributedString(fullText)
        } else {
            // 高亮失败，纯文本显示
            let plain = NSMutableAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor.textColor,
                ]
            )
            let fullText = showLineNumbers ? addLineNumbers(to: plain) : plain
            textView.textStorage?.setAttributedString(fullText)
        }
    }

    /// 在高亮结果前添加行号
    private func addLineNumbers(to attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsString = attributed.string as NSString
        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        // 计算行数和最大位数
        var lineRanges: [NSRange] = []
        var searchStart = 0
        while searchStart < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchStart, length: 0))
            lineRanges.append(lineRange)
            searchStart = NSMaxRange(lineRange)
        }
        let maxDigits = "\(lineRanges.count)".count

        for (i, lineRange) in lineRanges.enumerated() {
            // 行号
            let lineNum = String(format: "%\(maxDigits)d", i + 1)
            result.append(NSAttributedString(string: lineNum, attributes: lineNumAttrs))
            result.append(NSAttributedString(string: "  │  ", attributes: separatorAttrs))

            // 代码行（保留高亮属性）
            if lineRange.location + lineRange.length <= attributed.length {
                result.append(attributed.attributedSubstring(from: lineRange))
            }
        }

        return result
    }
}

/// 纯文本 + 行号视图
struct PlainTextView: NSViewRepresentable {
    let text: String
    let showLineNumbers: Bool

    init(text: String, showLineNumbers: Bool = true) {
        self.text = text
        self.showLineNumbers = showLineNumbers
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        applyText(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyText(to: textView)
    }

    private func applyText(to textView: NSTextView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)

        if showLineNumbers {
            let withNums = addLineNumbers(to: attributed)
            textView.textStorage?.setAttributedString(withNums)
        } else {
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    private func addLineNumbers(to attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsString = attributed.string as NSString
        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        var lineRanges: [NSRange] = []
        var searchStart = 0
        while searchStart < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchStart, length: 0))
            lineRanges.append(lineRange)
            searchStart = NSMaxRange(lineRange)
        }
        let maxDigits = "\(lineRanges.count)".count

        for (i, lineRange) in lineRanges.enumerated() {
            let lineNum = String(format: "%\(maxDigits)d", i + 1)
            result.append(NSAttributedString(string: lineNum, attributes: lineNumAttrs))
            result.append(NSAttributedString(string: "  │  ", attributes: separatorAttrs))

            if lineRange.location + lineRange.length <= attributed.length {
                result.append(attributed.attributedSubstring(from: lineRange))
            }
        }

        return result
    }
}

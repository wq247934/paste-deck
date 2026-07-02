//
//  MarkdownRenderedText.swift
//  PasteDeck
//
//  Renders Markdown clipboard text as readable blocks while keeping the original
//  clipboard content unchanged for copy and paste.
//

import SwiftUI

struct MarkdownRenderedText: View {
    let markdown: String
    var baseFontSize: CGFloat = 14

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .padding(.top, level == 1 ? 2 : 0)

        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: baseFontSize))
                .lineSpacing(3)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        inlineText(item)
                    }
                    .font(.system(size: baseFontSize))
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                        inlineText(item)
                    }
                    .font(.system(size: baseFontSize))
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                inlineText(text)
                    .font(.system(size: baseFontSize))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }

        case .code(let language, let text):
            CodeEditorPreviewView(
                code: text,
                language: language,
                title: language?.uppercased() ?? "代码块",
                showLineNumbers: lineCount(for: text) > 1,
                allowEditing: true,
                compact: true
            )
            .frame(height: codeBlockHeight(for: text))

        case .table(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(size: max(baseFontSize - 1, 11), design: .monospaced))
                .lineSpacing(2)
        }
    }

    private func inlineText(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return baseFontSize + 10
        case 2: return baseFontSize + 7
        case 3: return baseFontSize + 4
        default: return baseFontSize + 2
        }
    }

    private func codeBlockHeight(for code: String) -> CGFloat {
        let lineCount = lineCount(for: code)
        let contentHeight = CGFloat(lineCount) * 19 + 54
        return min(max(contentHeight, 104), 320)
    }

    private func lineCount(for text: String) -> Int {
        text.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, text: String)
    case table([String])
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let text = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraph.removeAll()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                flushParagraph()
                let language = parseFenceLanguage(line)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.code(language: language, text: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let item = parseUnorderedItem(line) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let next = parseUnorderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if let item = parseOrderedItem(line) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let next = parseOrderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if isTableStart(lines: lines, index: index) {
                flushParagraph()
                var tableLines: [String] = []
                while index < lines.count {
                    let tableLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard tableLine.contains("|"), !tableLine.isEmpty else { break }
                    tableLines.append(tableLine)
                    index += 1
                }
                blocks.append(.table(tableLines))
                continue
            }

            paragraph.append(rawLine)
            index += 1
        }

        flushParagraph()
        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard let match = line.range(of: #"^#{1,6}\s+\S.*$"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(line[match])
        let level = matched.prefix { $0 == "#" }.count
        let text = matched.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseFenceLanguage(_ line: String) -> String? {
        let language = line
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)
        return language?.isEmpty == false ? language : nil
    }

    private static func parseUnorderedItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^[-*+]\s+\S.*$"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range].dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseOrderedItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d+\.\s+\S.*$"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(line[range])
        guard let separator = matched.range(of: ". ") else { return nil }
        return String(matched[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let current = lines[index].trimmingCharacters(in: .whitespaces)
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return current.contains("|") &&
            next.range(of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#, options: .regularExpression) != nil
    }
}

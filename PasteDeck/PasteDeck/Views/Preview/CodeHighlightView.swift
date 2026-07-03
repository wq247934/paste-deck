//
//  CodeHighlightView.swift
//  PasteDeck
//
//  Renders syntax-highlighted code using Highlightr with line numbers.
//  Created on 2026-05-24.
//

import SwiftUI
import Highlightr

struct CodeEditorPreviewView: View {
    let code: String
    let language: String?
    var title: String = "代码预览"
    var showLineNumbers: Bool = true
    var allowEditing: Bool = true
    var compact: Bool = false
    var theme: CodePreviewTheme = .dark
    var onSave: ((String) -> Void)?

    @State private var isEditing = false
    @State private var draftCode: String

    init(
        code: String,
        language: String? = nil,
        title: String = "代码预览",
        showLineNumbers: Bool = true,
        allowEditing: Bool = true,
        compact: Bool = false,
        theme: CodePreviewTheme = .dark,
        onSave: ((String) -> Void)? = nil
    ) {
        self.code = code
        self.language = language
        self.title = title
        self.showLineNumbers = showLineNumbers
        self.allowEditing = allowEditing
        self.compact = compact
        self.theme = theme
        self.onSave = onSave
        _draftCode = State(initialValue: code)
    }

    private var visibleCode: String {
        isEditing ? draftCode : code
    }

    private var languageLabel: String {
        guard let language, !language.isEmpty else { return "TEXT" }
        return language.uppercased()
    }

    private var lineCount: Int {
        visibleCode.reduce(1) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isEditing {
                EditableCodeWithLineNumbersView(
                    text: $draftCode,
                    theme: theme,
                    onCommandSave: saveEditing
                )
                    .transition(.opacity)
            } else {
                CodeHighlightView(
                    code: visibleCode,
                    language: language,
                    showLineNumbers: showLineNumbers,
                    theme: theme
                )
            }
        }
        .background(theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 12))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 12)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: compact ? .clear : theme.shadow, radius: 18, x: 0, y: 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.34))
                Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.27))
                Circle().fill(Color(red: 0.22, green: 0.78, blue: 0.38))
            }
            .frame(width: 44)

            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text("\(lineCount) 行")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondaryText)

            Text(languageLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.accent.opacity(theme == .light ? 0.10 : 0.14))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            if allowEditing {
                Button(action: isEditing ? saveEditing : startEditing) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isEditing ? theme.accent : theme.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isEditing ? "保存编辑" : "编辑预览内容")

                if isEditing && draftCode != code {
                    Button(action: {
                        draftCode = code
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("恢复原始内容")
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .background(theme.header)
    }

    private func startEditing() {
        draftCode = code
        isEditing = true
    }

    private func saveEditing() {
        if draftCode != code {
            onSave?(draftCode)
        }
        isEditing = false
    }
}

struct CodeHighlightView: NSViewRepresentable {
    let code: String
    let language: String?
    let showLineNumbers: Bool
    let theme: CodePreviewTheme

    init(code: String, language: String? = nil, showLineNumbers: Bool = true, theme: CodePreviewTheme = .dark) {
        self.code = code
        self.language = language
        self.showLineNumbers = showLineNumbers
        self.theme = theme
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(theme.canvas)
        scrollView.contentInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(theme.canvas)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = true
        textView.allowsUndo = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0

        applyHighlight(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyHighlight(to: textView, coordinator: context.coordinator)
    }

    private func applyHighlight(to textView: NSTextView, coordinator: Coordinator) {
        guard coordinator.shouldRender(code: code, language: language, showLineNumbers: showLineNumbers, theme: theme) else {
            return
        }

        let result: NSAttributedString?

        if let lang = language {
            result = Self.highlightr(for: theme)?.highlight(code, as: lang)
        } else {
            result = Self.highlightr(for: theme)?.highlight(code)
        }

        if let attributed = result {
            let fullText = showLineNumbers ? addLineNumbers(to: attributed) : normalized(attributed)
            textView.textStorage?.setAttributedString(fullText)
        } else {
            // 高亮失败，纯文本显示
            let plain = NSMutableAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor(theme.primaryText),
                ]
            )
            let fullText = showLineNumbers ? addLineNumbers(to: plain) : normalized(plain)
            textView.textStorage?.setAttributedString(fullText)
        }
    }

    private static let darkHighlightr: Highlightr? = makeHighlightr(themeName: "atom-one-dark")
    private static let lightHighlightr: Highlightr? = makeHighlightr(themeName: "atom-one-light")

    private static func highlightr(for theme: CodePreviewTheme) -> Highlightr? {
        theme == .light ? lightHighlightr : darkHighlightr
    }

    private static func makeHighlightr(themeName: String) -> Highlightr? {
        let highlightr = Highlightr()
        highlightr?.setTheme(to: themeName)
        return highlightr
    }

    /// 在高亮结果前添加行号
    private func addLineNumbers(to attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsString = attributed.string as NSString
        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(theme.lineNumber),
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(theme.separator),
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
                result.append(normalized(attributed.attributedSubstring(from: lineRange)))
            }
        }

        return result
    }

    private func normalized(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        ], range: fullRange)
        return result
    }

    final class Coordinator {
        private var renderedCode: String?
        private var renderedLanguage: String?
        private var renderedLineNumbers: Bool?
        private var renderedTheme: CodePreviewTheme?

        func shouldRender(code: String, language: String?, showLineNumbers: Bool, theme: CodePreviewTheme) -> Bool {
            if renderedCode == code,
               renderedLanguage == language,
               renderedLineNumbers == showLineNumbers,
               renderedTheme == theme {
                return false
            }
            renderedCode = code
            renderedLanguage = language
            renderedLineNumbers = showLineNumbers
            renderedTheme = theme
            return true
        }
    }
}

struct EditableCodeWithLineNumbersView: NSViewRepresentable {
    @Binding var text: String
    let theme: CodePreviewTheme
    let onCommandSave: () -> Void

    init(text: Binding<String>, theme: CodePreviewTheme = .dark, onCommandSave: @escaping () -> Void) {
        _text = text
        self.theme = theme
        self.onCommandSave = onCommandSave
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> CodeEditingContainerView {
        let container = CodeEditingContainerView(theme: theme, onCommandSave: onCommandSave)
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.string = text
        container.updateLineNumbers()

        DispatchQueue.main.async {
            container.window?.makeFirstResponder(textView)
        }

        return container
    }

    func updateNSView(_ container: CodeEditingContainerView, context: Context) {
        let textView = container.textView
        context.coordinator.text = $text
        container.onCommandSave = onCommandSave
        if textView.string != text {
            textView.string = text
            container.updateLineNumbers()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            (textView.enclosingScrollView?.superview as? CodeEditingContainerView)?.updateLineNumbers()
        }
    }
}

final class CommandSavingTextView: NSTextView {
    var onCommandSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onCommandSave?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

final class CodeEditingContainerView: NSView {
    let textView: CommandSavingTextView
    var onCommandSave: () -> Void {
        didSet {
            textView.onCommandSave = onCommandSave
        }
    }

    private let theme: CodePreviewTheme
    private let lineNumberView = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private var lineNumberWidthConstraint: NSLayoutConstraint?

    init(theme: CodePreviewTheme, onCommandSave: @escaping () -> Void) {
        self.theme = theme
        self.onCommandSave = onCommandSave
        self.textView = CommandSavingTextView()
        super.init(frame: .zero)
        self.textView.onCommandSave = onCommandSave
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(theme.canvas).cgColor

        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        lineNumberView.textColor = NSColor(theme.lineNumber)
        lineNumberView.backgroundColor = .clear
        lineNumberView.alignment = .right
        lineNumberView.lineBreakMode = .byClipping
        lineNumberView.maximumNumberOfLines = 0

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(theme.canvas)
        scrollView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 14)
        scrollView.postsBoundsChangedNotifications = true

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(theme.canvas)
        textView.textColor = NSColor(theme.primaryText)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 0)
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView

        addSubview(lineNumberView)
        addSubview(scrollView)

        lineNumberWidthConstraint = lineNumberView.widthAnchor.constraint(equalToConstant: 42)
        lineNumberWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor, constant: 12),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateLineNumbers() {
        let count = max(1, textView.string.reduce(1) { total, character in
            character == "\n" ? total + 1 : total
        })
        let digits = max(2, "\(count)".count)
        let numbers = (1...count).map { String(format: "%\(digits)d", $0) }.joined(separator: "\n")
        lineNumberView.stringValue = numbers
        lineNumberWidthConstraint?.constant = CGFloat(digits) * 8 + 16
        updateLineNumberOffset()
    }

    @objc private func boundsDidChange() {
        updateLineNumberOffset()
    }

    private func updateLineNumberOffset() {
        lineNumberView.frame.origin.y = 12 - scrollView.contentView.bounds.origin.y
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

enum CodePreviewTheme: Equatable {
    case dark
    case light

    var canvas: Color {
        switch self {
        case .dark: return Color(red: 0.055, green: 0.063, blue: 0.09)
        case .light: return Color.white
        }
    }

    var header: Color {
        switch self {
        case .dark: return Color(red: 0.075, green: 0.085, blue: 0.12)
        case .light: return Color(red: 0.965, green: 0.972, blue: 0.985)
        }
    }

    var border: Color {
        switch self {
        case .dark: return Color.white.opacity(0.09)
        case .light: return Color.black.opacity(0.08)
        }
    }

    var primaryText: Color {
        switch self {
        case .dark: return Color(red: 0.88, green: 0.91, blue: 0.96)
        case .light: return Color(red: 0.12, green: 0.14, blue: 0.18)
        }
    }

    var secondaryText: Color {
        switch self {
        case .dark: return Color(red: 0.55, green: 0.60, blue: 0.68)
        case .light: return Color(red: 0.42, green: 0.47, blue: 0.55)
        }
    }

    var lineNumber: Color {
        switch self {
        case .dark: return Color(red: 0.36, green: 0.42, blue: 0.50)
        case .light: return Color(red: 0.58, green: 0.64, blue: 0.72)
        }
    }

    var separator: Color {
        switch self {
        case .dark: return Color(red: 0.22, green: 0.26, blue: 0.32)
        case .light: return Color(red: 0.82, green: 0.85, blue: 0.90)
        }
    }

    var accent: Color {
        switch self {
        case .dark: return Color(red: 0.38, green: 0.72, blue: 1.0)
        case .light: return Color(red: 0.02, green: 0.36, blue: 0.82)
        }
    }

    var shadow: Color {
        switch self {
        case .dark: return Color.black.opacity(0.18)
        case .light: return Color.black.opacity(0.08)
        }
    }
}

//
//  PreviewWindow.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI

struct PreviewWindow: View {
    let item: ClipboardItem
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: item.contentType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text(item.contentType.displayName)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text(item.displayTime)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: {
                    onClose?()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                previewContent
                    .padding(20)
            }

            Divider()

            HStack {
                Text(item.displaySize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button("复制") {
                    PasteService.shared.copyToPasteboard(item)
                }
                .buttonStyle(.bordered)

                Button("粘贴") {
                    PasteService.shared.paste(item)
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 600, height: 450)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.contentType {
        case .text:
            ScrollView {
                Text(item.textContent ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

        case .link:
            VStack(spacing: 16) {
                Image(systemName: "link.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                if let url = URL(string: item.textContent ?? "") {
                    Link(destination: url) {
                        Text(item.textContent ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                            .underline()
                    }
                }
            }
            .frame(maxWidth: .infinity)

        case .image:
            VStack(spacing: 12) {
                if let imagePath = item.imagePath,
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }

                Text("\(item.imageWidth) x \(item.imageHeight)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .file:
            filePreview

        case .color:
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: item.colorHex ?? "") ?? .clear)
                    .frame(width: 200, height: 200)

                VStack(spacing: 8) {
                    infoRow(label: "HEX", value: item.colorHex ?? "-")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - File Preview

    @ViewBuilder
    private var filePreview: some View {
        if isCodeFile(item.fileName ?? "") {
            // 代码文件：显示内容
            codeFilePreview
        } else {
            // 非代码文件：显示文件信息
            regularFilePreview
        }
    }

    private var codeFilePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件信息头
            HStack {
                Image(systemName: fileIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Text(item.fileName ?? "")
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Text(codeLanguage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }

            Divider()

            // 代码内容
            if let content = readFileContent() {
                ScrollView {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)

                    Text("无法读取文件内容")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    infoRow(label: "路径", value: item.filePath ?? "-")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var regularFilePreview: some View {
        VStack(spacing: 16) {
            Image(systemName: fileIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                infoRow(label: "文件名", value: item.fileName ?? "-")
                infoRow(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))
                infoRow(label: "路径", value: item.filePath ?? "-")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// 判断是否为代码文件
    private func isCodeFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let codeExtensions = [
            "swift", "go", "java", "py", "lua", "html", "vue", "js", "json",
            "css", "ts", "jsx", "tsx", "rb", "php", "c", "cpp", "h", "hpp",
            "cs", "kt", "rs", "scala", "sh", "bash", "zsh", "sql", "xml",
            "yaml", "yml", "toml", "ini", "cfg", "conf", "md", "txt",
            "dart", "r", "m", "mm", "pl", "ex", "exs", "erl", "clj",
            "hs", "ml", "fs", "vim", "el", "lisp", "proto", "graphql",
            "tf", "dockerfile", "makefile", "cmake"
        ]
        return codeExtensions.contains(ext)
    }

    /// 代码文件图标
    private var fileIcon: String {
        guard let fileName = item.fileName else { return "doc" }
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp3", "wav", "flac", "m4a": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "video"
        default:
            if isCodeFile(fileName) {
                return "chevron.left.forwardslash.chevron.right"
            }
            return "doc"
        }
    }

    /// 代码语言名称
    private var codeLanguage: String {
        guard let fileName = item.fileName else { return "" }
        let ext = (fileName as NSString).pathExtension.lowercased()

        let languageMap: [String: String] = [
            "swift": "Swift", "go": "Go", "java": "Java", "py": "Python",
            "lua": "Lua", "html": "HTML", "vue": "Vue", "js": "JavaScript",
            "json": "JSON", "css": "CSS", "ts": "TypeScript", "jsx": "JSX",
            "tsx": "TSX", "rb": "Ruby", "php": "PHP", "c": "C",
            "cpp": "C++", "h": "C Header", "hpp": "C++ Header",
            "cs": "C#", "kt": "Kotlin", "rs": "Rust", "scala": "Scala",
            "sh": "Shell", "bash": "Bash", "zsh": "Zsh", "sql": "SQL",
            "xml": "XML", "yaml": "YAML", "yml": "YAML", "toml": "TOML",
            "md": "Markdown", "txt": "Text", "dart": "Dart",
            "r": "R", "m": "Objective-C", "mm": "Obj-C++",
            "proto": "Protocol Buffers", "graphql": "GraphQL",
            "tf": "Terraform", "ex": "Elixir", "erl": "Erlang",
            "hs": "Haskell", "ml": "OCaml", "fs": "F#"
        ]

        return languageMap[ext] ?? ext.uppercased()
    }

    /// 读取文件内容（限制大小）
    private func readFileContent() -> String? {
        guard let filePath = item.filePath else { return nil }

        // 限制文件大小：大于 1MB 不读取
        let maxSize = 1024 * 1024
        if item.fileSize > maxSize {
            return "文件过大，无法预览（\(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))）"
        }

        let url = URL(fileURLWithPath: filePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // 限制显示行数
        let lines = content.components(separatedBy: .newlines)
        if lines.count > 500 {
            let limited = lines.prefix(500).joined(separator: "\n")
            return limited + "\n\n... (共 \(lines.count) 行，仅显示前 500 行)"
        }

        return content
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

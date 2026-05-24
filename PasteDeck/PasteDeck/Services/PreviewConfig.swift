//
//  PreviewConfig.swift
//  PasteDeck
//
//  Manages preview configuration: which file extensions get syntax highlighting,
//  which get plain text display, stored in ~/.pastedeck/config.json
//
//  Created on 2026-05-24.
//

import Foundation

struct PreviewFileConfig: Codable {
    /// 文件后缀 → 语法高亮语言名（Highlightr 识别的语言 ID）
    var highlightExtensions: [String: String]

    /// 纯文本显示的后缀（不高亮，等宽字体）
    var plainTextExtensions: [String]

    /// 文件内容预览大小上限（字节）
    var maxPreviewSize: Int

    static let `default` = PreviewFileConfig(
        highlightExtensions: [
            // 代码类
            "swift": "swift",
            "go": "go",
            "java": "java",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "jsx": "javascript",
            "tsx": "typescript",
            "c": "c",
            "cpp": "cpp",
            "h": "c",
            "hpp": "cpp",
            "rs": "rust",
            "rb": "ruby",
            "php": "php",
            "kt": "kotlin",
            "lua": "lua",
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash",
            "sql": "sql",
            "r": "r",
            // 标记/配置类
            "html": "xml",
            "css": "css",
            "vue": "xml",
            "json": "json",
            "xml": "xml",
            "yaml": "yaml",
            "yml": "yaml",
            "toml": "ini",
            "ini": "ini",
            "conf": "ini",
            "md": "markdown",
        ],
        plainTextExtensions: [
            "txt", "log", "csv", "tsv", "env", "gitignore", "dockerfile", "makefile"
        ],
        maxPreviewSize: 512 * 1024  // 512KB
    )
}

class PreviewConfigManager {
    static let shared = PreviewConfigManager()

    private let configDir: URL
    private let configURL: URL
    var config: PreviewFileConfig

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".pastedeck")
        configURL = configDir.appendingPathComponent("config.json")

        // 加载或使用默认
        if let loaded = Self.loadFrom(url: configURL) {
            config = loaded
        } else {
            config = .default
            // 首次运行写一份默认配置
            Self.save(config: config, to: configURL)
        }
    }

    /// 判断文件后缀是否应该预览内容
    func shouldPreviewContent(fileName: String?) -> PreviewMode {
        guard let fileName = fileName else { return .none }
        let ext = (fileName as NSString).pathExtension.lowercased()

        if !ext.isEmpty {
            if config.highlightExtensions[ext] != nil {
                return .highlight
            }
            if config.plainTextExtensions.contains(ext) {
                return .plain
            }
        } else {
            // 无后缀文件名匹配（如 Makefile, Dockerfile）
            let nameLower = fileName.lowercased()
            if config.plainTextExtensions.contains(nameLower) {
                return .plain
            }
        }
        return .none
    }

    /// 获取 Highlightr 语言 ID
    func highlightLanguage(for fileName: String?) -> String? {
        guard let fileName = fileName else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return config.highlightExtensions[ext]
    }

    /// 保存配置
    func save() {
        Self.save(config: config, to: configURL)
    }

    // MARK: - Private

    private static func loadFrom(url: URL) -> PreviewFileConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PreviewFileConfig.self, from: data)
    }

    private static func save(config: PreviewFileConfig, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// 预览模式
enum PreviewMode {
    case none       // 不预览文件内容
    case highlight  // 语法高亮
    case plain      // 纯文本
}

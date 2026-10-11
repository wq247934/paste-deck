//
//  ToolSearchService.swift
//  PasteDeck
//
//  统一搜索中的工具侧搜索：对内置工具的名称、别名、关键词与描述
//  做轻量打分匹配，并在查询本身可被严格识别为时间戳 / IP 时给出
//  内容建议。独立于 ClipboardHistoryStore，互不影响。
//

import Foundation

enum ToolSearchService {

    enum MatchReason: Equatable {
        case alias
        case name
        case keyword
        case summary
        case contentSuggestion
    }

    struct Result: Identifiable, Equatable {
        var id: String { tool.id }
        let tool: BuiltinTool
        let score: Int
        let reason: MatchReason
        /// 内容建议场景下的预填文本（例如用户直接搜索一个时间戳）。
        let prefilledText: String?
    }

    // MARK: - 打分权重

    private enum Score {
        static let aliasExact = 100
        static let aliasPrefix = 92
        static let nameExact = 95
        static let namePrefix = 88
        static let nameContains = 80
        static let keywordExact = 85
        static let keywordPrefix = 75
        static let keywordContains = 70
        static let summaryContains = 40
        static let contentSuggestion = 96
        static let minimumVisible = 40
    }

    /// 搜索工具。空查询返回空数组：搜索为空时主面板维持原有剪贴板界面。
    static func search(_ rawQuery: String) -> [Result] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var bestByTool: [BuiltinTool: Result] = [:]

        func offer(_ tool: BuiltinTool, score: Int, reason: MatchReason, prefill: String? = nil) {
            let candidate = Result(tool: tool, score: score, reason: reason, prefilledText: prefill)
            if let existing = bestByTool[tool] {
                if candidate.score > existing.score {
                    bestByTool[tool] = candidate
                }
            } else {
                bestByTool[tool] = candidate
            }
        }

        for tool in BuiltinTool.allCases {
            let descriptor = tool.descriptor

            if let score = aliasScore(aliasList: descriptor.aliases, query: query) {
                offer(tool, score: score.0, reason: .alias)
            }
            if let score = nameScore(name: descriptor.name.lowercased(), query: query) {
                offer(tool, score: score, reason: .name)
            }
            if let score = keywordScore(keywords: descriptor.keywords, query: query) {
                offer(tool, score: score, reason: .keyword)
            }
            if descriptor.summary.lowercased().contains(query) {
                offer(tool, score: Score.summaryContains, reason: .summary)
            }
        }

        offerContentSuggestions(query: query, offer: offer)

        return bestByTool.values
            .filter { $0.score >= Score.minimumVisible }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.tool.rawValue < $1.tool.rawValue
            }
    }

    // MARK: - 内容建议

    /// 查询本身是合法时间戳 / IP 时，把对应工具以内容建议的方式加入结果，
    /// 置信度要求由 ContentRecognizer 的严格解析保证。
    private static func offerContentSuggestions(
        query: String,
        offer: (BuiltinTool, Int, MatchReason, String?) -> Void
    ) {
        switch ContentRecognizer.recognizeText(query) {
        case .unixTimestamp:
            offer(.timestampConversion, Score.contentSuggestion, .contentSuggestion, query)
        case .ipv4Address, .ipv4CIDR:
            offer(.ipv4Subnet, Score.contentSuggestion, .contentSuggestion, query)
        case .unrecognized:
            break
        }
    }

    // MARK: - 字段打分

    private static func aliasScore(aliasList: [String], query: String) -> (Int, MatchReason)? {
        var best: Int?
        for alias in aliasList {
            let normalized = alias.lowercased()
            if normalized == query {
                return (Score.aliasExact, .alias)
            }
            if normalized.hasPrefix(query) {
                best = max(best ?? 0, Score.aliasPrefix)
            }
        }
        return best.map { ($0, MatchReason.alias) }
    }

    private static func nameScore(name: String, query: String) -> Int? {
        if name == query { return Score.nameExact }
        if name.hasPrefix(query) { return Score.namePrefix }
        if name.contains(query) { return Score.nameContains }
        return nil
    }

    private static func keywordScore(keywords: [String], query: String) -> Int? {
        var best: Int?
        for keyword in keywords {
            let normalized = keyword.lowercased()
            if normalized == query {
                return Score.keywordExact
            }
            if normalized.hasPrefix(query) {
                best = max(best ?? 0, Score.keywordPrefix)
            } else if normalized.contains(query) {
                best = max(best ?? 0, Score.keywordContains)
            }
        }
        return best
    }
}

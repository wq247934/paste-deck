//
//  TOMLDocument.swift
//  PasteDeck
//
//  面向 Codex config.toml 的轻量结构扫描器。
//  只实现本模块需要的语义：表头路径、键值定位（含多行括号续值）、
//  字符串值读取、标记块定位。完整 TOML 词法不在目标范围内；
//  无法识别的结构一律按"不属于本模块"处理（fail-closed）。
//

import Foundation

/// 一个表头：行号与点分路径。
public struct TOMLTableHeader: Equatable {
    public let lineIndex: Int
    public let path: [String]
}

/// 一个键值赋值：所属表路径与值的行范围（多行值含续行）。
public struct TOMLAssignment: Equatable {
    public let lineIndex: Int
    public let tablePath: [String]
    public let key: String
    public let valueRange: ClosedRange<Int>
}

/// 结构扫描结果。
public struct TOMLScanResult {
    public var lines: [String]
    public var headers: [TOMLTableHeader]
    public var assignments: [TOMLAssignment]

    /// 根级（任何表头之前）赋值。
    public var rootAssignments: [TOMLAssignment] {
        assignments.filter { $0.tablePath.isEmpty }
    }

    /// 读取字符串值（双引号基本字符串，处理转义）。
    public func stringValue(tablePath: [String], key: String) -> String? {
        guard let assignment = assignments.first(where: {
            $0.tablePath == tablePath && $0.key == key
        }) else { return nil }
        let text = lines[assignment.valueRange.lowerBound]
        return Self.decodeBasicString(text, key: key)
    }

    public static func decodeBasicString(_ line: String, key: String) -> String? {
        guard let range = line.range(of: "=") else { return nil }
        let raw = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard raw.hasPrefix("\"") else { return nil }
        return decodeQuotedBody(raw, from: raw.startIndex)
    }

    /// 解析以开引号起始的基本字符串体（处理 \\ 转义）。
    public static func decodeQuotedBody(_ raw: String, from quoteIndex: String.Index) -> String {
        var result = ""
        var index = raw.index(after: quoteIndex)
        while index < raw.endIndex {
            let character = raw[index]
            if character == "\\" {
                guard let next = raw.index(index, offsetBy: 1, limitedBy: raw.endIndex) else { break }
                if next < raw.endIndex {
                    let escaped = raw[next]
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default:
                        result.append(escaped)
                    }
                    index = raw.index(after: next)
                    continue
                }
                break
            }
            if character == "\"" { break }
            result.append(character)
            index = raw.index(after: index)
        }
        return result
    }
}

public enum TOMLScanError: LocalizedError {
    case unterminatedValue(Int)

    public var errorDescription: String? {
        switch self {
        case .unterminatedValue(let line):
            return "TOML 第 \(line + 1) 行的值未闭合，无法安全改写。"
        }
    }
}

public enum TOMLScanner {
    /// 扫描整个文档。括号/引号不闭合的续值会抛错——改写前必须中止，而不是猜测。
    public static func scan(_ text: String) throws -> TOMLScanResult {
        var lines = text.components(separatedBy: "\n")
        // 去掉结尾空行集合造成的最后一个空成分（保留原文件行数语义由调用方处理）。
        if lines.last?.isEmpty == true, text.hasSuffix("\n") { lines.removeLast() }

        var headers: [TOMLTableHeader] = []
        var assignments: [TOMLAssignment] = []
        var currentPath: [String] = []

        var index = 0
        while index < lines.count {
            let trimmed = trimLine(lines[index])
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            if trimmed.hasPrefix("[") {
                // 表头（含 [[array of tables]]，按路径处理即可）。
                if let path = parseHeaderPath(trimmed) {
                    headers.append(TOMLTableHeader(lineIndex: index, path: path))
                    currentPath = path
                    index += 1
                    continue
                }
                index += 1
                continue
            }
            if let equalIndex = trimmed.firstIndex(of: "="), isOutsideString(trimmed, position: equalIndex) {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = index
                let valueEnd = try continuationEnd(lines: lines, from: index)
                if !key.isEmpty {
                    assignments.append(TOMLAssignment(
                        lineIndex: index, tablePath: currentPath, key: key,
                        valueRange: valueStart...valueEnd))
                }
                index = valueEnd + 1
                continue
            }
            index += 1
        }
        return TOMLScanResult(lines: lines, headers: headers, assignments: assignments)
    }

    // MARK: - 内部

    private static func trimLine(_ line: String) -> String {
        guard let range = line.rangeOfCharacter(from: .whitespaces.inverted) else { return "" }
        return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseHeaderPath(_ trimmed: String) -> [String]? {
        guard trimmed.hasPrefix("[") else { return nil }
        let inner = trimmed.drop(while: { $0 == "[" })
        let reverse = inner.reversed().drop(while: { $0 == "]" })
        let body = String(reverse.reversed()).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return splitDottedPath(body)
    }

    /// 按点分拆路径，引号段内保留点。
    private static func splitDottedPath(_ body: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inBasic = false
        var inLiteral = false
        var escaped = false
        for character in body {
            if escaped { current.append(character); escaped = false; continue }
            switch character {
            case "\\" where inBasic: escaped = true
            case "\"" where inBasic: inBasic = false; parts.append(current); current = ""
            case "\"" where !inLiteral: inBasic = true
            case "'" where inLiteral: inLiteral = false; parts.append(current); current = ""
            case "'" where !inBasic: inLiteral = true
            case "." where !inBasic && !inLiteral:
                if !current.isEmpty { parts.append(current); current = "" }
            default: current.append(character)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// 判断位置是否在字符串之外（用于找真正的 '='）。
    private static func isOutsideString(_ line: String, position: String.Index) -> Bool {
        var inBasic = false
        var inLiteral = false
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if escaped { escaped = false; continue }
            if index == position { return !inBasic && !inLiteral }
            switch character {
            case "\\" where inBasic: escaped = true
            case "\"" where inBasic: inBasic = false
            case "\"" where !inLiteral && !inBasic: inBasic = true
            case "'" where inLiteral: inLiteral = false
            case "'" where !inBasic && !inLiteral: inLiteral = true
            default: break
            }
        }
        return true
    }

    /// 值从 from 行的 '=' 之后开始，返回值最后一行的行号。
    /// 跟踪括号深度、字符串状态与三引号多行字符串。
    private static func continuationEnd(lines: [String], from: Int) throws -> Int {
        var depth = 0
        var inBasic = false
        var inLiteral = false
        var inTripleBasic = false
        var inTripleLiteral = false
        var escaped = false
        var seenValue = false
        var index = from
        while index < lines.count {
            let line = lines[index]
            var position = line.startIndex
            while position < line.endIndex {
                let character = line[position]
                if escaped { escaped = false; seenValue = true; position = line.index(after: position); continue }
                if inTripleBasic {
                    if line[position...].hasPrefix("\"\"\"") {
                        inTripleBasic = false
                        position = line.index(position, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
                        seenValue = true
                        continue
                    }
                    if character == "\\" { escaped = true }
                    position = line.index(after: position)
                    continue
                }
                if inTripleLiteral {
                    if line[position...].hasPrefix("'''") {
                        inTripleLiteral = false
                        position = line.index(position, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
                        seenValue = true
                        continue
                    }
                    position = line.index(after: position)
                    continue
                }
                switch character {
                case "\\" where inBasic: escaped = true
                case "\"" where inBasic: inBasic = false
                case "\"" where !inLiteral && !inBasic:
                    if line[position...].hasPrefix("\"\"\"") {
                        inTripleBasic = true
                        position = line.index(position, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
                        seenValue = true
                        continue
                    }
                    inBasic = true
                case "'" where inLiteral: inLiteral = false
                case "'" where !inBasic && !inLiteral:
                    if line[position...].hasPrefix("'''") {
                        inTripleLiteral = true
                        position = line.index(position, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
                        seenValue = true
                        continue
                    }
                    inLiteral = true
                case "[", "{" where !inBasic && !inLiteral: depth += 1
                case "]", "}" where !inBasic && !inLiteral: depth -= 1
                case "#" where !inBasic && !inLiteral:
                    // 行内注释：若括号未闭合则续行仍属同一值，保守视为值结束。
                    if depth <= 0, !inTripleBasic, !inTripleLiteral { return index }
                default: break
                }
                if !inBasic && !inLiteral && !inTripleBasic && !inTripleLiteral,
                   !character.isWhitespace, character != "#" {
                    seenValue = true
                }
                position = line.index(after: position)
            }
            let insideTriple = inTripleBasic || inTripleLiteral
            if seenValue && depth <= 0 && !inBasic && !inLiteral && !insideTriple && !escaped {
                return index
            }
            index += 1
        }
        throw TOMLScanError.unterminatedValue(from)
    }
}

/// TOML 基本字符串字面量转义（对齐 config-manager 的 JSON.stringify 输出）。
public enum TOMLValue {
    public static func basicString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

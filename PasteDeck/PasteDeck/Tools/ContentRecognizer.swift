//
//  ContentRecognizer.swift
//  PasteDeck
//
//  对剪贴板快照做纯内存内容识别：无网络请求、无磁盘扫描。
//  只在整段内容严格命中格式时才推荐工具，避免普通文本被误判。
//

import Foundation

enum ContentRecognizer {

    /// 供测试与搜索内容建议使用的纯文本识别结果。
    enum TextMatch: Equatable {
        case unixTimestamp(TimestampMath.ParsedTimestamp)
        case ipv4Address(IPv4Math.Address)
        case ipv4CIDR(address: IPv4Math.Address, prefixLength: Int)
        case unrecognized
    }

    /// 卡片上下文识别结果：命中的工具与预填文本。
    struct Match: Equatable {
        let tool: BuiltinTool
        let prefilledText: String?
    }

    /// 超过该长度的文本不再做整段识别，避免对大段文本做无谓扫描。
    private static let maxRecognitionLength = 128

    // MARK: - 纯文本识别

    static func recognizeText(_ raw: String?) -> TextMatch {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.count <= maxRecognitionLength else {
            return .unrecognized
        }

        if trimmed.contains("/"),
           let parsed = IPv4Math.parseSubnet(trimmed) {
            return .ipv4CIDR(address: parsed.address, prefixLength: parsed.subnet.prefixLength)
        }

        if let address = IPv4Math.Address.parse(trimmed) {
            return .ipv4Address(address)
        }

        if let timestamp = TimestampMath.parse(trimmed) {
            return .unixTimestamp(timestamp)
        }

        return .unrecognized
    }

    // MARK: - 卡片识别

    /// 返回选中卡片适用的工具。图片、文件、颜色、链接等内容一律返回空，
    /// 不显示无意义的工具。
    static func recognize(_ snapshot: ClipboardItemSnapshot) -> [Match] {
        guard snapshot.contentType == .text,
              let text = snapshot.textContent else {
            return []
        }

        switch recognizeText(text) {
        case .unixTimestamp:
            return [Match(tool: .timestampConversion, prefilledText: trimmedText(text))]
        case .ipv4Address, .ipv4CIDR:
            return [Match(tool: .ipv4Subnet, prefilledText: trimmedText(text))]
        case .unrecognized:
            return []
        }
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

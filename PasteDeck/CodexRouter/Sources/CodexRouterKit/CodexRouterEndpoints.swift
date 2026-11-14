//
//  CodexRouterEndpoints.swift
//  PasteDeck
//
//  第三方 Responses API 端点与模型的配置存储。
//  持久层为 ~/.codex/pastedeck-router/endpoints.json（0600，原子写），
//  守护进程与主程序共享同一份文件；API Key 的持久层在 macOS Keychain，
//  启用路由时由控制器物化为 0600 的 credentials.json 供守护进程读取。
//

import Foundation

/// 一个第三方 Responses API 端点（中转站）。
public struct RouterEndpoint: Codable, Identifiable, Equatable {
    /// 稳定路由 id，也是模型 slug 的命名空间前缀，如 "routex"。
    /// 限定 [a-z0-9-]，不得与官方模型 slug 冲突。
    public var id: String
    public var displayName: String
    /// Base URL，例如 https://relay.example.com/v1（协议固定 /responses 后缀）。
    public var baseURL: String
    public var enabled: Bool
    public var models: [RouterEndpointModel]

    public init(
        id: String, displayName: String, baseURL: String,
        enabled: Bool, models: [RouterEndpointModel]
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.enabled = enabled
        self.models = models
    }
}

/// 端点下的一个模型。
public struct RouterEndpointModel: Codable, Identifiable, Equatable {
    /// 上游真实模型 ID（发送到端点的 model 字段），如 "deepseek-v4.1-flash"。
    public var modelID: String
    /// 选择器里的显示名称。
    public var displayName: String
    public var enabled: Bool
    /// 上下文窗口（token）。nil 时用保守默认。
    public var contextWindow: Int?
    /// 自动压缩阈值。nil 时用保守默认。
    public var autoCompact: Int?
    /// 推理等级（effort）列表，按从轻到重排序；空表示端点不接受 effort。
    public var reasoningEfforts: [String]
    /// 默认推理等级。
    public var defaultEffort: String?
    /// 输入模态，默认 ["text"]。
    public var inputModalities: [String]
    /// 是否支持推理摘要。
    public var supportsReasoningSummaries: Bool

    public var id: String { modelID }

    public static let defaultContextWindow = 131_072
    public static let defaultAutoCompact = 110_000

    public init(
        modelID: String, displayName: String, enabled: Bool,
        contextWindow: Int?, autoCompact: Int?, reasoningEfforts: [String],
        defaultEffort: String?, inputModalities: [String], supportsReasoningSummaries: Bool
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.enabled = enabled
        self.contextWindow = contextWindow
        self.autoCompact = autoCompact
        self.reasoningEfforts = reasoningEfforts
        self.defaultEffort = defaultEffort
        self.inputModalities = inputModalities
        self.supportsReasoningSummaries = supportsReasoningSummaries
    }

    /// 新建模型时的保守默认值（对齐 user-models.mjs 的 DEFAULT_*）。
    public static func standard(modelID: String, displayName: String) -> RouterEndpointModel {
        RouterEndpointModel(
            modelID: modelID,
            displayName: displayName,
            enabled: true,
            contextWindow: nil,
            autoCompact: nil,
            reasoningEfforts: ["high"],
            defaultEffort: "high",
            inputModalities: ["text"],
            supportsReasoningSummaries: false
        )
    }
}

/// 代理配置。
public struct RouterProxyConfig: Codable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Identifiable {
        case none          // 不使用代理
        case system        // 跟随系统代理
        case http          // 自定义 HTTP/HTTPS 代理
        case socks5        // 自定义 SOCKS5 代理

        public var id: String { rawValue }

        public var localizedName: String {
            switch self {
            case .none: return "不使用代理"
            case .system: return "跟随系统代理"
            case .http: return "HTTP / HTTPS 代理"
            case .socks5: return "SOCKS5 代理"
            }
        }
    }

    public var mode: Mode
    /// 自定义代理地址（mode 为 http / socks5 时有效）。
    public var host: String
    public var port: Int
    /// 可选用户名（密码存 Keychain）。
    public var username: String

    public init(mode: Mode, host: String, port: Int, username: String) {
        self.mode = mode
        self.host = host
        self.port = port
        self.username = username
    }

    public static func standard() -> RouterProxyConfig {
        RouterProxyConfig(mode: .none, host: "", port: 0, username: "")
    }

    public var isCustomConfigured: Bool {
        (mode == .http || mode == .socks5) && !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0
    }
}

/// 端点配置的持久化文档。
public struct RouterEndpointsDocument: Codable, Equatable {
    public var version: Int
    public var endpoints: [RouterEndpoint]
    public var proxy: RouterProxyConfig

    public static let currentVersion = 1

    public init(version: Int, endpoints: [RouterEndpoint], proxy: RouterProxyConfig) {
        self.version = version
        self.endpoints = endpoints
        self.proxy = proxy
    }

    public static func empty() -> RouterEndpointsDocument {
        RouterEndpointsDocument(version: currentVersion, endpoints: [], proxy: .standard())
    }
}

/// 端点配置存储：主程序写、守护进程读，双方都以同一文件为准。
public final class RouterEndpointStore {
    public let fileURL: URL

    public init(stateDirectory: URL? = nil) {
        let directory = stateDirectory ?? CodexRouterConstants.stateDirectory()
        self.fileURL = directory.appendingPathComponent("endpoints.json")
    }

    public func load() -> RouterEndpointsDocument {
        if let document = PrivateFile.readJSON(fileURL, as: RouterEndpointsDocument.self),
           document.version == RouterEndpointsDocument.currentVersion {
            return document
        }
        return .empty()
    }

    public func save(_ document: RouterEndpointsDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try PrivateFile.writeAtomically(data, to: fileURL)
    }
}

/// 运行时凭据文件（0600）：Keychain 中的 API Key 在启用路由时物化到这里，
/// 供守护进程读取；关闭路由时删除。
public struct RuntimeCredentialsDocument: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var endpointID: String
        public var apiKey: String

        public init(endpointID: String, apiKey: String) {
            self.endpointID = endpointID
            self.apiKey = apiKey
        }
    }
    public var version: Int
    public var entries: [Entry]
    public var proxyPassword: String?

    public init(version: Int, entries: [Entry], proxyPassword: String?) {
        self.version = version
        self.entries = entries
        self.proxyPassword = proxyPassword
    }

    public static let currentVersion = 1
}

public enum SlugBuilder {
    /// 模型 slug："<端点id>/<模型id>"。官方原生 slug 不含 "/"，天然无冲突。
    public static func slug(endpointID: String, modelID: String) -> String {
        "\(endpointID)/\(modelID)"
    }

    /// 从 slug 中拆出端点前缀。
    public static func endpointPrefix(of slug: String) -> String? {
        guard let index = slug.firstIndex(of: "/") else { return nil }
        return String(slug[..<index])
    }

    /// 校验端点 id：[a-z0-9-]，1-32 位。
    public static func isValidEndpointID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 32 else { return false }
        return id.allSatisfy { ($0.isLowercase && $0.isLetter) || ($0.isNumber && $0.isASCII) || $0 == "-" }
    }
}

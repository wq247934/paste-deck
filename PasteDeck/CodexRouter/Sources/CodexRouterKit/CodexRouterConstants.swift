//
//  CodexRouterConstants.swift
//  PasteDeck
//
//  Codex 模型路由模块的路径、端口与标记常量。
//  状态目录独立于旧 Codex Router（~/.codex/codex-router），互不干扰。
//

import Foundation

/// Codex 模型路由的全局常量。
public enum CodexRouterConstants {
    /// 服务标识，健康检查据此区分本模块与旧 Codex Router。
    public static let serviceIdentifier = "pastedeck-codex-router"

    /// 状态目录：~/.codex/pastedeck-router/（尊重 CODEX_HOME 覆盖）。
    public static func stateDirectory(codexHome: String? = nil) -> URL {
        let home = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? NSHomeDirectory().appending("/.codex")
        return URL(fileURLWithPath: home).appendingPathComponent("pastedeck-router", isDirectory: true)
    }

    /// Codex 主配置文件路径。
    public static func codexConfigPath(codexHome: String? = nil) -> URL {
        let home = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? NSHomeDirectory().appending("/.codex")
        return URL(fileURLWithPath: home).appendingPathComponent("config.toml")
    }

    /// Codex 原生目录缓存（Codex 登录后由客户端自行写入）。
    public static func modelsCachePath(codexHome: String? = nil) -> URL {
        let home = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? NSHomeDirectory().appending("/.codex")
        return URL(fileURLWithPath: home).appendingPathComponent("models_cache.json")
    }

    /// 官方 ChatGPT Codex 后端（原生 GPT 转发目标）。
    public static let nativeBaseURL = "https://chatgpt.com/backend-api/codex"

    /// 默认监听端口。旧 Codex Router 使用 4202，本模块错开。
    public static let defaultPort = 4212
    /// 端口冲突时的探测上限（4212...4239）。
    public static let maxPortProbe = 28

    // MARK: - 托管标记（与旧 Codex Router 的 codex-router-managed 标记区分）

    public static let markerRootBegin = "# BEGIN pastedeck-router-managed"
    public static let markerRootEnd = "# END pastedeck-router-managed"
    public static let markerProviderBegin = "# BEGIN pastedeck-router-provider-managed"
    public static let markerProviderEnd = "# END pastedeck-router-provider-managed"
    public static let markerSignedBegin = "# BEGIN pastedeck-router-signed-provider-managed"
    public static let markerSignedEnd = "# END pastedeck-router-signed-provider-managed"

    /// 本模块管理的 provider id。
    public static let providerID = "pastedeck-router"
    public static let signedProviderID = "pastedeck-router-signed"
    /// 旧 Codex Router 的 provider id（共存检测用）。
    public static let legacyProviderID = "codex-router"
    public static let legacySignedProviderID = "codex-router-signed"
    /// 旧 Codex Router 的托管标记前缀。
    public static let legacyMarkerPrefix = "# BEGIN codex-router"

    /// Responses WebSocket 协议令牌（与 Codex 客户端约定）。
    public static let responsesWebSocketBeta = "responses_websockets=2026-02-06"
}

//
//  CodexAuthSession.swift
//  PasteDeck
//
//  只读访问 Codex 本地登录会话（~/.codex/auth.json）。
//  用途一：验证调用方（Codex 客户端）带来的 Bearer 是否就是本机登录会话；
//  用途二：目录捕获时为账户目录请求提供请求头。
//  绝不记录、返回或转发令牌内容；只报告"可用/过期/邮箱"等元信息。
//

import Foundation

public struct CodexSessionStatus: Equatable {
    public var present: Bool
    public var usable: Bool
    public var expired: Bool
    public var hasAccountID: Bool
    public var email: String?
    public var expiresInHours: Double?
    public var ageHours: Double?
}

public enum CodexAuthSessionError: LocalizedError {
    case notSignedIn

    public var errorDescription: String {
        "本机 Codex 尚未登录 ChatGPT 账号，无法使用官方 Plus 通道。请先在 Codex 中完成登录。"
    }
}

/// auth.json 的只读读取器（对齐 codex-native-session.mjs 的验证语义）。
public struct CodexAuthSession {
    public let authFileURL: URL

    init(codexHome: String? = nil) {
        let home = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? NSHomeDirectory().appending("/.codex")
        self.authFileURL = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
    }

    public struct Session {
        public let accessToken: String
        public let accountID: String
        public let email: String?
        public let expiresAtMs: Double?
    }

    /// 读取会话；文件缺失或损坏返回 nil（不是错误——调用方按无会话处理）。
    func readSession() -> Session? {
        guard let data = FileManager.default.contents(atPath: authFileURL.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any] else { return nil }
        guard let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else { return nil }
        let accountID = tokens["account_id"] as? String ?? ""
        let idToken = tokens["id_token"] as? String
        return Session(
            accessToken: accessToken,
            accountID: accountID,
            email: idToken.flatMap(Self.email(fromIDToken:)),
            expiresAtMs: Self.tokenExpiryMs(accessToken)
        )
    }

    /// 会话是否有效（提前 2 分钟视为过期，避免轮次中途断线）。
    func isUsable(_ session: Session?, at date: Date = Date()) -> Bool {
        guard let session else { return false }
        guard let expiresAtMs = session.expiresAtMs else { return true }
        return expiresAtMs - 120_000 > date.timeIntervalSince1970 * 1000
    }

    func status(at date: Date = Date()) -> CodexSessionStatus {
        let present = FileManager.default.fileExists(atPath: authFileURL.path)
        let session = present ? readSession() : nil
        var ageHours: Double?
        if present,
           let attributes = try? FileManager.default.attributesOfItem(atPath: authFileURL.path),
           let modified = attributes[.modificationDate] as? Date {
            ageHours = (date.timeIntervalSince(modified) / 3600).rounded()
        }
        var expiresInHours: Double?
        if let expiresAtMs = session?.expiresAtMs {
            expiresInHours = ((expiresAtMs - date.timeIntervalSince1970 * 1000) / 3_600_000 * 10).rounded() / 10
        }
        return CodexSessionStatus(
            present: present,
            usable: isUsable(session, at: date),
            expired: session != nil && !isUsable(session, at: date),
            hasAccountID: !(session?.accountID ?? "").isEmpty,
            email: session?.email,
            expiresInHours: expiresInHours,
            ageHours: ageHours
        )
    }

    /// 验证一个 Bearer 令牌：与本地登录会话匹配，或为官方 API Key 登录模式。
    /// 这只用于鉴权调用方身份，绝不开启会话共享。
    func bearerMatchesLocalSession(_ token: String, at date: Date = Date()) -> Bool {
        guard !token.isEmpty else { return false }
        guard let data = FileManager.default.contents(atPath: authFileURL.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let tokens = object["tokens"] as? [String: Any],
           let accessToken = tokens["access_token"] as? String {
            let session = readSession()
            if let session, isUsable(session, at: date), constantTimeEquals(token, accessToken) {
                return true
            }
        }
        if (object["auth_mode"] as? String) == "apikey",
           let apiKey = object["OPENAI_API_KEY"] as? String {
            return constantTimeEquals(token, apiKey)
        }
        return false
    }

    /// 为只读账户目录请求（GET /backend-api/codex/models）构造请求头。
    /// 只允许用于该固定端点。
    func nativeAccountCatalogHeaders() throws -> [String: String] {
        var session = readSession()
        if !isUsable(session) {
            try refreshViaCodexCLI()
            session = readSession()
        }
        guard let session, isUsable(session) else { throw CodexAuthSessionError.notSignedIn }
        var headers = ["authorization": "Bearer \(session.accessToken)"]
        if !session.accountID.isEmpty {
            headers["chatgpt-account-id"] = session.accountID
        }
        return headers
    }

    // MARK: - 内部

    /// 令牌过期时让 Codex 自己刷新（codex login status 是只读探测，Codex
    /// 会按自己的节奏改写 auth.json）。尽力而为：失败则按过期处理。
    private func refreshViaCodexCLI() throws {
        let binary = CodexBinaryLocator.locateCodexBinary()
        guard let binary else { throw CodexAuthSessionError.notSignedIn }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["login", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        if process.isRunning {
            let deadline = Date().addingTimeInterval(30)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
        }
    }

    private static func tokenExpiryMs(_ accessToken: String) -> Double? {
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
        // base64url → base64。
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = claims["exp"] as? Double else { return nil }
        return expiry * 1000
    }

    private static func email(fromIDToken idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = claims["email"] as? String else { return nil }
        return email.count <= 320 && email.contains("@") ? email : nil
    }

    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        var difference = a.count == b.count ? 0 : 1
        let limit = max(a.count, b.count)
        for index in 0..<limit {
            let left = index < a.count ? Int(a[index]) : 0
            let right = index < b.count ? Int(b[index]) : 0
            difference |= left ^ right
        }
        return difference == 0
    }
}

/// 定位本机 Codex CLI（对齐 CodexQuotaService 的探测顺序）。
public enum CodexBinaryLocator {
    static func locateCodexBinary() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CODEX_CLI_PATH"], !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

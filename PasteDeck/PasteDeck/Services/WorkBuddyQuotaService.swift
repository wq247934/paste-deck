//
//  WorkBuddyQuotaService.swift
//  PasteDeck
//
//  WorkBuddy（腾讯 CodeBuddy）剩余积分查询：读取 WorkBuddy 桌面版写入的
//  本地凭证文件，直连腾讯官方计费接口获取各资源包总额 / 已用 / 剩余积分。
//  逻辑与 codex-quota-utools 插件的 workbuddy-quota.js 保持一致，
//  token 失效时自动用 refreshToken 续期并原子写回凭证文件。
//
//  Created on 2026-10-11.
//

import Foundation

enum WorkBuddyQuotaService {

    private static let endpoint = "https://copilot.tencent.com"
    private static let summaryPath = "/billing/meter/get-user-resource-summary"
    private static let refreshPath = "/v2/auth/token/refresh"
    private static let requestTimeout: TimeInterval = 15

    enum WorkBuddyQuotaError: LocalizedError {
        case credentialMissing
        case credentialUnreadable
        case credentialMissingToken
        case credentialInvalid(status: Int)
        case requestFailed(status: Int)
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .credentialMissing:
                return "未检测到 WorkBuddy 凭证。请确认已安装 WorkBuddy 桌面版，并至少登录过一次"
            case .credentialUnreadable:
                return "WorkBuddy 凭证文件无法解析，请打开 WorkBuddy 重新登录"
            case .credentialMissingToken:
                return "WorkBuddy 凭证中没有 accessToken，请打开应用重新登录"
            case .credentialInvalid(let status):
                return "WorkBuddy 凭证已失效（HTTP \(status)），请打开应用重新登录"
            case .requestFailed(let status):
                return "WorkBuddy 接口无响应（HTTP \(status)），请检查网络"
            case .apiError(let message):
                return "WorkBuddy 接口返回错误：\(message)"
            }
        }
    }

    // MARK: - 数据模型

    struct Package: Equatable, Identifiable {
        var code: String
        var name: String
        var total: Double
        var used: Double
        var remain: Double
        var unit: String

        var id: String { code }
    }

    struct Snapshot: Equatable {
        var packages: [Package]
        var total: Double
        var used: Double
        var remain: Double
        var isPaidUser: Bool
        var subscriptionName: String?
        var accountName: String?
        var accountType: String?
        var tokenExpiresAt: Date?
    }

    /// 资源包码 → 可读名称（取自 WorkBuddy 应用内 CommodityCode 枚举）。
    static let packageNames: [String: String] = [
        "TCACA_code_001_PqouKr6QWV": "免费包",
        "TCACA_code_002_AkiJS3ZHF5": "Pro 月付",
        "TCACA_code_003_FAnt7lcmRT": "Pro 年付",
        "TCACA_code_005_maRGyrHhw1": "Pro 月付 Plus",
        "TCACA_code_006_DbXS0lrypC": "赠送包",
        "TCACA_code_007_nzdH5h4Nl0": "运营裂变包（Growth Plan）",
        "TCACA_code_008_cfWoLwvjU4": "赠送月包",
        "TCACA_code_009_0XmEQc2xOf": "加量包",
        "TCACA_code_023_4xbGhMrE6q": "青春版",
        "TCACA_code_026_BaESVICNoi": "进阶版",
        "TCACA_code_027_0FCGVA6vSa": "旗舰版",
        "TCACA_code_028_NtpWi0jzXs": "赠送包 28",
        "TCACA_code_029_6wCGEWquYy": "赠送包 29",
        "TCACA_code_030_BjSt89qTvr": "赠送包 30",
        "TCACA_code_035_ArVxJcGDsm": "免费月包（海外版）",
        "TCACA_code_036_lupO5WgNdG": "加量包（海外版）",
        "TCACA_code_037_WxOD3MpI2o": "赠送包（海外版）",
        "TCACA_code_038_OhvqZtiPKr": "加量包 38",
    ]

    // MARK: - 查询入口

    static func query() async throws -> Snapshot {
        let credential = try readCredential()
        var raw = credential.raw
        var auth = credential.auth

        var response = try await post(path: summaryPath, headers: summaryHeaders(auth), body: [:])

        // token 失效时自动续期并重试一次
        if response.status == 401 || response.status == 403 {
            let freshAuth = try await refreshToken(auth: auth)
            var mergedAuth = auth
            for (key, value) in freshAuth {
                mergedAuth[key] = value
            }
            mergedAuth["lastRefreshTime"] = Date().timeIntervalSince1970 * 1000
            raw["auth"] = mergedAuth
            writeCredential(raw)
            auth = mergedAuth

            response = try await post(path: summaryPath, headers: summaryHeaders(auth), body: [:])
            guard let payload = response.json else {
                throw WorkBuddyQuotaError.requestFailed(status: response.status)
            }
            guard double(payload["code"]) == 0 else {
                throw WorkBuddyQuotaError.apiError(payload["msg"] as? String ?? "HTTP \(response.status)")
            }
            guard let data = payload["data"] as? [String: Any] else {
                throw WorkBuddyQuotaError.requestFailed(status: response.status)
            }
            return formatSummary(data, credential: raw)
        }

        guard let payload = response.json else {
            throw WorkBuddyQuotaError.requestFailed(status: response.status)
        }
        guard double(payload["code"]) == 0 else {
            throw WorkBuddyQuotaError.apiError(payload["msg"] as? String ?? "HTTP \(response.status)")
        }
        guard let data = payload["data"] as? [String: Any] else {
            throw WorkBuddyQuotaError.requestFailed(status: response.status)
        }
        return formatSummary(data, credential: raw)
    }

    /// WorkBuddy 桌面版写入的凭证文件位置。
    static var credentialURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodeBuddyExtension/Data/Public/auth/workbuddy-desktop.info")
    }

    // MARK: - 凭证读写

    private static func readCredential() throws -> (raw: [String: Any], auth: [String: Any]) {
        let url = credentialURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkBuddyQuotaError.credentialMissing
        }
        guard let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WorkBuddyQuotaError.credentialUnreadable
        }
        let auth = raw["auth"] as? [String: Any] ?? [:]
        guard let accessToken = auth["accessToken"] as? String, !accessToken.isEmpty else {
            throw WorkBuddyQuotaError.credentialMissingToken
        }
        return (raw, auth)
    }

    /// 凭证文件整体写回（刷新 token 后持久化）。原子替换，写回失败不影响本次查询。
    private static func writeCredential(_ raw: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return }
        do {
            try data.write(to: credentialURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: credentialURL.path
            )
        } catch {
            // 写回失败不影响本次查询
        }
    }

    // MARK: - 网络

    private static func summaryHeaders(_ auth: [String: Any]) -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(auth["accessToken"] as? String ?? "")",
            "Accept-Language": "zh",
        ]
        if let domain = auth["domain"] as? String, !domain.isEmpty {
            headers["X-Domain"] = domain
        }
        return headers
    }

    /// 用 refreshToken 换新的 accessToken；refreshToken 本身也有有效期（通常 70 天）。
    private static func refreshToken(auth: [String: Any]) async throws -> [String: Any] {
        guard let refreshTokenValue = auth["refreshToken"] as? String, !refreshTokenValue.isEmpty else {
            throw WorkBuddyQuotaError.credentialInvalid(status: 401)
        }

        let response = try await post(
            path: refreshPath,
            headers: [
                "Content-Type": "application/json",
                "X-Refresh-Token": refreshTokenValue,
                "X-Auth-Refresh-Source": "plugin",
            ],
            body: [:]
        )

        guard let payload = response.json,
              let fresh = payload["data"] as? [String: Any],
              let accessToken = fresh["accessToken"] as? String, !accessToken.isEmpty else {
            throw WorkBuddyQuotaError.credentialInvalid(status: response.status)
        }
        return fresh
    }

    private struct HTTPResponse {
        let status: Int
        let json: [String: Any]?
    }

    private static func post(path: String, headers: [String: String], body: [String: Any]) async throws -> HTTPResponse {
        guard let url = URL(string: endpoint + path) else {
            throw WorkBuddyQuotaError.requestFailed(status: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return HTTPResponse(status: status, json: json)
    }

    // MARK: - 快照解析

    /// 把接口原始数据整理成展示结构；与 workbuddy-quota.js formatSummary 对齐。
    static func formatSummary(_ data: [String: Any], credential raw: [String: Any]) -> Snapshot {
        let packages: [Package] = ((data["Packages"] as? [[String: Any]]) ?? []).map { item in
            let code = item["PackageCode"] as? String ?? ""
            return Package(
                code: code,
                name: packageNames[code] ?? code,
                total: rounded(item["CycleTotalCapacity"]),
                used: rounded(item["CycleUsedCapacity"]),
                remain: rounded(item["CycleRemainCapacity"]),
                unit: item["CapacityUnit"] as? String ?? "credits"
            )
        }
        .sorted(by: sortPackages)

        let total = packages.reduce(0) { $0 + $1.total }
        let used = packages.reduce(0) { $0 + $1.used }
        let remain = packages.reduce(0) { $0 + $1.remain }

        let account = raw["account"] as? [String: Any] ?? [:]
        let auth = raw["auth"] as? [String: Any] ?? [:]
        let subscriptionCode = data["SubscriptionPackageCode"] as? String ?? ""

        return Snapshot(
            packages: packages,
            total: (total * 100).rounded() / 100,
            used: (used * 100).rounded() / 100,
            remain: (remain * 100).rounded() / 100,
            isPaidUser: isTruthy(data["IsPaidUser"]),
            subscriptionName: subscriptionCode.isEmpty ? nil : (packageNames[subscriptionCode] ?? subscriptionCode),
            accountName: account["nickname"] as? String,
            accountType: account["type"] as? String,
            tokenExpiresAt: double(auth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// 分层排序：正在消耗的最上，未动的其次，已耗尽的垫底；同层按剩余多到少。
    static func sortPackages(_ lhs: Package, _ rhs: Package) -> Bool {
        let lhsTier = packageTier(lhs)
        let rhsTier = packageTier(rhs)
        if lhsTier != rhsTier {
            return lhsTier < rhsTier
        }
        return lhs.remain > rhs.remain
    }

    private static func packageTier(_ package: Package) -> Int {
        if package.remain <= 0 { return 2 }
        if package.used > 0 { return 0 }
        return 1
    }

    // MARK: - 宽松取值

    /// 容量字段可能是数字也可能是字符串（如 "9607"），统一做宽松转换。
    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private static func rounded(_ value: Any?) -> Double {
        let number = double(value) ?? 0
        return (number * 100).rounded() / 100
    }

    private static func isTruthy(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = (value as? NSNumber)?.boolValue { return number }
        if let text = (value as? String)?.lowercased() {
            return text == "true" || text == "1"
        }
        return false
    }
}

//
//  WorkBuddyGatewayService.swift
//  PasteDeck
//
//  workbuddy2api(-panel) 自托管网关客户端：
//  完整移植 /Users/wangqian/Documents/go-project/codex-quota-utools/gateway.js，
//  对接账号池、多账号积分包、用量统计（按模型/按账号）与映射模型列表。
//
//  Created on 2026-10-13.
//

import Foundation

enum WorkBuddyGatewayService {

    static let defaultBaseURL = "http://127.0.0.1:17863"
    static let defaultApiKey = "46eaa9ea701982b8b3030fbd2e1188277fbe0da4586872d48aba840f173262cb"
    private static let requestTimeout: TimeInterval = 15

    enum GatewayError: LocalizedError {
        case invalidURL
        case unauthorized
        case gatewayUnavailable(String)
        case requestFailed(status: Int)
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "网关地址格式不正确，需以 http:// 或 https:// 开头"
            case .unauthorized:
                return "网关 API Key 无效或缺失（401 Unauthorized）"
            case .gatewayUnavailable(let msg):
                return "无法连接网关：\(msg)。请确认 SSH 隧道与网关进程正在运行"
            case .requestFailed(let status):
                return "网关返回错误（HTTP \(status)）"
            case .invalidResponse:
                return "网关返回数据解析失败"
            case .apiError(let message):
                return "网关接口错误：\(message)"
            }
        }
    }

    // MARK: - 数据模型

    struct GatewayAccount: Equatable, Identifiable {
        var uid: String
        var nickname: String?
        var realm: String?
        var credits: Double
        var creditsTotal: Double?
        var creditsEarliestExpiry: String?
        var creditsEarliestRemaining: Double?
        var disabled: Bool
        var disabledReason: String?
        var cooling: Bool
        var coolRemainingSec: Int?
        var coolKind: String?
        var until: String?
        var reason: String?
        var successCount: Int
        var errTotal: Int
        var consecutiveFails: Int
        var inFlight: Int
        var lastSuccess: String?
        var breakerUntil: String?
        var degradeUntil: String?

        var id: String { uid }

        var displayName: String {
            if let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nick.isEmpty {
                return nick
            }
            return uid
        }

        var avatarInitial: String {
            String(displayName.prefix(1)).uppercased()
        }

        var successRateText: String {
            let total = successCount + errTotal
            guard total > 0 else { return "--" }
            return "\(Int(round(Double(successCount) * 100.0 / Double(total))))%"
        }

        var isRateBad: Bool {
            let total = successCount + errTotal
            return total > 0 && successCount * 2 < total
        }
    }

    struct GatewayOverview: Equatable {
        var service: String
        var version: String
        var healthy: Int
        var total: Int
        var cooling: Int
        var disabled: Int
        var stickySessions: Int
        var uptimeSec: Int
        var redisMode: String?
        var accounts: [GatewayAccount]

        var healthPercentage: Int {
            guard total > 0 else { return 0 }
            return Int(round(Double(healthy) * 100.0 / Double(total)))
        }
    }

    struct GatewayPackageItem: Equatable, Identifiable {
        var packageCode: String
        var name: String
        var size: Double
        var remain: Double
        var used: Double
        var endTime: Date?

        var id: String { packageCode + "_\(remain)" }

        var usedPercentage: Double {
            guard size > 0 else { return 0 }
            return min(100.0, max(0.0, used / size * 100.0))
        }

        var tier: Int {
            if remain <= 0 { return 2 }
            if used > 0 { return 0 }
            return 1
        }
    }

    struct GatewayPackageAccount: Equatable, Identifiable {
        var uid: String
        var nickname: String?
        var realm: String?
        var remain: Double
        var packages: [GatewayPackageItem]
        var error: String?

        var id: String { uid }

        var displayName: String {
            if let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nick.isEmpty {
                return nick
            }
            return uid
        }

        var avatarInitial: String {
            String(displayName.prefix(1)).uppercased()
        }
    }

    struct UsageTotals: Equatable {
        var requests: Int
        var errors: Int
        var totalTokens: Double
        var promptTokens: Double
        var completionTokens: Double

        var successRateText: String {
            guard requests > 0 else { return "--" }
            let success = max(0, requests - errors)
            return "\(Int(round(Double(success) * 100.0 / Double(requests))))%"
        }
    }

    struct UsageRow: Equatable, Identifiable {
        var key: String
        var requests: Int
        var totalTokens: Double
        var avgLatencyMs: Double?
        var extra: String?

        var id: String { key }

        var latencyText: String {
            guard let lat = avgLatencyMs else { return "--" }
            return "\(Int(round(lat)))ms"
        }
    }

    struct GatewayUsage: Equatable {
        var hours: Int
        var generated: String?
        var totals: UsageTotals
        var byModel: [UsageRow]
        var byAccount: [UsageRow]
    }

    struct GatewayModel: Equatable, Identifiable {
        var id: String
        var credits: String
        var contextLength: Int?
        var supportsImages: Bool
        var supportsReasoning: Bool
        var supportsToolCall: Bool

        var contextLengthText: String {
            guard let len = contextLength else { return "--" }
            if len >= 1_000_000 {
                return "\(len / 1_000_000)M"
            } else if len >= 1_000 {
                return "\(len / 1_000)K"
            }
            return "\(len)"
        }
    }

    // MARK: - 查询接口

    static func getOverview(baseURL: String? = nil, apiKey: String? = nil) async throws -> GatewayOverview {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        let json = try await request(resolvedURL, path: "/panel/api/overview", apiKey: resolvedKey)
        guard let dict = json as? [String: Any] else {
            throw GatewayError.invalidResponse
        }
        return parseOverview(dict)
    }

    static func getPackages(baseURL: String? = nil, apiKey: String? = nil) async throws -> [GatewayPackageAccount] {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        let json = try await request(resolvedURL, path: "/panel/api/packages", apiKey: resolvedKey)
        guard let dict = json as? [String: Any] else {
            throw GatewayError.invalidResponse
        }
        return parsePackages(dict)
    }

    static func getUsage(hours: Int = 72, baseURL: String? = nil, apiKey: String? = nil) async throws -> GatewayUsage {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        let json = try await request(resolvedURL, path: "/panel/api/usage?hours=\(hours)", apiKey: resolvedKey)
        guard let dict = json as? [String: Any] else {
            throw GatewayError.invalidResponse
        }
        return parseUsage(dict, hours: hours)
    }

    static func getModels(baseURL: String? = nil, apiKey: String? = nil) async throws -> [GatewayModel] {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        let json = try await request(resolvedURL, path: "/panel/api/models", apiKey: resolvedKey)
        guard let dict = json as? [String: Any] else {
            throw GatewayError.invalidResponse
        }
        return parseModels(dict)
    }

    // MARK: - 运维操作接口 (POST)

    static func accountAction(uid: String, action: String, baseURL: String? = nil, apiKey: String? = nil) async throws {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        guard let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GatewayError.invalidURL
        }
        _ = try await request(resolvedURL, path: "/panel/api/accounts/\(encodedUID)/\(action)", method: "POST", apiKey: resolvedKey)
    }

    static func bulkAction(action: String, baseURL: String? = nil, apiKey: String? = nil) async throws {
        let (resolvedURL, resolvedKey) = resolveConfig(baseURL: baseURL, apiKey: apiKey)
        _ = try await request(resolvedURL, path: "/panel/api/\(action)", method: "POST", apiKey: resolvedKey, timeout: 60)
    }

    // MARK: - 网络请求核心

    private static func request(
        _ baseURL: String,
        path: String,
        method: String = "GET",
        apiKey: String,
        timeout: TimeInterval = requestTimeout
    ) async throws -> Any {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GatewayError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = "{}".data(using: .utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && (
                nsError.code == NSURLErrorCannotConnectToHost ||
                nsError.code == NSURLErrorTimedOut ||
                nsError.code == NSURLErrorNetworkConnectionLost
            ) {
                throw GatewayError.gatewayUnavailable(error.localizedDescription)
            }
            throw GatewayError.apiError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw GatewayError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GatewayError.requestFailed(status: httpResponse.statusCode)
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - 数据解析逻辑

    static func parseOverview(_ dict: [String: Any]) -> GatewayOverview {
        let service = (dict["service"] as? String) ?? "workbuddy2api"
        let version = (dict["version"] as? String) ?? "unknown"
        let healthy = (dict["healthy"] as? Int) ?? 0
        let total = (dict["total"] as? Int) ?? 0
        let cooling = (dict["cooling"] as? Int) ?? 0
        let disabled = (dict["disabled"] as? Int) ?? 0
        let sticky = (dict["sticky_sessions"] as? Int) ?? 0
        let uptime = (dict["uptime_sec"] as? Int) ?? 0
        let redis = dict["redis_mode"] as? String

        var accountsList: [GatewayAccount] = []
        if let rawAccounts = dict["accounts"] as? [[String: Any]] {
            for a in rawAccounts {
                guard let uid = (a["uid"] as? String) ?? (a["id"] as? String) else { continue }
                let nick = a["nickname"] as? String
                let realm = a["realm"] as? String
                let credits = (a["credits"] as? Double) ?? Double((a["credits"] as? Int) ?? 0)
                let creditsTotal = (a["credits_total"] as? Double) ?? (a["credits_total"] as? Int).map(Double.init)
                let earliestExpiry = a["credits_earliest_expiry"] as? String
                let earliestRemain = (a["credits_earliest_remaining"] as? Double) ?? (a["credits_earliest_remaining"] as? Int).map(Double.init)
                let dis = (a["disabled"] as? Bool) ?? false
                let disReason = a["disabled_reason"] as? String
                let cool = (a["cooling"] as? Bool) ?? false
                let coolSec = a["cool_remaining_sec"] as? Int
                let coolKind = a["cool_kind"] as? String
                let until = a["until"] as? String
                let reason = a["reason"] as? String
                let succ = (a["success_count"] as? Int) ?? 0
                let err = (a["err_total"] as? Int) ?? 0
                let fails = (a["consecutive_fails"] as? Int) ?? 0
                let inFlight = (a["in_flight"] as? Int) ?? 0
                let lastSucc = a["last_success"] as? String
                let breaker = a["breaker_until"] as? String
                let degrade = a["degrade_until"] as? String

                accountsList.append(GatewayAccount(
                    uid: uid,
                    nickname: nick,
                    realm: realm,
                    credits: credits,
                    creditsTotal: creditsTotal,
                    creditsEarliestExpiry: earliestExpiry,
                    creditsEarliestRemaining: earliestRemain,
                    disabled: dis,
                    disabledReason: disReason,
                    cooling: cool,
                    coolRemainingSec: coolSec,
                    coolKind: coolKind,
                    until: until,
                    reason: reason,
                    successCount: succ,
                    errTotal: err,
                    consecutiveFails: fails,
                    inFlight: inFlight,
                    lastSuccess: lastSucc,
                    breakerUntil: breaker,
                    degradeUntil: degrade
                ))
            }
        }

        return GatewayOverview(
            service: service,
            version: version,
            healthy: healthy,
            total: total,
            cooling: cooling,
            disabled: disabled,
            stickySessions: sticky,
            uptimeSec: uptime,
            redisMode: redis,
            accounts: accountsList
        )
    }

    static func parsePackages(_ dict: [String: Any]) -> [GatewayPackageAccount] {
        guard let rawAccounts = dict["accounts"] as? [[String: Any]] else {
            return []
        }

        return rawAccounts.compactMap { a -> GatewayPackageAccount? in
            guard let uid = a["uid"] as? String else { return nil }
            let nick = a["nickname"] as? String
            let realm = a["realm"] as? String
            let remain = (a["remain"] as? Double) ?? Double((a["remain"] as? Int) ?? 0)
            let err = a["error"] as? String

            var pkgs: [GatewayPackageItem] = []
            if let rawPkgs = a["packages"] as? [[String: Any]] {
                for p in rawPkgs {
                    let code = (p["package_code"] as? String) ?? ""
                    let name = (p["name"] as? String) ?? WorkBuddyQuotaService.packageNames[code] ?? code
                    let size = (p["size"] as? Double) ?? Double((p["size"] as? Int) ?? 0)
                    let pRemain = (p["remain"] as? Double) ?? Double((p["remain"] as? Int) ?? 0)
                    let used = (p["used"] as? Double) ?? Double((p["used"] as? Int) ?? 0)
                    var endDate: Date?
                    if let endTs = p["end_time"] as? Double {
                        endDate = Date(timeIntervalSince1970: endTs > 1_000_000_000_000 ? endTs / 1000 : endTs)
                    }

                    pkgs.append(GatewayPackageItem(
                        packageCode: code,
                        name: name,
                        size: size,
                        remain: pRemain,
                        used: used,
                        endTime: endDate
                    ))
                }
            }

            // 智能排序：使用中 (Tier 0) -> 未动 (Tier 1) -> 已耗尽 (Tier 2)；层内按剩余降序
            let sortedPkgs = pkgs.sorted { a, b in
                if a.tier != b.tier {
                    return a.tier < b.tier
                }
                return a.remain > b.remain
            }

            return GatewayPackageAccount(
                uid: uid,
                nickname: nick,
                realm: realm,
                remain: remain,
                packages: sortedPkgs,
                error: err
            )
        }
    }

    static func parseUsage(_ dict: [String: Any], hours: Int) -> GatewayUsage {
        let gen = dict["generated"] as? String
        let rawTotals = dict["totals"] as? [String: Any] ?? [:]
        let reqs = numberToInt(rawTotals["requests"])
        let errs = numberToInt(rawTotals["errors"])
        let totalTokens = numberToDouble(rawTotals["total_tokens"])
        let promptTokens = numberToDouble(rawTotals["prompt_tokens"])
        let compTokens = numberToDouble(rawTotals["completion_tokens"])

        let totals = UsageTotals(
            requests: reqs,
            errors: errs,
            totalTokens: totalTokens,
            promptTokens: promptTokens,
            completionTokens: compTokens
        )

        let parseRows: ([[String: Any]]) -> [UsageRow] = { array in
            array.compactMap { r -> UsageRow? in
                guard let key = (r["key"] as? String) ?? (r["model"] as? String) ?? (r["name"] as? String) else { return nil }
                let rReqs = numberToInt(r["requests"])
                let rTokens = numberToDouble(r["total_tokens"])
                let rLat = (r["avg_latency_ms"] as? Double) ?? (r["avg_latency_ms"] as? Int).map(Double.init)
                let rExtra = r["extra"] as? String
                return UsageRow(key: key, requests: rReqs, totalTokens: rTokens, avgLatencyMs: rLat, extra: rExtra)
            }.sorted { $0.requests > $1.requests }
        }

        let byModel = parseRows((dict["by_model"] as? [[String: Any]]) ?? [])
        let byAccount = parseRows((dict["by_account"] as? [[String: Any]]) ?? [])

        return GatewayUsage(
            hours: hours,
            generated: gen,
            totals: totals,
            byModel: byModel,
            byAccount: byAccount
        )
    }

    private static func numberToInt(_ val: Any?) -> Int {
        if let i = val as? Int { return i }
        if let d = val as? Double { return Int(d) }
        if let n = val as? NSNumber { return n.intValue }
        if let s = val as? String, let parsed = Int(s) { return parsed }
        return 0
    }

    private static func numberToDouble(_ val: Any?) -> Double {
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        if let n = val as? NSNumber { return n.doubleValue }
        if let s = val as? String, let parsed = Double(s) { return parsed }
        return 0.0
    }

    static func parseModels(_ dict: [String: Any]) -> [GatewayModel] {
        guard let rawModels = dict["models"] as? [[String: Any]] else {
            return []
        }

        return rawModels.compactMap { m -> GatewayModel? in
            guard let id = m["id"] as? String else { return nil }
            let credits = (m["credits"] as? String) ?? "x1.0"
            let contextLen = m["context_length"] as? Int
            let images = (m["supports_images"] as? Bool) ?? false
            let reasoning = (m["supports_reasoning"] as? Bool) ?? false
            let tool = (m["supports_tool_call"] as? Bool) ?? false

            return GatewayModel(
                id: id,
                credits: credits,
                contextLength: contextLen,
                supportsImages: images,
                supportsReasoning: reasoning,
                supportsToolCall: tool
            )
        }
    }

    // MARK: - 格式化辅助函数 (与 codex-quota-utools 丝毫不差)

    /// 账号健康状态判定：已禁用 (off)、冷却 (warn)、熔断 (bad)、降级 (warn)、正常 (ok)
    static func accountStatus(_ a: GatewayAccount) -> (text: String, pill: String) {
        if a.disabled {
            return ("已禁用", "off")
        }
        if a.cooling {
            var text = "冷却"
            if let sec = a.coolRemainingSec, sec > 0 {
                text += " " + fmtCountdown(sec)
            }
            if a.coolKind == "hard_credit" {
                text += " · 积分耗尽"
            }
            return (text, "warn")
        }
        if let breaker = a.breakerUntil, isFuture(breaker) {
            return ("熔断", "bad")
        }
        if let degrade = a.degradeUntil, isFuture(degrade) {
            return ("降级", "warn")
        }
        return ("正常", "ok")
    }

    static func fmtNumber(_ value: Double) -> String {
        let rounded = round(value * 100.0) / 100.0
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }

    static func fmtCredits(_ n: Double) -> String {
        fmtNumber(n)
    }

    static func fmtBig(_ n: Double) -> String {
        let absVal = abs(n)
        if absVal < 10_000 {
            return String(format: "%.0f", n)
        } else if absVal < 1_000_000 {
            return String(format: "%.1fK", n / 1_000)
        } else if absVal < 1_000_000_000 {
            return String(format: "%.1fM", n / 1_000_000)
        } else {
            return String(format: "%.2fB", n / 1_000_000_000)
        }
    }

    static func fmtUptime(_ sec: Int) -> String {
        let days = sec / 86400
        let hours = (sec % 86400) / 3600
        if days > 0 {
            return "\(days) 天 \(hours) 小时"
        }
        let mins = (sec % 3600) / 60
        return "\(hours) 小时 \(mins) 分"
    }

    static func fmtCountdown(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }

    static func fmtRelTime(_ ts: String?) -> String {
        guard let ts, let date = parseISO8601(ts) else { return "--" }
        let diff = Date().timeIntervalSince(date)
        if diff < 0 {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            return df.string(from: date)
        }
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        return "\(Int(diff / 86400)) 天前"
    }

    private static func isFuture(_ iso: String) -> Bool {
        guard let date = parseISO8601(iso) else { return false }
        return date.timeIntervalSinceNow > 0
    }

    static func resolveConfig(baseURL: String?, apiKey: String?) -> (baseURL: String, apiKey: String) {
        let envURL = ProcessInfo.processInfo.environment["WORKBUDDY_GATEWAY_URL"]
        let envKey = ProcessInfo.processInfo.environment["WORKBUDDY_GATEWAY_API_KEY"]

        let finalURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? baseURL! : (envURL ?? defaultBaseURL)
        let finalKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? apiKey! : (envKey ?? defaultApiKey)

        let cleanedURL = finalURL.hasSuffix("/") ? String(finalURL.dropLast()) : finalURL
        return (cleanedURL, finalKey)
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        isoFormatterWithFractional.date(from: string) ?? isoFormatterStandard.date(from: string)
    }
}

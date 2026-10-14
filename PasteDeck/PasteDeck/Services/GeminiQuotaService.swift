//
//  GeminiQuotaService.swift
//  PasteDeck
//
//  Gemini 速率限制与模型额度查询：直连本地 Antigravity-Manager 代理管理接口，
//  读取 Gemini 各模型及限流窗口（5 小时 / 每周）的剩余比例与重置时间。
//
//  Created on 2026-10-13.
//

import Foundation

enum GeminiQuotaService {

    static let sessionWindowLabel = "5 小时额度"
    static let weeklyWindowLabel = "每周额度"

    static let defaultEndpoint = "http://127.0.0.1:8045"
    static let defaultToken = "1cfd8d9aa91431c4"
    private static let requestTimeout: TimeInterval = 15

    enum GeminiQuotaError: LocalizedError {
        case serviceUnavailable
        case unauthorized
        case requestFailed(status: Int)
        case invalidResponse
        case apiError(String)
        case noAccountData

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable:
                return "未连接到 Gemini 服务（端口 8045 未监听或代理未启动）"
            case .unauthorized:
                return "Gemini 管理凭据错误（401 Unauthorized），请在设置中检查管理密码"
            case .requestFailed(let status):
                return "Gemini 接口无响应（HTTP \(status)），请检查服务状态"
            case .invalidResponse:
                return "Gemini 接口返回数据解析失败"
            case .apiError(let message):
                return "Gemini 接口返回错误：\(message)"
            case .noAccountData:
                return "未检测到 Gemini 账号数据"
            }
        }
    }

    // MARK: - 数据模型

    /// 额度时间窗口（5 小时 / 每周）。
    struct Window: Equatable {
        var label: String
        var isAvailable: Bool
        var usedPercent: Double
        var remainingPercent: Double
        var resetsAt: Date?
        var isLimitReached: Bool

        var displayRemainingPercent: Double {
            isLimitReached ? 0 : remainingPercent
        }
    }

    /// 单个具体模型额度明细。
    struct ModelQuota: Equatable, Identifiable {
        var name: String
        var percentage: Double
        var resetTime: Date?

        var id: String { name }
    }

    /// 账号额度完整快照。
    struct Snapshot: Equatable {
        var accountId: String?
        var accountEmail: String?
        var accountName: String?
        var subscriptionTier: String?
        var isForbidden: Bool
        /// Gemini 5 小时窗口
        var session: Window
        /// Gemini 每周窗口
        var weekly: Window
        /// 各模型额度百分比明细
        var models: [ModelQuota]
        /// 第三方模型窗口（Claude / GPT 3p 组，如存在）
        var thirdPartySession: Window?
        var thirdPartyWeekly: Window?
        var lastUpdated: Date?
    }

    // MARK: - Token 统计数据模型

    enum TokenStatsPeriod: String, CaseIterable, Identifiable {
        case hourly = "hour"
        case daily = "day"
        case weekly = "week"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .hourly: return "小时"
            case .daily: return "日"
            case .weekly: return "周"
            }
        }
        var queryHours: Int {
            switch self {
            case .hourly: return 24
            case .daily: return 168
            case .weekly: return 720
            }
        }
    }

    struct TokenStatsSummary: Equatable {
        var totalTokens: Double
        var totalInputTokens: Double
        var totalOutputTokens: Double
        var totalCachedTokens: Double
        var totalRequests: Int
        var uniqueAccounts: Int
        var modelsCount: Int
    }

    struct ModelTokenStat: Equatable, Identifiable {
        var model: String
        var requestCount: Int
        var inputTokens: Double
        var outputTokens: Double
        var cachedTokens: Double
        var totalTokens: Double
        var percentage: Double

        var id: String { model }
    }

    struct AccountTokenStat: Equatable, Identifiable {
        var accountEmail: String
        var requestCount: Int
        var inputTokens: Double
        var outputTokens: Double
        var cachedTokens: Double
        var totalTokens: Double
        var percentage: Double

        var id: String { accountEmail }
    }

    struct TokenTrendPoint: Equatable, Identifiable {
        var period: String
        var totalTokens: Double
        var inputTokens: Double
        var outputTokens: Double
        var cachedTokens: Double
        var requestCount: Int

        var id: String { period }
    }

    struct TokenStatsSnapshot: Equatable {
        var summary: TokenStatsSummary
        var models: [ModelTokenStat]
        var accounts: [AccountTokenStat]
        var trends: [TokenTrendPoint]
        var period: TokenStatsPeriod
        var lastUpdated: Date
    }

    // MARK: - 查询入口

    /// 查询 Gemini 配额信息。
    static func query(
        endpoint: String? = nil,
        token: String? = nil
    ) async throws -> Snapshot {
        let targetEndpoint = resolvedEndpoint(endpoint)
        let targetToken = resolvedToken(token)

        guard let url = URL(string: "\(targetEndpoint)/api/accounts") else {
            throw GeminiQuotaError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(targetToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && (
                nsError.code == NSURLErrorCannotConnectToHost ||
                nsError.code == NSURLErrorTimedOut ||
                nsError.code == NSURLErrorNetworkConnectionLost
            ) {
                throw GeminiQuotaError.serviceUnavailable
            }
            throw GeminiQuotaError.apiError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiQuotaError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw GeminiQuotaError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GeminiQuotaError.requestFailed(status: httpResponse.statusCode)
        }

        return try parseAccountsData(data)
    }

    /// 主动触发后台刷新配额。
    static func triggerRefresh(
        endpoint: String? = nil,
        token: String? = nil
    ) async throws {
        let targetEndpoint = resolvedEndpoint(endpoint)
        let targetToken = resolvedToken(token)

        guard let url = URL(string: "\(targetEndpoint)/api/accounts/refresh") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(targetToken)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: request)
    }

    /// 查询 Token 消费统计。
    static func queryTokenStats(
        endpoint: String? = nil,
        token: String? = nil,
        period: TokenStatsPeriod = .daily
    ) async throws -> TokenStatsSnapshot {
        let targetEndpoint = resolvedEndpoint(endpoint)
        let targetToken = resolvedToken(token)

        async let summaryData = requestJson(endpoint: targetEndpoint, path: "/api/stats/token/summary?hours=\(period.queryHours)", token: targetToken)
        async let modelsData = requestJson(endpoint: targetEndpoint, path: "/api/stats/token/by-model?hours=\(period.queryHours)", token: targetToken)
        async let accountsData = requestJson(endpoint: targetEndpoint, path: "/api/stats/token/by-account?hours=\(period.queryHours)", token: targetToken)

        let trendPath: String
        switch period {
        case .hourly: trendPath = "/api/stats/token/hourly?hours=24"
        case .daily: trendPath = "/api/stats/token/daily?days=7"
        case .weekly: trendPath = "/api/stats/token/weekly?weeks=4"
        }
        async let trendData = requestJson(endpoint: targetEndpoint, path: trendPath, token: targetToken)

        let (rawSummary, rawModels, rawAccounts, rawTrends) = try await (summaryData, modelsData, accountsData, trendData)

        let summaryDict = rawSummary as? [String: Any] ?? [:]
        let modelsArray = rawModels as? [[String: Any]] ?? []
        let accountsArray = rawAccounts as? [[String: Any]] ?? []
        let trendsArray = rawTrends as? [[String: Any]] ?? []

        let summary = parseTokenStatsSummary(json: summaryDict, modelsCount: modelsArray.count)
        let models = parseModelTokenStats(jsonArray: modelsArray, totalTokens: summary.totalTokens)
        let accounts = parseAccountTokenStats(jsonArray: accountsArray, totalTokens: summary.totalTokens)
        let trends = parseTokenTrendPoints(jsonArray: trendsArray)

        return TokenStatsSnapshot(
            summary: summary,
            models: models,
            accounts: accounts,
            trends: trends,
            period: period,
            lastUpdated: Date()
        )
    }

    private static func requestJson(endpoint: String, path: String, token: String) async throws -> Any {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            throw GeminiQuotaError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiQuotaError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw GeminiQuotaError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GeminiQuotaError.requestFailed(status: httpResponse.statusCode)
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - 解析逻辑

    static func parseAccountsData(_ data: Data) throws -> Snapshot {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiQuotaError.invalidResponse
        }
        return try parseSnapshot(json: jsonObject)
    }

    static func parseSnapshot(json: [String: Any]) throws -> Snapshot {
        guard let accounts = json["accounts"] as? [[String: Any]], !accounts.isEmpty else {
            throw GeminiQuotaError.noAccountData
        }

        // 优先使用当前活跃账号，若未指定则使用第一个账号
        let currentAccountId = json["current_account_id"] as? String
        let account = accounts.first { ($0["id"] as? String) == currentAccountId } ?? accounts[0]

        let accountId = account["id"] as? String
        let email = account["email"] as? String
        let name = account["name"] as? String
        let quota = account["quota"] as? [String: Any] ?? [:]

        let subscriptionTier = quota["subscription_tier"] as? String
        let isForbidden = (quota["is_forbidden"] as? Bool) ?? false

        var lastUpdated: Date?
        if let timestamp = quota["last_updated"] as? Double {
            lastUpdated = Date(timeIntervalSince1970: timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp)
        }

        // 解析各个细分模型
        var modelQuotas: [ModelQuota] = []
        if let modelsArray = quota["models"] as? [[String: Any]] {
            for item in modelsArray {
                if let modelName = item["name"] as? String {
                    let percentage = (item["percentage"] as? Double) ?? Double((item["percentage"] as? Int) ?? 0)
                    let resetString = item["reset_time"] as? String
                    let resetDate = resetString.flatMap { parseISO8601($0) }
                    modelQuotas.append(ModelQuota(name: modelName, percentage: percentage, resetTime: resetDate))
                }
            }
        }

        // 解析配额组 (quota_groups)
        var sessionWindow: Window?
        var weeklyWindow: Window?
        var thirdPartySession: Window?
        var thirdPartyWeekly: Window?

        if let groups = quota["quota_groups"] as? [[String: Any]] {
            for group in groups {
                let displayName = (group["display_name"] as? String) ?? ""
                let buckets = group["buckets"] as? [[String: Any]] ?? []

                let isGeminiGroup = displayName.localizedCaseInsensitiveContains("gemini") || displayName.isEmpty
                let isThirdPartyGroup = displayName.localizedCaseInsensitiveContains("claude") ||
                    displayName.localizedCaseInsensitiveContains("gpt") ||
                    displayName.localizedCaseInsensitiveContains("3p")

                for bucket in buckets {
                    let bucketId = (bucket["bucket_id"] as? String) ?? ""
                    let windowType = (bucket["window"] as? String) ?? ""
                    let remainingFraction = (bucket["remaining_fraction"] as? Double) ?? 0.0
                    let remainingPercent = min(100.0, max(0.0, remainingFraction * 100.0))
                    let usedPercent = max(0.0, 100.0 - remainingPercent)
                    let resetDate = (bucket["reset_time"] as? String).flatMap { parseISO8601($0) }
                    let isLimitReached = remainingPercent <= 0.0

                    let is5h = windowType == "5h" || bucketId.contains("5h")
                    let isWeekly = windowType == "weekly" || bucketId.contains("weekly")

                    if isGeminiGroup {
                        if is5h && sessionWindow == nil {
                            sessionWindow = Window(
                                label: sessionWindowLabel,
                                isAvailable: true,
                                usedPercent: usedPercent,
                                remainingPercent: remainingPercent,
                                resetsAt: resetDate,
                                isLimitReached: isLimitReached
                            )
                        } else if isWeekly && weeklyWindow == nil {
                            weeklyWindow = Window(
                                label: weeklyWindowLabel,
                                isAvailable: true,
                                usedPercent: usedPercent,
                                remainingPercent: remainingPercent,
                                resetsAt: resetDate,
                                isLimitReached: isLimitReached
                            )
                        }
                    } else if isThirdPartyGroup {
                        if is5h && thirdPartySession == nil {
                            thirdPartySession = Window(
                                label: "第三方 5 小时",
                                isAvailable: true,
                                usedPercent: usedPercent,
                                remainingPercent: remainingPercent,
                                resetsAt: resetDate,
                                isLimitReached: isLimitReached
                            )
                        } else if isWeekly && thirdPartyWeekly == nil {
                            thirdPartyWeekly = Window(
                                label: "第三方 每周",
                                isAvailable: true,
                                usedPercent: usedPercent,
                                remainingPercent: remainingPercent,
                                resetsAt: resetDate,
                                isLimitReached: isLimitReached
                            )
                        }
                    }
                }
            }
        }

        // 若 quota_groups 缺省但 models 存在，降级从模型列表推导
        if sessionWindow == nil, let primaryModel = modelQuotas.first {
            let remaining = primaryModel.percentage
            let used = max(0.0, 100.0 - remaining)
            sessionWindow = Window(
                label: sessionWindowLabel,
                isAvailable: true,
                usedPercent: used,
                remainingPercent: remaining,
                resetsAt: primaryModel.resetTime,
                isLimitReached: remaining <= 0.0
            )
        }

        let fallbackSession = sessionWindow ?? Window(
            label: sessionWindowLabel,
            isAvailable: false,
            usedPercent: 0,
            remainingPercent: 0,
            resetsAt: nil,
            isLimitReached: false
        )

        let fallbackWeekly = weeklyWindow ?? Window(
            label: weeklyWindowLabel,
            isAvailable: false,
            usedPercent: 0,
            remainingPercent: 0,
            resetsAt: nil,
            isLimitReached: false
        )

        return Snapshot(
            accountId: accountId,
            accountEmail: email,
            accountName: name,
            subscriptionTier: subscriptionTier,
            isForbidden: isForbidden,
            session: fallbackSession,
            weekly: fallbackWeekly,
            models: modelQuotas,
            thirdPartySession: thirdPartySession,
            thirdPartyWeekly: thirdPartyWeekly,
            lastUpdated: lastUpdated
        )
    }

    static func parseTokenStatsSummary(json: [String: Any], modelsCount: Int) -> TokenStatsSummary {
        let total = (json["total_tokens"] as? Double) ?? Double((json["total_tokens"] as? Int) ?? 0)
        let input = (json["total_input_tokens"] as? Double) ?? Double((json["total_input_tokens"] as? Int) ?? 0)
        let output = (json["total_output_tokens"] as? Double) ?? Double((json["total_output_tokens"] as? Int) ?? 0)
        let cached = (json["total_cached_tokens"] as? Double) ?? Double((json["total_cached_tokens"] as? Int) ?? 0)
        let reqs = (json["total_requests"] as? Int) ?? Int((json["total_requests"] as? Double) ?? 0)
        let accts = (json["unique_accounts"] as? Int) ?? Int((json["unique_accounts"] as? Double) ?? 0)

        return TokenStatsSummary(
            totalTokens: total,
            totalInputTokens: input,
            totalOutputTokens: output,
            totalCachedTokens: cached,
            totalRequests: reqs,
            uniqueAccounts: accts,
            modelsCount: modelsCount
        )
    }

    static func parseModelTokenStats(jsonArray: [[String: Any]], totalTokens: Double) -> [ModelTokenStat] {
        return jsonArray.compactMap { dict -> ModelTokenStat? in
            guard let model = dict["model"] as? String else { return nil }
            let reqs = (dict["request_count"] as? Int) ?? Int((dict["request_count"] as? Double) ?? 0)
            let input = (dict["total_input_tokens"] as? Double) ?? Double((dict["total_input_tokens"] as? Int) ?? 0)
            let output = (dict["total_output_tokens"] as? Double) ?? Double((dict["total_output_tokens"] as? Int) ?? 0)
            let cached = (dict["total_cached_tokens"] as? Double) ?? Double((dict["total_cached_tokens"] as? Int) ?? 0)
            let total = (dict["total_tokens"] as? Double) ?? Double((dict["total_tokens"] as? Int) ?? 0)
            let pct = totalTokens > 0 ? (total / totalTokens) * 100.0 : 0.0

            return ModelTokenStat(
                model: model,
                requestCount: reqs,
                inputTokens: input,
                outputTokens: output,
                cachedTokens: cached,
                totalTokens: total,
                percentage: pct
            )
        }
    }

    static func parseAccountTokenStats(jsonArray: [[String: Any]], totalTokens: Double) -> [AccountTokenStat] {
        return jsonArray.compactMap { dict -> AccountTokenStat? in
            guard let email = (dict["account_email"] as? String) ?? (dict["email"] as? String) else { return nil }
            let reqs = (dict["request_count"] as? Int) ?? Int((dict["request_count"] as? Double) ?? 0)
            let input = (dict["total_input_tokens"] as? Double) ?? Double((dict["total_input_tokens"] as? Int) ?? 0)
            let output = (dict["total_output_tokens"] as? Double) ?? Double((dict["total_output_tokens"] as? Int) ?? 0)
            let cached = (dict["total_cached_tokens"] as? Double) ?? Double((dict["total_cached_tokens"] as? Int) ?? 0)
            let total = (dict["total_tokens"] as? Double) ?? Double((dict["total_tokens"] as? Int) ?? 0)
            let pct = totalTokens > 0 ? (total / totalTokens) * 100.0 : 0.0

            return AccountTokenStat(
                accountEmail: email,
                requestCount: reqs,
                inputTokens: input,
                outputTokens: output,
                cachedTokens: cached,
                totalTokens: total,
                percentage: pct
            )
        }
    }

    static func parseTokenTrendPoints(jsonArray: [[String: Any]]) -> [TokenTrendPoint] {
        return jsonArray.compactMap { dict -> TokenTrendPoint? in
            guard let period = dict["period"] as? String else { return nil }
            let input = (dict["total_input_tokens"] as? Double) ?? Double((dict["total_input_tokens"] as? Int) ?? 0)
            let output = (dict["total_output_tokens"] as? Double) ?? Double((dict["total_output_tokens"] as? Int) ?? 0)
            let cached = (dict["total_cached_tokens"] as? Double) ?? Double((dict["total_cached_tokens"] as? Int) ?? 0)
            let total = (dict["total_tokens"] as? Double) ?? Double((dict["total_tokens"] as? Int) ?? 0)
            let reqs = (dict["request_count"] as? Int) ?? Int((dict["request_count"] as? Double) ?? 0)

            return TokenTrendPoint(
                period: period,
                totalTokens: total,
                inputTokens: input,
                outputTokens: output,
                cachedTokens: cached,
                requestCount: reqs
            )
        }
    }

    // MARK: - 工具函数

    static func resolvedEndpoint(_ custom: String?) -> String {
        if let custom = custom?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom.hasSuffix("/") ? String(custom.dropLast()) : custom
        }
        if let env = ProcessInfo.processInfo.environment["GEMINI_QUOTA_ENDPOINT"], !env.isEmpty {
            return env.hasSuffix("/") ? String(env.dropLast()) : env
        }
        return defaultEndpoint
    }

    static func resolvedToken(_ custom: String?) -> String {
        if let custom = custom?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        if let env = ProcessInfo.processInfo.environment["GEMINI_QUOTA_TOKEN"], !env.isEmpty {
            return env
        }
        if let env = ProcessInfo.processInfo.environment["ANTIGRAVITY_WEB_PASSWORD"], !env.isEmpty {
            return env
        }
        return defaultToken
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

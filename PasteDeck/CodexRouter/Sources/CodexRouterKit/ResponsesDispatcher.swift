//
//  ResponsesDispatcher.swift
//  PasteDeck
//
//  /responses 分发核心。路由规则（确定且可测试）：
//  1. model 含 "/"（provider 前缀）→ 查路由表；命中 → 用端点凭据转发第三方；
//     未命中 → 本地 400（unrouted_model），绝不发往官方。
//  2. model 无 "/" → 官方原生 GPT：原样转发（过滤头白名单），凭据由调用方
//     自带（requires_openai_auth），previous_response_id 剥离（状态less 全量会话）。
//  3. 任何第三方请求绝不携带官方 OAuth 凭据；任何原生请求绝不改写请求体
//     （Codex 发来的即合规请求，字节级透传是硬承诺）。
//

import Foundation

/// 请求拒绝原因。
enum DispatchRejectError: LocalizedError {
    case unauthorized
    case unroutedModel(String, endpointRegistered: Bool, endpointEnabled: Bool)
    case invalidBody(String)
    case oversizedBody

    var errorDescription: String {
        switch self {
        case .unauthorized:
            return "本地路由端点需要配置的调用方凭据。"
        case .unroutedModel(let slug, let registered, let enabled):
            var sentences = [
                "The model \"\(slug)\" has no route in this running router, so it was refused locally instead of being sent to ChatGPT."
            ]
            if !slug.contains("/") {
                sentences.append("The slug does not start with a provider id.")
            } else if !registered {
                let prefix = String(slug.prefix(while: { $0 != "/" }))
                sentences.append("No enabled provider named \"\(prefix)\" is registered with this router.")
            } else if !enabled {
                sentences.append("Provider is registered but disabled or lacks a stored credential.")
            } else {
                sentences.append("Provider is registered and enabled, but the router loaded no model with this slug.")
            }
            sentences.append("A model added in PasteDeck after the router started becomes routable when the daemon reloads endpoints (automatic on next request).")
            return sentences.joined(separator: " ")
        case .invalidBody(let detail):
            return "请求体无法解析：\(detail)"
        case .oversizedBody:
            return "请求体超出本地路由的大小上限。"
        }
    }
}

/// 原生转发的请求头白名单（对齐 FORWARD_HEADERS）。
let nativeForwardHeaders: Set<String> = [
    "authorization", "chatgpt-account-id", "openai-beta", "originator",
    "session_id", "session-id", "thread-id", "traceparent", "tracestate",
    "x-client-request-id", "x-codex-beta-features", "x-codex-installation-id",
    "x-codex-parent-thread-id", "x-codex-turn-metadata", "x-codex-turn-state",
    "x-codex-window-id", "x-oai-attestation",
    "x-openai-internal-codex-responses-lite", "x-openai-subagent",
    "x-responsesapi-include-timing-metrics",
]

/// 分发结果：状态、回传头、内容流。
struct DispatchResult {
    let status: Int
    let headers: [String: String]
    /// 原始内容流（SSE 字节或完整 JSON）。
    let stream: AsyncThrowingStream<Data, Error>
}

/// 分发请求（HTTP 与 WS 边缘共用）。
struct DispatchRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

/// 分发器。
final class ResponsesDispatcher {
    let routeTable: RouteTable
    let upstream: UpstreamClient
    let authSession: CodexAuthSession
    let callerSecret: String
    let nativeBaseURL: String
    /// 最近一次错误（诊断用，不含敏感内容）。
    private(set) var lastError: String?
    private let lock = NSLock()

    init(
        routeTable: RouteTable,
        upstream: UpstreamClient,
        authSession: CodexAuthSession,
        callerSecret: String,
        nativeBaseURL: String = CodexRouterConstants.nativeBaseURL
    ) {
        self.routeTable = routeTable
        self.upstream = upstream
        self.authSession = authSession
        self.callerSecret = callerSecret
        self.nativeBaseURL = nativeBaseURL
    }

    func recordLastError(_ message: String) {
        lock.withLock { lastError = message }
    }

    func currentLastError() -> String? {
        lock.withLock { lastError }
    }

    // MARK: - 鉴权

    /// Bearer = 本机 caller-secret，或与本地 Codex 登录会话匹配。
    func authenticate(bearerToken token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        if constantTimeEquals(token, callerSecret) { return true }
        return authSession.bearerMatchesLocalSession(token)
    }

    private func bearerToken(of headers: [String: String]) -> String? {
        guard let authorization = headers["authorization"] else { return nil }
        let trimmed = authorization.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bearer") else { return nil }
        let rest = trimmed.dropFirst("bearer".count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let token = rest.trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    // MARK: - 分发入口

    func dispatch(_ request: DispatchRequest) async -> DispatchResult {
        guard authenticate(bearerToken: bearerToken(of: request.headers)) else {
            recordLastError("401 调用方凭据缺失或不匹配（\(request.path)）")
            return Self.errorResult(status: 401, type: "authentication_error", message: DispatchRejectError.unauthorized.errorDescription)
        }
        let isCompactV1 = request.path.hasSuffix("/responses/compact")
        let payloadData: Data
        let contentEncoding = (request.headers["content-encoding"] ?? "").lowercased()
        if contentEncoding.contains("zstd") {
            do {
                payloadData = try ZstdSupport.decompress(request.body)
            } catch {
                recordLastError("请求体 zstd 解压失败（\(request.path)）")
                return Self.errorResult(status: 400, type: "invalid_request_error", message: "请求体 zstd 解压失败。")
            }
        } else {
            payloadData = request.body
        }
        guard payloadData.count <= ZstdSupport.maxDecodedBytes else {
            return Self.errorResult(status: 413, type: "request_too_large", message: DispatchRejectError.oversizedBody.errorDescription)
        }

        // 解析 model 字段（流式解析以避免整棵 JSON 树的开销不现实——直接反序列化）。
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            // 非 JSON 请求体：原生路径也可能收到（探测）。统一拒绝。
            recordLastError("请求体不是 JSON 对象（\(request.path)）")
            return Self.errorResult(status: 400, type: "invalid_request_error", message: DispatchRejectError.invalidBody("不是 JSON 对象").errorDescription)
        }
        let requestedModel = payload["model"] as? String ?? ""

        // 路由规则 1：provider 前缀 slug。
        if let prefix = SlugBuilder.endpointPrefix(of: requestedModel) {
            guard let route = routeTable.route(for: requestedModel) else {
                let registered = routeTable.endpointExists(prefix)
                recordLastError("400 未路由模型 \(requestedModel)")
                return Self.errorResult(
                    status: 400,
                    type: "invalid_request_error",
                    code: "unrouted_model",
                    param: "model",
                    message: DispatchRejectError.unroutedModel(
                        requestedModel, endpointRegistered: registered, endpointEnabled: registered
                    ).errorDescription
                )
            }
            return await forwardExternal(route: route, payload: payload, request: request, compactV1: isCompactV1)
        }

        // 路由规则 2：官方原生 GPT 透传。无需要剥离的字段时保留原始请求字节。
        return await forwardNative(
            payload: payload, originalBody: payloadData,
            request: request, compactV1: isCompactV1)
    }

    // MARK: - 第三方转发

    private func forwardExternal(
        route: ExternalRoute, payload: [String: Any], request: DispatchRequest, compactV1: Bool
    ) async -> DispatchResult {
        var body = payload
        body["model"] = route.upstreamModel
        // 未声明服务层级的路由不接受 service_tier。
        if body["service_tier"] != nil { body.removeValue(forKey: "service_tier") }
        // agent_message 是 Codex 内部协作项，第三方端点不认识：还原为用户消息。
        if var input = body["input"] as? [[String: Any]] {
            input = input.map { item in
                guard (item["type"] as? String) == "agent_message",
                      let content = item["content"] else { return item }
                var converted = item
                converted["type"] = "message"
                converted["role"] = "user"
                converted["content"] = content
                return converted
            }
            body["input"] = input
        }

        guard JSONSerialization.isValidJSONObject(body),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            recordLastError("第三方请求体序列化失败 \(route.slug)")
            return Self.errorResult(status: 500, type: "local_router_error", message: "请求体序列化失败。")
        }

        var headers: [String: String] = [
            "content-type": "application/json",
            "authorization": "Bearer \(route.apiKey)",
            "accept": "text/event-stream",
        ]
        // 端点自定义附加头留给端点配置的未来扩展；这里保留会话/追踪类透传头。
        for name in ["session_id", "session-id", "thread-id", "traceparent", "tracestate", "x-client-request-id", "originator", "user-agent", "version", "conversation_id"] {
            if let value = request.headers[name] { headers[name] = value }
        }

        let target = Self.endpointResponsesURL(baseURL: route.baseURL, path: request.path)
        return await relay(headers: headers, body: bodyData, target: target, label: route.slug)
    }

    /// 端点 Base URL + 请求路径（/responses 或 /responses/compact）。
    /// baseURL 允许带或不带 /v1 后缀；路径保持调用方的 compact 语义。
    static func endpointResponsesURL(baseURL: String, path: String) -> String {
        var base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if base.hasSuffix("/") { base.removeLast() }
        let suffix = path.hasSuffix("/responses/compact") ? "/responses/compact" : "/responses"
        return base + suffix
    }

    // MARK: - 原生转发

    private func forwardNative(
        payload: [String: Any], originalBody: Data?,
        request: DispatchRequest, compactV1: Bool
    ) async -> DispatchResult {
        // 原生轮次按无状态全量会话转发：剥离 previous_response_id（compact V1 例外）。
        // 无该字段时字节级透传原始请求体（JSON 反序列化仅用于路由判定）。
        let bodyData: Data
        if !compactV1, payload["previous_response_id"] == nil, let originalBody {
            bodyData = originalBody
        } else {
            var native = payload
            if !compactV1 { native.removeValue(forKey: "previous_response_id") }
            guard JSONSerialization.isValidJSONObject(native),
                  let serialized = try? JSONSerialization.data(withJSONObject: native) else {
                recordLastError("原生请求体序列化失败")
                return Self.errorResult(status: 400, type: "invalid_request_error", message: "请求体不是合法 JSON。")
            }
            bodyData = serialized
        }
        let (maybeCompressed, compressed) = ZstdSupport.compressNativeBodyIfBeneficial(bodyData)
        _ = compressed

        var headers: [String: String] = [
            "content-type": "application/json",
            "accept": "text/event-stream",
            "accept-encoding": "identity",
        ]
        if compressed {
            headers["content-encoding"] = "zstd"
        }
        for name in nativeForwardHeaders {
            if let value = request.headers[name] {
                headers[name] = value
            }
        }
        // WS 令牌不出现在 HTTP 逐跳：剥离 Responses WS 协议标记。
        if let beta = headers["openai-beta"] {
            let filtered = beta.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0 != CodexRouterConstants.responsesWebSocketBeta }
                .joined(separator: ", ")
            if filtered.isEmpty { headers.removeValue(forKey: "openai-beta") } else { headers["openai-beta"] = filtered }
        }

        // 路径透传：/v1/responses → NATIVE_BASE/responses。
        let withoutV1 = request.path.hasPrefix("/v1/") ? String(request.path.dropFirst(3)) : request.path
        let target = nativeBaseURL + withoutV1
        return await relay(headers: headers, body: maybeCompressed, target: target, label: "native")
    }

    // MARK: - 中继

    private func relay(
        headers: [String: String], body: Data, target: String, label: String
    ) async -> DispatchResult {
        do {
            let upstreamResponse = try await upstream.post(url: target, headers: headers, body: body)
            var relayedHeaders: [String: String] = [:]
            for (name, value) in upstreamResponse.headers where !hopByHopResponseHeaders.contains(name) {
                relayedHeaders[name] = value
            }
            if relayedHeaders["content-type"] == nil {
                relayedHeaders["content-type"] = "text/event-stream; charset=utf-8"
            }
            let status = upstreamResponse.status
            if status >= 400 {
                recordLastError("上游 \(status)（\(label)）")
            }
            // 字节级透传：SSE 的空行事件边界必须原样保留（.lines 会吞掉空行，
            // 导致 Codex 无法分帧）。按行触发即时 flush，兼顾延迟与块大小。
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        var pending = [UInt8]()
                        pending.reserveCapacity(8192)
                        for try await byte in upstreamResponse.bytes {
                            pending.append(byte)
                            if byte == 0x0A || pending.count >= 16384 {
                                continuation.yield(Data(pending))
                                pending.removeAll(keepingCapacity: true)
                            }
                        }
                        if !pending.isEmpty {
                            continuation.yield(Data(pending))
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
            return DispatchResult(status: status, headers: relayedHeaders, stream: stream)
        } catch {
            recordLastError("上游连接失败（\(label)）：\(error.localizedDescription)")
            return Self.errorResult(
                status: 502,
                type: "local_router_error",
                code: "upstream_connect_failed",
                message: "本地路由无法连接上游：\(error.localizedDescription)"
            )
        }
    }

    // MARK: - 工具

    static func errorResult(
        status: Int, type: String, code: String? = nil, param: String? = nil, message: String
    ) -> DispatchResult {
        var errorObject: [String: Any] = ["type": type, "message": message]
        if let code { errorObject["code"] = code }
        if let param { errorObject["param"] = param }
        let body: Data
        if let data = try? JSONSerialization.data(withJSONObject: ["error": errorObject]) {
            body = data
        } else {
            body = Data("{\"error\":{\"type\":\"\(type)\",\"message\":\"\(message)\"}}".utf8)
        }
        return DispatchResult(
            status: status,
            headers: ["content-type": "application/json"],
            stream: AsyncThrowingStream { $0.yield(body); $0.finish() }
        )
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


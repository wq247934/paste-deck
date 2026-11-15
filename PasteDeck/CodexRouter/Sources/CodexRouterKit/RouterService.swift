//
//  RouterService.swift
//  PasteDeck
//
//  守护进程顶层服务：组装监听、鉴权、路由分发、SSE 写回、WS 边缘、
//  健康检查与管理端点。仅监听 127.0.0.1；日志不记录凭据与完整请求体。
//

import Foundation

/// 守护进程运行状态（健康检查与 UI 状态共用）。
public struct RouterServiceStatus: Codable, Equatable {
    public var ok: Bool
    public var service: String
    public var version: String
    public var port: Int
    public var pid: Int
    public var uptimeSeconds: Int
    public var activeConnections: Int
    public var routesLoaded: Int
}

/// 路由服务。
public final class RouterService {
    public let stateDirectory: URL
    public let port: UInt16
    public let bootID = UUID().uuidString
    public let startedAt = Date()

    private var server: RouterHTTPServer?
    private(set) var dispatcher: ResponsesDispatcher?
    private var routeTable: RouteTable?
    private var callerSecret: String = ""
    private var lastProxyRevision = 0
    private let stateLock = NSLock()

    public init(stateDirectory: URL, port: UInt16) {
        self.stateDirectory = stateDirectory
        self.port = port
    }

    // MARK: - 生命周期

    /// 启动服务。端口被占用返回 nil（错误信息写入 error 输出）。
    @discardableResult
    public func start() -> Bool {
        // 1. 读取本地凭据。
        let secretURL = stateDirectory.appendingPathComponent("caller-secret")
        guard let secret = PrivateFile.readText(secretURL)?.trimmingCharacters(in: .whitespacesAndNewlines),
              secret.count >= 32 else {
            RouterService.log("caller-secret 缺失或过短；先在 PasteDeck 中启用路由。")
            return false
        }
        callerSecret = secret

        // 2. 组装组件。
        let table = RouteTable(stateDirectory: stateDirectory)
        routeTable = table
        _ = table.allRoutes()  // 触发首次加载，取得代理基线
        let upstream = UpstreamClient(proxy: table.proxy, proxyPassword: table.proxyPassword)
        let session = CodexAuthSession()
        let dispatcher = ResponsesDispatcher(
            routeTable: table, upstream: upstream, authSession: session, callerSecret: secret)
        self.dispatcher = dispatcher
        lastProxyRevision = table.revision

        // 3. 监听（成功后再写 pidfile，避免残留状态误导停止逻辑）。
        let server = RouterHTTPServer(port: port) { [weak self] request, connection in
            self?.handleRequest(request, connection)
        }
        guard server.start() else {
            RouterService.log("端口 \(port) 监听失败（可能被占用）。")
            return false
        }
        self.server = server
        writeRuntimeState()
        RouterService.log("listening on 127.0.0.1:\(port)")
        return true
    }

    public func stop() {
        server?.stop()
        server = nil
        removeRuntimeState()
        RouterService.log("stopped")
    }

    private func writeRuntimeState() {
        let state = RuntimeStateDocument(
            version: 1,
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            port: Int(port),
            bootID: bootID
        )
        if let data = try? JSONEncoder().encode(state) {
            try? PrivateFile.writeAtomically(data, to: stateDirectory.appendingPathComponent("daemon.json"))
        }
    }

    private func removeRuntimeState() {
        try? FileManager.default.removeItem(
            atPath: stateDirectory.appendingPathComponent("daemon.json").path)
    }

    /// 代理/凭据配置变化时重建 dispatcher（新的 UpstreamClient 会话）。
    private func rebuildDispatcherIfProxyChanged() {
        stateLock.lock()
        let knownRevision = lastProxyRevision
        stateLock.unlock()
        guard let table = routeTable else { return }
        table.reloadIfNeeded()
        let current = table.revision
        guard current != knownRevision else { return }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard lastProxyRevision != current else { return }
        let upstream = UpstreamClient(proxy: table.proxy, proxyPassword: table.proxyPassword)
        let session = CodexAuthSession()
        dispatcher = ResponsesDispatcher(
            routeTable: table, upstream: upstream, authSession: session, callerSecret: callerSecret)
        lastProxyRevision = current
        RouterService.log("检测到端点/凭据/代理配置变化，已重建上游会话（revision \(current)）")
    }

    // MARK: - 请求路由

    private func handleRequest(_ request: HTTPRequest, _ connection: HTTPConnection) {
        // 健康检查免鉴权（本机可见性有限，且不含敏感信息）。
        if request.method == "GET", request.path == "/health" {
            handleHealth(connection)
            return
        }

        // WebSocket 升级。
        if (request.header("upgrade") ?? "").lowercased() == "websocket" {
            handleUpgrade(request, connection)
            return
        }

        // 代理配置热更新：endpoints/credentials 变更触发重建上游会话。
        rebuildDispatcherIfProxyChanged()

        // 其余端点一律鉴权。
        let dispatcher = self.dispatcher
        guard let dispatcher else {
            RouterHTTPServer.writeSimpleError(connection, status: 503, message: "service_unavailable")
            return
        }
        let token = Self.bearerToken(from: request.headers)
        guard dispatcher.authenticate(bearerToken: token) else {
            RouterService.log("401 未授权请求 path=\(request.path)")
            RouterHTTPServer.writeSimpleError(connection, status: 401, message: "authentication_error")
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/models"), ("GET", "/v1/models"):
            handleModels(connection)
        case ("GET", "/v1/health"):
            handleHealth(connection)
        case ("POST", "/responses"), ("POST", "/v1/responses"),
             ("POST", "/responses/compact"), ("POST", "/v1/responses/compact"):
            handleResponses(request, connection)
        case ("POST", "/_admin/stop"):
            handleAdminStop(request, connection)
        case ("OPTIONS", _):
            connection.send(Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n".utf8))
        default:
            RouterHTTPServer.writeSimpleError(connection, status: 404, message: "proxy_route_not_found")
        }
    }

    // MARK: - /responses（SSE/JSON 写回）

    private func handleResponses(_ request: HTTPRequest, _ connection: HTTPConnection) {
        // 连接线程阻塞至响应写完：SSE 与 keep-alive 不会交错；
        // 客户端断开（send 失败）触发 onClientGone → 取消上游。
        let semaphore = DispatchSemaphore(value: 0)
        var currentTask: Task<Void, Never>?
        connection.onClientGone = { currentTask?.cancel() }

        let body = request.body
        let headers = request.headers
        let path = request.path
        let service = self
        currentTask = Task { [weak connection] in
            defer { semaphore.signal() }
            guard let connection else { return }
            guard let dispatcher = service.dispatcher else { return }
            let dispatchRequest = DispatchRequest(
                method: "POST", path: path, headers: headers,
                body: RouterService.decodeChunkedIfNeeded(body: body, headers: headers))
            let result = await dispatcher.dispatch(dispatchRequest)
            await service.writeDispatchResult(result, to: connection)
        }
        semaphore.wait()
    }

    /// 把分发结果写回 HTTP 客户端（SSE 走 chunked；JSON 走 Content-Length）。
    private func writeDispatchResult(_ result: DispatchResult, to connection: HTTPConnection) async {
        let reason = RouterHTTPServer.reasonPhrase(result.status)
        var head = "HTTP/1.1 \(result.status) \(reason)\r\n"
        for (name, value) in result.headers {
            head += "\(name): \(value)\r\n"
        }
        let isJSON = (result.headers["content-type"] ?? "").contains("application/json")
        if isJSON {
            // 收集完整 JSON（错误或非流式响应）。
            var collected = Data()
            do {
                for try await chunk in result.stream {
                    collected.append(chunk)
                    if collected.count > (1 << 22) { break }
                }
            } catch {
                collected = Data("{\"error\":{\"type\":\"local_router_error\",\"message\":\"上游读取失败\"}}".utf8)
            }
            head += "Content-Length: \(collected.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(head.utf8)
            payload.append(collected)
            connection.send(payload) { connection.close() }
        } else {
            head += "Transfer-Encoding: chunked\r\n\r\n"
            connection.send(Data(head.utf8))
            do {
                for try await chunk in result.stream {
                    if connection.isClosed { return }
                    var frame = Data("\(String(chunk.count, radix: 16))\r\n".utf8)
                    frame.append(chunk)
                    frame.append(Data("\r\n".utf8))
                    connection.send(frame)
                    if connection.hasBackpressure {
                        while connection.hasBackpressure, !connection.isClosed {
                            try await Task.sleep(nanoseconds: 5_000_000)
                        }
                    }
                }
                connection.send(Data("0\r\n\r\n".utf8)) { connection.close() }
            } catch is CancellationError {
                connection.close(afterWriting: false)
            } catch {
                // 中途失败：尽力发出一个终态错误事件再关闭。
                let message = "{\"error\":{\"type\":\"local_router_error\",\"message\":\"上游流中断\"}}"
                let frameData = Data("data: \(message)\n\n".utf8)
                var frame = Data("\(String(frameData.count, radix: 16))\r\n".utf8)
                frame.append(frameData)
                frame.append(Data("\r\n".utf8))
                connection.send(frame)
                connection.send(Data("0\r\n\r\n".utf8)) { connection.close() }
            }
        }
    }

    // MARK: - /models

    private func handleModels(_ connection: HTTPConnection) {
        let routes = routeTable?.allRoutes() ?? []
        let models: [[String: Any]] = routes.map { route in
            [
                "id": route.slug,
                "object": "model",
                "created": 0,
                "owned_by": route.endpointID,
            ]
        }
        let payload: [String: Any] = ["object": "list", "data": models]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"object\":\"list\",\"data\":[]}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        response.append(body)
        connection.send(response) { connection.close() }
    }

    // MARK: - /health

    private func handleHealth(_ connection: HTTPConnection) {
        let status = RouterServiceStatus(
            ok: dispatcher != nil,
            service: CodexRouterConstants.serviceIdentifier,
            version: RouterService.selfVersion,
            port: Int(port),
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            uptimeSeconds: Int(Date().timeIntervalSince(startedAt)),
            activeConnections: server?.activeConnections ?? 0,
            routesLoaded: routeTable?.allRoutes().count ?? 0
        )
        let body = (try? JSONEncoder().encode(status)) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        response.append(body)
        connection.send(response) { connection.close() }
    }

    // MARK: - 管理端点

    private func handleAdminStop(_ request: HTTPRequest, _ connection: HTTPConnection) {
        // 管理端点要求 caller-secret 本身（不能只用 Codex 会话令牌）。
        let token = Self.bearerToken(from: request.headers) ?? ""
        guard token == callerSecret else {
            RouterHTTPServer.writeSimpleError(connection, status: 403, message: "forbidden")
            return
        }
        let body = Data("{\"stopped\":true}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        response.append(body)
        connection.send(response) {
            self.stop()
            exit(0)
        }
    }

    // MARK: - WS 升级

    private func handleUpgrade(_ request: HTTPRequest, _ connection: HTTPConnection) {
        let dispatcher = self.dispatcher
        guard let dispatcher else {
            RouterHTTPServer.writeSimpleError(connection, status: 503, message: "service_unavailable")
            return
        }
        // 升级路径必须是 /responses 或 /v1/responses。
        guard request.path == "/responses" || request.path == "/v1/responses" else {
            RouterHTTPServer.writeSimpleError(connection, status: 404, message: "proxy_route_not_found")
            return
        }
        // 鉴权（升级请求携带 Codex OAuth 或 caller-secret Bearer）。
        let token = Self.bearerToken(from: request.headers)
        guard dispatcher.authenticate(bearerToken: token) else {
            RouterHTTPServer.writeSimpleError(connection, status: 401, message: "authentication_error")
            return
        }
        guard case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
            if case .reject(let status, let message) = ResponsesWebSocketEdge.validateUpgrade(request: request) {
                let body = "{\"error\":{\"type\":\"websocket_upgrade_rejected\",\"message\":\"\(message)\"}}"
                var response = Data("HTTP/1.1 \(status) \(RouterHTTPServer.reasonPhrase(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n".utf8)
                response.append(Data(body.utf8))
                connection.send(response) { connection.close() }
            }
            return
        }
        // 101 接受。
        let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
        let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        connection.send(Data(head.utf8))
        let session = ResponsesWebSocketSession(
            connection: connection, dispatcher: dispatcher, upgradeHeaders: request.headers)
        // 阻塞连接线程：成为该 WS 的常驻读循环。
        session.runBlocking()
    }

    // MARK: - 工具

    public static let selfVersion = "1.0.0"

    static func bearerToken(from headers: [String: String]) -> String? {
        guard let authorization = headers["authorization"] else { return nil }
        let trimmed = authorization.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bearer") else { return nil }
        let rest = trimmed.dropFirst("bearer".count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let token = rest.trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    static func decodeChunkedIfNeeded(body: Data, headers: [String: String]) -> Data {
        guard headers["x-internal-chunked"] == "1" else { return body }
        return HTTPRequest.decodeChunked(body) ?? body
    }

    public static func log(_ message: String) {
        let line = "[pastedeck-codex-router] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// daemon.json 运行时状态。
public struct RuntimeStateDocument: Codable {
    public var version: Int
    public var pid: Int
    public var port: Int
    public var bootID: String

    public init(version: Int, pid: Int, port: Int, bootID: String) {
        self.version = version
        self.pid = pid
        self.port = port
        self.bootID = bootID
    }
}

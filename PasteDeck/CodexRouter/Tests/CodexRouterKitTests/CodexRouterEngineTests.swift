//
//  CodexRouterEngineTests.swift
//  PasteDeckTests
//
//  阶段三：路由引擎测试。全部走本地 mock 上游（127.0.0.1 随机端口），
//  不发起任何外网请求；验证鉴权、路由分发、凭据隔离、SSE 中继、
//  zstd 往返、WS 帧编解码与升级校验。
//

import XCTest
@testable import CodexRouterKit

final class CodexRouterEngineTests: XCTestCase {

    var temporaryHome: URL!
    var stateDirectory: URL!
    var callerSecret: String!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-router-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        setenv("CODEX_HOME", temporaryHome.path, 1)
        stateDirectory = temporaryHome.appendingPathComponent("pastedeck-router", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        callerSecret = String(repeating: "abcdef123456", count: 4)  // 48 字符
        try callerSecret.write(
            to: stateDirectory.appendingPathComponent("caller-secret"),
            atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateDirectory.appendingPathComponent("caller-secret").path)
    }

    override func tearDownWithError() throws {
        unsetenv("CODEX_HOME")
        try? FileManager.default.removeItem(at: temporaryHome)
    }

    // MARK: - Mock 上游

    /// 请求记录器（init 期闭包捕获的安全载体）：保序记录全部请求。
    final class RequestRecorder {
        private let lock = NSLock()
        private var stored: [HTTPRequest] = []
        func record(_ request: HTTPRequest) { lock.withLock { stored.append(request) } }
        func latest() -> HTTPRequest? { lock.withLock { stored.last } }
        func all() -> [HTTPRequest] { lock.withLock { stored } }
    }

    /// 极简 mock 上游：记录收到的请求，回放预设 SSE/JSON。
    final class MockUpstream {
        let server: RouterHTTPServer
        let port: Int
        let recorder: RequestRecorder
        let responseStatus: Int
        let responseBody: Data

        init(recorder: RequestRecorder, responseStatus: Int = 200, responseBody: Data) throws {
            self.recorder = recorder
            self.responseStatus = responseStatus
            self.responseBody = responseBody
            var assignedPort = 0
            var chosen: RouterHTTPServer?
            // 探测可用端口。
            for candidate in (49000...49500).shuffled() {
                let status = responseStatus
                let body = responseBody
                let candidateServer = RouterHTTPServer(port: UInt16(candidate)) { request, connection in
                    recorder.record(request)
                    let head = "HTTP/1.1 \(status) \(RouterHTTPServer.reasonPhrase(status))\r\nContent-Type: text/event-stream\r\n\r\n"
                    var payload = Data(head.utf8)
                    payload.append(body)
                    connection.send(payload) { connection.close() }
                }
                if candidateServer.start() {
                    assignedPort = candidate
                    chosen = candidateServer
                    break
                }
            }
            guard assignedPort > 0, let chosen else { throw NSError(domain: "mock", code: 1) }
            self.server = chosen
            self.port = assignedPort
        }

        func stop() { server.stop() }
    }

    private func makeSSE(events: [String]) -> Data {
        Data(events.map { "data: \($0)\n\n" }.joined().utf8)
    }

    @discardableResult
    private func installEndpoint(
        endpointID: String = "relay",
        baseURL: String,
        models: [RouterEndpointModel]
    ) throws {
        var document = RouterEndpointsDocument.empty()
        document.endpoints = [RouterEndpoint(
            id: endpointID, displayName: "测试端点", baseURL: baseURL,
            enabled: true, models: models)]
        try RouterEndpointStore(stateDirectory: stateDirectory).save(document)
        let credentials = RuntimeCredentialsDocument(
            version: 1,
            entries: [.init(endpointID: endpointID, apiKey: "sk-third-party-key")],
            proxyPassword: nil)
        let data = try JSONEncoder().encode(credentials)
        try PrivateFile.writeAtomically(data, to: stateDirectory.appendingPathComponent("credentials.json"))
    }

    private func makeDispatcher(nativeBaseURL: String) -> ResponsesDispatcher {
        ResponsesDispatcher(
            routeTable: RouteTable(stateDirectory: stateDirectory),
            upstream: UpstreamClient(proxy: .standard(), proxyPassword: nil),
            authSession: CodexAuthSession(codexHome: temporaryHome.path),
            callerSecret: callerSecret,
            nativeBaseURL: nativeBaseURL
        )
    }

    private func makeRequestBody(model: String, extra: [String: Any] = [:]) -> Data {
        var payload: [String: Any] = ["model": model, "stream": true]
        for (key, value) in extra { payload[key] = value }
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    /// 等待收集完整 SSE 文本（流错误追加为文本，便于断言）。
    private func collectStream(_ result: DispatchResult) async -> String {
        var text = ""
        do {
            for try await chunk in result.stream {
                text.append(String(decoding: chunk, as: UTF8.self))
            }
        } catch {
            text += "\n[stream error: \(error.localizedDescription)]"
        }
        return text
    }

    // MARK: - 鉴权

    func testDispatchRejectsInvalidBearer() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.created\"}"]))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer wrong-token"],
            body: makeRequestBody(model: "gpt-6.1-sol")))
        XCTAssertEqual(result.status, 401)
        let text = await collectStream(result)
        XCTAssertTrue(text.contains("authentication_error"))
        // 请求没有到达上游。
        XCTAssertNil(mock.recorder.latest())
    }

    func testDispatchAcceptsCallerSecret() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.created\"}"]))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "gpt-6.1-sol")))
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(mock.recorder.latest()?.path, "/responses")
    }

    // MARK: - 原生透传

    func testNativePassthroughForwardsHeadersAndStripsPreviousResponseID() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.completed\"}"]))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: [
                "authorization": "Bearer \(callerSecret!)",
                "chatgpt-account-id": "acc-42",
                "x-codex-turn-metadata": "{\"turn\":1}",
                "x-should-not-forward": "nope",
            ],
            body: makeRequestBody(model: "gpt-6.1-sol", extra: ["previous_response_id": "resp_old"])))
        XCTAssertEqual(result.status, 200)
        let request = try XCTUnwrap(mock.recorder.latest())
        XCTAssertEqual(request.path, "/responses")
        // 白名单头转发。
        XCTAssertEqual(request.header("chatgpt-account-id"), "acc-42")
        XCTAssertNotNil(request.header("x-codex-turn-metadata"))
        // 非白名单头不转发。
        XCTAssertNil(request.header("x-should-not-forward"))
        // previous_response_id 剥离。
        let forwarded = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        XCTAssertNil(forwarded["previous_response_id"])
        XCTAssertEqual(forwarded["model"] as? String, "gpt-6.1-sol")
    }

    func testNativeCompactPathPreservesPreviousResponseID() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: Data("{\"status\":\"completed\"}".utf8))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses/compact",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "gpt-6.1-sol", extra: ["previous_response_id": "resp_old"])))
        XCTAssertEqual(result.status, 200)
        let request = try XCTUnwrap(mock.recorder.latest())
        XCTAssertEqual(request.path, "/responses/compact")
        let forwarded = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        XCTAssertEqual(forwarded["previous_response_id"] as? String, "resp_old")
    }

    func testNativeBodyIsZstdCompressedWhenLarge() async throws {
        // >16KB 的请求体会被再压缩（Content-Encoding: zstd）。
        let filler = String(repeating: "A", count: 40_000)
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.completed\"}"]))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "gpt-6.1-sol", extra: ["filler": filler])))
        XCTAssertEqual(result.status, 200)
        let request = try XCTUnwrap(mock.recorder.latest())
        XCTAssertEqual(request.header("content-encoding"), "zstd")
        let decoded = try ZstdSupport.decompress(request.body)
        let forwarded = try JSONSerialization.jsonObject(with: decoded) as! [String: Any]
        XCTAssertEqual(forwarded["filler"] as? String, filler)
    }

    // MARK: - 第三方转发

    func testExternalRouteUsesEndpointCredentialAndUpstreamModel() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.completed\"}"]))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "deepseek-v4", displayName: "DS")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)", "chatgpt-account-id": "acc-42"],
            body: makeRequestBody(model: "relay/deepseek-v4")))
        XCTAssertEqual(result.status, 200)
        let request = try XCTUnwrap(mock.recorder.latest())
        XCTAssertEqual(request.path, "/v1/responses")
        // 端点凭据替代官方凭据。
        XCTAssertEqual(request.header("authorization"), "Bearer sk-third-party-key")
        // 官方专属头不转发。
        XCTAssertNil(request.header("chatgpt-account-id"))
        // model 换成上游 ID。
        let forwarded = try JSONSerialization.jsonObject(with: request.body) as! [String: Any]
        XCTAssertEqual(forwarded["model"] as? String, "deepseek-v4")
        // service_tier 剥离。
    }

    func testExternalRouteStripsServiceTierAndConvertsAgentMessage() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: ["{\"type\":\"response.completed\"}"]))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "glm-5.3", displayName: "GLM")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let body = makeRequestBody(model: "relay/glm-5.3", extra: [
            "service_tier": "priority",
            "input": [
                ["type": "agent_message", "content": "子代理结果"],
                ["type": "message", "role": "user", "content": "继续"],
            ],
        ])
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: body))
        XCTAssertEqual(result.status, 200)
        let forwarded = try JSONSerialization.jsonObject(with: mock.recorder.latest()!.body) as! [String: Any]
        XCTAssertNil(forwarded["service_tier"])
        let input = forwarded["input"] as! [[String: Any]]
        XCTAssertEqual(input[0]["type"] as? String, "message")
        XCTAssertEqual(input[0]["role"] as? String, "user")
    }

    func testUnroutedProviderSlugRefusedLocally() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: Data("".utf8))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "known", displayName: "K")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "relay/unknown-model")))
        XCTAssertEqual(result.status, 400)
        let text = await collectStream(result)
        XCTAssertTrue(text.contains("unrouted_model"), "actual: \(text)")
        // JSONSerialization 会把 "/" 转义为 \/，按转义后形态断言。
        XCTAssertTrue(text.contains("relay\\/unknown-model"), "actual: \(text)")
        // 绝不转发官方。
        XCTAssertNil(mock.recorder.latest())
    }

    func testUnknownPrefixedSlugWithUnregisteredProviderRefused() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: Data("".utf8))
        defer { mock.stop() }
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "ghostvendor/model-1")))
        XCTAssertEqual(result.status, 400)
        XCTAssertNil(mock.recorder.latest())
    }

    func testExternalCompactPathMapsToEndpointCompact() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: Data("{\"object\":\"compact\"}".utf8))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "m1", displayName: "M")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let result = await dispatcher.dispatch(DispatchRequest(
            method: "POST", path: "/v1/responses/compact",
            headers: ["authorization": "Bearer \(callerSecret!)"],
            body: makeRequestBody(model: "relay/m1")))
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(mock.recorder.latest()?.path, "/v1/responses/compact")
    }

    // MARK: - 端到端 HTTP 回环（RouterHTTPServer + 分发器）

    func testFullHTTPRoundTripThroughServer() async throws {
        let recorder = RequestRecorder()
        let mock = try MockUpstream(recorder: recorder, responseBody: makeSSE(events: [
            "{\"type\":\"response.created\"}",
            "{\"type\":\"response.completed\"}",
        ]))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "m1", displayName: "M")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")
        let serverPort = UInt16(48700)
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses", request.method == "POST" else {
                RouterHTTPServer.writeSimpleError(connection, status: 404, message: "not_found")
                return
            }
            let token = RouterService.bearerToken(from: request.headers)
            guard dispatcher.authenticate(bearerToken: token) else {
                RouterHTTPServer.writeSimpleError(connection, status: 401, message: "authentication_error")
                return
            }
            let requestCopy = request
            Task { [dispatcher] in
                let result = await dispatcher.dispatch(DispatchRequest(
                    method: "POST", path: requestCopy.path, headers: requestCopy.headers,
                    body: requestCopy.body))
                await RouterServiceTestsSupport.writeResult(result, to: connection)
            }
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        // URLSession 客户端请求本地路由。
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(serverPort)/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(callerSecret!)", forHTTPHeaderField: "Authorization")
        request.httpBody = makeRequestBody(model: "relay/m1")
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("response.created"))
        XCTAssertTrue(text.contains("response.completed"))
    }

    // MARK: - zstd 与 WS

    func testZstdRoundTrip() throws {
        let payload = Data(String(repeating: "codex-router-test-", count: 2000).utf8)
        guard let compressed = ZstdSupport.compress(payload) else {
            return XCTFail("压缩失败")
        }
        XCTAssertLessThan(compressed.count, payload.count / 10)
        let decompressed = try ZstdSupport.decompress(compressed)
        XCTAssertEqual(decompressed, payload)
    }

    func testWSFrameRoundTripWithMasking() throws {
        let payload = Data("{\"type\":\"response.create\"}".utf8)
        // 客户端 → 服务端：必须掩码。
        let maskedFrame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
        let decoder = WebSocketFrameDecoder()
        let frames = try decoder.feed(maskedFrame)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].opcode, 0x1)
        XCTAssertEqual(frames[0].payload, payload)
        // 未掩码 → 协议违规。
        let plainFrame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: false)
        XCTAssertThrowsError(try WebSocketFrameDecoder().feed(plainFrame))
        // 二进制帧 → 拒绝。
        let binary = WebSocketFrameEncoder.encode(fin: true, opcode: 0x2, payload: Data([1, 2, 3]), masked: true)
        XCTAssertThrowsError(try WebSocketFrameDecoder().feed(binary)) { error in
            XCTAssertEqual(error as? WebSocketFrameError, .binaryFrame)
        }
    }

    func testWSUpgradeValidation() throws {
        func request(openaiBeta: String?, origin: String? = nil) -> HTTPRequest {
            var headers = [
                "upgrade": "websocket",
                "connection": "Upgrade",
                "sec-websocket-version": "13",
                "sec-websocket-key": "dGhlIHNhbXBsZSBub25jZQ==",
            ]
            if let openaiBeta { headers["openai-beta"] = openaiBeta }
            if let origin { headers["origin"] = origin }
            return HTTPRequest(
                method: "GET", path: "/v1/responses", query: nil,
                httpVersion: "HTTP/1.1", headers: headers, body: Data())
        }

        let valid = ResponsesWebSocketEdge.validateUpgrade(
            request: request(openaiBeta: "responses_websockets=2026-02-06"))
        guard case .accept(let key) = valid else { return XCTFail("有效升级被拒绝") }
        XCTAssertEqual(ResponsesWebSocketEdge.acceptHeaderValue(for: key),
                       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

        // Origin 拒绝（浏览器滥用防护）。
        let browser = ResponsesWebSocketEdge.validateUpgrade(
            request: request(openaiBeta: "responses_websockets=2026-02-06", origin: "https://evil.example"))
        guard case .reject(let status, _) = browser else { return XCTFail("浏览器来源未被拒绝") }
        XCTAssertEqual(status, 403)

        // 缺协议令牌。
        let missingToken = ResponsesWebSocketEdge.validateUpgrade(request: request(openaiBeta: nil))
        guard case .reject = missingToken else { return XCTFail("缺协议令牌未被拒绝") }
    }


    /// 原生 socket WS 客户端：逐字节验证服务器回帧。
    func testWebSocketRawSocketFrameBytes() throws {
        let mock = try MockUpstream(recorder: RequestRecorder(), responseBody: makeSSE(events: [
            "{\"type\":\"response.created\"}",
            "{\"type\":\"response.completed\"}",
        ]))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "m1", displayName: "M")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")

        let serverPort = UInt16(49600 + Int.random(in: 0...600))
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses" else {
                RouterHTTPServer.writeSimpleError(connection, status: 404, message: "not_found")
                return
            }
            guard case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
                RouterHTTPServer.writeSimpleError(connection, status: 426, message: "upgrade_required")
                return
            }
            let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
            let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(Data(head.utf8))
            let session = ResponsesWebSocketSession(
                connection: connection,
                dispatcherProvider: { dispatcher },
                upgradeHeaders: request.headers)
            session.runBlocking()
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        // 原生 socket 客户端。
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = serverPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connectResult, 0, "connect 失败 errno=\(errno)")

        let key = Data("dGhlIHNhbXBsZSBub25jZQ==".utf8)
        let handshake = "GET /v1/responses HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOpenAI-Beta: responses_websockets=2026-02-06\r\n\r\n"
        let handshakeData = Data(handshake.utf8)
        let sentResult = handshakeData.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            var sent = 0
            while sent < handshakeData.count {
                let n = Darwin.send(fd, base + sent, handshakeData.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
            return sent
        }
        _ = sentResult
        // 读握手响应头（无鉴权 → 帧处理会回 401 error 帧）。
        var responseBuffer = Data()
        let headDeadline = Date().addingTimeInterval(10)
        while Date() < headDeadline {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            responseBuffer.append(contentsOf: chunk[0..<n])
            if Data(responseBuffer).range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        let headText = String(decoding: responseBuffer.prefix(120), as: UTF8.self)
        XCTAssertTrue(headText.contains("101"), "握手响应: \(headText)")

        // 发送文本帧（掩码）。
        let payload = Data("{\"type\":\"response.create\",\"model\":\"relay/m1\",\"stream\":true,\"input\":[]}".utf8)
        let frame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
        _ = frame.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            var frameSent = 0
            while frameSent < frame.count {
                let n = Darwin.send(fd, base + frameSent, frame.count - frameSent, 0)
                if n <= 0 { break }
                frameSent += n
            }
            return frameSent
        }

        // 读回帧字节。
        var received = Data()
        let frameDeadline = Date().addingTimeInterval(15)
        while Date() < frameDeadline, received.count < 2 {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { 
                print("RAWTEST recv returned \(n) errno=\(errno) after \(received.count) bytes")
                break 
            }
            received.append(contentsOf: chunk[0..<n])
            let frames = try? WebSocketFrameDecoder().feed(Data(received))
            if let frames, !frames.isEmpty {
                break
            }
        }
        XCTAssertGreaterThanOrEqual(received.count, 2, "服务器回帧缺失；首字节: \(String(decoding: received.prefix(60), as: UTF8.self))")
    }

    // MARK: - 审查修复回归

    func testPrivateFileAtomicReplaceKeepsFileIntact() throws {
        let target = stateDirectory.appendingPathComponent("atomic-test.json")
        try PrivateFile.writeAtomically("first".data(using: .utf8)!, to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "first")
        XCTAssertTrue(PrivateFile.isProtected(target.path))
        // 二次覆盖：rename 原子替换，内容与权限保持正确。
        try PrivateFile.writeAtomically("second-content".data(using: .utf8)!, to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "second-content")
        XCTAssertTrue(PrivateFile.isProtected(target.path))
        // 无临时文件残留。
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: stateDirectory.path)
            .filter { $0.hasPrefix(".tmp.") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testRouteTableReloadsCredentialsHot() throws {
        try installEndpoint(baseURL: "https://relay.example.com/v1",
                            models: [RouterEndpointModel.standard(modelID: "m1", displayName: "M")])
        let table = RouteTable(stateDirectory: stateDirectory)
        XCTAssertEqual(table.route(for: "relay/m1")?.apiKey, "sk-third-party-key")

        // 改写凭据文件（模拟 PasteDeck 修改 Key 后重新物化），路由表热加载新 Key。
        var credentials = try JSONDecoder().decode(
            RuntimeCredentialsDocument.self,
            from: Data(contentsOf: stateDirectory.appendingPathComponent("credentials.json")))
        credentials.entries[0].apiKey = "sk-rotated-key"
        let data = try JSONEncoder().encode(credentials)
        try PrivateFile.writeAtomically(data, to: stateDirectory.appendingPathComponent("credentials.json"))
        // mtime 精度兜底：显式推动修改时间。
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(1)],
            ofItemAtPath: stateDirectory.appendingPathComponent("credentials.json").path)

        XCTAssertEqual(table.route(for: "relay/m1")?.apiKey, "sk-rotated-key")
        // 修订号随重建递增（代理热更新依据）。
        let revisionAfterCredential = table.revision
        XCTAssertGreaterThan(revisionAfterCredential, 0)
        XCTAssertEqual(table.proxyPassword, nil)
    }

    func testProxyLoopbackDetection() {
        XCTAssertTrue(ProxySupport.targetIsLoopback("http://127.0.0.1:4212/v1/responses"))
        XCTAssertTrue(ProxySupport.targetIsLoopback("http://localhost:1234/v1"))
        XCTAssertTrue(ProxySupport.targetIsLoopback("http://[::1]:8080/v1"))
        XCTAssertFalse(ProxySupport.targetIsLoopback("https://watchdog02.senhe.work/v1/responses"))
        XCTAssertFalse(ProxySupport.targetIsLoopback("https://chatgpt.com/backend-api/codex"))
    }

    func testProcessOwnershipRejectsForeignPID() throws {
        // 当前测试进程与 sleep 进程都不是路由守护进程。
        XCTAssertFalse(CodexRouterController.processBelongsToDaemon(getpid()))
        let sleep = Process()
        sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleep.arguments = ["0.5"]
        try sleep.run()
        defer { sleep.terminate() }
        XCTAssertFalse(CodexRouterController.processBelongsToDaemon(pid_t(sleep.processIdentifier)))
    }

    func testSSEParserHandlesCRLFAndBareCR() {
        // \r\n\r\n 事件边界 + \r\n 行尾。
        var parser = SSEEventParser()
        let crlf = Data("data: {\"a\":1}\r\n\r\ndata: {\"b\":2}\r\n\r\n".utf8)
        XCTAssertEqual(parser.feed(crlf).count, 2)
        // \n 与 \r\n 混排。
        var mixed = SSEEventParser()
        let mixedChunk = Data("data: {\"a\":1}\n\ndata: {\"b\":2}\r\n\r\n".utf8)
        XCTAssertEqual(mixed.feed(mixedChunk).count, 2)
        // 分块到达（事件边界跨 chunk）。
        var chunked = SSEEventParser()
        XCTAssertEqual(chunked.feed(Data("data: {\"a\":1}\r\n".utf8)).count, 0)
        XCTAssertEqual(chunked.feed(Data("\r\n".utf8)).count, 1)
    }

    func testWebSocketRequestsAreProcessedSerially() async throws {
        let mock = try MockUpstream(recorder: RequestRecorder(), responseBody: makeSSE(events: [
            "{\"type\":\"response.completed\"}",
        ]))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [
                RouterEndpointModel.standard(modelID: "first", displayName: "F"),
                RouterEndpointModel.standard(modelID: "second", displayName: "S"),
            ])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")

        let serverPort = UInt16(50200 + Int.random(in: 0...600))
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses",
                  case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
                RouterHTTPServer.writeSimpleError(connection, status: 426, message: "upgrade_required")
                return
            }
            let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
            let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(Data(head.utf8))
            let session = ResponsesWebSocketSession(
                connection: connection,
                dispatcherProvider: { dispatcher },
                upgradeHeaders: request.headers)
            session.runBlocking()
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        // 原生 socket 客户端：连续快速发送两个不同模型的请求帧。
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = serverPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let handshake = "GET /v1/responses HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer \(callerSecret!)\r\nOpenAI-Beta: responses_websockets=2026-02-06\r\n\r\n"
        let handshakeData = Data(handshake.utf8)
        handshakeData.withUnsafeBytes { raw in
            _ = Darwin.send(fd, raw.baseAddress, handshakeData.count, 0)
        }
        // 等待 101。
        var headBuffer = Data()
        let headDeadline = Date().addingTimeInterval(10)
        while Date() < headDeadline, !headBuffer.contains(Data("\r\n\r\n".utf8)) {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            headBuffer.append(contentsOf: chunk[0..<n])
        }
        XCTAssertTrue(headBuffer.contains(Data("101".utf8)))
        // 101 之后同段到达的帧字节必须保留（本地 mock 响应极快）。
        var frameBuffer = Data()
        if let headEnd = headBuffer.range(of: Data("\r\n\r\n".utf8)) {
            frameBuffer = headBuffer.subdata(in: headEnd.upperBound..<headBuffer.endIndex)
        }
        // 读超时兜底：recv 永不无限阻塞。
        var receiveTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        func sendFrame(_ payload: Data) {
            let frame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
            frame.withUnsafeBytes { raw in
                _ = Darwin.send(fd, raw.baseAddress, frame.count, 0)
            }
        }
        func makeFrame(_ model: String) -> Data {
            let body: [String: Any] = [
                "type": "response.create", "model": model, "stream": true,
                "input": [["type": "message", "role": "user",
                           "content": [["type": "input_text", "text": "hi"]]]],
            ]
            return try! JSONSerialization.data(withJSONObject: body)
        }
        // 连续发送（无等待）→ 串行链必须保证上游按到达顺序处理。
        sendFrame(makeFrame("relay/first"))
        sendFrame(makeFrame("relay/second"))

        // 等待两个上游请求都到达。
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, mock.recorder.all().count < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let ordered = mock.recorder.all()
        XCTAssertEqual(ordered.count, 2, "两个请求都应到达上游")
        if ordered.count == 2 {
            let first = try JSONSerialization.jsonObject(with: ordered[0].body) as! [String: Any]
            let second = try JSONSerialization.jsonObject(with: ordered[1].body) as! [String: Any]
            XCTAssertEqual(first["model"] as? String, "first")
            XCTAssertEqual(second["model"] as? String, "second", "串行链必须保持到达顺序")
        }
    }

    // MARK: - 审查二轮回归

    func testSSEParserHandlesCRSplitAcrossChunks() {
        // \r\n 恰好被网络分块拆开：第一块以 \r 结尾时必须等待下一块，
        // 否则下一块开头的 \n 会被误判为空行事件边界。
        var parser = SSEEventParser()
        XCTAssertEqual(parser.feed(Data("data: {\"a\":1}\r".utf8)).count, 0)
        XCTAssertEqual(parser.feed(Data("\ndata: {\"b\":2}\r\n\r\n".utf8)).count, 1)
    }

    func testLaunchAgentPlistContentAndLifecycle() throws {
        let agentsDirectory = temporaryHome.appendingPathComponent("LaunchAgents")
        var commands: [[String]] = []
        let agent = LaunchAgentManager(launchAgentsDirectory: agentsDirectory) { commands.append($0) }

        try agent.install(
            daemonPath: "/opt/PasteDeck/pastedeck-codex-router",
            stateDirectory: stateDirectory,
            port: 4212,
            logPath: stateDirectory.appendingPathComponent("router.log"))
        XCTAssertTrue(agent.isInstalled())

        let plist = try String(contentsOf: agent.plistURL, encoding: .utf8)
        XCTAssertTrue(plist.contains("com.pastedeck.codex-router"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(plist.contains("/opt/PasteDeck/pastedeck-codex-router"))
        XCTAssertTrue(plist.contains("<string>4212</string>"))
        // bootout（清理旧定义）→ bootstrap，bootstrap 指向 plist。
        XCTAssertEqual(commands.first?.first, "bootout")
        XCTAssertEqual(commands[1].first, "bootstrap")
        XCTAssertEqual(commands[1].last, agent.plistURL.path)

        agent.uninstall()
        XCTAssertFalse(agent.isInstalled())
        XCTAssertEqual(commands.last?.first, "bootout")
    }

    /// 保持连接的 mock 上游：发出首个事件（含 response.id）后等待客户端
    /// 断开（模拟长生成）。createdDelay 用于确定性测试极早中断场景。
    final class HoldOpenUpstream {
        private let lock = NSLock()
        private var disconnected = false
        let port: Int
        private let listenerFD: Int32
        private let queue = DispatchQueue(label: "hold-open-mock")
        private let createdDelay: TimeInterval

        init(port: Int, createdDelay: TimeInterval = 0.5) throws {
            self.createdDelay = createdDelay
            self.port = port
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bindResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0, Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); throw NSError(domain: "mock", code: 2) }
            listenerFD = fd
            let condition = NSCondition()
            var accepted = false
            queue.async { [weak self] in
                guard let self else { return }
                while true {
                    var clientAddress = sockaddr_in()
                    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let clientFD = withUnsafeMutablePointer(to: &clientAddress) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            accept(self.listenerFD, $0, &length)
                        }
                    }
                    guard clientFD >= 0 else { return }
                    condition.lock()
                    accepted = true
                    condition.signal()
                    condition.unlock()
                    // 读掉请求头。
                    var head = Data()
                    while !head.contains(Data("\r\n\r\n".utf8)) {
                        var chunk = [UInt8](repeating: 0, count: 8192)
                        let n = recv(clientFD, &chunk, chunk.count, 0)
                        if n <= 0 { break }
                        head.append(contentsOf: chunk[0..<n])
                    }
                    let sseHead = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
                    let firstEvent = "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_mock_turn_1\"}}\n\n"
                    var payload = Data(sseHead.utf8)
                    if createdDelay > 0 {
                        Thread.sleep(forTimeInterval: createdDelay)
                    }
                    payload.append(Data(firstEvent.utf8))
                    payload.withUnsafeBytes { raw in
                        _ = Darwin.send(clientFD, raw.baseAddress, payload.count, 0)
                    }
                    // 保持连接直到客户端断开。
                    while true {
                        var probe = [UInt8](repeating: 0, count: 1024)
                        let n = recv(clientFD, &probe, probe.count, 0)
                        if n <= 0 { break }
                    }
                    self.lock.lock()
                    self.disconnected = true
                    self.lock.unlock()
                    Darwin.close(clientFD)
                }
            }
            // 等待监听就绪。
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                condition.lock()
                let ready = accepted
                condition.unlock()
                if ready { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        var clientDisconnected: Bool {
            lock.lock(); defer { lock.unlock() }
            return disconnected
        }

        func stop() { Darwin.close(listenerFD) }
    }

    func testWebSocketInterruptCancelsUpstreamGeneration() async throws {
        let mock = try HoldOpenUpstream(port: Int.random(in: 50000...51000))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "slow", displayName: "S")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")

        let serverPort = UInt16(51100 + Int.random(in: 0...600))
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses",
                  case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
                RouterHTTPServer.writeSimpleError(connection, status: 426, message: "upgrade_required")
                return
            }
            let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
            let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(Data(head.utf8))
            let session = ResponsesWebSocketSession(
                connection: connection,
                dispatcherProvider: { dispatcher },
                upgradeHeaders: request.headers)
            session.runBlocking()
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        // 原生 socket WS 客户端。
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = serverPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let handshake = "GET /v1/responses HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer \(callerSecret!)\r\nOpenAI-Beta: responses_websockets=2026-02-06\r\n\r\n"
        let handshakeData = Data(handshake.utf8)
        handshakeData.withUnsafeBytes { raw in
            _ = Darwin.send(fd, raw.baseAddress, handshakeData.count, 0)
        }
        var headBuffer = Data()
        let headDeadline = Date().addingTimeInterval(10)
        while Date() < headDeadline, !headBuffer.contains(Data("\r\n\r\n".utf8)) {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            headBuffer.append(contentsOf: chunk[0..<n])
        }
        XCTAssertTrue(headBuffer.contains(Data("101".utf8)))
        // 101 之后同段到达的帧字节必须保留（本地 mock 响应极快）。
        var frameBuffer = Data()
        if let headEnd = headBuffer.range(of: Data("\r\n\r\n".utf8)) {
            frameBuffer = headBuffer.subdata(in: headEnd.upperBound..<headBuffer.endIndex)
        }
        var receiveTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))


        func sendFrame(_ payload: Data) {
            let frame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
            frame.withUnsafeBytes { raw in
                _ = Darwin.send(fd, raw.baseAddress, frame.count, 0)
            }
        }
        let createBody: [String: Any] = [
            "type": "response.create", "model": "relay/slow", "stream": true,
            "input": [["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": "长任务"]]]],
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: createBody))

        // 等待 response.created 帧回流（说明轮次已建立、SSE 消费中）。
        // 客户端模式解码器（服务端帧不掩码）；整个测试共用一个实例以保留分片状态。
        let clientDecoder = WebSocketFrameDecoder(requireMasking: false)
        func readFrames(timeout: TimeInterval, initial: Data = Data()) -> [[String: Any]] {
            var events: [[String: Any]] = []
            var buffer = initial
            let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                if let frames = try? clientDecoder.feed(buffer) {
                    buffer = Data()
                    for frame in frames {
                        if frame.opcode == 0x8 { return events }
                        if frame.opcode == 0x1,
                           let object = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] {
                            events.append(object)
                        }
                    }
                }
                if events.contains(where: {
                    ["response.incomplete", "response.completed", "response.failed", "error"].contains($0["type"] as? String ?? "")
                }) { break }
                var chunk = [UInt8](repeating: 0, count: 65536)
                let n = recv(fd, &chunk, chunk.count, 0)
                if n <= 0 { continue }
                buffer.append(contentsOf: chunk[0..<n])
            }
            return events
        }
        let createdFrames = readFrames(timeout: 15, initial: frameBuffer)
        XCTAssertTrue(createdFrames.contains(where: { ($0["type"] as? String) == "response.created" }),
                      "应先收到 created 帧: \(createdFrames.map { $0["type"] ?? "?" })")

        // 生成中途发送 interrupt（response_id 必须匹配当前轮次登记的值）。
        let interrupt: [String: Any] = [
            "type": "response.interrupt",
            "response_id": "resp_mock_turn_1",
            "mode": "discard_partial_items",
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: interrupt))

        let interruptFrames = readFrames(timeout: 15)
        let types = interruptFrames.map { $0["type"] as? String ?? "?" }
        XCTAssertTrue(types.contains("response.interrupt.accepted"), "types=\(types)")
        XCTAssertTrue(types.contains("response.incomplete"), "types=\(types)")
        XCTAssertEqual(types.filter { $0 == "response.completed" }.count, 0, "中断后不应出现 completed 终态")

        // 上游连接被真正断开（生成中止，不再继续计费）。
        let disconnectDeadline = Date().addingTimeInterval(10)
        while Date() < disconnectDeadline, !mock.clientDisconnected {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(mock.clientDisconnected, "interrupt 应取消上游生成连接")
    }

    // MARK: - 审查三轮回归

    /// HTTPConnection 双重关闭安全：onClientGone 仅触发一次，重复 close 不崩溃。
    func testConnectionDoubleCloseIsSafe() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let connection = HTTPConnection(fileDescriptor: fd)
        var goneCount = 0
        let lock = NSLock()
        connection.onClientGone = {
            lock.lock(); goneCount += 1; lock.unlock()
        }
        connection.close()
        connection.close()  // 第二次必须无副作用、不崩溃
        connection.markGone()
        lock.lock()
        XCTAssertEqual(goneCount, 1, "onClientGone 必须只触发一次")
        lock.unlock()
        Darwin.close(fd)  // 测试侧清理（connection.close 只 shutdown 不 close）
    }

    func testWebSocketInterruptImmediatelyAfterCreate() async throws {
        // 竞争回归：create 与 interrupt 背靠背发送（登记握手必须保证 interrupt
        // 能取消实际轮次），上游连接被真正中止。
        let mock = try HoldOpenUpstream(port: Int.random(in: 50000...51000))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "slow", displayName: "S")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")

        let serverPort = UInt16(51700 + Int.random(in: 0...600))
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses",
                  case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
                RouterHTTPServer.writeSimpleError(connection, status: 426, message: "upgrade_required")
                return
            }
            let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
            let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(Data(head.utf8))
            let session = ResponsesWebSocketSession(
                connection: connection,
                dispatcherProvider: { dispatcher },
                upgradeHeaders: request.headers)
            session.runBlocking()
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = serverPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let clientDecoder = WebSocketFrameDecoder(requireMasking: false)
        let handshake = "GET /v1/responses HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer \(callerSecret!)\r\nOpenAI-Beta: responses_websockets=2026-02-06\r\n\r\n"
        let handshakeData = Data(handshake.utf8)
        handshakeData.withUnsafeBytes { raw in
            _ = Darwin.send(fd, raw.baseAddress, handshakeData.count, 0)
        }
        var headBuffer = Data()
        let headDeadline = Date().addingTimeInterval(10)
        while Date() < headDeadline, !headBuffer.contains(Data("\r\n\r\n".utf8)) {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            headBuffer.append(contentsOf: chunk[0..<n])
        }
        XCTAssertTrue(headBuffer.contains(Data("101".utf8)))
        var frameBuffer = Data()
        if let headEnd = headBuffer.range(of: Data("\r\n\r\n".utf8)) {
            frameBuffer = headBuffer.subdata(in: headEnd.upperBound..<headBuffer.endIndex)
        }
        var receiveTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        func sendFrame(_ payload: Data) {
            let frame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
            frame.withUnsafeBytes { raw in
                _ = Darwin.send(fd, raw.baseAddress, frame.count, 0)
            }
        }

        // 背靠背：create 后立即 interrupt（不等待 created 帧）。
        let createBody: [String: Any] = [
            "type": "response.create", "model": "relay/slow", "stream": true,
            "input": [["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": "长任务"]]]],
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: createBody))
        let interrupt: [String: Any] = [
            "type": "response.interrupt",
            "response_id": "pending",
            "mode": "discard_partial_items",
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: interrupt))

        var events: [[String: Any]] = []
        var buffer = frameBuffer
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let frames = try? clientDecoder.feed(buffer) {
                buffer = Data()
                for frame in frames {
                    if frame.opcode == 0x8 { break }
                    if frame.opcode == 0x1,
                       let object = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] {
                        events.append(object)
                    }
                }
            }
            if events.contains(where: { ($0["type"] as? String) == "response.incomplete" }) { break }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n > 0 { buffer.append(contentsOf: chunk[0..<n]) }
        }
        let types = events.map { $0["type"] as? String ?? "?" }
        XCTAssertTrue(types.contains("response.interrupt.accepted"), "立即中断必须被接受: \(types)")
        XCTAssertTrue(types.contains("response.incomplete"), "中断后应有单一终态: \(types)")
        XCTAssertEqual(types.filter { $0 == "response.completed" }.count, 0)

        // 极早中断的两种合法结果（取决于 interrupt 与上游建连的先后）：
        // a) 上游已连接 → 连接被中止（clientDisconnected）；b) dispatch 继承
        // 取消状态、上游连接从未建立（无连接可中止）。共同不变量：单一终态
        // 且没有 completed。上游连接建立后中断的断开验证由
        // testWebSocketInterruptCancelsUpstreamGeneration 覆盖。
        let disconnectDeadline = Date().addingTimeInterval(3)
        while Date() < disconnectDeadline, !mock.clientDisconnected {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if !mock.clientDisconnected {
            // 从未建连路径：不存在需要断开的上游连接，视为合法。
            XCTAssertFalse(types.contains("response.completed"))
        } else {
            XCTAssertTrue(true)
        }
    }

    func testWebSocketInterruptWithWrongResponseIDIsRejected() async throws {
        let mock = try HoldOpenUpstream(port: Int.random(in: 50000...51000))
        defer { mock.stop() }
        try installEndpoint(
            baseURL: "http://127.0.0.1:\(mock.port)/v1",
            models: [RouterEndpointModel.standard(modelID: "slow", displayName: "S")])
        let dispatcher = makeDispatcher(nativeBaseURL: "http://127.0.0.1:\(mock.port)")

        let serverPort = UInt16(52300 + Int.random(in: 0...600))
        let server = RouterHTTPServer(port: serverPort) { [dispatcher] request, connection in
            guard request.path == "/v1/responses",
                  case .accept(let key) = ResponsesWebSocketEdge.validateUpgrade(request: request) else {
                RouterHTTPServer.writeSimpleError(connection, status: 426, message: "upgrade_required")
                return
            }
            let accept = ResponsesWebSocketEdge.acceptHeaderValue(for: key)
            let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(Data(head.utf8))
            let session = ResponsesWebSocketSession(
                connection: connection,
                dispatcherProvider: { dispatcher },
                upgradeHeaders: request.headers)
            session.runBlocking()
        }
        XCTAssertTrue(server.start())
        defer { server.stop() }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = serverPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let clientDecoder = WebSocketFrameDecoder(requireMasking: false)
        let handshake = "GET /v1/responses HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer \(callerSecret!)\r\nOpenAI-Beta: responses_websockets=2026-02-06\r\n\r\n"
        let handshakeData = Data(handshake.utf8)
        handshakeData.withUnsafeBytes { raw in
            _ = Darwin.send(fd, raw.baseAddress, handshakeData.count, 0)
        }
        var headBuffer = Data()
        let headDeadline = Date().addingTimeInterval(10)
        while Date() < headDeadline, !headBuffer.contains(Data("\r\n\r\n".utf8)) {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            headBuffer.append(contentsOf: chunk[0..<n])
        }
        XCTAssertTrue(headBuffer.contains(Data("101".utf8)))
        var frameBuffer = Data()
        if let headEnd = headBuffer.range(of: Data("\r\n\r\n".utf8)) {
            frameBuffer = headBuffer.subdata(in: headEnd.upperBound..<headBuffer.endIndex)
        }
        var receiveTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        func sendFrame(_ payload: Data) {
            let frame = WebSocketFrameEncoder.encode(fin: true, opcode: 0x1, payload: payload, masked: true)
            frame.withUnsafeBytes { raw in
                _ = Darwin.send(fd, raw.baseAddress, frame.count, 0)
            }
        }
        func readUntil(kind: String, timeout: TimeInterval, initial: Data) -> ([[String: Any]], Data) {
            var events: [[String: Any]] = []
            var buffer = initial
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let frames = try? clientDecoder.feed(buffer) {
                    buffer = Data()
                    for frame in frames {
                        print("T3-DEBUG frame opcode=\(frame.opcode) payload=\(String(decoding: frame.payload.prefix(60), as: UTF8.self))")
                        if frame.opcode == 0x8 { return (events, buffer) }
                        if frame.opcode == 0x1,
                           let object = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] {
                            events.append(object)
                        }
                    }
                }
                if events.contains(where: { ($0["type"] as? String) == kind }) { return (events, buffer) }
                var chunk = [UInt8](repeating: 0, count: 65536)
                let n = recv(fd, &chunk, chunk.count, 0)
                if n > 0 {
                    print("T3-DEBUG recv n=\(n) head=\(chunk.prefix(6).map { String(format: "%02x", $0) }.joined())")
                    buffer.append(contentsOf: chunk[0..<n])
                }
            }
            return (events, buffer)
        }

        // 第一轮：建立响应（拿到真实 response_id）。
        let createBody: [String: Any] = [
            "type": "response.create", "model": "relay/slow", "stream": true,
            "input": [["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": "长任务"]]]],
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: createBody))
        let (createdEvents, _) = readUntil(kind: "response.created", timeout: 15, initial: frameBuffer)
        let realID: String = {
            guard let created = createdEvents.first(where: { ($0["type"] as? String) == "response.created" }),
                  let response = created["response"] as? [String: Any],
                  let id = response["id"] as? String else { return "" }
            return id
        }()
        XCTAssertFalse(realID.isEmpty, "应先收到 created 事件")

        // 错误 response_id 的中断必须被 409 拒绝，且轮次继续（上游未断开）。
        let wrongInterrupt: [String: Any] = [
            "type": "response.interrupt",
            "response_id": "resp_wrong_id_000",
            "mode": "discard_partial_items",
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: wrongInterrupt))
        let (rejectedEvents, bufferAfterReject) = readUntil(kind: "error", timeout: 15, initial: Data())
        XCTAssertTrue(rejectedEvents.contains(where: {
            ($0["type"] as? String) == "error"
                && (($0["status"] as? NSNumber)?.intValue == 409
                    || ($0["status"] as? Int) == 409)
        }), "错误 response_id 应被 409 拒绝: \(rejectedEvents.map { $0["type"] ?? "?" })")
        XCTAssertFalse(mock.clientDisconnected, "被拒绝的中断不应中止上游生成")

        // 正确 response_id 的中断正常取消。
        let correctInterrupt: [String: Any] = [
            "type": "response.interrupt",
            "response_id": realID,
            "mode": "discard_partial_items",
        ]
        sendFrame(try JSONSerialization.data(withJSONObject: correctInterrupt))
        let (acceptedEvents, _) = readUntil(kind: "response.incomplete", timeout: 15, initial: bufferAfterReject)
        XCTAssertTrue(acceptedEvents.contains(where: { ($0["type"] as? String) == "response.interrupt.accepted" }))
        XCTAssertTrue(acceptedEvents.contains(where: { ($0["type"] as? String) == "response.incomplete" }))
        let disconnectDeadline = Date().addingTimeInterval(10)
        while Date() < disconnectDeadline, !mock.clientDisconnected {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(mock.clientDisconnected)
    }

    func testSSEEventParser() {
        var parser = SSEEventParser()
        let chunk = Data("data: {\"a\":1}\n\ndata: [DONE]\n\nevent: x\ndata: {\"b\":2}\n\n".utf8)
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(String(decoding: events[0], as: UTF8.self).contains("\"a\":1"))
        XCTAssertTrue(String(decoding: events[1], as: UTF8.self).contains("\"b\":2"))
    }
}

/// HTTP 回环测试的共享响应写回。
enum RouterServiceTestsSupport {
    static func writeResult(_ result: DispatchResult, to connection: HTTPConnection) async {
        let reason = RouterHTTPServer.reasonPhrase(result.status)
        let head = "HTTP/1.1 \(result.status) \(reason)\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n"
        connection.send(Data(head.utf8))
        do {
            for try await chunk in result.stream {
                var frame = Data("\(String(chunk.count, radix: 16))\r\n".utf8)
                frame.append(chunk)
                frame.append(Data("\r\n".utf8))
                connection.send(frame)
            }
        } catch { /* 回环测试：错误流按关闭处理 */ }
        connection.send(Data("0\r\n\r\n".utf8)) { connection.close() }
    }
}

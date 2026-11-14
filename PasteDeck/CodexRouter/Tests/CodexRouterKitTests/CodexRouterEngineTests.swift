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

    /// 请求记录器（init 期闭包捕获的安全载体）。
    final class RequestRecorder {
        private let lock = NSLock()
        private var stored: HTTPRequest?
        func record(_ request: HTTPRequest) { lock.withLock { stored = request } }
        func latest() -> HTTPRequest? { lock.withLock { stored } }
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
                connection: connection, dispatcher: dispatcher, upgradeHeaders: request.headers)
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
                print("RAWTEST 收到 \(frames.count) 帧: opcodes=\(frames.map { $0.opcode }) payloadHead=\(String(decoding: frames[0].payload.prefix(80), as: UTF8.self))")
                break
            }
        }
        XCTAssertGreaterThanOrEqual(received.count, 2, "服务器回帧缺失；首字节: \(String(decoding: received.prefix(60), as: UTF8.self))")
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

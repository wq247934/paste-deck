//
//  ResponsesWebSocketEdge.swift
//  PasteDeck
//
//  Responses WebSocket 边缘：Codex 客户端（provider 配置 supports_websockets=true
//  时）以一条长连接承载轮次。边缘只做协议翻译——每个完整请求重新进入
//  分发器，路由、凭据隔离、取消、错误形状都只有一份实现。
//  协议：responses_websockets=2026-02-06（对齐 responses-websocket.mjs）。
//

import Foundation
import CommonCrypto
import os

/// WS 升级握手校验结果。
enum WebSocketUpgradeOutcome {
    case accept(key: String)
    case reject(status: Int, message: String)
}

enum ResponsesWebSocketEdge {

    /// 校验升级请求（Origin 拒绝、方法/头校验、协议令牌）。
    static func validateUpgrade(request: HTTPRequest) -> WebSocketUpgradeOutcome {
        if request.header("origin") != nil || request.header("sec-fetch-site") != nil {
            return .reject(status: 403, message: "Browser-originated WebSocket requests are not accepted.")
        }
        guard request.method == "GET",
              request.header("upgrade")?.lowercased() == "websocket",
              request.header("connection")?.lowercased().split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }).contains("upgrade") == true,
              request.header("sec-websocket-version") == "13" else {
            return .reject(status: 426, message: "WebSocket upgrade request malformed.")
        }
        guard let key = request.header("sec-websocket-key"), Self.validSecWebSocketKey(key) else {
            return .reject(status: 426, message: "Missing or invalid Sec-WebSocket-Key.")
        }
        guard let beta = request.header("openai-beta"),
              beta.components(separatedBy: ",")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .contains(CodexRouterConstants.responsesWebSocketBeta) else {
            return .reject(status: 426, message: "Missing \(CodexRouterConstants.responsesWebSocketBeta) protocol token in OpenAI-Beta.")
        }
        return .accept(key: key)
    }

    static func acceptHeaderValue(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = Data((key + magic).utf8)
        let digest = SHA1(combined)
        return digest.base64EncodedString()
    }

    static func validSecWebSocketKey(_ key: String) -> Bool {
        guard key.count == 24 else { return false }
        guard let decoded = Data(base64Encoded: key) else { return false }
        return decoded.count == 16
    }

    /// SHA1 摘要（CommonCrypto）。
    static func SHA1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: 20)
        data.withUnsafeBytes { raw in
            _ = CC_SHA1(raw.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
}

/// 单条 WS 连接的会话：严格顺序处理请求（每连接同一时刻最多一个在途轮次）。
final class ResponsesWebSocketSession {
    static let maxQueuedRequests = 2
    static let maxContinuationEntries = 64
    static let maxContinuationBytes = 8 * 1024 * 1024

    private let connection: HTTPConnection
    private let dispatcher: ResponsesDispatcher
    private let upgradeHeaders: [String: String]
    private let decoder = WebSocketFrameDecoder()
    /// previous_response_id → {input, output} 基线。
    private var continuations: [String: [String: Any]] = [:]
    private var continuationOrder: [String] = []
    private struct SessionState {
        /// 串行链尾：新请求排队等待前一个完成后才执行（严格 FIFO）。
        var tail: Task<Void, Never>?
        /// 排队深度（含在途），超过上限直接关闭连接。
        var pendingRequests = 0
        /// 当前在途分发任务（interrupt 只取消它——串行化后同一时刻最多一个）。
        var currentDispatch: Task<DispatchResult, Never>?
        var closed = false
    }

    private let state = OSAllocatedUnfairLock<SessionState>(initialState: SessionState())

    init(connection: HTTPConnection, dispatcher: ResponsesDispatcher, upgradeHeaders: [String: String]) {
        self.connection = connection
        self.dispatcher = dispatcher
        self.upgradeHeaders = upgradeHeaders
    }



    /// 阻塞式接收循环（运行在连接线程上）。
    func runBlocking() {
        var buffer = Data()
        while !isClosed && !connection.isClosed {
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            let n = recv(connection.fileDescriptor, &chunk, chunk.count, 0)
            if n <= 0 {
                if errno == EINTR { continue }
                transportClosed()
                return
            }
            buffer.append(contentsOf: chunk[0..<n])
            do {
                let frames = try decoder.feed(Data(buffer))
                buffer = Data()
                for frame in frames {
                    handleFrame(frame)
                    if isClosed { return }
                }
            } catch WebSocketFrameError.binaryFrame {
                close(code: .unsupportedData, reason: "Binary messages are not supported")
                return
            } catch WebSocketFrameError.oversizedMessage {
                close(code: .messageTooBig, reason: "Message too large")
                return
            } catch {
                close(code: .protocolError, reason: "Protocol violation")
                return
            }
        }
    }

    private func handleFrame(_ frame: WebSocketFrame) {
        switch frame.opcode {
        case 0x9: // ping → pong
            connection.send(WebSocketFrameEncoder.pongFrame(frame.payload))
        case 0xA: // pong → ignore
            break
        case 0x8: // close → echo and finish
            let payload = frame.payload
            connection.send(WebSocketFrameEncoder.closeFrame(
                code: .normal,
                reason: payload.count >= 2 ? String(data: payload.dropFirst(2), encoding: .utf8) ?? "" : ""))
            close(code: .normal)
        case 0x1:
            handleTextMessage(frame.payload)
        default:
            break
        }
    }

    private func handleTextMessage(_ payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            sendErrorFrame(status: 400, type: "invalid_request_error", message: "Frame is not a JSON object.")
            return
        }
        switch object["type"] as? String {
        case "response.create":
            enqueue { await self.processResponseCreate(object) }
        case "response.interrupt":
            handleInterrupt(object)
        default:
            sendErrorFrame(status: 400, type: "unsupported_websocket_event", message: "Unknown event type.")
        }
    }

    /// 严格串行：请求按到达顺序链式执行，两个 response.create 不会并发
    /// 修改 latestRequestInput / continuations。
    private func enqueue(_ work: @escaping () async -> Void) {
        let overflow = state.withLock { state -> Task<Void, Never>? in
            guard state.pendingRequests < Self.maxQueuedRequests else { return nil }
            state.pendingRequests += 1
            let previousTail = state.tail
            let chained = Task { [weak self] in
                await previousTail?.value
                guard let self, !self.isClosed else { return }
                await work()
                self.state.withLock { $0.pendingRequests -= 1 }
            }
            state.tail = chained
            return chained
        }
        if overflow == nil {
            close(code: .policyViolation, reason: "Too many queued requests")
        }
    }

    var isClosed: Bool {
        state.withLock { $0.closed }
    }

    // MARK: - response.create

    private func processResponseCreate(_ object: [String: Any]) async {
        var request = object
        request.removeValue(forKey: "type")
        request.removeValue(forKey: "generate")

        // 增量请求：previous_response_id 指向连接内存储的基线。
        var baselineItems: [[String: Any]] = []
        let responseID = request["previous_response_id"] as? String
        if let responseID {
            guard let baseline = continuations[responseID] else {
                sendErrorFrame(status: 409, type: "previous_response_not_found", message: "No stored baseline for this previous_response_id on this connection.")
                return
            }
            baselineItems = (baseline["input"] as? [[String: Any]] ?? [])
                + (baseline["output"] as? [[String: Any]] ?? [])
            request.removeValue(forKey: "previous_response_id")
        }
        if !baselineItems.isEmpty {
            let suffix = request["input"] as? [[String: Any]] ?? []
            request["input"] = baselineItems + suffix
        }

        // 预热请求：立即返回零用量合成事件。
        if (object["generate"] as? Bool) == false {
            sendPrewarmEvents()
            return
        }

        guard JSONSerialization.isValidJSONObject(request),
              let bodyData = try? JSONSerialization.data(withJSONObject: request) else {
            sendErrorFrame(status: 400, type: "invalid_request_error", message: "Frame body is not a valid request.")
            return
        }

        // 暂存基线 input（response.completed 时与 output 一起登记）。
        latestRequestInput = request["input"] as? [[String: Any]] ?? []

        let dispatchRequest = DispatchRequest(
            method: "POST",
            path: "/v1/responses",
            headers: upgradeHeaders,
            body: bodyData
        )
        // 在途分发单独建 Task，使 response.interrupt 能精确取消当前轮次
        // （串行链保证同一时刻只有一个在途轮次）。
        let dispatchTask = Task { await dispatcher.dispatch(dispatchRequest) }
        state.withLock { $0.currentDispatch = dispatchTask }
        let result = await dispatchTask.value
        state.withLock { $0.currentDispatch = nil }

        if result.status >= 400 {
            latestRequestInput = nil
            await relayErrorFrame(status: result.status, headers: result.headers, stream: result.stream)
            return
        }

        await relaySseAsFrames(stream: result.stream) { [weak self] event in
            self?.rememberBaseline(event: event)
        }
    }

    /// 从 response.completed 事件记录 {input, output} 基线。
    private func rememberBaseline(event: [String: Any]) {
        guard let type = event["type"] as? String, type == "response.completed",
              let response = event["response"] as? [String: Any],
              let responseID = response["id"] as? String, !responseID.isEmpty else { return }
        // 基线 input 取自最近一次请求体（由 processResponseCreate 在入队时暂存）。
        guard let input = latestRequestInput, let output = response["output"] as? [[String: Any]] else { return }
        let encoded = (try? JSONSerialization.data(withJSONObject: ["input": input, "output": output])) ?? Data()
        guard encoded.count < Self.maxContinuationBytes else { return }
        continuations[responseID] = ["input": input, "output": output]
        continuationOrder.append(responseID)
        latestRequestInput = nil
        while continuationOrder.count > Self.maxContinuationEntries {
            let evicted = continuationOrder.removeFirst()
            continuations.removeValue(forKey: evicted)
        }
    }

    private var latestRequestInput: [[String: Any]]?

    // MARK: - response.interrupt

    private func handleInterrupt(_ object: [String: Any]) {
        guard let responseID = object["response_id"] as? String,
              let mode = object["mode"] as? String else {
            sendErrorFrame(status: 400, type: "invalid_request_error", message: "response.interrupt requires response_id and mode.")
            return
        }
        // 只取消当前在途轮次（串行链保证它就是 interrupt 指向的那个）。
        state.withLock { $0.currentDispatch }?.cancel()
        var accepted: [String: Any] = [
            "type": "response.interrupt.accepted",
            "response_id": responseID,
        ]
        _ = mode
        accepted["sequence_number"] = nextSequence()
        sendJSON(accepted)
        // 中断后的终态：response.incomplete（对齐 finishInterrupted 语义）。
        let incomplete: [String: Any] = [
            "type": "response.incomplete",
            "response_id": responseID,
            "incomplete_details": ["reason": "interrupted"],
        ]
        sendJSON(incomplete)
    }

    // MARK: - SSE → 帧中继

    private func relaySseAsFrames(
        stream: AsyncThrowingStream<Data, Error>,
        onTerminal: @escaping ([String: Any]) -> Void
    ) async {
        var parser = SSEEventParser()
        do {
            for try await chunk in stream {
                for event in parser.feed(chunk) {
                    guard let object = try? JSONSerialization.jsonObject(with: event) as? [String: Any] else { continue }
                    sendJSON(object)
                    if let type = object["type"] as? String,
                       type == "response.completed" || type == "response.failed" || type == "response.incomplete" {
                        onTerminal(object)
                    }
                }
                if connection.hasBackpressure {
                    // 简单背压：等待写队列消化。
                    while connection.hasBackpressure, !isClosed {
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                }
            }
        } catch is CancellationError {
            // 上游被中断取消：帧已由 interrupt 流程发出。
        } catch {
            sendErrorFrame(status: 502, type: "local_router_error", message: "Upstream stream failed: \(error.localizedDescription)")
        }
    }

    private func relayErrorFrame(
        status: Int, headers: [String: String], stream: AsyncThrowingStream<Data, Error>
    ) async {
        // 错误响应：完整 JSON 读出，折叠进 error 帧。
        var collected = Data()
        do {
            for try await chunk in stream { collected.append(chunk); if collected.count > (1 << 20) { break } }
        } catch { /* 读失败按空错误体处理 */ }
        var errorObject: [String: Any] = [
            "type": "upstream_error",
            "message": "Upstream returned status \(status).",
        ]
        if let upstream = try? JSONSerialization.jsonObject(with: collected) as? [String: Any],
           let nested = upstream["error"] as? [String: Any] {
            errorObject = nested
        }
        var frame: [String: Any] = [
            "type": "error",
            "status": status,
            "error": errorObject,
        ]
        if !headers.isEmpty { frame["headers"] = headers }
        sendJSON(frame)
    }

    // MARK: - 发送

    private var sequenceCounter = 0

    private func nextSequence() -> Int {
        sequenceCounter += 1
        return sequenceCounter
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        connection.send(WebSocketFrameEncoder.textFrame(data))
    }

    private func sendErrorFrame(status: Int, type: String, message: String) {
        let frame: [String: Any] = [
            "type": "error",
            "status": status,
            "error": ["type": type, "message": message],
        ]
        sendJSON(frame)
    }

    private func sendPrewarmEvents() {
        let responseID = "resp_router_prewarm_\(UUID().uuidString)"
        sendJSON([
            "type": "response.created",
            "response": ["id": responseID, "status": "in_progress", "output": []],
        ])
        sendJSON([
            "type": "response.completed",
            "response": ["id": responseID, "status": "completed", "output": [], "usage": ["input_tokens": 0, "output_tokens": 0]],
        ])
    }

    // MARK: - 关闭

    private func close(code: WebSocketCloseCode, reason: String = "") {
        let inFlight = state.withLock { state -> Task<DispatchResult, Never>? in
            state.closed = true
            return state.currentDispatch
        }
        inFlight?.cancel()
        connection.send(WebSocketFrameEncoder.closeFrame(code: code, reason: reason)) {
            self.connection.close()
        }
    }

    private func transportClosed() {
        let inFlight = state.withLock { state -> Task<DispatchResult, Never>? in
            state.closed = true
            return state.currentDispatch
        }
        inFlight?.cancel()
        connection.close()
    }
}

/// SSE 字节流解析器：行级解析，事件边界为空行。
/// 行终止符支持 \n、\r\n 与 \r；字段只取 data:（事件类型由 JSON type 承载）。
struct SSEEventParser {
    private var buffer = [UInt8]()
    private var dataLines: [String] = []

    mutating func feed(_ chunk: Data) -> [Data] {
        buffer.append(contentsOf: [UInt8](chunk))
        var events: [Data] = []
        while let line = Self.takeLine(&buffer) {
            if line.isEmpty {
                if let event = Self.event(from: dataLines) {
                    events.append(event)
                }
                dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
            // event:/id:/retry: 等字段不影响按 JSON type 分帧的语义，忽略。
        }
        return events
    }

    /// 取一行（含终止符消费）；行尾 \r\n / \n / \r 均视为终止。
    static func takeLine(_ buffer: inout [UInt8]) -> String? {
        guard let terminator = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return nil }
        var line = buffer[..<terminator]
        var consumed = terminator + 1
        // \r\n 视为单个终止符。
        if buffer[terminator] == 0x0D, consumed < buffer.count, buffer[consumed] == 0x0A {
            consumed += 1
        }
        if line.last == 0x0D { line = line.dropLast() }
        buffer.removeFirst(consumed)
        return String(decoding: line, as: UTF8.self)
    }

    static func event(from lines: [String]) -> Data? {
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: "\n")
        guard joined != "[DONE]" else { return nil }
        return Data(joined.utf8)
    }
}

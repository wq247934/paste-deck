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
    private var currentTask: Task<Void, Never>?
    private var pendingRequests = 0
    private var closed = false

    init(connection: HTTPConnection, dispatcher: ResponsesDispatcher, upgradeHeaders: [String: String]) {
        self.connection = connection
        self.dispatcher = dispatcher
        self.upgradeHeaders = upgradeHeaders
    }



    /// 阻塞式接收循环（运行在连接线程上）。
    func runBlocking() {
        var buffer = Data()
        while !closed && !connection.isClosed {
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
                    if closed { return }
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

    private func enqueue(_ work: @escaping () async -> Void) {
        if pendingRequests >= Self.maxQueuedRequests {
            close(code: .policyViolation, reason: "Too many queued requests")
            return
        }
        pendingRequests += 1
        currentTask = Task { [weak self] in
            await work()
            self?.pendingRequests -= 1
        }
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
        let result = await dispatcher.dispatch(dispatchRequest)

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
        currentTask?.cancel()
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
                    while connection.hasBackpressure, !closed {
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
        guard !closed else { return }
        closed = true
        currentTask?.cancel()
        connection.send(WebSocketFrameEncoder.closeFrame(code: code, reason: reason)) {
            self.connection.close()
        }
    }

    private func transportClosed() {
        guard !closed else { return }
        closed = true
        currentTask?.cancel()
        connection.close()
    }
}

/// SSE 字节流解析器：按空行分隔事件，提取 data: 行内容。
struct SSEEventParser {
    private var buffer = Data()

    mutating func feed(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var events: [Data] = []
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let block = buffer[..<range.lowerBound]
            buffer = buffer.subdata(in: range.upperBound..<buffer.endIndex)
            let event = Self.dataPayload(from: block)
            if let event { events.append(event) }
        }
        return events
    }

    /// 从一个事件块提取 data: 负载（合并多行）。
    static func dataPayload(from block: Data) -> Data? {
        guard let text = String(data: block, encoding: .utf8) else { return nil }
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            var trimmed = line
            if trimmed.hasSuffix("\r") { trimmed.removeLast() }
            if trimmed.hasPrefix("data:") {
                lines.append(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: "\n")
        guard joined != "[DONE]" else { return nil }
        return Data(joined.utf8)
    }
}

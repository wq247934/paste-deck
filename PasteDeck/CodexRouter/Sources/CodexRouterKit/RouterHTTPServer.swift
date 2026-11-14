//
//  RouterHTTPServer.swift
//  PasteDeck
//
//  本地路由的 HTTP/1.1 服务器：POSIX socket 实现（本机网络扩展环境下
//  Network.framework 的 NWListener 会报 EINVAL，POSIX bind 实测正常）。
//  仅监听 127.0.0.1；支持 Content-Length / chunked 请求体、SSE 流式
//  响应、keep-alive、客户端断开取消。WebSocket 升级由响应层移交。
//

import Foundation

/// 解析后的 HTTP 请求。
struct HTTPRequest {
    var method: String
    var path: String
    var query: String?
    var httpVersion: String
    /// 头名（小写）→ 值。同名多值时以逗号连接。
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var isChunked: Bool {
        get { headers["x-internal-chunked"] == "1" }
        set { headers["x-internal-chunked"] = newValue ? "1" : "0" }
    }

    var expectedBodyBytes: Int {
        if isChunked { return Int.max }
        if let length = header("content-length"),
           let value = Int(length.trimmingCharacters(in: .whitespaces)) {
            return max(0, value)
        }
        return 0
    }

    /// 从 chunked 编码体解码完整内容。
    static func decodeChunked(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var result = Data()
        var index = 0
        func readLine() -> String? {
            guard index < bytes.count else { return nil }
            var line = Data()
            while index < bytes.count {
                if bytes[index] == 13, index + 1 < bytes.count, bytes[index + 1] == 10 {
                    index += 2
                    return String(decoding: line, as: UTF8.self)
                }
                line.append(bytes[index])
                index += 1
            }
            return nil
        }
        while index < bytes.count {
            guard let sizeLine = readLine() else { return nil }
            let sizeText = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
            if size == 0 {
                while index < bytes.count {
                    guard let trailer = readLine(), !trailer.isEmpty else { break }
                }
                return result
            }
            guard index + size <= bytes.count else { return nil }
            result.append(contentsOf: bytes[index..<(index + size)])
            index += size
            if index + 2 <= bytes.count, bytes[index] == 13, bytes[index + 1] == 10 {
                index += 2
            }
        }
        return nil
    }
}

/// 服务器持有的连接上下文（响应写回与升级移交）。
final class HTTPConnection {
    let fileDescriptor: Int32
    /// 串行化 send（SSE 写线程与控制流并发）。
    private let writeLock = NSLock()
    /// 客户端断开回调（用于中止上游转发）。
    var onClientGone: (() -> Void)?
    private var notifiedGone = false
    private let goneLock = NSLock()

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
        var noSigpipe: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
    }

    var isClosed: Bool {
        goneLock.lock(); defer { goneLock.unlock() }
        return notifiedGone
    }

    /// 满背压检测：SSE 写直发 socket，无应用层积压队列，恒为 false。
    var hasBackpressure: Bool { false }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        defer { completion?() }
        if data.isEmpty { return }
        let result = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            var sent = 0
            writeLock.lock()
            defer { writeLock.unlock() }
            while sent < data.count {
                let n = Darwin.send(fileDescriptor, base + sent, data.count - sent, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                sent += n
            }
            return sent
        }
        if result < 0 {
            markGone()
        }
    }

    /// 主动关闭。
    func close(afterWriting: Bool = true) {
        markGone()
        Darwin.close(fileDescriptor)
    }

    func markGone() {
        goneLock.lock()
        let first = !notifiedGone
        notifiedGone = true
        goneLock.unlock()
        if first {
            onClientGone?()
        }
    }
}

/// HTTP 请求处理器。
typealias HTTPHandler = (HTTPRequest, HTTPConnection) -> Void

/// 轻量 HTTP/1.1 服务器（POSIX socket，线程每连接）。
final class RouterHTTPServer {
    private let port: UInt16
    private let handler: HTTPHandler
    private var listenerFD: Int32 = -1
    private let stateLock = NSLock()
    private(set) var activeConnections = 0
    private var stopping = false

    init(port: UInt16, handler: @escaping HTTPHandler, queue: DispatchQueue? = nil) {
        self.port = port
        self.handler = handler
    }

    /// 启动监听（accept 循环在独立线程）。返回 false 表示端口被占用。
    @discardableResult
    func start() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listenerFD < 0, !stopping else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 64) == 0 else {
            Darwin.close(fd)
            return false
        }
        listenerFD = fd
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "pastedeck-codex-router.listener"
        thread.start()
        return true
    }

    func stop() {
        stateLock.lock()
        stopping = true
        let fd = listenerFD
        listenerFD = -1
        stateLock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let fd = listenerFD
            let stopped = stopping
            stateLock.unlock()
            if fd < 0 || stopped { return }
            var clientAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &length)
                }
            }
            if clientFD < 0 {
                if errno == EINTR { continue }
                return
            }
            stateLock.lock()
            activeConnections += 1
            stateLock.unlock()
            let thread = Thread { [weak self] in
                self?.serve(clientFD: clientFD)
            }
            thread.name = "pastedeck-codex-router.conn"
            thread.stackSize = 1 << 20
            thread.start()
        }
    }

    /// 单连接生命周期：keep-alive 逐请求解析与分发。
    private func serve(clientFD: Int32) {
        defer {
            Darwin.close(clientFD)
            stateLock.lock()
            activeConnections = max(0, activeConnections - 1)
            stateLock.unlock()
        }
        let connection = HTTPConnection(fileDescriptor: clientFD)
        var buffer = Data()

        while !connection.isClosed {
            // 1. 读到完整请求头。
            var headerRange: Range<Data.Index>?
            while true {
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    headerRange = range
                    break
                }
                guard buffer.count < (1 << 20) else {
                    RouterHTTPServer.writeSimpleError(connection, status: 431, message: "headers_too_large")
                    return
                }
                guard readMore(clientFD, into: &buffer) else { return }
            }
            let range = headerRange!
            let headData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            guard var request = RouterHTTPServer.parseHead(headData) else {
                RouterHTTPServer.writeSimpleError(connection, status: 400, message: "invalid_request")
                return
            }
            buffer = buffer.subdata(in: range.upperBound..<buffer.endIndex)

            // 2. 读请求体。
            if request.isChunked {
                var decoded: Data?
                var tooLarge = false
                while true {
                    if let parsed = HTTPRequest.decodeChunked(buffer) {
                        decoded = parsed
                        break
                    }
                    guard buffer.count < (1 << 26) else { tooLarge = true; break }
                    guard readMore(clientFD, into: &buffer) else { return }
                }
                if tooLarge {
                    RouterHTTPServer.writeSimpleError(connection, status: 413, message: "request_too_large")
                    return
                }
                request.body = decoded ?? Data()
                buffer = Data()
            } else {
                let needed = request.expectedBodyBytes
                while buffer.count < needed {
                    guard readMore(clientFD, into: &buffer) else { return }
                }
                request.body = buffer.prefix(needed)
                buffer = buffer.dropFirst(needed)
            }

            // 3. 分发（handler 可以流式写回；keep-alive 由下一个循环继续读）。
            handler(request, connection)
            if connection.isClosed { return }

            // Connection: close 或 HTTP/1.0 → 结束本连接。
            let wantsClose = (request.header("connection") ?? "").lowercased().contains("close")
            if wantsClose || request.httpVersion == "HTTP/1.0" {
                connection.close()
                return
            }
        }
    }

    private func readMore(_ fd: Int32, into buffer: inout Data) -> Bool {
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        let n = recv(fd, &chunk, chunk.count, 0)
        if n > 0 {
            buffer.append(contentsOf: chunk[0..<n])
            return true
        }
        return false
    }

    // MARK: - 静态解析与错误响应

    static func parseHead(_ data: Data) -> HTTPRequest? {
        guard let headText = String(data: data, encoding: .utf8) else { return nil }
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let version = String(parts[2])
        var path = target
        var query: String?
        if let questionIndex = target.firstIndex(of: "?") {
            path = String(target[..<questionIndex])
            query = String(target[target.index(after: questionIndex)...])
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }
        var request = HTTPRequest(
            method: method, path: path, query: query, httpVersion: version,
            headers: headers, body: Data())
        if let transferEncoding = request.header("transfer-encoding"),
           transferEncoding.lowercased().contains("chunked") {
            request.isChunked = true
        }
        return request
    }

    static func writeSimpleError(_ connection: HTTPConnection, status: Int, message: String) {
        let reason = reasonPhrase(status)
        let body = "{\"error\":{\"type\":\"\(message)\"}}"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(Data(body.utf8))
        connection.send(data) { connection.close() }
    }

    static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 426: return "Upgrade Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}

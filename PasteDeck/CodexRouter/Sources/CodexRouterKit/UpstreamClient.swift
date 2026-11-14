//
//  UpstreamClient.swift
//  PasteDeck
//
//  上游 HTTP 客户端：URLSession 流式转发，带代理与取消。
//  回环目标不走代理；SSE 以字节流形式回传给分发器。
//

import Foundation

/// 上游响应：状态、响应头（已过滤逐跳头）与原始字节流。
struct UpstreamResponse {
    let status: Int
    let headers: [String: String]
    let bytes: URLSession.AsyncBytes
    let task: URLSessionTask?
}

enum UpstreamError: LocalizedError {
    case invalidURL(String)
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "上游地址无效：\(url)"
        case .transportFailed(let detail):
            return "上游连接失败：\(detail)"
        }
    }
}

/// 逐跳响应头（不回传给调用方）。
let hopByHopResponseHeaders: Set<String> = [
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
    // URLSession 已透明解压（gzip/deflate/br），转发时按 chunked 重新分帧。
    "content-encoding", "content-length",
]

/// 上游转发客户端。
final class UpstreamClient {
    let session: URLSession

    init(proxy: RouterProxyConfig, proxyPassword: String?) {
        let configuration = ProxySupport.upstreamConfiguration(proxy: proxy, proxyPassword: proxyPassword)
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// 发起 POST，返回可流式读取的响应。请求体不得携带 Content-Encoding 之外
    /// 的伪头；调用方负责头白名单。
    func post(
        url: String,
        headers: [String: String],
        body: Data
    ) async throws -> UpstreamResponse {
        guard let requestURL = URL(string: url) else { throw UpstreamError.invalidURL(url) }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers {
            guard name.lowercased() != "host", name.lowercased() != "content-length" else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }
        // 流式响应：显式要求底层不缓冲。
        request.timeoutInterval = 600

        do {
            let (bytes, response) = try await session.bytes(
                for: request, delegate: nil)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw UpstreamError.transportFailed("非 HTTP 响应")
            }
            var headerMap: [String: String] = [:]
            for (field, value) in httpResponse.allHeaderFields {
                guard let name = field as? String else { continue }
                headerMap[name.lowercased()] = "\(value)"
            }
            return UpstreamResponse(
                status: httpResponse.statusCode,
                headers: headerMap,
                bytes: bytes,
                task: nil
            )
        } catch {
            throw UpstreamError.transportFailed(error.localizedDescription)
        }
    }

    /// 连通性测试：GET 一个 URL，返回状态与耗时。
    func probe(url: String, timeout: TimeInterval = 8) async -> (status: Int?, error: String?) {
        guard let requestURL = URL(string: url) else { return (nil, "地址无效") }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let startedAt = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            return (status, nil)
        } catch {
            _ = Date().timeIntervalSince(startedAt)
            return (nil, error.localizedDescription)
        }
    }
}

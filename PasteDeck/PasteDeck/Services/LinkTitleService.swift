//
//  LinkTitleService.swift
//  PasteDeck
//
//  Fetches representative web titles without blocking clipboard capture or UI.
//

import Foundation
import LinkPresentation

extension Notification.Name {
    static let linkTitleFetchingPreferenceChanged = Notification.Name("linkTitleFetchingPreferenceChanged")
}

enum LinkTitleNotification {
    static let enabledKey = "enabled"
}

enum LinkTitleFetchResult {
    case success(String)
    case unavailable
    case cancelled
}

@MainActor
final class LinkTitleService {
    static let shared = LinkTitleService()

    private static let maximumConcurrentRequests = 2
    private static let maximumQueuedRequests = 20
    private static let successCacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let failureCacheLifetime: TimeInterval = 60 * 60

    private final class PendingRequest {
        /// 待抓取的公共网页地址。
        let url: URL

        /// 去除 fragment 后用于去重和短期缓存的 URL key。
        let key: String

        /// 抓取完成后回传给剪贴板记录的结果回调。
        let completion: (LinkTitleFetchResult) -> Void

        init(url: URL, key: String, completion: @escaping (LinkTitleFetchResult) -> Void) {
            self.url = url
            self.key = key
            self.completion = completion
        }
    }

    private final class ActiveRequest {
        /// 当前网络请求对应的缓存 key。
        let key: String

        /// 每个请求独立的系统元数据提供器，可被取消。
        let provider: LPMetadataProvider

        /// 等待同一 URL 结果的所有剪贴板记录回调。
        var completions: [(LinkTitleFetchResult) -> Void]

        init(key: String, provider: LPMetadataProvider, completion: @escaping (LinkTitleFetchResult) -> Void) {
            self.key = key
            self.provider = provider
            self.completions = [completion]
        }
    }

    private struct CacheEntry {
        /// 规范化后的网页标题；nil 表示本次请求没有可用标题。
        let title: String?

        /// 本次成功或失败结果写入内存缓存的时间。
        let storedAt: Date
    }

    private var pendingRequests: [PendingRequest] = []
    private var activeRequests: [ActiveRequest] = []
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    func fetchTitle(for url: URL, completion: @escaping (LinkTitleFetchResult) -> Void) {
        guard Self.isEligible(url) else {
            completion(.unavailable)
            return
        }

        let key = Self.cacheKey(for: url)
        if let entry = cache[key], Self.isCacheEntryValid(entry) {
            if let title = entry.title {
                completion(.success(title))
            } else {
                completion(.unavailable)
            }
            return
        }

        if let activeRequest = activeRequests.first(where: { $0.key == key }) {
            activeRequest.completions.append(completion)
            return
        }

        pendingRequests.append(PendingRequest(url: url, key: key, completion: completion))
        if pendingRequests.count > Self.maximumQueuedRequests,
           let droppedRequest = pendingRequests.first {
            pendingRequests.removeFirst()
            droppedRequest.completion(.unavailable)
        }
        startNextRequests()
    }

    func cancelAll() {
        let activeRequestsToCancel = activeRequests
        activeRequests.removeAll()
        for activeRequest in activeRequestsToCancel {
            activeRequest.provider.cancel()
            activeRequest.completions.forEach { $0(.cancelled) }
        }

        let pendingRequestsToCancel = pendingRequests
        pendingRequests.removeAll()
        pendingRequestsToCancel.forEach { $0.completion(.cancelled) }
    }

    private func startNextRequests() {
        while activeRequests.count < Self.maximumConcurrentRequests,
              !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            if let activeRequest = activeRequests.first(where: { $0.key == request.key }) {
                activeRequest.completions.append(request.completion)
                continue
            }

            let provider = LPMetadataProvider()
            provider.shouldFetchSubresources = false
            provider.timeout = 3
            let activeRequest = ActiveRequest(key: request.key, provider: provider, completion: request.completion)
            activeRequests.append(activeRequest)

            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpShouldHandleCookies = false
            let requestKey = request.key
            provider.startFetchingMetadata(for: urlRequest) { [weak self] metadata, _ in
                let title = metadata?.title.flatMap(Self.normalizedTitle)
                Task { @MainActor [weak self] in
                    self?.finish(key: requestKey, title: title)
                }
            }
        }
    }

    private func finish(key: String, title: String?) {
        guard let index = activeRequests.firstIndex(where: { $0.key == key }) else { return }
        let activeRequest = activeRequests.remove(at: index)
        cache[key] = CacheEntry(title: title, storedAt: Date())
        let result: LinkTitleFetchResult = title.map(LinkTitleFetchResult.success) ?? .unavailable
        activeRequest.completions.forEach { $0(result) }
        startNextRequests()
    }

    private static func isCacheEntryValid(_ entry: CacheEntry) -> Bool {
        let lifetime = entry.title == nil ? failureCacheLifetime : successCacheLifetime
        return Date().timeIntervalSince(entry.storedAt) < lifetime
    }

    nonisolated static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host.contains("."),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"),
              !host.hasSuffix(".lan"),
              host != "localhost",
              !isIPAddress(host) else {
            return false
        }

        return true
    }

    nonisolated private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }

        let components = host.split(separator: ".")
        guard components.count == 4 else { return false }
        return components.allSatisfy { component in
            guard let value = Int(component) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func cacheKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    nonisolated private static func normalizedTitle(_ title: String) -> String? {
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(300))
    }
}

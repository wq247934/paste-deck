//
//  RouteTable.swift
//  PasteDeck
//
//  模型 slug → 上游路由表。来源：endpoints.json + credentials.json。
//  每次外部请求前检查文件 mtime，热更新，无需重启守护进程。
//  路由规则确定且可测试：slug 前缀 = 端点 id；未知带前缀 slug 永不转发官方。
//

import Foundation

/// 一条外部路由。
struct ExternalRoute {
    let slug: String
    let endpointID: String
    let upstreamModel: String
    let baseURL: String
    let apiKey: String
    let model: RouterEndpointModel
}

/// 路由表：从配置文件构建，热更新。
final class RouteTable {
    private let endpointsFileURL: URL
    private let credentialsFileURL: URL
    private let lock = NSLock()
    private var routes: [String: ExternalRoute] = [:]
    private var cachedMtime: (mtime: Date, size: Int)?
    private(set) var loadedAt: Date = .distantPast

    init(stateDirectory: URL) {
        self.endpointsFileURL = stateDirectory.appendingPathComponent("endpoints.json")
        self.credentialsFileURL = stateDirectory.appendingPathComponent("credentials.json")
    }

    /// slug → 路由（找不到返回 nil）。
    func route(for slug: String) -> ExternalRoute? {
        reloadIfNeeded()
        return lock.withLock { routes[slug] }
    }

    /// 当前全部启用路由（诊断用）。
    func allRoutes() -> [ExternalRoute] {
        reloadIfNeeded()
        return lock.withLock { Array(routes.values).sorted { $0.slug < $1.slug } }
    }

    /// 按端点前缀解析：用于给出更准确的拒绝错误。
    func endpointExists(_ prefix: String) -> Bool {
        reloadIfNeeded()
        return lock.withLock { routes.values.contains { $0.endpointID == prefix } }
    }

    private func reloadIfNeeded() {
        let fingerprint = Self.fileFingerprint(endpointsFileURL)
        guard let fingerprint = fingerprint else { return }
        let shouldReload = lock.withLock {
            cachedMtime.map { $0.mtime != fingerprint.mtime || $0.size != fingerprint.size } ?? true
        }
        guard shouldReload else { return }
        rebuild(fingerprint: fingerprint)
    }

    private func rebuild(fingerprint: (mtime: Date, size: Int)) {
        let store = RouterEndpointStore(stateDirectory: endpointsFileURL.deletingLastPathComponent())
        let document = store.load()
        let credentials = PrivateFile.readJSON(credentialsFileURL, as: RuntimeCredentialsDocument.self)
        var newRoutes: [String: ExternalRoute] = [:]
        for endpoint in document.endpoints where endpoint.enabled {
            guard let apiKey = credentials?.entries.first(where: { $0.endpointID == endpoint.id })?.apiKey,
                  !apiKey.isEmpty else { continue }
            for model in endpoint.models where model.enabled {
                let slug = SlugBuilder.slug(endpointID: endpoint.id, modelID: model.modelID)
                newRoutes[slug] = ExternalRoute(
                    slug: slug,
                    endpointID: endpoint.id,
                    upstreamModel: model.modelID,
                    baseURL: endpoint.baseURL,
                    apiKey: apiKey,
                    model: model
                )
            }
        }
        lock.withLock {
            routes = newRoutes
            cachedMtime = fingerprint
            loadedAt = Date()
        }
    }

    private static func fileFingerprint(_ url: URL) -> (mtime: Date, size: Int)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return (modified, size)
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

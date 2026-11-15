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
    private var cachedFingerprint: (endpoints: (mtime: Date, size: Int), credentials: (mtime: Date, size: Int)?)?
    /// 每次重建递增；代理配置变化时守护进程据此重建上游会话。
    public private(set) var revision: Int = 0
    /// 当前生效的代理配置（含凭据文件里的代理密码）。
    public private(set) var proxy: RouterProxyConfig = .standard()
    public private(set) var proxyPassword: String?
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

    public func reloadIfNeeded() {
        let endpointFingerprint = Self.fileFingerprint(endpointsFileURL)
        let credentialFingerprint = Self.fileFingerprint(credentialsFileURL)
        guard let endpointFingerprint else { return }
        let shouldReload = lock.withLock {
            cachedFingerprint.map {
                $0.endpoints.mtime != endpointFingerprint.mtime
                    || $0.endpoints.size != endpointFingerprint.size
                    || $0.credentials?.mtime != credentialFingerprint?.mtime
                    || $0.credentials?.size != credentialFingerprint?.size
            } ?? true
        }
        guard shouldReload else { return }
        rebuild(fingerprint: (endpointFingerprint, credentialFingerprint))
    }

    private func rebuild(fingerprint: (endpoints: (mtime: Date, size: Int), credentials: (mtime: Date, size: Int)?)) {
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
            proxy = document.proxy
            proxyPassword = credentials?.proxyPassword
            cachedFingerprint = fingerprint
            revision += 1
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

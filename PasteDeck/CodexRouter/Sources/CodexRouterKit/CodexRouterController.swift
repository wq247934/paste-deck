//
//  CodexRouterController.swift
//  PasteDeck
//
//  一键启用 / 关闭 / 恢复 的编排控制器（主程序侧）。
//  流程：
//  启用 = 冲突检测 → 登录检查 → 凭据物化 → 端口选择 → 守护进程启动
//        → 模型目录发布 → config.toml 托管切换 → 重启提示。
//  关闭 = config.toml 恢复 → 守护进程停止 → 凭据物化文件删除。
//  恢复 = 清理托管残留与孤立状态（备份只在结构损坏时使用，且从不覆盖
//        用户在备份之后的合法修改——恢复以"外科手术式移除托管块"为主）。
//

import Foundation

public enum RouterControllerError: LocalizedError, Equatable {
    case legacyRouterInstalled
    case notSignedIn
    case daemonBinaryMissing
    case daemonStartFailed(port: Int)
    case catalogPublishFailed(String)
    case endpointIDConflict(String)
    case noEndpoints

    public var errorDescription: String {
        switch self {
        case .legacyRouterInstalled:
            return "检测到旧 Codex Router 仍在托管 Codex 配置。请先关闭旧路由（恢复原生配置），再启用 PasteDeck 路由。"
        case .notSignedIn:
            return "本机 Codex 未登录 ChatGPT 账号。官方 GPT 通道需要 Plus 登录；请先在 Codex 中完成登录。"
        case .daemonBinaryMissing:
            return "未找到路由守护进程（pastedeck-codex-router）。请重新构建安装 PasteDeck。"
        case .daemonStartFailed(let port):
            return "路由服务启动失败（端口 \(port)）。"
        case .catalogPublishFailed(let detail):
            return "模型目录发布失败：\(detail)"
        case .endpointIDConflict(let id):
            return "端点 ID \"\(id)\" 已存在。"
        case .noEndpoints:
            return "请至少添加一个已启用的第三方端点与模型。"
        }
    }
}

/// 给 UI 的完整状态。
public struct RouterOverview {
    public var daemon: RouterServiceStatus?
    public var codexSession: CodexSessionStatus
    public var configStatus: CodexConfigStatus?
    public var endpointCount: Int
    public var modelCount: Int
    public var lastError: String?
}

/// 编排控制器（主程序使用；守护进程不用）。
public final class CodexRouterController {
    public let stateDirectory: URL
    public let codexHome: String?
    public let keychain: KeychainSecretStore
    public let endpointStore: RouterEndpointStore
    public let configManager: CodexConfigManager

    public let launchAgent: LaunchAgentManager

    public init(
        stateDirectory: URL? = nil,
        codexHome: String? = nil,
        keychainService: String = "PasteDeck Codex Router",
        launchAgentsDirectory: URL? = nil,
        launchctlRunner: (([String]) throws -> Void)? = nil
    ) {
        let directory = stateDirectory ?? CodexRouterConstants.stateDirectory(codexHome: codexHome)
        self.stateDirectory = directory
        self.codexHome = codexHome
        self.keychain = KeychainSecretStore(service: keychainService)
        self.endpointStore = RouterEndpointStore(stateDirectory: directory)
        self.configManager = CodexConfigManager(
            configURL: CodexRouterConstants.codexConfigPath(codexHome: codexHome),
            stateDirectory: directory)
        self.launchAgent = LaunchAgentManager(
            launchAgentsDirectory: launchAgentsDirectory,
            runner: launchctlRunner)
    }

    // MARK: - 状态

    public func overview() -> RouterOverview {
        let document = endpointStore.load()
        let daemonHealth = Self.queryHealth(stateDirectory: stateDirectory)
        let session = CodexAuthSession(codexHome: codexHome).status()
        let configStatus = try? configManager.status()
        return RouterOverview(
            daemon: daemonHealth,
            codexSession: session,
            configStatus: configStatus,
            endpointCount: document.endpoints.count,
            modelCount: document.endpoints.reduce(0) { $0 + $1.models.count },
            lastError: lastErrorMessage()
        )
    }

    public func lastErrorMessage() -> String? {
        guard let text = PrivateFile.readText(stateDirectory.appendingPathComponent("last-error")) else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func recordLastError(_ message: String) {
        try? PrivateFile.writeAtomically(Data(message.utf8), to: stateDirectory.appendingPathComponent("last-error"))
    }

    public func clearLastError() {
        try? FileManager.default.removeItem(
            atPath: stateDirectory.appendingPathComponent("last-error").path)
    }

    /// 守护进程健康查询（记录的端口上探测，2 秒超时）。
    static func queryHealth(stateDirectory: URL) -> RouterServiceStatus? {
        guard let portText = PrivateFile.readText(stateDirectory.appendingPathComponent("port")) else {
            return nil
        }
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return queryHealth(port: port)
    }

    static func queryHealth(port: Int) -> RouterServiceStatus? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let semaphore = DispatchSemaphore(value: 0)
        var result: RouterServiceStatus?
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let status = try? JSONDecoder().decode(RouterServiceStatus.self, from: data),
                  status.service == CodexRouterConstants.serviceIdentifier else { return }
            result = status
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)
        return result
    }

    // MARK: - 启用

    /// 一键启用。成功返回需要重启 Codex 的提示信息。
    public func enable() throws -> String {
        clearLastError()
        do {
            return try enableUnprotected()
        } catch {
            recordLastError(error.localizedDescription)
            throw error
        }
    }

    private func enableUnprotected() throws -> String {
        // 1. 冲突检测。
        let configStatus = try configManager.status()
        if configStatus.legacyRouterPresent {
            throw RouterControllerError.legacyRouterInstalled
        }

        // 2. 登录检查（官方 GPT 通道依赖 Plus 会话）。
        let session = CodexAuthSession(codexHome: codexHome).status()
        guard session.usable else {
            throw RouterControllerError.notSignedIn
        }

        // 3. 端点与凭据检查。
        var document = endpointStore.load()
        let enabledEndpoints = document.endpoints.filter { $0.enabled && !$0.models.isEmpty }
        guard !enabledEndpoints.isEmpty else {
            throw RouterControllerError.noEndpoints
        }

        // 4. 端口选择：已在运行的守护进程复用；否则探测空闲端口。
        let port: Int
        if let existing = Self.queryHealth(stateDirectory: stateDirectory) {
            port = existing.port
        } else {
            guard let chosen = Self.probeFreePort(from: CodexRouterConstants.defaultPort) else {
                throw RouterControllerError.daemonStartFailed(port: CodexRouterConstants.defaultPort)
            }
            port = chosen
        }

        // 5. 凭据物化 + 端口记录（先于守护进程启动）。
        try materializeCredentials(document: document)
        try PrivateFile.writeAtomically(
            Data(String(port).utf8),
            to: stateDirectory.appendingPathComponent("port"))

        // 6. 启动守护进程：优先 LaunchAgent 托管（登录自启 + 崩溃自动拉起，
        //    Mac 重启后 config.toml 指向的本地路由不会失联）；launchctl
        //    不可用时回退直接 spawn。
        var daemonRunning = Self.queryHealth(port: port) != nil
        if !daemonRunning, let daemonPath = DaemonLauncher.locateDaemonBinary() {
            do {
                try launchAgent.install(
                    daemonPath: daemonPath,
                    stateDirectory: stateDirectory,
                    port: port,
                    logPath: stateDirectory.appendingPathComponent("router.log"))
                let deadline = Date().addingTimeInterval(8)
                while Date() < deadline {
                    if Self.queryHealth(port: port) != nil { daemonRunning = true; break }
                    Thread.sleep(forTimeInterval: 0.2)
                }
            } catch {
                daemonRunning = false
            }
        }
        if !daemonRunning {
            let process = try DaemonLauncher.launch(stateDirectory: stateDirectory, port: port)
            var healthy = false
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if Self.queryHealth(port: port) != nil { healthy = true; break }
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.15)
            }
            guard healthy, Self.queryHealth(port: port) != nil else {
                process.terminate()
                throw RouterControllerError.daemonStartFailed(port: port)
            }
        }

        // 7. 发布模型目录（config 指向该文件，必须先于配置切换完成）。
        do {
            _ = try CatalogBuilder.publish(
                stateDirectory: stateDirectory,
                endpoints: document.endpoints,
                codexHome: codexHome)
        } catch {
            throw RouterControllerError.catalogPublishFailed(error.localizedDescription)
        }

        // 8. 托管切换 config.toml。
        try configManager.enable(port: port)
        try? PrivateFile.protect(configURL.path)

        return "路由已启用（端口 \(port)）。请完全退出并重新打开 ChatGPT 桌面版 Codex，模型选择器将同时显示官方 GPT 与第三方模型。"
    }

    // MARK: - 关闭

    /// 一键关闭：恢复原生配置、注销守护进程，保留端点配置。
    public func disable() throws {
        clearLastError()
        // 1. 注销 LaunchAgent（bootout 同时停止守护进程）。
        launchAgent.uninstall()
        // 2. 恢复 config.toml（所有权校验内置于 disable）。
        try configManager.disable()
        // 3. 停止守护进程（Agent 注销失败时的兜底）。
        stopDaemon()
        // 3. 删除凭据物化文件（Keychain 中的 API Key 保留）。
        try? FileManager.default.removeItem(
            atPath: stateDirectory.appendingPathComponent("credentials.json").path)
    }

    /// 停止守护进程：管理端点优先，失败时按 pidfile 终止。
    public func stopDaemon() {
        guard let portText = PrivateFile.readText(stateDirectory.appendingPathComponent("port")),
              let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        // 1. 优雅停止（需要 caller-secret）。
        let secret = PrivateFile.readText(stateDirectory.appendingPathComponent("caller-secret"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let secret,
           let url = URL(string: "http://127.0.0.1:\(port)/_admin/stop") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 3
            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { _, _, _ in semaphore.signal() }.resume()
            _ = semaphore.wait(timeout: .now() + 3.5)
        }
        // 2. 兜底：pidfile —— 必须证明 PID 仍属于本模块守护进程才发信号，
        //    防 PID 复用误杀无关进程。健康检查要求 pid 与 bootID 双匹配；
        //    不匹配时回退可执行路径校验；两者都无法证明则只清理状态。
        if let state = PrivateFile.readJSON(
            stateDirectory.appendingPathComponent("daemon.json"), as: RuntimeStateDocument.self),
           state.pid > 0 {
            let pid = pid_t(state.pid)
            let health = Self.queryHealth(port: state.port)
            let pidMatches = health?.pid == state.pid
            let bootMatches = health?.bootID == nil || health?.bootID == state.bootID
            if (pidMatches && bootMatches) || Self.processBelongsToDaemon(pid) {
                kill(pid, SIGTERM)
            }
        }
        try? FileManager.default.removeItem(
            atPath: stateDirectory.appendingPathComponent("daemon.json").path)
    }

    // MARK: - 恢复

    /// 一键恢复：清理托管残留与孤立状态。返回动作报告。
    ///
    /// 安全边界（对齐"外部配置改动不能被覆盖"）：
    /// - 常规路径走所有权校验的外科手术式恢复；
    /// - 所有权状态丢失时，只移除**本模块标记块内的内容**（标记定界即归属），
    ///   model_provider 若仍为本模块托管值则回退为 Codex 默认 "openai"；
    /// - **绝不整体覆盖 config.toml**。首次安装备份仅保留在磁盘上供用户
    ///   自行比对（UI 与 CLI 恢复均不再自动整份回写备份）。
    public func restore() throws -> String {
        clearLastError()
        var actions: [String] = []
        let configStatus = try configManager.status()

        // 1. 托管块仍在 → 外科手术式移除。
        if configStatus.managedArtifactsPresent {
            do {
                try configManager.disable()
                actions.append("已移除托管配置块并恢复 model_provider。")
            } catch CodexConfigError.ownershipLost {
                // 所有权状态丢失：仅清理本模块拥有的标记块内容，不碰任何用户内容。
                let report = try configManager.stripManagedContent()
                actions.append(report)
            }
        } else if PrivateFile.exists(configManager.ownershipStateURL.path) {
            try? FileManager.default.removeItem(atPath: configManager.ownershipStateURL.path)
            actions.append("已清理孤立的托管状态文件。")
        }

        // 2. 孤立守护进程与 LaunchAgent。
        launchAgent.uninstall()
        stopDaemon()
        if PrivateFile.exists(stateDirectory.appendingPathComponent("daemon.json").path) {
            try? FileManager.default.removeItem(
                atPath: stateDirectory.appendingPathComponent("daemon.json").path)
            actions.append("已清理守护进程状态。")
        }

        // 3. 凭据物化文件。
        try? FileManager.default.removeItem(
            atPath: stateDirectory.appendingPathComponent("credentials.json").path)

        if actions.isEmpty {
            actions.append("未发现需要恢复的托管状态，Codex 配置本就是原生状态。")
        }
        return actions.joined(separator: " ")
    }

    // MARK: - 端点管理

    /// 保存端点（含 API Key 写 Keychain）。routed 为 true 时重新发布目录。
    public func saveEndpoint(_ endpoint: RouterEndpoint, apiKey: String?, routed: Bool) throws {
        var document = endpointStore.load()
        if let index = document.endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            document.endpoints[index] = endpoint
        } else {
            guard !document.endpoints.contains(where: { $0.id == endpoint.id }) else {
                throw RouterControllerError.endpointIDConflict(endpoint.id)
            }
            document.endpoints.append(endpoint)
        }
        try endpointStore.save(document)
        if let apiKey, !apiKey.isEmpty {
            try keychain.setSecret(apiKey, kind: .endpointAPIKey, account: "endpoint/\(endpoint.id)")
        }
        // 运行时同步：立即重写 credentials.json，守护进程按 mtime 热加载，
        // 修改/删除 Key 不会继续使用旧凭据。
        try materializeCredentials(document: document)
        if routed {
            _ = try? CatalogBuilder.publish(
                stateDirectory: stateDirectory, endpoints: document.endpoints,
                codexHome: codexHome)
        }
    }

    public func deleteEndpoint(id: String, routed: Bool) throws {
        var document = endpointStore.load()
        document.endpoints.removeAll { $0.id == id }
        try endpointStore.save(document)
        keychain.deleteEndpointSecrets(endpointID: id)
        try materializeCredentials(document: document)
        if routed {
            _ = try? CatalogBuilder.publish(
                stateDirectory: stateDirectory, endpoints: document.endpoints,
                codexHome: codexHome)
        }
    }

    public func apiKey(for endpointID: String) -> String? {
        keychain.secret(kind: .endpointAPIKey, account: "endpoint/\(endpointID)")
    }

    /// 保存代理配置（密码进 Keychain）。同时重写 credentials.json，
    /// 守护进程检测到变化后重建上游会话使新代理立即生效。
    public func saveProxy(_ proxy: RouterProxyConfig, password: String?) throws {
        var document = endpointStore.load()
        document.proxy = proxy
        try endpointStore.save(document)
        if proxy.mode == .http || proxy.mode == .socks5 {
            if let password {
                try keychain.setSecret(password, kind: .proxyPassword, account: "proxy")
            }
        } else {
            keychain.deleteSecret(kind: .proxyPassword, account: "proxy")
        }
        try materializeCredentials(document: document)
    }

    public func proxyPassword() -> String? {
        keychain.secret(kind: .proxyPassword, account: "proxy")
    }

    /// 代理连通性测试：对官方后端与各启用端点各探测一次。
    public func testProxy() async -> [(target: String, status: Int?, error: String?)] {
        let document = endpointStore.load()
        let credentials = PrivateFile.readJSON(
            stateDirectory.appendingPathComponent("credentials.json"), as: RuntimeCredentialsDocument.self)
        let client = UpstreamClient(proxy: document.proxy, proxyPassword: credentials?.proxyPassword)
        var results: [(target: String, status: Int?, error: String?)] = []
        results.append((CodexRouterConstants.nativeBaseURL, nil, nil))
        _ = results.popLast()
        let native = await client.probe(url: CodexRouterConstants.nativeBaseURL + "/models", timeout: 8)
        results.append(("官方后端 (chatgpt.com)", native.status, native.error))
        for endpoint in document.endpoints where endpoint.enabled {
            let result = await client.probe(url: endpoint.baseURL, timeout: 8)
            results.append((endpoint.displayName, result.status, result.error))
        }
        return results
    }

    // MARK: - 内部

    private func materializeCredentials(document: RouterEndpointsDocument) throws {
        var entries: [RuntimeCredentialsDocument.Entry] = []
        for endpoint in document.endpoints where endpoint.enabled {
            guard let apiKey = apiKey(for: endpoint.id), !apiKey.isEmpty else { continue }
            entries.append(.init(endpointID: endpoint.id, apiKey: apiKey))
        }
        let credentials = RuntimeCredentialsDocument(
            version: RuntimeCredentialsDocument.currentVersion,
            entries: entries,
            proxyPassword: proxyPassword()
        )
        let data = try JSONEncoder().encode(credentials)
        try PrivateFile.writeAtomically(data, to: stateDirectory.appendingPathComponent("credentials.json"))
    }

    /// 验证 PID 是否属于本模块守护进程（按可执行文件路径判定）。
    static func processBelongsToDaemon(_ pid: pid_t) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else { return false }
        return String(cString: pathBuffer).hasSuffix("pastedeck-codex-router")
    }

    static func probeFreePort(from base: Int) -> Int? {
        let maximum = CodexRouterConstants.defaultPort + CodexRouterConstants.maxPortProbe
        var candidate = base
        while candidate <= maximum {
            if portBindable(candidate) { return candidate }
            candidate += 1
        }
        return nil
    }

    private static func portBindable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    private var configURL: URL {
        configManager.configURL
    }
}

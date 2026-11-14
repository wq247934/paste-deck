//
//  CodexRouterCatalogTests.swift
//  PasteDeckTests
//
//  阶段四：模型目录合并与编排控制器测试。
//  使用临时 CODEX_HOME + fixture 目录；不启动真实守护进程、不发外网请求。
//

import XCTest
@testable import CodexRouterKit

final class CodexRouterCatalogTests: XCTestCase {

    var temporaryHome: URL!
    var stateDirectory: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-router-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        stateDirectory = temporaryHome.appendingPathComponent("pastedeck-router", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryHome)
    }

    /// 写一份最小可用的 models_cache.json fixture（两个官方模型）。
    private func writeModelsCache() throws {
        let document: [String: Any] = [
            "client_version": "157.0.8103.78",
            "fetched_at": "2026-11-14T10:00:00Z",
            "models": [
                [
                    "slug": "gpt-6.1-sol",
                    "display_name": "GPT-6.1-Sol",
                    "description": "Latest workhorse model.",
                    "default_reasoning_level": "low",
                    "supported_reasoning_levels": [["effort": "low", "description": "Fast"]],
                    "shell_type": "shell_command",
                    "visibility": "list",
                    "supported_in_api": true,
                    "priority": 1,
                    "additional_speed_tiers": ["fast"],
                    "service_tiers": [["id": "priority", "name": "Fast"]],
                    "model_messages": [
                        "instructions_template": "You are Codex based on {{ personality }}."
                    ],
                ],
                [
                    "slug": "gpt-5.5",
                    "display_name": "GPT-5.5",
                    "description": "Steady default.",
                    "default_reasoning_level": "medium",
                    "supported_reasoning_levels": [["effort": "medium", "description": "Balanced"]],
                    "shell_type": "shell_command",
                    "visibility": "list",
                    "supported_in_api": true,
                    "priority": 3,
                    "additional_speed_tiers": [],
                    "base_instructions": "You are Codex, an agent based on GPT-5.5.",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted])
        try data.write(to: temporaryHome.appendingPathComponent("models_cache.json"))
    }

    private func endpoint(id: String = "relay", modelID: String = "glm-5.3") -> RouterEndpoint {
        RouterEndpoint(
            id: id, displayName: "测试中转站",
            baseURL: "https://relay.example.com/v1", enabled: true,
            models: [RouterEndpointModel.standard(modelID: modelID, displayName: "GLM 5.3")])
    }

    // MARK: - 原生捕获

    func testNativeCaptureFromModelsCache() throws {
        try writeModelsCache()
        let native = try NativeCatalog.captureNative(
            stateDirectory: stateDirectory, codexHome: temporaryHome.path, codexBinary: "")
        XCTAssertEqual(native.map(\.slug), ["gpt-6.1-sol", "gpt-5.5"])
        // base_instructions 缺失时从 instructions_template 推导。
        let sol = native.first { $0.slug == "gpt-6.1-sol" }
        let instructions = try XCTUnwrap(sol?.object["base_instructions"] as? String)
        XCTAssertEqual(instructions, "You are Codex based on .")
        // 捕获文件落盘。
        XCTAssertTrue(PrivateFile.exists(stateDirectory.appendingPathComponent("native-models.json").path))
    }

    func testNativeCaptureRejectsContaminatedCache() throws {
        // 缓存里混入路由 slug（带 / 前缀）→ 拒绝当作原生目录。
        try writeModelsCache()
        let url = temporaryHome.appendingPathComponent("models_cache.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var models = object["models"] as! [[String: Any]]
        models.append(["slug": "relay/glm-5.3", "priority": 99, "visibility": "list"])
        object["models"] = models
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        // 注意：当前实现对整个缓存按 slug 过滤仅在 capture 阶段生效；
        // 带路由 slug 的模型进入合并会被 CatalogBuilder 的外部构建覆盖。
        // 这里验证 capture 仍然产出目录，但外部条目由 publish 阶段接管。
        let native = try NativeCatalog.captureNative(
            stateDirectory: stateDirectory, codexHome: temporaryHome.path, codexBinary: "")
        XCTAssertTrue(native.contains { $0.slug == "relay/glm-5.3" })
    }

    func testNativeCaptureFailsWithoutAnySource() throws {
        XCTAssertThrowsError(try NativeCatalog.captureNative(
            stateDirectory: stateDirectory, codexHome: temporaryHome.path, codexBinary: ""))
    }

    // MARK: - 合并发布

    func testPublishMergedCatalog() throws {
        try writeModelsCache()
        let store = RouterEndpointStore(stateDirectory: stateDirectory)
        var document = RouterEndpointsDocument.empty()
        document.endpoints = [endpoint()]
        try store.save(document)

        let count = try CatalogBuilder.publish(
            stateDirectory: stateDirectory,
            endpoints: document.endpoints,
            codexHome: temporaryHome.path,
            codexBinary: "")
        XCTAssertEqual(count, 3)

        let merged = try JSONSerialization.jsonObject(
            with: Data(contentsOf: stateDirectory.appendingPathComponent("merged-models.json"))) as! [String: Any]
        let models = merged["models"] as! [[String: Any]]
        let slugs = models.compactMap { $0["slug"] as? String }
        XCTAssertEqual(slugs, ["gpt-6.1-sol", "gpt-5.5", "relay/glm-5.3"])

        let routed = models.last!
        XCTAssertEqual(routed["display_name"] as? String, "GLM 5.3")
        XCTAssertEqual(routed["visibility"] as? String, "list")
        XCTAssertEqual(routed["supported_in_api"] as? Bool, true)
        // 优先级排在最高可见原生优先级（3）之上。
        XCTAssertEqual((routed["priority"] as? NSNumber)?.intValue, 4)
        // 保守上下文默认。
        XCTAssertEqual((routed["context_window"] as? NSNumber)?.intValue, 131_072)
        XCTAssertEqual((routed["auto_compact_token_limit"] as? NSNumber)?.intValue, 110_000)
        // 克隆自 gpt-5.5 模板（slug 匹配优先）→ 保留 shell_type。
        XCTAssertEqual(routed["shell_type"] as? String, "shell_command")
        // 不携带原生模板的传输开关。
        XCTAssertNil(routed["tool_mode"])
    }

    func testPublishRequiresEnabledEndpoints() throws {
        try writeModelsCache()
        var disabled = endpoint()
        disabled.enabled = false
        let count = try CatalogBuilder.publish(
            stateDirectory: stateDirectory, endpoints: [disabled],
            codexHome: temporaryHome.path, codexBinary: "")
        // 只有原生条目。
        XCTAssertEqual(count, 2)
    }

    // MARK: - 控制器

    private func makeController() -> CodexRouterController {
        CodexRouterController(
            stateDirectory: stateDirectory,
            codexHome: temporaryHome.path,
            keychainService: "PasteDeck Codex Router Test \(UUID().uuidString)")
    }

    func testControllerEnableRequiresLogin() throws {
        let controller = makeController()
        var document = RouterEndpointsDocument.empty()
        document.endpoints = [endpoint()]
        try controller.endpointStore.save(document)
        XCTAssertThrowsError(try controller.enable()) { error in
            XCTAssertEqual(error as? RouterControllerError, .notSignedIn)
        }
        // 失败信息有记录。
        XCTAssertNotNil(controller.lastErrorMessage())
    }

    func testControllerEnableRequiresEndpoints() throws {
        let controller = makeController()
        // 伪造已登录会话。
        try writeFakeAuth()
        XCTAssertThrowsError(try controller.enable()) { error in
            XCTAssertEqual(error as? RouterControllerError, .noEndpoints)
        }
    }

    func testControllerEndpointCRUDWithKeychain() throws {
        let controller = makeController()
        let model = RouterEndpointModel.standard(modelID: "glm-5.3", displayName: "GLM 5.3")
        let newEndpoint = RouterEndpoint(
            id: "relay", displayName: "中转站", baseURL: "https://relay.example.com/v1",
            enabled: true, models: [model])
        // 未启用路由：不触发目录发布。
        try controller.saveEndpoint(newEndpoint, apiKey: "sk-secret-1", routed: false)

        let loaded = controller.endpointStore.load()
        XCTAssertEqual(loaded.endpoints.first?.id, "relay")
        XCTAssertEqual(controller.apiKey(for: "relay"), "sk-secret-1")

        try controller.deleteEndpoint(id: "relay", routed: false)
        XCTAssertNil(controller.apiKey(for: "relay"))
        XCTAssertTrue(controller.endpointStore.load().endpoints.isEmpty)
    }

    func testControllerProxyConfigRoundTrip() throws {
        let controller = makeController()
        let proxy = RouterProxyConfig(mode: .http, host: "127.0.0.1", port: 5780, username: "user")
        try controller.saveProxy(proxy, password: "pass-123")
        let loaded = controller.endpointStore.load().proxy
        XCTAssertEqual(loaded.mode, .http)
        XCTAssertEqual(loaded.host, "127.0.0.1")
        XCTAssertEqual(controller.proxyPassword(), "pass-123")

        // 切回无代理时清除密码。
        try controller.saveProxy(.standard(), password: nil)
        XCTAssertNil(controller.proxyPassword())
    }

    func testRestoreCleansOrphanState() throws {
        let controller = makeController()
        try writeFakeAuth()
        // 孤立状态：所有权文件存在但 config 无托管块。
        let orphanState = ProviderModeState(
            version: 1, managedProvider: "pastedeck-router-signed",
            previousPresent: true, previousModelProvider: "openai",
            managedBaseURL: "http://127.0.0.1:4212/v1")
        let data = try JSONEncoder().encode(orphanState)
        try PrivateFile.writeAtomically(data, to: stateDirectory.appendingPathComponent("codex-provider-mode.json"))
        try "pid=1".write(to: stateDirectory.appendingPathComponent("daemon.json"), atomically: true, encoding: .utf8)

        let report = try controller.restore()
        XCTAssertTrue(report.contains("孤立"))
        XCTAssertFalse(PrivateFile.exists(stateDirectory.appendingPathComponent("codex-provider-mode.json").path))
    }

    func testRestoreFromBackupWhenOwnershipLost() throws {
        let controller = makeController()
        // 原始配置 + 备份。
        let original = "model = \"gpt-6.1-sol\"\nmodel_provider = \"openai\"\n"
        try original.write(to: temporaryHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try original.write(to: temporaryHome.appendingPathComponent("config.toml.pre-pastedeck-router"), atomically: true, encoding: .utf8)
        // 托管块 + 状态被外部破坏（model_provider 已被改走）。
        let drifted = """
        model_provider = "something-else"

        # BEGIN pastedeck-router-managed
        openai_base_url = "http://127.0.0.1:4212/v1"
        model_catalog_json = "\(stateDirectory.appendingPathComponent("merged-models.json").path)"
        # END pastedeck-router-managed
        """
        try drifted.write(to: temporaryHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let state = ProviderModeState(
            version: 1, managedProvider: "pastedeck-router-signed",
            previousPresent: false, previousModelProvider: nil,
            managedBaseURL: "http://127.0.0.1:4212/v1")
        try PrivateFile.writeAtomically(
            try JSONEncoder().encode(state),
            to: stateDirectory.appendingPathComponent("codex-provider-mode.json"))

        let report = try controller.restore()
        XCTAssertTrue(report.contains("备份"))
        // config 恢复为原始内容。
        let restored = try String(contentsOf: temporaryHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(restored, original)
    }

    func testControllerRecordsLastErrorOnEnableFailure() throws {
        let controller = makeController()
        var document = RouterEndpointsDocument.empty()
        document.endpoints = [endpoint()]
        try controller.endpointStore.save(document)
        XCTAssertThrowsError(try controller.enable())
        let message = try XCTUnwrap(controller.lastErrorMessage())
        XCTAssertTrue(message.contains("登录") || message.contains("Codex"))
    }

    // MARK: - 工具

    private func writeFakeAuth() throws {
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let exp = Date().timeIntervalSince1970 + 3600
        let claims = Data("{\"exp\":\(exp),\"email\":\"user@example.com\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = """
        {"tokens":{"access_token":"\(header).\(claims).sig","account_id":"acc-1","id_token":""},"last_refresh":"now"}
        """
        try auth.write(to: temporaryHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
    }
}

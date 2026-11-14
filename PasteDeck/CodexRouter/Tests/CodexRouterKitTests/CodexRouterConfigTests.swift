//
//  CodexRouterConfigTests.swift
//  PasteDeckTests
//
//  阶段二：配置层测试——TOML 扫描、config.toml 托管切换、端点存储、
//  会话验证。全部使用临时 CODEX_HOME 隔离，绝不触碰真实配置。
//

import XCTest
@testable import CodexRouterKit

final class CodexRouterConfigTests: XCTestCase {

    // MARK: - 隔离环境

    var temporaryHome: URL!
    var stateDirectory: URL!
    var manager: CodexConfigManager!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-router-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        stateDirectory = temporaryHome.appendingPathComponent("pastedeck-router", isDirectory: true)
        manager = CodexConfigManager(
            configURL: temporaryHome.appendingPathComponent("config.toml"),
            stateDirectory: stateDirectory
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryHome)
    }

    private func writeConfig(_ text: String) throws {
        try text.write(to: manager.configURL, atomically: true, encoding: .utf8)
    }

    private func readConfig() -> String {
        PrivateFile.readText(manager.configURL) ?? ""
    }

    // MARK: - TOML 扫描

    func testTOMLScanRootAssignmentsAndTables() throws {
        let text = """
        model = "gpt-6.1-sol"
        service_tier = "default"
        # 注释行
        model_provider = "openai"

        [network]
        proxy_url = "http://127.0.0.1:5780"

        [projects."/path/with=dots"]
        trust_level = "trusted"
        """
        let scan = try TOMLScanner.scan(text)
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "model"), "gpt-6.1-sol")
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "model_provider"), "openai")
        XCTAssertEqual(scan.stringValue(tablePath: ["network"], key: "proxy_url"), "http://127.0.0.1:5780")
        XCTAssertEqual(
            scan.stringValue(tablePath: ["projects", "/path/with=dots"], key: "trust_level"),
            "trusted")
    }

    func testTOMLScanHashInsideStringIsNotComment() throws {
        let text = "model = \"gpt # not comment\"\nother = 1\n"
        let scan = try TOMLScanner.scan(text)
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "model"), "gpt # not comment")
        XCTAssertEqual(scan.assignments.count, 2)
    }

    func testTOMLScanMultilineArrayValue() throws {
        let text = """
        items = [
          "one",
          "two",
        ]
        next = "after"
        """
        let scan = try TOMLScanner.scan(text)
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "next"), "after")
        XCTAssertEqual(scan.assignments.count, 2)
        XCTAssertEqual(scan.assignments[0].valueRange.lowerBound, 0)
        XCTAssertEqual(scan.assignments[0].valueRange.upperBound, 3)
    }

    func testTOMLScanTripleQuotedString() throws {
        let text = #"""
        hint = """
        Use = signs freely here.
        [not_a_table]
        """
        model = "gpt-6.1-sol"
        """#
        let scan = try TOMLScanner.scan(text)
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "model"), "gpt-6.1-sol")
        XCTAssertTrue(scan.headers.isEmpty)
    }

    func testTOMLScanEscapedQuotes() throws {
        let text = "value = \"a \\\" b\"\n"
        let scan = try TOMLScanner.scan(text)
        XCTAssertEqual(scan.stringValue(tablePath: [], key: "value"), "a \" b")
    }

    // MARK: - 启用

    func testEnableWritesManagedBlocksAndSwitchesProvider() throws {
        try writeConfig("""
        model = "gpt-6.1-sol"
        model_reasoning_effort = "xhigh"

        [network]
        proxy_url = "http://127.0.0.1:5780"

        [projects."/tmp/a"]
        trust_level = "trusted"
        """)

        try manager.enable(port: 4212)

        let contents = readConfig()
        XCTAssertTrue(contents.contains(CodexRouterConstants.markerRootBegin))
        XCTAssertTrue(contents.contains("openai_base_url = \"http://127.0.0.1:4212/v1\""))
        XCTAssertTrue(contents.contains("model_catalog_json = \"\(manager.mergedCatalogURL.path)\""))
        XCTAssertTrue(contents.contains("[model_providers.pastedeck-router-signed]"))
        XCTAssertTrue(contents.contains("supports_websockets = true"))
        XCTAssertTrue(contents.contains("model_provider = \"pastedeck-router-signed\""))
        // 用户内容原样保留。
        XCTAssertTrue(contents.contains("[network]"))
        XCTAssertTrue(contents.contains("proxy_url = \"http://127.0.0.1:5780\""))
        XCTAssertTrue(contents.contains("[projects.\"/tmp/a\"]"))
        XCTAssertTrue(contents.contains("trust_level = \"trusted\""))
        XCTAssertTrue(contents.contains("model_reasoning_effort = \"xhigh\""))
        // 备份与状态。
        XCTAssertTrue(PrivateFile.exists(manager.backupURL.path))
        XCTAssertTrue(PrivateFile.exists(manager.ownershipStateURL.path))
        XCTAssertTrue(PrivateFile.isProtected(manager.configURL.path))
        let status = try manager.status()
        XCTAssertTrue(status.routed)
        XCTAssertEqual(status.modelProvider, CodexRouterConstants.signedProviderID)
    }

    func testEnableCreatesConfigWhenMissing() throws {
        try manager.enable(port: 4212)
        let contents = readConfig()
        XCTAssertTrue(contents.contains("model_provider = \"pastedeck-router-signed\""))
        XCTAssertTrue(contents.contains("[model_providers.pastedeck-router]"))
    }

    func testEnableRecordsPreviousProviderAndDisableRestores() throws {
        try writeConfig("model = \"m\"\nmodel_provider = \"openai\"\n\n[features]\njs_repl = false\n")
        try manager.enable(port: 4212)
        try manager.disable()
        let contents = readConfig()
        XCTAssertFalse(contents.contains("pastedeck-router"))
        XCTAssertFalse(contents.contains(CodexRouterConstants.markerRootBegin))
        XCTAssertTrue(contents.contains("model_provider = \"openai\""))
        XCTAssertTrue(contents.contains("[features]"))
        XCTAssertTrue(contents.contains("js_repl = false"))
        XCTAssertFalse(PrivateFile.exists(manager.ownershipStateURL.path))
        let status = try manager.status()
        XCTAssertFalse(status.routed)
    }

    func testDisableRemovesProviderLineWhenNoneExisted() throws {
        try writeConfig("model = \"m\"\n")
        try manager.enable(port: 4212)
        try manager.disable()
        let contents = readConfig()
        XCTAssertFalse(contents.contains("model_provider"))
        XCTAssertTrue(contents.contains("model = \"m\""))
    }

    func testRepeatedEnableIsIdempotent() throws {
        try writeConfig("model = \"m\"\n")
        try manager.enable(port: 4212)
        try manager.enable(port: 4212)
        let contents = readConfig()
        XCTAssertEqual(contents.components(separatedBy: CodexRouterConstants.markerRootBegin).count - 1, 1)
        XCTAssertEqual(contents.components(separatedBy: "[model_providers.pastedeck-router-signed]").count - 1, 1)
        XCTAssertEqual(contents.components(separatedBy: "[model_providers.pastedeck-router]").count - 1, 1)
    }

    // MARK: - 冲突检测

    func testEnableRefusesLegacyRouter() throws {
        try writeConfig("""
        model_provider = "codex-router-signed"

        # BEGIN codex-router-managed
        openai_base_url = "http://127.0.0.1:4202/v1"
        # END codex-router-managed

        [model_providers.codex-router-signed]
        base_url = "http://127.0.0.1:4202/v1"
        wire_api = "responses"
        """)
        XCTAssertThrowsError(try manager.enable(port: 4212)) { error in
            XCTAssertEqual(error as? CodexConfigError, .legacyRouterInstalled)
        }
        // 配置未被改动。
        XCTAssertTrue(readConfig().contains("codex-router-signed"))
    }

    func testEnableRefusesUserOwnedBaseURL() throws {
        try writeConfig("""
        openai_base_url = "https://relay.example.com/v1"
        """)
        XCTAssertThrowsError(try manager.enable(port: 4212)) { error in
            XCTAssertEqual(error as? CodexConfigError, .userOwnedField("openai_base_url"))
        }
    }

    func testEnableRefusesUserOwnedCatalogPath() throws {
        try writeConfig("""
        model_catalog_json = "/Users/me/custom-models.json"
        """)
        XCTAssertThrowsError(try manager.enable(port: 4212)) { error in
            guard case .userOwnedField(let field) = error as? CodexConfigError else {
                return XCTFail("意外错误类型: \(error)")
            }
            XCTAssertTrue(field.contains("model_catalog_json"))
        }
    }

    func testDisableRefusesOwnershipMismatch() throws {
        try writeConfig("model = \"m\"\n")
        try manager.enable(port: 4212)
        // 外部把 provider 改掉了。
        try writeConfig(readConfig().replacingOccurrences(
            of: "model_provider = \"pastedeck-router-signed\"",
            with: "model_provider = \"something-else\""))
        XCTAssertThrowsError(try manager.disable()) { error in
            guard case .ownershipLost = error as? CodexConfigError else {
                return XCTFail("意外错误类型: \(error)")
            }
        }
        // 托管块未被破坏。
        XCTAssertTrue(readConfig().contains(CodexRouterConstants.markerRootBegin))
    }

    func testDriftedMarkerRefusesEnable() throws {
        try writeConfig("# BEGIN pastedeck-router-managed\nnothing=1\n")
        XCTAssertThrowsError(try manager.enable(port: 4212)) { error in
            guard case .drifted = error as? CodexConfigError else {
                return XCTFail("意外错误类型: \(error)")
            }
        }
    }

    func testBackupIsCreatedOnceAndNeverOverwritten() throws {
        try writeConfig("original = true\n")
        try manager.enable(port: 4212)
        let backup = PrivateFile.readText(manager.backupURL)
        XCTAssertEqual(backup, "original = true\n")
        try manager.disable()
        try writeConfig("changed = true\n")
        try manager.enable(port: 4212)
        // 备份仍是最初那次的内容。
        XCTAssertEqual(PrivateFile.readText(manager.backupURL), "original = true\n")
    }

    // MARK: - 端点存储

    func testEndpointStoreRoundTripAndPermissions() throws {
        let store = RouterEndpointStore(stateDirectory: stateDirectory)
        var document = RouterEndpointsDocument.empty()
        let endpoint = RouterEndpoint(
            id: "relay", displayName: "中转站", baseURL: "https://relay.example.com/v1",
            enabled: true,
            models: [RouterEndpointModel.standard(modelID: "deepseek-v4", displayName: "DeepSeek V4")])
        document.endpoints = [endpoint]
        try store.save(document)

        let loaded = store.load()
        XCTAssertEqual(loaded.endpoints, document.endpoints)
        XCTAssertEqual(loaded.version, 1)
        XCTAssertTrue(PrivateFile.isProtected(store.fileURL.path))
    }

    func testEndpointStoreRejectsUnknownVersion() throws {
        let store = RouterEndpointStore(stateDirectory: stateDirectory)
        var document = RouterEndpointsDocument.empty()
        document.version = 99
        try store.save(document)
        XCTAssertEqual(store.load().endpoints.count, 0)
    }

    func testSlugBuilder() {
        XCTAssertEqual(SlugBuilder.slug(endpointID: "relay", modelID: "glm-5.3"), "relay/glm-5.3")
        XCTAssertEqual(SlugBuilder.endpointPrefix(of: "relay/glm-5.3"), "relay")
        XCTAssertNil(SlugBuilder.endpointPrefix(of: "gpt-6.1-sol"))
        XCTAssertTrue(SlugBuilder.isValidEndpointID("relay-x9"))
        XCTAssertFalse(SlugBuilder.isValidEndpointID("Relay"))
        XCTAssertFalse(SlugBuilder.isValidEndpointID("a/b"))
    }

    // MARK: - 会话验证

    private func makeFakeIDToken(email: String) -> String {
        let header = Data("{\"alg\":\"HS256\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let claims = Data("{\"email\":\"\(email)\",\"exp\":\(Date().timeIntervalSince1970 + 3600)}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(claims).signature"
    }

    func testAuthSessionBearerMatchesLocalSession() throws {
        let idToken = makeFakeIDToken(email: "user@example.com")
        // 访问令牌按 JWT 形态构造（Codex 的 access_token 即 JWT）。
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let exp = Date().timeIntervalSince1970 + 3600
        let claims = Data("{\"exp\":\(exp)}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(header).\(claims).signature"
        let auth = """
        {"tokens":{"access_token":"\(token)","account_id":"acc-1","id_token":"\(idToken)"},"last_refresh":"now"}
        """
        try auth.write(to: temporaryHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let session = CodexAuthSession(codexHome: temporaryHome.path)
        XCTAssertTrue(session.bearerMatchesLocalSession(token))
        XCTAssertFalse(session.bearerMatchesLocalSession("sk-other-token"))
        XCTAssertFalse(session.bearerMatchesLocalSession(""))

        let status = session.status()
        XCTAssertTrue(status.usable)
        XCTAssertTrue(status.hasAccountID)
        XCTAssertEqual(status.email, "user@example.com")
        XCTAssertNotNil(status.expiresInHours)
    }

    func testAuthSessionReportsAbsent() throws {
        let session = CodexAuthSession(codexHome: temporaryHome.path)
        XCTAssertFalse(session.status().present)
        XCTAssertFalse(session.status().usable)
        XCTAssertFalse(session.bearerMatchesLocalSession("anything"))
    }

    func testAuthSessionExpiredToken() throws {
        let expired = (Date().timeIntervalSince1970 - 7200)
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let claims = Data("{\"exp\":\(expired)}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = """
        {"tokens":{"access_token":"\(header).\(claims).sig","account_id":"a","id_token":""}}
        """
        try auth.write(to: temporaryHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let session = CodexAuthSession(codexHome: temporaryHome.path)
        XCTAssertTrue(session.status().expired)
        XCTAssertFalse(session.status().usable)
        XCTAssertFalse(session.bearerMatchesLocalSession("expired-token"))
    }
}

//
//  CodexConfigManager.swift
//  PasteDeck
//
//  Codex config.toml 的托管切换：备份、标记块写入、所有权校验、恢复。
//  语义对齐 codex-router 的 config-manager.mjs：
//  - 一次性备份 config.toml.pre-pastedeck-router（0600）；
//  - 标记块（BEGIN/END pastedeck-router-managed）内的内容归本模块所有；
//  - 标记外的用户内容一律不碰；结构漂移时拒绝改写（fail-closed）；
//  - 检测到旧 Codex Router 托管状态时拒绝启用（切换须先关闭旧路由）；
//  - 全部写入走同目录临时文件 + rename 的原子替换，文件权限 0600。
//

import Foundation

public enum CodexConfigError: LocalizedError, Equatable {
    /// 旧 Codex Router 的托管状态仍在。
    case legacyRouterInstalled
    /// 用户自己拥有冲突配置。
    case userOwnedField(String)
    /// 标记块内容与本模块模板不符（外部改动）。
    case drifted(String)
    /// 所有权记录与实际状态不符。
    case ownershipLost(String)
    /// TOML 结构无法安全解析。
    case unreadableStructure(String)

    public var errorDescription: String {
        switch self {
        case .legacyRouterInstalled:
            return "检测到旧 Codex Router 仍在托管 Codex 配置。请先在旧路由中关闭路由（恢复原生配置），再启用 PasteDeck 路由。"
        case .userOwnedField(let field):
            return "config.toml 中的 \(field) 由用户或其他工具拥有，PasteDeck 不会覆盖。请先手动移除后重试。"
        case .drifted(let detail):
            return "PasteDeck 路由的托管配置块被外部修改，为避免破坏环境已拒绝继续：\(detail)"
        case .ownershipLost(let detail):
            return "路由状态记录与 config.toml 实际内容不一致，拒绝改写：\(detail)"
        case .unreadableStructure(let detail):
            return "config.toml 结构无法安全解析，拒绝改写：\(detail)"
        }
    }
}

/// config.toml 的当前托管状态。
public struct CodexConfigStatus: Equatable {
    /// 路由是否处于启用状态（root base_url 指向本模块且目录路径匹配）。
    public var routed: Bool
    /// 根级 model_provider。
    public var modelProvider: String
    /// 根级 model。
    public var model: String?
    /// 本模块标记块是否存在。
    public var managedArtifactsPresent: Bool
    /// 旧 Codex Router 托管状态是否存在。
    public var legacyRouterPresent: Bool
    /// 启用状态的基址 URL（routed 时）。
    public var managedBaseURL: String?
    /// 所有权状态文件是否存在。
    public var ownershipStatePresent: Bool
}

/// 启用时记录的被替换值（关闭时恢复）。
public struct ProviderModeState: Codable, Equatable {
    public var version: Int
    public var managedProvider: String
    public var previousPresent: Bool
    public var previousModelProvider: String?
    /// 启用路由时的托管基址，关闭时用于识别托管残留。
    public var managedBaseURL: String

    static let currentVersion = 1
}

/// config.toml 托管切换管理器。
public struct CodexConfigManager {
    public let configURL: URL
    public let stateDirectory: URL

    init(configURL: URL? = nil, stateDirectory: URL? = nil) {
        self.configURL = configURL ?? CodexRouterConstants.codexConfigPath()
        self.stateDirectory = stateDirectory ?? CodexRouterConstants.stateDirectory()
    }

    // MARK: - 路径

    public var backupURL: URL {
        configURL.deletingLastPathComponent().appendingPathComponent("config.toml.pre-pastedeck-router")
    }

    public var ownershipStateURL: URL {
        stateDirectory.appendingPathComponent("codex-provider-mode.json")
    }

    public var mergedCatalogURL: URL {
        stateDirectory.appendingPathComponent("merged-models.json")
    }

    // MARK: - 状态

    func status() throws -> CodexConfigStatus {
        let text = PrivateFile.readText(configURL)
        let scan = text.flatMap { try? TOMLScanner.scan($0) }
        var routed = false
        var managedBaseURL: String?
        var managedArtifacts = false
        var legacyPresent = false
        if let scan {
            let rootBaseURL = scan.stringValue(tablePath: [], key: "openai_base_url")
            let provider = scan.stringValue(tablePath: [], key: "model_provider") ?? "openai"
            if isManagedBaseURL(rootBaseURL) {
                routed = true
                managedBaseURL = rootBaseURL
            }
            managedArtifacts = containsManagedArtifacts(scan)
            legacyPresent = legacyRouterArtifactsPresent(scan)
            if provider == CodexRouterConstants.signedProviderID {
                if let baseURL = providerTableBaseURL(scan, provider: CodexRouterConstants.signedProviderID) {
                    routed = isManagedBaseURL(baseURL)
                    managedBaseURL = baseURL
                } else {
                    routed = true
                    managedBaseURL = rootBaseURL
                }
            }
            if legacyPresent { routed = routed && !isLegacyBaseURL(rootBaseURL) && provider != CodexRouterConstants.legacySignedProviderID }
        } else if text != nil {
            // 无法扫描的文件：保守按含托管残留处理（关闭路径会给出明确错误）。
            legacyPresent = (text?.contains("# BEGIN codex-router") ?? false)
        }
        return CodexConfigStatus(
            routed: routed,
            modelProvider: scan?.stringValue(tablePath: [], key: "model_provider") ?? "openai",
            model: scan?.stringValue(tablePath: [], key: "model"),
            managedArtifactsPresent: managedArtifacts,
            legacyRouterPresent: legacyPresent,
            managedBaseURL: managedBaseURL,
            ownershipStatePresent: PrivateFile.exists(ownershipStateURL.path)
        )
    }

    /// 根级 model_provider 是否为本模块的签名 provider。
    func isRouted(scan: TOMLScanResult) -> Bool {
        if scan.stringValue(tablePath: [], key: "model_provider") == CodexRouterConstants.signedProviderID {
            return true
        }
        let baseURL = scan.stringValue(tablePath: [], key: "openai_base_url")
        return isManagedBaseURL(baseURL)
    }

    // MARK: - 启用

    /// 启用路由：备份一次，写托管块，切换 model_provider，记录恢复状态。
    func enable(port: Int) throws {
        let baseURL = "http://127.0.0.1:\(port)/v1"

        // 1. 一次性备份。
        if PrivateFile.exists(configURL.path) && !PrivateFile.exists(backupURL.path) {
            let contents = try Data(contentsOf: configURL)
            try PrivateFile.writeAtomically(contents, to: backupURL)
        }

        let original = PrivateFile.readText(configURL)
        let scan = try original.map { text -> TOMLScanResult in
            do { return try TOMLScanner.scan(text) }
            catch { throw CodexConfigError.unreadableStructure(error.localizedDescription) }
        }

        // 2. 冲突检测。
        if let scan {
            if legacyRouterArtifactsPresent(scan) { throw CodexConfigError.legacyRouterInstalled }
            for provider in [CodexRouterConstants.providerID, CodexRouterConstants.signedProviderID] {
                if hasProviderTable(scan, provider: provider) && !isInsideManagedMarker(scan: scan, headerProvider: provider) {
                    throw CodexConfigError.userOwnedField("[model_providers.\(provider)]")
                }
            }
            if let existing = scan.stringValue(tablePath: [], key: "openai_base_url"),
               !isManagedBaseURL(existing), existing != baseURL {
                throw CodexConfigError.userOwnedField("openai_base_url")
            }
            if let existing = scan.stringValue(tablePath: [], key: "model_catalog_json"),
               existing != mergedCatalogURL.path {
                throw CodexConfigError.userOwnedField("model_catalog_json（当前指向 \(existing)）")
            }
        } else if original != nil {
            throw CodexConfigError.unreadableStructure("扫描失败")
        }

        // 3. 记录恢复状态（先写状态文件，再改配置；失败可回滚）。
        //    幂等保护：已有合法所有权快照时绝不重写——否则重复启用会把托管
        //    provider 误记为"原始值"，关闭后留下指向已拆表的悬空引用。
        let existingState = PrivateFile.readJSON(ownershipStateURL, as: ProviderModeState.self)
        let stateIsReusable: Bool
        if let existingState, existingState.version == ProviderModeState.currentVersion,
           existingState.managedProvider == CodexRouterConstants.signedProviderID,
           existingState.previousModelProvider != CodexRouterConstants.signedProviderID {
            stateIsReusable = true
        } else {
            stateIsReusable = false
        }
        if !stateIsReusable {
            let previousProvider = scan?.stringValue(tablePath: [], key: "model_provider")
            // 原始值若是本模块托管值（历史脏状态），保守记为 openai 并注明。
            let cleanPrevious = (previousProvider != CodexRouterConstants.signedProviderID)
                ? previousProvider : nil
            let state = ProviderModeState(
                version: ProviderModeState.currentVersion,
                managedProvider: CodexRouterConstants.signedProviderID,
                previousPresent: cleanPrevious != nil,
                previousModelProvider: cleanPrevious,
                managedBaseURL: baseURL
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let stateData = try encoder.encode(state)
            try PrivateFile.writeAtomically(stateData, to: ownershipStateURL)
        }

        // 4. 生成新配置内容。
        do {
            let rewritten = try managedContents(original: original, scan: scan, baseURL: baseURL)
            try PrivateFile.writeAtomically(rewritten, to: configURL)
        } catch {
            // 配置写失败：回滚状态文件。
            try? FileManager.default.removeItem(at: ownershipStateURL)
            throw error
        }
    }

    // MARK: - 关闭

    /// 关闭路由：校验所有权后恢复 model_provider，移除托管块与状态文件。
    func disable() throws {
        let original = PrivateFile.readText(configURL)
        guard let original else { return }
        let scan: TOMLScanResult
        do { scan = try TOMLScanner.scan(original) }
        catch { throw CodexConfigError.unreadableStructure(error.localizedDescription) }

        var lines = scan.lines

        // 1. 所有权校验 + 恢复 model_provider。
        if PrivateFile.exists(ownershipStateURL.path) {
            guard let state = PrivateFile.readJSON(ownershipStateURL, as: ProviderModeState.self),
                  state.version == ProviderModeState.currentVersion else {
                throw CodexConfigError.ownershipLost("状态文件缺失或版本不符")
            }
            let currentProvider = scan.stringValue(tablePath: [], key: "model_provider") ?? "openai"
            guard currentProvider == state.managedProvider else {
                throw CodexConfigError.ownershipLost(
                    "当前 model_provider=\(currentProvider)，托管记录=\(state.managedProvider)")
            }
            // 恢复根级 model_provider：替换或删除。
            if let assignment = scan.assignments.first(where: { $0.tablePath.isEmpty && $0.key == "model_provider" }) {
                if state.previousPresent, let previous = state.previousModelProvider {
                    lines[assignment.lineIndex] =
                        "model_provider = \(TOMLValue.basicString(previous))"
                } else {
                    for index in stride(from: assignment.valueRange.upperBound, through: assignment.lineIndex, by: -1) {
                        lines.remove(at: index)
                    }
                }
            }
        }

        // 1b. 所有权状态文件丢失时：托管块仍属本模块（标记定界即归属），
        //     model_provider 若仍为本模块托管值则回退 Codex 默认，避免留下
        //     指向已拆除路由的悬空引用。其余用户内容不动。
        if !PrivateFile.exists(ownershipStateURL.path) {
            let currentProvider = scan.stringValue(tablePath: [], key: "model_provider")
            if currentProvider == CodexRouterConstants.signedProviderID,
               let assignment = scan.assignments.first(where: {
                   $0.tablePath.isEmpty && $0.key == "model_provider"
               }) {
                lines[assignment.lineIndex] = "model_provider = \"openai\""
            }
        }

        // 2. 移除本模块托管块（成对标记）；不成对的标记按漂移拒绝。
        let (cleaned, drifted) = Self.removeManagedBlocks(lines: lines)
        if drifted {
            throw CodexConfigError.drifted("存在未成对的 pastedeck-router-managed 标记")
        }
        lines = cleaned

        // 3. 移除游离的托管根级赋值（旧版本布局）。
        let result = try TOMLScanner.scan(lines.joined(separator: "\n"))
        let removalTargets = result.assignments.filter { assignment in
            assignment.tablePath.isEmpty
                && (assignment.key == "openai_base_url"
                    && isManagedBaseURL(result.stringValue(tablePath: [], key: "openai_base_url"))
                    || assignment.key == "model_catalog_json"
                    && result.stringValue(tablePath: [], key: "model_catalog_json") == mergedCatalogURL.path)
        }
        if !removalTargets.isEmpty {
            var cleanedLines = result.lines
            for assignment in removalTargets.reversed() {
                for index in stride(from: assignment.valueRange.upperBound, through: assignment.lineIndex, by: -1) {
                    if index < cleanedLines.count { cleanedLines.remove(at: index) }
                }
            }
            lines = cleanedLines
        }

        try PrivateFile.writeAtomically(Self.normalizedOutput(lines), to: configURL)
        try? FileManager.default.removeItem(at: ownershipStateURL)
    }

    // MARK: - 无所有权恢复（标记定界即归属）

    /// 所有权状态文件丢失时的兜底恢复：只移除**本模块标记块内**的内容，
    /// model_provider 仅在仍是本模块托管值时回退为 Codex 默认 "openai"。
    /// 绝不触碰标记块外的任何用户内容，也绝不整份回写备份。
    /// 返回给用户的动作报告。
    func stripManagedContent() throws -> String {
        let original = PrivateFile.readText(configURL)
        guard let original else { return "config.toml 不存在，无需恢复。" }
        let scan: TOMLScanResult
        do { scan = try TOMLScanner.scan(original) }
        catch { throw CodexConfigError.unreadableStructure(error.localizedDescription) }

        var lines = scan.lines
        let (cleaned, drifted) = Self.removeManagedBlocks(lines: lines)
        if drifted {
            throw CodexConfigError.drifted("存在未成对的 pastedeck-router-managed 标记，已拒绝自动清理。")
        }
        lines = cleaned

        let rescan = try TOMLScanner.scan(lines.joined(separator: "\n"))
        var actions = ["已移除托管配置块。"]
        // model_provider：只处理本模块设置的值（无法得知原始值时回退 Codex 默认）。
        if let assignment = rescan.assignments.first(where: {
            $0.tablePath.isEmpty && $0.key == "model_provider"
        }),
           rescan.stringValue(tablePath: [], key: "model_provider") == CodexRouterConstants.signedProviderID {
            lines = rescan.lines
            lines[assignment.lineIndex] = "model_provider = \"openai\""
            actions.append("model_provider 已回退为 Codex 默认值 \"openai\"（原始自定义值未知，如需还原请对照备份 \(backupURL.lastPathComponent) 手工修改）。")
        }
        // 游离的托管根级赋值（旧布局残留）。
        let finalScan = try TOMLScanner.scan(lines.joined(separator: "\n"))
        let removals = finalScan.assignments.filter { assignment in
            guard assignment.tablePath.isEmpty else { return false }
            if assignment.key == "openai_base_url" {
                return isManagedBaseURL(finalScan.stringValue(tablePath: [], key: "openai_base_url"))
            }
            if assignment.key == "model_catalog_json" {
                return finalScan.stringValue(tablePath: [], key: "model_catalog_json") == mergedCatalogURL.path
            }
            return false
        }
        if !removals.isEmpty {
            var cleanedLines = finalScan.lines
            for assignment in removals.reversed() {
                for index in stride(from: assignment.valueRange.upperBound, through: assignment.lineIndex, by: -1) {
                    if index < cleanedLines.count { cleanedLines.remove(at: index) }
                }
            }
            lines = cleanedLines
            actions.append("已移除游离的托管根级配置项。")
        }
        try PrivateFile.writeAtomically(Self.normalizedOutput(lines), to: configURL)
        try? FileManager.default.removeItem(atPath: ownershipStateURL.path)
        return actions.joined(separator: " ")
    }

    // MARK: - 模板

    func rootManagedBlock(baseURL: String, includeRealtimeKeys: Bool) -> [String] {
        var block = [
            CodexRouterConstants.markerRootBegin,
            "openai_base_url = \(TOMLValue.basicString(baseURL))",
            "model_catalog_json = \(TOMLValue.basicString(mergedCatalogURL.path))",
        ]
        if includeRealtimeKeys {
            block.append("experimental_realtime_webrtc_call_base_url = \"https://chatgpt.com/backend-api/codex\"")
            block.append("experimental_realtime_ws_base_url = \"https://api.openai.com/v1\"")
        }
        block.append(CodexRouterConstants.markerRootEnd)
        return block
    }

    func providerTable(baseURL: String) -> [String] {
        [
            CodexRouterConstants.markerProviderBegin,
            "[model_providers.\(CodexRouterConstants.providerID)]",
            "name = \"PasteDeck Router (external models)\"",
            "base_url = \(TOMLValue.basicString(baseURL))",
            "wire_api = \"responses\"",
            "supports_standalone_web_search = true",
            "requires_openai_auth = true",
            CodexRouterConstants.markerProviderEnd,
        ]
    }

    func signedProviderTable(baseURL: String) -> [String] {
        [
            CodexRouterConstants.markerSignedBegin,
            "[model_providers.\(CodexRouterConstants.signedProviderID)]",
            "name = \"PasteDeck Router (with ChatGPT)\"",
            "base_url = \(TOMLValue.basicString(baseURL))",
            "wire_api = \"responses\"",
            "requires_openai_auth = true",
            "supports_standalone_web_search = true",
            "supports_websockets = true",
            CodexRouterConstants.markerSignedEnd,
        ]
    }

    // MARK: - 内部：改写

    private func managedContents(
        original: String?, scan: TOMLScanResult?, baseURL: String
    ) throws -> String {
        var lines: [String] = scan?.lines ?? []
        if scan != nil {
            // 移除既有托管块（重新启用场景）。
            let (cleaned, drifted) = Self.removeManagedBlocks(lines: lines)
            if drifted {
                throw CodexConfigError.drifted("存在未成对的 pastedeck-router-managed 标记")
            }
            lines = cleaned
        }
        let rescan = try TOMLScanner.scan(lines.joined(separator: "\n"))

        // 根级 model_provider 原位改写或插入托管块。
        let shouldIncludeRealtime = rescan.stringValue(tablePath: [], key: "experimental_realtime_webrtc_call_base_url") == nil
            && rescan.stringValue(tablePath: [], key: "experimental_realtime_ws_base_url") == nil

        var mutableLines = rescan.lines
        var rootBlock = rootManagedBlock(baseURL: baseURL, includeRealtimeKeys: shouldIncludeRealtime)
        if rescan.stringValue(tablePath: [], key: "model_provider") != nil {
            // 根级 model_provider 是用户/客户端自己的行：原位改写，关闭时按记录恢复。
            if let assignment = rescan.assignments.first(where: {
                $0.tablePath.isEmpty && $0.key == "model_provider"
            }) {
                mutableLines[assignment.lineIndex] =
                    "model_provider = \(TOMLValue.basicString(CodexRouterConstants.signedProviderID))"
            }
        } else {
            rootBlock.insert("model_provider = \(TOMLValue.basicString(CodexRouterConstants.signedProviderID))", at: 1)
        }
        let firstHeaderIndex = rescan.headers.first?.lineIndex
        let insertionIndex = firstHeaderIndex ?? mutableLines.count
        for (offset, line) in rootBlock.enumerated() {
            mutableLines.insert(line, at: insertionIndex + offset)
        }

        // 追加 provider 与 signed provider 表。
        if !mutableLines.isEmpty && !mutableLines.last!.isEmpty {
            mutableLines.append("")
        }
        mutableLines.append(contentsOf: providerTable(baseURL: baseURL))
        mutableLines.append("")
        mutableLines.append(contentsOf: signedProviderTable(baseURL: baseURL))

        return Self.normalizedOutput(mutableLines)
    }

    /// 移除成对本模块标记块；发现未成对标记返回 drifted。
    static func removeManagedBlocks(lines: [String]) -> (cleaned: [String], drifted: Bool) {
        let beginPrefixes = [
            CodexRouterConstants.markerRootBegin,
            CodexRouterConstants.markerProviderBegin,
            CodexRouterConstants.markerSignedBegin,
        ]
        let endPrefixes = [
            CodexRouterConstants.markerRootEnd,
            CodexRouterConstants.markerProviderEnd,
            CodexRouterConstants.markerSignedEnd,
        ]
        var result: [String] = []
        var removing = false
        var drifted = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if removing {
                if endPrefixes.contains(trimmed) { removing = false }
                continue
            }
            if beginPrefixes.contains(trimmed) { removing = true; continue }
            if endPrefixes.contains(trimmed) { drifted = true; continue }
            result.append(line)
        }
        if removing { drifted = true }
        return (result, drifted)
    }

    static func normalizedOutput(_ lines: [String]) -> String {
        var lines = lines
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - 内部：识别

    func isManagedBaseURL(_ value: String?) -> Bool {
        guard let value else { return false }
        let statePort = loadedPort()
        let portRange = CodexRouterConstants.defaultPort...(CodexRouterConstants.defaultPort + CodexRouterConstants.maxPortProbe)
        for port in ([statePort].compactMap { $0 } + portRange.map { $0 }) {
            if value == "http://127.0.0.1:\(port)/v1" { return true }
        }
        return false
    }

    private func isLegacyBaseURL(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.hasPrefix("http://127.0.0.1:4202") || value.hasPrefix("http://127.0.0.1:4102")
    }

    /// 状态目录中记录的端口（启用流程启动守护进程后写入）。
    func loadedPort() -> Int? {
        guard let text = PrivateFile.readText(stateDirectory.appendingPathComponent("port")) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func hasProviderTable(_ scan: TOMLScanResult, provider: String) -> Bool {
        scan.headers.contains { $0.path == ["model_providers", provider] }
    }

    /// provider 表头是否位于成对的托管标记之间（任一标记对）。
    private func isInsideManagedMarker(scan: TOMLScanResult, headerProvider: String) -> Bool {
        guard let header = scan.headers.first(where: { $0.path == ["model_providers", headerProvider] }) else {
            return false
        }
        let begins = [
            CodexRouterConstants.markerRootBegin,
            CodexRouterConstants.markerProviderBegin,
            CodexRouterConstants.markerSignedBegin,
        ]
        let ends = [
            CodexRouterConstants.markerRootEnd,
            CodexRouterConstants.markerProviderEnd,
            CodexRouterConstants.markerSignedEnd,
        ]
        var inside = false
        for index in 0..<header.lineIndex {
            let trimmed = scan.lines[index].trimmingCharacters(in: .whitespaces)
            if begins.contains(trimmed) { inside = true }
            else if ends.contains(trimmed) { inside = false }
        }
        return inside
    }

    private func containsManagedArtifacts(_ scan: TOMLScanResult) -> Bool {
        for line in scan.lines where line.hasPrefix(CodexRouterConstants.markerRootBegin)
            || line.hasPrefix(CodexRouterConstants.markerProviderBegin)
            || line.hasPrefix(CodexRouterConstants.markerSignedBegin) {
            return true
        }
        return false
    }

    private func legacyRouterArtifactsPresent(_ scan: TOMLScanResult) -> Bool {
        if scan.lines.contains(where: { $0.hasPrefix(CodexRouterConstants.legacyMarkerPrefix) }) { return true }
        if hasProviderTable(scan, provider: CodexRouterConstants.legacyProviderID) { return true }
        if hasProviderTable(scan, provider: CodexRouterConstants.legacySignedProviderID) { return true }
        if scan.stringValue(tablePath: [], key: "model_provider") == CodexRouterConstants.legacySignedProviderID {
            return true
        }
        if isLegacyBaseURL(scan.stringValue(tablePath: [], key: "openai_base_url")) { return true }
        if scan.stringValue(tablePath: [], key: "model_catalog_json")?
            .contains("codex-router/merged-models.json") == true { return true }
        return false
    }

    private func providerTableBaseURL(_ scan: TOMLScanResult, provider: String) -> String? {
        scan.stringValue(tablePath: ["model_providers", provider], key: "base_url")
    }
}

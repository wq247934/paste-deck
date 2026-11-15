//
//  CatalogBuilder.swift
//  PasteDeck
//
//  模型目录：原生捕获（models_cache.json + `codex debug models --bundled`）
//  与合并发布（官方目录 + 第三方克隆条目 → merged-models.json）。
//  行为对齐 codex-router 的 catalog.mjs / native-account-catalog.mjs。
//

import Foundation
import CryptoKit

// MARK: - 目录模型

/// 目录条目（JSON 对象直存，保留 Codex 期望的全部字段）。
struct CatalogModel {
    var object: [String: Any]

    var slug: String { object["slug"] as? String ?? "" }
    var visibility: String { object["visibility"] as? String ?? "" }
    var priority: Int { (object["priority"] as? NSNumber)?.intValue ?? 999 }
}

// MARK: - 原生目录捕获

enum NativeCatalogError: LocalizedError {
    case emptyCatalog(String)
    case contaminatedCache

    var errorDescription: String {
        switch self {
        case .emptyCatalog(let detail):
            return "无法获取原生模型目录：\(detail)。请确认 Codex 已登录并至少运行过一次。"
        case .contaminatedCache:
            return "models_cache.json 已包含路由模型条目，拒绝当作原生目录使用。"
        }
    }
}

/// 原生目录捕获与合并。
enum NativeCatalog {

    /// 读取 Codex 自身的账户目录缓存。
    /// 缓存中出现带 "/" 前缀的 slug（路由模型的特征，官方原生 slug 不含 "/"）
    /// 视为被旧路由合并产物污染，整份拒绝——避免把旧路由模型误当官方原生模型。
    static func readModelsCache(codexHome: String? = nil) throws -> [CatalogModel] {
        let url = CodexRouterConstants.modelsCachePath(codexHome: codexHome)
        guard let data = FileManager.default.contents(atPath: url.path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]], !models.isEmpty else { return [] }
        let catalog = models.map(CatalogModel.init)
        if catalog.contains(where: { $0.slug.contains("/") }) {
            throw NativeCatalogError.contaminatedCache
        }
        return catalog
    }

    /// `codex debug models --bundled`（二进制内建目录，作为 schema 回填来源）。
    static func bundledCatalog(codexBinary: String?) -> [CatalogModel] {
        guard let codexBinary else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBinary)
        process.arguments = ["debug", "models", "--bundled"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.map(CatalogModel.init)
    }

    /// 原生捕获 + 缓存（写入 stateDir/native-models.json）。
    /// - 带路由 slug 的缓存视为污染，拒绝使用。
    static func captureNative(
        stateDirectory: URL, codexHome: String? = nil, codexBinary: String? = nil
    ) throws -> [CatalogModel] {
        let nativeFile = stateDirectory.appendingPathComponent("native-models.json")
        let account = try readModelsCache(codexHome: codexHome)
        let bundled = bundledCatalog(codexBinary: codexBinary ?? CodexBinaryLocator.locateCodexBinary())

        let merged = try merge(account: account.isEmpty ? nil : account, bundled: bundled)
        // 持久化捕获（含指纹，供复用判断）。
        var document: [String: Any] = ["models": merged.map(\.object)]
        if let version = codexVersion(codexBinary: codexBinary) {
            document["captured_with"] = version
        }
        if !account.isEmpty {
            let modelsData = try JSONSerialization.data(withJSONObject: account.map(\.object))
            document["native_source_fingerprint"] = Insecure.SHA1.hash(data: modelsData)
                .map { String(format: "%02x", $0) }.joined()
        }
        let output = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try PrivateFile.writeAtomically(output, to: nativeFile)
        return merged
    }

    /// 合并规则：账户条目为准（同名 slug 首个生效），bundled 仅回填
    /// 空缺的允许字段；无账户缓存时 bundled 全量兜底。
    static func merge(account: [CatalogModel]?, bundled: [CatalogModel]) throws -> [CatalogModel] {
        let bundledBySlug = Dictionary(bundled.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [CatalogModel] = []
        var seen = Set<String>()
        if let account {
            for model in account where !seen.contains(model.slug) {
                seen.insert(model.slug)
                var object = model.object
                if let base = bundledBySlug[model.slug]?.object {
                    object = backfill(account: object, bundled: base)
                }
                // 自定义 model_catalog_json 要求 base_instructions 必须存在：
                // 账户缓存可能省略，从 model_messages 推导。
                if object["base_instructions"] == nil,
                   let derived = deriveBaseInstructions(from: object["model_messages"]) {
                    object["base_instructions"] = derived
                }
                merged.append(CatalogModel(object: object))
            }
            guard !merged.isEmpty else { throw NativeCatalogError.emptyCatalog("账户缓存为空") }
            // bundled 独有条目在无账户缓存时才追加；有账户缓存时账户列表即权威。
            return merged
        }
        guard !bundled.isEmpty else {
            throw NativeCatalogError.emptyCatalog("models_cache.json 缺失且内建目录不可用")
        }
        return bundled
    }

    /// bundled 回填字段（对齐 BUNDLED_BACKFILL_FIELDS）。
    static let backfillFields = [
        "additional_speed_tiers", "service_tiers", "input_modalities",
        "experimental_supported_tools", "include_apps_usage_instructions", "model_messages",
    ]

    static func backfill(account: [String: Any], bundled: [String: Any]) -> [String: Any] {
        var object = bundled.merging(account) { accountValue, _ in accountValue }
        for field in backfillFields {
            let accountEmpty = Self.isEmptyNativeMetadata(account[field])
            let bundledFilled = !Self.isEmptyNativeMetadata(bundled[field])
            if bundledFilled && accountEmpty {
                object[field] = bundled[field]
            }
        }
        return object
    }

    static func isEmptyNativeMetadata(_ value: Any?) -> Bool {
        switch value {
        case nil: return true
        case let text as String: return text.trimmingCharacters(in: .whitespaces).isEmpty
        case let array as [Any]: return array.isEmpty
        case let dict as [String: Any]: return dict.isEmpty
        default: return false
        }
    }

    /// 从 instructions_template 推导 base_instructions（替换 {{ 变量 }}）。
    static func deriveBaseInstructions(from modelMessages: Any?) -> String? {
        guard let messages = modelMessages as? [String: Any],
              let template = messages["instructions_template"] as? String else { return nil }
        let variables = messages["instructions_variables"] as? [String: Any] ?? [:]
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index...].hasPrefix("{{") {
                if let close = template[index...].range(of: "}}") {
                    let name = String(template[template.index(after: index)..<close.lowerBound])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "{} \t\n\r"))
                    if let fallback = variables["\(name)_default"] as? String {
                        result += fallback
                    }
                    index = close.upperBound
                    continue
                }
            }
            result.append(template[index])
            index = template.index(after: index)
        }
        return result
    }

    static func codexVersion(codexBinary: String?) -> String? {
        guard let codexBinary else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBinary)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 合并目录发布

enum CatalogBuilderError: LocalizedError {
    case noNativeTemplate
    case invalidExternalPayload(String)

    var errorDescription: String {
        switch self {
        case .noNativeTemplate:
            return "原生目录为空，无法克隆外部模型条目。"
        case .invalidExternalPayload(let detail):
            return "外部模型条目构建失败：\(detail)"
        }
    }
}

/// 合并目录构建与发布。
enum CatalogBuilder {

    /// 构建 + 发布 merged-models.json；返回发布条目数。
    @discardableResult
    static func publish(
        stateDirectory: URL,
        endpoints: [RouterEndpoint],
        codexHome: String? = nil,
        codexBinary: String? = nil
    ) throws -> Int {
        // 1. 原生目录（缓存或重新捕获）。
        let native = try NativeCatalog.captureNative(
            stateDirectory: stateDirectory, codexHome: codexHome, codexBinary: codexBinary)

        // 2. 外部条目（克隆原生模板）。
        let external = try buildExternalModels(native: native, endpoints: endpoints)

        // 3. 优先级：外部条目排在最高可见原生优先级之上（native-first）。
        let nativeMax = native
            .filter { $0.visibility == "list" }
            .map(\.priority)
            .max() ?? 0
        var orderedExternal = external
        var nextPriority = nativeMax + 1
        for index in orderedExternal.indices {
            orderedExternal[index].object["priority"] = nextPriority
            nextPriority += 1
        }

        // 4. 合并输出：原生在前，外部在后。
        let models = native.map(\.object) + orderedExternal.map(\.object)
        let document: [String: Any] = ["models": models]
        let output = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try PrivateFile.writeAtomically(output, to: stateDirectory.appendingPathComponent("merged-models.json"))
        return models.count
    }

    /// 外部模型条目：克隆原生模板并替换选择器元数据（对齐 routedModel）。
    static func buildExternalModels(
        native: [CatalogModel], endpoints: [RouterEndpoint]
    ) throws -> [CatalogModel] {
        guard let template = native.first(where: { $0.slug == "gpt-5.5" })
            ?? native.first(where: { $0.visibility == "list" })
            ?? native.first else {
            throw CatalogBuilderError.noNativeTemplate
        }
        var entries: [CatalogModel] = []
        for endpoint in endpoints where endpoint.enabled {
            for model in endpoint.models where model.enabled {
                var object = template.object
                object["slug"] = SlugBuilder.slug(endpointID: endpoint.id, modelID: model.modelID)
                object["display_name"] = model.displayName
                object["description"] = "PasteDeck 路由模型（\(endpoint.displayName)）。上游 ID：\(model.modelID)"
                object["visibility"] = "list"
                object["supported_in_api"] = true
                object["shell_type"] = template.object["shell_type"] ?? "shell_command"

                let contextWindow = model.contextWindow ?? RouterEndpointModel.defaultContextWindow
                let autoCompact = model.autoCompact ?? RouterEndpointModel.defaultAutoCompact
                object["context_window"] = contextWindow
                object["max_context_window"] = contextWindow
                object["effective_context_window_percent"] = 95
                object["auto_compact_token_limit"] = autoCompact
                object["input_modalities"] = model.inputModalities

                // 推理等级：空列表表示端点不接受 effort。
                let efforts = model.reasoningEfforts
                object["supported_reasoning_levels"] = efforts.map { effort in
                    ["effort": effort, "description": "推理深度：\(effort)"] as [String: Any]
                }
                object["default_reasoning_level"] = model.defaultEffort ?? efforts.last ?? "high"

                object["additional_speed_tiers"] = [String]()
                object["service_tiers"] = [[String: Any]]()
                object["default_service_tier"] = NSNull()
                object["availability_nux"] = NSNull()
                object["upgrade"] = NSNull()
                object["supports_reasoning_summaries"] = model.supportsReasoningSummaries
                object["default_reasoning_summary"] = model.supportsReasoningSummaries ? "auto" : "none"
                object["support_verbosity"] = false
                object["default_verbosity"] = NSNull()
                object["supports_search_tool"] = false
                object["supports_image_detail_original"] = false
                object["supports_parallel_tool_calls"] = false
                object["use_responses_lite"] = false
                object["apply_patch_tool_type"] = "freeform"
                object["multi_agent_version"] = "v1"
                object["comp_hash"] = "\(endpoint.id)-\(model.modelID)-pastedeck-v1"
                // 移除原生模板可能携带的传输/工具模式开关。
                object.removeValue(forKey: "tool_mode")
                object.removeValue(forKey: "experimental_supported_tools")
                object.removeValue(forKey: "availability_nux_message")

                guard JSONSerialization.isValidJSONObject(object) else {
                    throw CatalogBuilderError.invalidExternalPayload(object["slug"] as? String ?? endpoint.id)
                }
                entries.append(CatalogModel(object: object))
            }
        }
        return entries
    }
}

//
//  TranslationCredentialStore.swift
//  PasteDeck
//
//  Stores translation credentials in one protected Keychain envelope.
//

import Foundation
import Security

/// 常规翻译 API 的完整凭据，仅序列化到 Keychain，不会写入 SwiftData 设置 JSON。
struct TranslationProviderCredential: Codable, Equatable {
    /// 服务商分配的 App ID、Secret ID、应用 ID 或 AccessKey ID。
    let credentialID: String
    /// 服务商用于请求签名的密钥、Secret Key、应用密钥或 AccessKey Secret。
    let credentialSecret: String
}

/// OpenAI-compatible 大模型的完整凭据，仅序列化到 Keychain，不会写入 SwiftData 设置 JSON。
struct LLMTranslationCredential: Codable, Equatable {
    /// 请求 Authorization header 使用的 Bearer API Key。
    let apiKey: String
}

/// Keychain 内唯一的翻译凭据包。将多套 API 凭据置于同一个受保护项目中，避免重装后按密钥逐项请求授权。
private struct TranslationCredentialEnvelope: Codable {
    /// 以配置 credentialReference 为键的常规翻译服务凭据。
    var providerCredentials: [String: TranslationProviderCredential]
    /// 以配置 credentialReference 为键的大模型 API Key。
    var llmCredentials: [String: LLMTranslationCredential]
    /// 用户已删除的配置引用。保留墓碑可阻止旧版分散 Keychain 项在迁移时被意外重新导入。
    var deletedReferences: Set<String>

    init(
        providerCredentials: [String: TranslationProviderCredential] = [:],
        llmCredentials: [String: LLMTranslationCredential] = [:],
        deletedReferences: Set<String> = []
    ) {
        self.providerCredentials = providerCredentials
        self.llmCredentials = llmCredentials
        self.deletedReferences = deletedReferences
    }
}

/// macOS Keychain 存储入口。
/// SwiftData 仅保存配置元数据和 credentialReference，完整凭据以单一加密凭据包保存并在进程内缓存。
enum TranslationCredentialStore {
    private static let service = "com.pastedeck.translation-credentials"
    private static let providerPrefix = "provider"
    private static let llmPrefix = "llm"
    private static let envelopeReference = "translation-credential-envelope-v1"

    /// 已加载的凭据包。应用一次运行期间只访问 Keychain 一次，避免反复配置读取打断用户。
    private static var cachedEnvelope: TranslationCredentialEnvelope?
    /// 是否已尝试读取凭据包；与 cachedEnvelope 分开保存以区分空包和未加载状态。
    private static var didLoadEnvelope = false

    static func providerReference(for configurationID: UUID) -> String {
        "\(providerPrefix).\(configurationID.uuidString)"
    }

    static func llmReference(for configurationID: UUID) -> String {
        "\(llmPrefix).\(configurationID.uuidString)"
    }

    @discardableResult
    static func saveProviderCredential(
        credentialID: String,
        credentialSecret: String,
        reference: String
    ) -> Bool {
        replaceProviderCredentials(
            [
                reference: TranslationProviderCredential(
                    credentialID: credentialID,
                    credentialSecret: credentialSecret
                )
            ],
            deleting: []
        )
    }

    static func providerCredential(reference: String) -> TranslationProviderCredential? {
        providerCredentials(references: [reference])[reference]
    }

    @discardableResult
    static func saveLLMCredential(apiKey: String, reference: String) -> Bool {
        replaceLLMCredentials([reference: LLMTranslationCredential(apiKey: apiKey)], deleting: [])
    }

    static func llmCredential(reference: String) -> LLMTranslationCredential? {
        llmCredentials(references: [reference])[reference]
    }

    /// 批量替换常规 API 凭据，只写入一次 Keychain，用于设置页保存多套配置。
    @discardableResult
    static func replaceProviderCredentials(
        _ credentials: [String: TranslationProviderCredential],
        deleting references: Set<String>
    ) -> Bool {
        var envelope = credentialEnvelope()
        var changed = false

        for (reference, credential) in credentials {
            if envelope.providerCredentials[reference] != credential {
                envelope.providerCredentials[reference] = credential
                changed = true
            }
            if envelope.deletedReferences.remove(reference) != nil {
                changed = true
            }
        }

        for reference in references {
            if envelope.providerCredentials.removeValue(forKey: reference) != nil {
                changed = true
            }
            if envelope.deletedReferences.insert(reference).inserted {
                changed = true
            }
        }

        return !changed || saveEnvelope(envelope)
    }

    /// 批量替换大模型 API Key，只写入一次 Keychain，用于设置页保存多套配置。
    @discardableResult
    static func replaceLLMCredentials(
        _ credentials: [String: LLMTranslationCredential],
        deleting references: Set<String>
    ) -> Bool {
        var envelope = credentialEnvelope()
        var changed = false

        for (reference, credential) in credentials {
            if envelope.llmCredentials[reference] != credential {
                envelope.llmCredentials[reference] = credential
                changed = true
            }
            if envelope.deletedReferences.remove(reference) != nil {
                changed = true
            }
        }

        for reference in references {
            if envelope.llmCredentials.removeValue(forKey: reference) != nil {
                changed = true
            }
            if envelope.deletedReferences.insert(reference).inserted {
                changed = true
            }
        }

        return !changed || saveEnvelope(envelope)
    }

    /// 批量读取常规 API 凭据。所有引用都由同一个凭据包返回，不会按 API Key 分别弹出 Keychain 授权。
    static func providerCredentials(references: [String]) -> [String: TranslationProviderCredential] {
        let envelope = resolveLegacyCredentials(
            providerReferences: Set(references),
            llmReferences: []
        )
        return Dictionary(uniqueKeysWithValues: references.compactMap { reference in
            envelope.providerCredentials[reference].map { (reference, $0) }
        })
    }

    /// 批量读取大模型 API Key。所有引用都由同一个凭据包返回，不会按端点分别访问 Keychain。
    static func llmCredentials(references: [String]) -> [String: LLMTranslationCredential] {
        let envelope = resolveLegacyCredentials(
            providerReferences: [],
            llmReferences: Set(references)
        )
        return Dictionary(uniqueKeysWithValues: references.compactMap { reference in
            envelope.llmCredentials[reference].map { (reference, $0) }
        })
    }

    /// 从凭据包删除配置，并记录墓碑避免旧版分散 Keychain 项被再次迁移。
    static func deleteCredential(reference: String) {
        var envelope = credentialEnvelope()
        let providerRemoved = envelope.providerCredentials.removeValue(forKey: reference) != nil
        let llmRemoved = envelope.llmCredentials.removeValue(forKey: reference) != nil
        let tombstoneAdded = envelope.deletedReferences.insert(reference).inserted
        guard providerRemoved || llmRemoved || tombstoneAdded else { return }
        _ = saveEnvelope(envelope)
    }

    /// 读取单一凭据包，并在首次遇到旧版配置时批量导入所需的旧 Keychain 条目。
    private static func resolveLegacyCredentials(
        providerReferences: Set<String>,
        llmReferences: Set<String>
    ) -> TranslationCredentialEnvelope {
        var envelope = credentialEnvelope()
        let requestedReferences = providerReferences.union(llmReferences)
        let missingReferences = requestedReferences.filter {
            envelope.providerCredentials[$0] == nil
                && envelope.llmCredentials[$0] == nil
                && !envelope.deletedReferences.contains($0)
        }
        guard !missingReferences.isEmpty else { return envelope }

        let legacyData = legacyCredentialData(references: Set(missingReferences))
        var changed = false
        for reference in missingReferences {
            guard let data = legacyData[reference] else { continue }
            if providerReferences.contains(reference),
               let credential = try? JSONDecoder().decode(TranslationProviderCredential.self, from: data) {
                envelope.providerCredentials[reference] = credential
                changed = true
            } else if llmReferences.contains(reference),
                      let credential = try? JSONDecoder().decode(LLMTranslationCredential.self, from: data) {
                envelope.llmCredentials[reference] = credential
                changed = true
            }
        }

        if changed {
            _ = saveEnvelope(envelope)
        }
        return envelope
    }

    /// 返回进程内缓存的单一凭据包；第一次访问才读取 Keychain。
    private static func credentialEnvelope() -> TranslationCredentialEnvelope {
        if didLoadEnvelope {
            return cachedEnvelope ?? TranslationCredentialEnvelope()
        }
        didLoadEnvelope = true
        let envelope = load(TranslationCredentialEnvelope.self, reference: envelopeReference)
        cachedEnvelope = envelope ?? TranslationCredentialEnvelope()
        return cachedEnvelope ?? TranslationCredentialEnvelope()
    }

    /// 一次查询所有旧版分散项，迁移过程中不会按引用逐一调用 SecItemCopyMatching。
    private static func legacyCredentialData(references: Set<String>) -> [String: Data] {
        guard !references.isEmpty else { return [:] }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let entries = result as? [[String: Any]] else {
            return [:]
        }

        var credentials: [String: Data] = [:]
        for entry in entries {
            guard let reference = entry[kSecAttrAccount as String] as? String,
                  references.contains(reference),
                  let data = entry[kSecValueData as String] as? Data else {
                continue
            }
            credentials[reference] = data
        }
        return credentials
    }

    @discardableResult
    private static func saveEnvelope(_ envelope: TranslationCredentialEnvelope) -> Bool {
        guard save(envelope, reference: envelopeReference) else { return false }
        cachedEnvelope = envelope
        didLoadEnvelope = true
        return true
    }

    @discardableResult
    private static func save<Credential: Encodable>(_ credential: Credential, reference: String) -> Bool {
        guard let data = try? JSONEncoder().encode(credential) else { return false }
        let query = baseQuery(reference: reference)
        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func load<Credential: Decodable>(_ type: Credential.Type, reference: String) -> Credential? {
        var query = baseQuery(reference: reference)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    private static func baseQuery(reference: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference
        ]
    }
}

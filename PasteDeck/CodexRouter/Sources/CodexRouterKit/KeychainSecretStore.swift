//
//  KeychainSecretStore.swift
//  PasteDeck
//
//  Codex 模型路由的 Keychain 密钥存储。
//  API Key 与代理密码的持久层都在这里；credentials.json 只是启用期间
//  的派生物化文件（0600），关闭路由时删除。
//

import Foundation
import Security

/// Keychain 中的路由密钥项。
public enum RouterSecretKind: String {
    /// 端点 API Key，account = "endpoint/<id>"。
    case endpointAPIKey = "endpoint"
    /// 代理密码，account = "proxy"。
    case proxyPassword = "proxy"
}

public enum KeychainSecretStoreError: LocalizedError {
    case failure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .failure(let status):
            return "Keychain 操作失败：\(status)"
        }
    }
}

/// 单一 Keychain 服务名下的密钥存取（个人使用，无需访问组隔离）。
public struct KeychainSecretStore {
    public let service: String

    init(service: String = "PasteDeck Codex Router") {
        self.service = service
    }

    // MARK: - 基础存取

    func setSecret(_ secret: String, kind: RouterSecretKind, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(kind: kind, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainSecretStoreError.failure(status) }
    }

    func secret(kind: RouterSecretKind, account: String) -> String? {
        var query = baseQuery(kind: kind, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(kind: RouterSecretKind, account: String) {
        SecItemDelete(baseQuery(kind: kind, account: account) as CFDictionary)
    }

    /// 删除一个端点的全部密钥。
    func deleteEndpointSecrets(endpointID: String) {
        deleteSecret(kind: .endpointAPIKey, account: "endpoint/\(endpointID)")
    }

    private func baseQuery(kind: RouterSecretKind, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(kind.rawValue)/\(account)",
        ]
    }
}

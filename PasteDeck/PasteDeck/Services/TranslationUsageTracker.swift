//
//  TranslationUsageTracker.swift
//  PasteDeck
//
//  Serializes daily translation-usage snapshot updates outside the UI path.
//

import CryptoKit
import Foundation
import SwiftData

/// 翻译调用种类；原始值保存到 TranslationUsageSnapshot，新增候选值必须保持向后兼容。
enum TranslationUsageKind: String {
    /// 百度、腾讯云、有道和阿里云等常规机器翻译 API。
    case api
    /// OpenAI-compatible chat/completions 大模型翻译调用。
    case llm
}

/// 将翻译调用结果写入本地按日聚合快照。
/// 使用串行队列避免多个已启用 API 并行完成时创建重复的当日快照。
enum TranslationUsageTracker {
    private static let writeQueue = DispatchQueue(label: "com.pastedeck.translation-usage")

    static func recordAPI(
        configuration: TranslationProviderConfiguration,
        sourceText: String,
        result: Result<String, Error>
    ) {
        record(
            usageKind: .api,
            providerKind: configuration.kind.rawValue,
            configurationID: configuration.id.uuidString,
            providerName: configuration.name.isEmpty ? configuration.kind.displayName : configuration.name,
            credentialFingerprint: fingerprint(for: "\(configuration.credentialId)|\(configuration.credentialSecret)"),
            modelName: "",
            sourceText: sourceText,
            result: result,
            promptTokens: 0,
            completionTokens: 0
        )
    }

    static func recordLLM(
        configuration: LLMTranslationConfiguration,
        sourceText: String,
        result: Result<String, Error>,
        promptTokens: Int,
        completionTokens: Int
    ) {
        record(
            usageKind: .llm,
            providerKind: TranslationUsageKind.llm.rawValue,
            configurationID: configuration.id.uuidString,
            providerName: configuration.name,
            credentialFingerprint: fingerprint(for: configuration.apiKey),
            modelName: configuration.model,
            sourceText: sourceText,
            result: result,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    private static func record(
        usageKind: TranslationUsageKind,
        providerKind: String,
        configurationID: String,
        providerName: String,
        credentialFingerprint: String,
        modelName: String,
        sourceText: String,
        result: Result<String, Error>,
        promptTokens: Int,
        completionTokens: Int
    ) {
        writeQueue.async {
            let context = ModelContext(AppModelContainer.container)
            let currentDate = Date()
            let dayStart = Calendar.current.startOfDay(for: currentDate)
            let descriptor = FetchDescriptor<TranslationUsageSnapshot>(
                predicate: #Predicate { $0.date == dayStart }
            )
            let snapshots = (try? context.fetch(descriptor)) ?? []
            let snapshot = snapshots.first {
                $0.usageKindRawValue == usageKind.rawValue
                    && $0.configurationID == configurationID
                    && $0.modelName == modelName
            } ?? TranslationUsageSnapshot(
                date: dayStart,
                usageKindRawValue: usageKind.rawValue,
                providerKindRawValue: providerKind,
                configurationID: configurationID,
                providerName: providerName,
                credentialFingerprint: credentialFingerprint,
                modelName: modelName
            )

            if snapshot.modelContext == nil {
                context.insert(snapshot)
            }

            snapshot.providerName = providerName
            snapshot.credentialFingerprint = credentialFingerprint
            snapshot.requestCount += 1
            snapshot.sourceCharacterCount += sourceText.count
            snapshot.promptTokenCount += max(0, promptTokens)
            snapshot.completionTokenCount += max(0, completionTokens)
            switch result {
            case .success(let translatedText):
                snapshot.successCount += 1
                snapshot.translatedCharacterCount += translatedText.count
            case .failure:
                snapshot.failedCount += 1
            }
            snapshot.updatedAt = currentDate

            guard (try? context.save()) != nil else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .translationUsageDidChange, object: nil)
            }
        }
    }

    private static func fingerprint(for secret: String) -> String {
        let normalizedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty else { return "未配置" }
        let digest = SHA256.hash(data: Data(normalizedSecret.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return "…\(hexDigest.suffix(8))"
    }
}

extension Notification.Name {
    /// 翻译调用统计发生变化时发送，供统计页面刷新按日聚合数据。
    static let translationUsageDidChange = Notification.Name("PasteDeck.translationUsageDidChange")
}

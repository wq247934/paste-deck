//
//  TranslationUsageSnapshot.swift
//  PasteDeck
//
//  Stores one daily aggregate for each translation credential or LLM model.
//

import Foundation
import SwiftData

/// 翻译调用的按日聚合快照。
/// 同一天、同一调用种类、同一配置和同一模型共用一条记录，避免每次翻译都写入一条明细数据。
@Model
final class TranslationUsageSnapshot {
    /// 快照稳定标识，供 SwiftData 和统计列表使用。
    var id: UUID
    /// 快照所属日期的零点，由 Calendar.startOfDay 生成。
    var date: Date
    /// 调用种类原始值；候选值为 api、llm。
    var usageKindRawValue: String
    /// 常规 API 的服务商原始值；候选值为 baidu、tencent、youdao、alibaba，LLM 使用 llm。
    var providerKindRawValue: String
    /// 配置稳定标识的字符串，关联 TranslationProviderConfiguration 或 LLMTranslationConfiguration。
    var configurationID: String
    /// 用户设置的服务或密钥显示名称，保留历史名称以便审计旧调用。
    var providerName: String
    /// 不可逆密钥指纹，仅显示末尾标识，避免在统计中泄露完整密钥。
    var credentialFingerprint: String
    /// 大模型模型标识；常规翻译 API 为空字符串。
    var modelName: String
    /// 当天该配置发出的翻译请求总数，包含失败请求。
    var requestCount: Int
    /// 当天成功返回译文的请求数量。
    var successCount: Int
    /// 当天失败或响应格式异常的请求数量。
    var failedCount: Int
    /// 当天发送给服务商的原文字符数，用于没有 token 返回的常规 API 粗略衡量用量。
    var sourceCharacterCount: Int
    /// 当天成功返回的译文字符数。
    var translatedCharacterCount: Int
    /// 大模型服务返回的输入 token 总数；服务未返回时为零。
    var promptTokenCount: Int
    /// 大模型服务返回的输出 token 总数；服务未返回时为零。
    var completionTokenCount: Int
    /// 最近一次写入该统计快照的时间。
    var updatedAt: Date

    init(
        date: Date,
        usageKindRawValue: String,
        providerKindRawValue: String,
        configurationID: String,
        providerName: String,
        credentialFingerprint: String,
        modelName: String
    ) {
        self.id = UUID()
        self.date = date
        self.usageKindRawValue = usageKindRawValue
        self.providerKindRawValue = providerKindRawValue
        self.configurationID = configurationID
        self.providerName = providerName
        self.credentialFingerprint = credentialFingerprint
        self.modelName = modelName
        self.requestCount = 0
        self.successCount = 0
        self.failedCount = 0
        self.sourceCharacterCount = 0
        self.translatedCharacterCount = 0
        self.promptTokenCount = 0
        self.completionTokenCount = 0
        self.updatedAt = Date()
    }
}

import AppKit
import XCTest
@testable import PasteDeck

final class TranslationConfigurationTests: XCTestCase {
    func testTranslationDefaultsKeepAutomaticSelectionOptIn() {
        let settings = AppSettings()

        XCTAssertEqual(settings.automaticSelectionTranslationEnabled, false)
        XCTAssertNil(settings.automaticSelectionTranslationServiceOrderJSON)
        XCTAssertEqual(settings.selectionTranslationShortcutEnabled, true)
        XCTAssertEqual(settings.screenshotTranslationShortcutEnabled, true)
        XCTAssertEqual(settings.inputTranslationShortcutEnabled, true)
        XCTAssertEqual(settings.selectionTranslationDisplay, "D")
        XCTAssertEqual(settings.screenshotTranslationDisplay, "S")
        XCTAssertEqual(settings.inputTranslationDisplay, "A")
        XCTAssertEqual(
            settings.selectionTranslationModifiers,
            Int(NSEvent.ModifierFlags.option.rawValue)
        )
    }

    func testAutomaticSelectionTranslationUsesConfiguredOrderAcrossAPIAndLLM() {
        let settings = AppSettings()
        let providerConfiguration = TranslationProviderConfiguration(
            kind: .baidu,
            name: "百度默认",
            enabled: true,
            credentialId: "provider-id",
            credentialSecret: "provider-secret",
            region: "ap-guangzhou",
            allowsConcurrentRequests: false
        )
        let llmConfiguration = LLMTranslationConfiguration(
            name: "模型默认",
            baseURL: "https://example.com/v1",
            apiKey: "llm-key",
            model: "translation-model",
            enabled: true
        )
        defer {
            TranslationCredentialStore.deleteCredential(reference: providerConfiguration.credentialReference)
            TranslationCredentialStore.deleteCredential(reference: llmConfiguration.credentialReference)
        }

        settings.translationProviderConfigurations = [providerConfiguration]
        settings.llmTranslationConfigurations = [llmConfiguration]
        settings.automaticSelectionTranslationServiceOrder = [
            AutomaticSelectionTranslationServiceReference(
                kind: .llm,
                configurationID: llmConfiguration.id
            ),
            AutomaticSelectionTranslationServiceReference(
                kind: .api,
                configurationID: providerConfiguration.id
            )
        ]

        let services = settings.resolvedAutomaticSelectionTranslationServices()

        XCTAssertEqual(services.map(\.kind), [.llm, .api])
        XCTAssertEqual(
            services.map(\.configurationID),
            [llmConfiguration.id, providerConfiguration.id]
        )
    }

    func testAutomaticSelectionTranslationAllowsExplicitlyDisablingAllServices() {
        let settings = AppSettings()
        settings.automaticSelectionTranslationServiceOrder = []

        XCTAssertNotNil(settings.automaticSelectionTranslationServiceOrderJSON)
        XCTAssertTrue(settings.resolvedAutomaticSelectionTranslationServices().isEmpty)
    }

    func testMultipleProviderKeysAndLLMConfigurationsRoundTripThroughJSON() {
        let settings = AppSettings()
        let primaryProvider = TranslationProviderConfiguration(
            kind: .tencent,
            name: "腾讯云翻译",
            enabled: true,
            credentialId: "secret-id",
            credentialSecret: "secret-key",
            region: "ap-shanghai",
            allowsConcurrentRequests: true
        )
        let standbyProvider = TranslationProviderConfiguration(
            kind: .tencent,
            name: "腾讯云备用密钥",
            enabled: false,
            credentialId: "standby-id",
            credentialSecret: "standby-key",
            region: "ap-shanghai",
            allowsConcurrentRequests: false
        )
        let llmConfigurations = [
            LLMTranslationConfiguration(name: "模型一", baseURL: "https://one.example/v1", apiKey: "one", model: "model-one"),
            LLMTranslationConfiguration(name: "模型二", baseURL: "https://two.example/v1", apiKey: "two", model: "model-two")
        ]
        defer {
            [primaryProvider, standbyProvider].forEach {
                TranslationCredentialStore.deleteCredential(reference: $0.credentialReference)
            }
            llmConfigurations.forEach {
                TranslationCredentialStore.deleteCredential(reference: $0.credentialReference)
            }
        }

        settings.translationProviderConfigurations = [primaryProvider, standbyProvider]
        settings.llmTranslationConfigurations = llmConfigurations

        XCTAssertEqual(settings.translationProviderConfigurations, [primaryProvider, standbyProvider])
        XCTAssertEqual(settings.llmTranslationConfigurations, llmConfigurations)
        XCTAssertFalse(settings.translationProviderConfigurationsJSON?.contains("secret-id") ?? true)
        XCTAssertFalse(settings.translationProviderConfigurationsJSON?.contains("secret-key") ?? true)
        XCTAssertFalse(settings.llmTranslationConfigurationsJSON?.contains("\"one\"") ?? true)
        XCTAssertEqual(
            TranslationCredentialStore.providerCredential(reference: primaryProvider.credentialReference)?.credentialSecret,
            "secret-key"
        )
        XCTAssertEqual(
            TranslationCredentialStore.llmCredential(reference: llmConfigurations[0].credentialReference)?.apiKey,
            "one"
        )
    }

    func testProviderConfigurationsLimitOneEnabledKeyPerAPI() {
        let settings = AppSettings()
        let primary = TranslationProviderConfiguration(
            kind: .baidu,
            name: "主密钥",
            enabled: true,
            credentialId: "primary-id",
            credentialSecret: "primary-secret",
            region: "ap-guangzhou",
            allowsConcurrentRequests: false
        )
        let backup = TranslationProviderConfiguration(
            kind: .baidu,
            name: "备用密钥",
            enabled: true,
            credentialId: "backup-id",
            credentialSecret: "backup-secret",
            region: "ap-guangzhou",
            allowsConcurrentRequests: false
        )
        let tencent = TranslationProviderConfiguration(
            kind: .tencent,
            name: "腾讯云",
            enabled: true,
            credentialId: "tencent-id",
            credentialSecret: "tencent-secret",
            region: "ap-guangzhou",
            allowsConcurrentRequests: false
        )
        defer {
            [primary, backup, tencent].forEach {
                TranslationCredentialStore.deleteCredential(reference: $0.credentialReference)
            }
        }

        settings.translationProviderConfigurations = [primary, backup, tencent]

        XCTAssertEqual(settings.translationProviderConfigurations.filter { $0.enabled && $0.kind == .baidu }.count, 1)
        XCTAssertEqual(settings.translationProviderConfigurations.filter { $0.enabled && $0.kind == .tencent }.count, 1)
        XCTAssertEqual(settings.translationProviderConfigurations.first(where: { $0.name == "备用密钥" })?.credentialSecret, "backup-secret")
    }

    func testTargetLanguageDetectionSwitchesBetweenChineseAndEnglish() {
        XCTAssertEqual(TranslateService.detectTargetLanguage(for: "这是中文内容"), "en")
        XCTAssertEqual(TranslateService.detectTargetLanguage(for: "PasteDeck translates selected text"), "zh")
    }

    func testLLMPresetsKeepModelEmptyUntilUserSelectsOrEntersOne() {
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.deepSeek))
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.glm))
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.kimi))
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.mimo))
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.openAI))
        XCTAssertTrue(LLMTranslationPreset.allCases.contains(.miniMax))

        let configuration = LLMTranslationConfiguration(
            name: LLMTranslationPreset.deepSeek.displayName,
            baseURL: LLMTranslationPreset.deepSeek.baseURL,
            model: ""
        )
        XCTAssertEqual(configuration.model, "")
        XCTAssertFalse(configuration.isConfigured)
    }

    func testTranslationBrandsMapEverySupportedProviderAndPresetToBundledLogos() {
        XCTAssertEqual(Set(TranslationProviderKind.allCases.map(\.translationBrand)), Set([
            .baidu,
            .tencentCloud,
            .youdao,
            .alibabaCloud
        ]))
        XCTAssertEqual(Set(LLMTranslationPreset.allCases.map(\.translationBrand)), Set([
            .deepSeek,
            .glm,
            .kimi,
            .mimo,
            .openAI,
            .miniMax,
            .qwen
        ]))

        let allBrands = TranslationProviderKind.allCases.map(\.translationBrand)
            + LLMTranslationPreset.allCases.map(\.translationBrand)
        for brand in allBrands {
            guard let logoURL = brand.bundledLogoURL else {
                XCTFail("缺少 \(brand.displayName) 的本地 Logo")
                continue
            }
            XCTAssertNotNil(NSImage(contentsOf: logoURL), "无法解析 \(brand.displayName) 的 SVG Logo")
        }
    }

    func testLLMBrandInferenceUsesOfficialPresetEndpoints() {
        for preset in LLMTranslationPreset.allCases {
            let configuration = LLMTranslationConfiguration(
                name: preset.displayName,
                baseURL: preset.baseURL,
                apiKey: "test-key",
                model: "test-model"
            )
            XCTAssertEqual(configuration.translationBrand, preset.translationBrand)
        }
    }

    func testLongLLMInputRequiresExplicitRiskConfirmation() {
        let source = String(repeating: "翻", count: LLMTranslationTokenSafety.warningTokenLimit)

        XCTAssertGreaterThan(
            LLMTranslationTokenSafety.estimatedInputTokens(for: source),
            LLMTranslationTokenSafety.warningTokenLimit
        )
    }

    func testTranslationWorkspaceSnapshotPreservesRepeatedLLMResultsForComparison() throws {
        let configurationID = UUID()
        let firstOutput = TranslationOutput(
            id: UUID(),
            kind: .llm,
            configurationID: configurationID,
            providerName: "DeepSeek",
            detail: "model-a",
            translatedText: "第一版译文",
            errorMessage: nil,
            isTranslating: false
        )
        let secondOutput = TranslationOutput(
            id: UUID(),
            kind: .llm,
            configurationID: configurationID,
            providerName: "DeepSeek",
            detail: "model-a",
            translatedText: "第二版译文",
            errorMessage: nil,
            isTranslating: false
        )

        let data = try JSONEncoder().encode(TranslationWorkspaceSnapshot(outputs: [firstOutput, secondOutput]))
        let decoded = try JSONDecoder().decode(TranslationWorkspaceSnapshot.self, from: data)

        XCTAssertEqual(decoded.outputs.count, 2)
        XCTAssertEqual(decoded.outputs.map(\.translatedText), ["第一版译文", "第二版译文"])
        XCTAssertEqual(decoded.outputs.map(\.configurationID), [configurationID, configurationID])
    }

    func testMultipleProviderCredentialsResolveFromOneCredentialEnvelope() {
        let firstReference = TranslationCredentialStore.providerReference(for: UUID())
        let secondReference = TranslationCredentialStore.providerReference(for: UUID())
        let credentials = [
            firstReference: TranslationProviderCredential(
                credentialID: "first-id",
                credentialSecret: "first-secret"
            ),
            secondReference: TranslationProviderCredential(
                credentialID: "second-id",
                credentialSecret: "second-secret"
            )
        ]
        defer {
            TranslationCredentialStore.deleteCredential(reference: firstReference)
            TranslationCredentialStore.deleteCredential(reference: secondReference)
        }

        XCTAssertTrue(TranslationCredentialStore.replaceProviderCredentials(credentials, deleting: []))
        XCTAssertEqual(
            TranslationCredentialStore.providerCredentials(references: [firstReference, secondReference]),
            credentials
        )
    }
}

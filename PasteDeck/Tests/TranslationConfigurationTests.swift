import AppKit
import XCTest
@testable import PasteDeck

final class TranslationConfigurationTests: XCTestCase {
    func testTranslationDefaultsKeepAutomaticSelectionOptIn() {
        let settings = AppSettings()

        XCTAssertEqual(settings.automaticSelectionTranslationEnabled, false)
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

    func testLegacyBaiduConfigurationRemainsAvailable() {
        let settings = AppSettings()
        settings.baiduTranslateEnabled = true
        settings.baiduTranslateAppId = "legacy-app-id"
        settings.baiduTranslateSecretKey = "legacy-secret"
        settings.baiduTranslateIsAdvanced = true

        let configuration = settings.translationProviderConfiguration

        XCTAssertEqual(configuration.kind, .baidu)
        XCTAssertEqual(configuration.credentialId, "legacy-app-id")
        XCTAssertEqual(configuration.credentialSecret, "legacy-secret")
        XCTAssertTrue(configuration.allowsConcurrentRequests)
        XCTAssertTrue(configuration.isConfigured)
    }

    func testProviderAndMultipleLLMConfigurationsRoundTripThroughJSON() {
        let settings = AppSettings()
        let provider = TranslationProviderConfiguration(
            kind: .tencent,
            name: "腾讯云翻译",
            enabled: true,
            credentialId: "secret-id",
            credentialSecret: "secret-key",
            region: "ap-shanghai",
            allowsConcurrentRequests: true
        )
        let llmConfigurations = [
            LLMTranslationConfiguration(name: "模型一", baseURL: "https://one.example/v1", apiKey: "one", model: "model-one"),
            LLMTranslationConfiguration(name: "模型二", baseURL: "https://two.example/v1", apiKey: "two", model: "model-two")
        ]

        settings.translationProviderConfiguration = provider
        settings.llmTranslationConfigurations = llmConfigurations

        XCTAssertEqual(settings.translationProviderConfiguration, provider)
        XCTAssertEqual(settings.llmTranslationConfigurations, llmConfigurations)
    }

    func testTargetLanguageDetectionSwitchesBetweenChineseAndEnglish() {
        XCTAssertEqual(TranslateService.detectTargetLanguage(for: "这是中文内容"), "en")
        XCTAssertEqual(TranslateService.detectTargetLanguage(for: "PasteDeck translates selected text"), "zh")
    }
}

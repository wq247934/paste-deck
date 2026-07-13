import XCTest
@testable import PasteDeck

final class TranslationUsageStatsTests: XCTestCase {
    func testTranslationUsageFilteringSummaryAndChartsShareTheSameScope() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let secondDate = calendar.date(byAdding: .day, value: 1, to: firstDate)!
        let usage = [
            makeUsage(
                date: firstDate,
                usageKind: .api,
                providerName: "百度主账号",
                modelName: "",
                requestCount: 3,
                successCount: 2,
                failedCount: 1,
                promptTokenCount: 0,
                completionTokenCount: 0
            ),
            makeUsage(
                date: firstDate,
                usageKind: .api,
                providerName: "腾讯云",
                modelName: "",
                requestCount: 2,
                successCount: 2,
                failedCount: 0,
                promptTokenCount: 0,
                completionTokenCount: 0
            ),
            makeUsage(
                date: secondDate,
                usageKind: .llm,
                providerName: "DeepSeek",
                modelName: "deepseek-chat",
                requestCount: 4,
                successCount: 4,
                failedCount: 0,
                promptTokenCount: 1_200,
                completionTokenCount: 320
            )
        ]

        let apiUsage = StatsService.filterTranslationUsage(usage, by: .api)
        let llmUsage = StatsService.filterTranslationUsage(usage, by: .llm)
        let apiSummary = StatsService.makeTranslationUsageSummary(from: apiUsage)
        let llmSummary = StatsService.makeTranslationUsageSummary(from: llmUsage)
        let dailyPoints = StatsService.makeTranslationUsageDailyPoints(
            from: usage,
            days: 2,
            endingAt: secondDate
        )
        let servicePoints = StatsService.makeTranslationUsageServicePoints(from: usage)

        XCTAssertEqual(apiUsage.reduce(0) { $0 + $1.requestCount }, 5)
        XCTAssertEqual(apiSummary.sourceCharacterCount, 200)
        XCTAssertEqual(apiSummary.translatedCharacterCount, 160)
        XCTAssertEqual(llmSummary.requestCount, 4)
        XCTAssertEqual(llmSummary.successRate, 1)
        XCTAssertEqual(llmSummary.promptTokenCount, 1_200)
        XCTAssertEqual(llmSummary.completionTokenCount, 320)
        XCTAssertEqual(dailyPoints.map(\.requestCount), [5, 0, 0, 4])
        XCTAssertEqual(dailyPoints.map(\.successCount), [4, 0, 0, 4])
        XCTAssertEqual(dailyPoints.map(\.failedCount), [1, 0, 0, 0])
        XCTAssertEqual(dailyPoints.map(\.sourceCharacterCount), [200, 0, 0, 100])
        XCTAssertEqual(servicePoints.first?.displayName, "DeepSeek · deepseek-chat")
        XCTAssertEqual(servicePoints.first?.requestCount, 4)
        XCTAssertEqual(servicePoints.first?.promptTokenCount, 1_200)
        XCTAssertEqual(servicePoints.first?.completionTokenCount, 320)
    }

    private func makeUsage(
        date: Date,
        usageKind: TranslationUsageKind,
        providerName: String,
        modelName: String,
        requestCount: Int,
        successCount: Int,
        failedCount: Int,
        promptTokenCount: Int,
        completionTokenCount: Int
    ) -> TranslationUsageStat {
        TranslationUsageStat(
            id: UUID(),
            date: date,
            usageKind: usageKind.rawValue,
            providerKind: usageKind == .api ? TranslationProviderKind.baidu.rawValue : TranslationUsageKind.llm.rawValue,
            providerName: providerName,
            credentialFingerprint: "…test",
            modelName: modelName,
            requestCount: requestCount,
            successCount: successCount,
            failedCount: failedCount,
            sourceCharacterCount: 100,
            translatedCharacterCount: 80,
            promptTokenCount: promptTokenCount,
            completionTokenCount: completionTokenCount
        )
    }
}

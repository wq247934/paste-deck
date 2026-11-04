import AgentSpeedCore
import Foundation
import Testing
@testable import AgentSpeedKit

/// PasteDeck 集成层的最小回归测试：设置隔离、显示模式与监控开关语义。
/// 引擎算法一致性由 AgentSpeedCoreTests（889 项）保证，此处不重复。
@MainActor
@Suite("AgentSpeedKit integration")
struct AgentSpeedKitTests {

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "AgentSpeedKitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func settingsRoundTripAndDefaults() {
        let defaults = Self.isolatedDefaults()
        let settings = AgentSpeedSettings(defaults: defaults)
        // 全新用户：总监控开启、菜单栏仅额度（保持升级前行为）、全部来源启用。
        #expect(settings.monitorEnabled)
        #expect(settings.barSpeedDisplay == .quotaOnly)
        #expect(settings.enabledSources == Set(SourceKind.allCases))
        #expect(settings.effects == .standard)

        settings.monitorEnabled = false
        settings.barSpeedDisplay = .both
        settings.enabledSources = [.codex, .claudeCode]

        let reloaded = AgentSpeedSettings(defaults: defaults)
        #expect(!reloaded.monitorEnabled)
        #expect(reloaded.barSpeedDisplay == .both)
        #expect(reloaded.enabledSources == [.codex, .claudeCode])
    }

    @Test func monitorConfigurationFollowsEnabledSourcesAndRoots() throws {
        let defaults = Self.isolatedDefaults()
        let settings = AgentSpeedSettings(defaults: defaults)
        settings.enabledSources = [SourceKind.zcode]
        let root = URL(fileURLWithPath: "/tmp/agent-speed-kit-tests-zcode")
        settings.zcodeRoot = root

        let configuration = settings.monitorConfiguration
        #expect(configuration.enabledSources == [SourceKind.zcode])
        #expect(configuration.zcodeRoot == root)
    }

    @Test func speedBarDisplayTitlesAreStable() {
        #expect(SpeedBarDisplay.quotaOnly.title == "仅显示额度")
        #expect(SpeedBarDisplay.speedOnly.title == "仅显示实时速度")
        #expect(SpeedBarDisplay.both.title == "额度＋实时速度")
        #expect(SpeedBarDisplay.off.title == "不显示额外数据")
    }

    @Test func speedFormatMatchesCoreSemantics() {
        // 仪表盘与菜单栏共用 Core 的 SpeedFormat；抽两例确认语义未被集成层改变。
        #expect(SpeedFormat.speed(0) == "0")
        #expect(SpeedFormat.speed(42.5) == "43" || SpeedFormat.speed(42.5) == "42.5")
    }
}

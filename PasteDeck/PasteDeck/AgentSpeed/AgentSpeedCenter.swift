//
//  AgentSpeedCenter.swift
//  PasteDeck
//
//  AI 实时测速的宿主接线层：持有 AgentSpeedKit 的 AgentSpeedModel，
//  实现其 AgentSpeedCommands 协议（仪表窗口、历史窗口、悬浮球开关与设置入口），
//  并管理悬浮球窗口栈与监控生命周期。
//
//  引擎与动画来自 Agent Speed（MIT，见 PasteDeck/AgentSpeed/LICENSE-AgentSpeed）；
//  此层只做生命周期、窗口与 PasteDeck 设置体系的桥接，不重复实现任何测速逻辑。
//

import AgentSpeedCore
import AgentSpeedOrbModel
import AgentSpeedKit
import AgentSpeedKit
import AppKit
import SwiftUI

// MARK: - 通知

extension Notification.Name {
    /// 每个 500ms 引擎快照后发出（主线程），供菜单栏速度文本与菜单区块刷新。
    static let agentSpeedSnapshotDidUpdate = Notification.Name("PasteDeck.agentSpeedSnapshotDidUpdate")
    /// 菜单栏速度显示模式变化后发出，AppDelegate 重新合成状态栏文本。
    static let agentSpeedBarDisplayDidChange = Notification.Name("PasteDeck.agentSpeedBarDisplayDidChange")
    /// 打开「AI 实时测速」独立工具窗口。
    static let openAgentSpeedDashboard = Notification.Name("PasteDeck.openAgentSpeedDashboard")
    /// 打开设置窗口并定位到「AI 测速」页。
    static let openAgentSpeedSettings = Notification.Name("PasteDeck.openAgentSpeedSettings")
    /// AI 测速设置发生变化，工具窗口等宿主界面刷新本地状态。
    static let agentSpeedSettingsDidReload = Notification.Name("PasteDeck.agentSpeedSettingsDidReload")
}

@MainActor
final class AgentSpeedCenter {

    static let shared = AgentSpeedCenter()

    let model = AgentSpeedModel()

    private var orbWindows: OrbWindowManager?
    private var historyWindow: HistoryWindowController?
    private(set) var isActivated = false

    private init() {
        model.commands = self
    }

    // MARK: - 生命周期

    /// 启动监控与悬浮球窗口栈。幂等；AppDelegate 在启动完成后调用。
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        model.activate(live: model.settings.monitorEnabled)
        orbWindows = OrbWindowManager(model: model)
        orbWindows?.boardShapes = { [] }
        // 引擎每 500ms 发布一次快照；主线程监听转发为 PasteDeck 通知。
        model.store.addLiveListener { [weak self] _ in
            NotificationCenter.default.post(name: .agentSpeedSnapshotDidUpdate, object: nil)
        }
    }

    func shutdown() {
        guard isActivated else { return }
        isActivated = false
        historyWindow?.close()
        historyWindow = nil
        orbWindows = nil
        model.shutdown()
    }

    // MARK: - 悬浮球窗口

    var areOrbWindowsActive: Bool { orbWindows != nil }

    /// 总开关关闭时监控重启（设置页切换后调用）。
    func applyMonitorEnabled() {
        guard isActivated else { return }
        let enabled = model.settings.monitorEnabled
        if enabled, model.monitor == nil {
            model.activate(live: true)
        } else if !enabled, let monitor = model.monitor {
            monitor.stop()
        }
    }

    // MARK: - 菜单栏速度文本

    /// 当前实时速度的一段式文本（数值已按显示指标换算）。
    var speedBarText: String? {
        let snapshot = model.store.snapshot
        let value = model.value(of: snapshot.live)
        return SpeedFormat.speed(value)
    }

    /// 活跃（生成中）Agent 数量。
    var activeAgentCount: Int { model.store.snapshot.generatingCount }

    // MARK: - 菜单栏速度分段

    /// 等宽数字字体，与额度分段保持一致。
    private static let barFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    /// 宽度治理：数值变大立即放宽，变小延迟 5 秒收窄，避免状态栏宽度频繁跳变
    /// （对齐上游 StatusItemWidthGovernor 的语义）。
    private var lastSpeedText: String?
    private var lastSpeedWidth: CGFloat = 0
    private var shrinkPendingSince: Date?

    /// 菜单栏图标旁的实时速度分段；监控关闭或不可测量时返回 nil。
    /// - Parameter force: true 时跳过收窄延迟（例如打开菜单时）。
    func menuBarSpeedAttributedTitle(force: Bool = false) -> NSAttributedString? {
        guard model.settings.monitorEnabled else { return nil }
        let text = speedBarText
        guard let text else { return nil }

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.barFont,
                .foregroundColor: speedColor(for: model.value(of: model.store.snapshot.live)),
            ]
        )
        let width = attributed.size().width

        if lastSpeedWidth > 0 {
            if width < lastSpeedWidth - 0.5, !force {
                // 变窄：5 秒内保持旧宽度对应的文本，期间只更新数值颜色。
                if shrinkPendingSince == nil { shrinkPendingSince = Date() }
                if let since = shrinkPendingSince, Date().timeIntervalSince(since) < 5 {
                    if let held = lastSpeedText {
                        return NSAttributedString(
                            string: held,
                            attributes: [
                                .font: Self.barFont,
                                .foregroundColor: speedColor(for: model.value(of: model.store.snapshot.live)),
                            ]
                        )
                    }
                }
            }
        }
        shrinkPendingSince = nil
        lastSpeedText = text
        lastSpeedWidth = width
        return attributed
    }

    /// 速度文本颜色：接近红线时转暖。
    private func speedColor(for value: Double) -> NSColor {
        let redline = model.settings.redline
        guard redline > 0 else { return .labelColor }
        let ratio = value / redline
        if ratio >= 0.75 { return .systemRed }
        if ratio >= 0.375 { return .systemOrange }
        return .labelColor
    }
}

// MARK: - AgentSpeedCommands（宿主实现）

extension AgentSpeedCenter: AgentSpeedCommands {

    func showDashboard() {
        NotificationCenter.default.post(name: .openAgentSpeedDashboard, object: nil)
    }

    func closeDashboard() {
        // 工具窗口自带关闭逻辑（Esc / ⌘W / 关闭按钮），此处无需额外动作。
    }

    func showHistory(source: SourceKind?) {
        openHistory(source: source, metric: nil)
    }

    func showHistory(source: SourceKind?, metric: HistoryChartMetric) {
        openHistory(source: source, metric: metric)
    }

    private func openHistory(source: SourceKind?, metric: HistoryChartMetric?) {
        if historyWindow == nil {
            historyWindow = HistoryWindowController(model: model)
        }
        historyWindow?.show(source: source, metric: metric)
    }

    func setOrbsVisible(_ visible: Bool) {
        model.orbs.masterVisible = visible
    }

    func resetOrbPosition(_ id: String) {
        model.orbs.resetPosition(id)
    }

    func showOrbSettings(_ id: String?) {
        model.orbs.settingsSelection = id
        NotificationCenter.default.post(name: .openSettingsWindow, object: SettingsPane.agentSpeed)
    }

    func showAgentSpeedSettings() {
        NotificationCenter.default.post(name: .openSettingsWindow, object: SettingsPane.agentSpeed)
    }

    func quit() {
        // 宿主应用的退出交给 PasteDeck 菜单；悬浮球菜单里的“退出”按隐藏悬浮球处理，
        // 避免用户从仪表菜单意外关闭整个 PasteDeck。
        setOrbsVisible(false)
    }
}

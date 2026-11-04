//
//  AgentSpeedSettingsView.swift
//  PasteDeck
//
//  设置页「AI 测速」面板：总监控开关、数据来源开关、悬浮仪表、动画强度、
//  菜单栏显示模式与历史数据维护。全部配置落在 AgentSpeedKit 的
//  AgentSpeedSettings（UserDefaults，键名与上游 Agent Speed 兼容）。
//

import AgentSpeedCore
import AgentSpeedOrbModel
import AgentSpeedKit
import SwiftUI

struct AgentSpeedSettingsView: View {
    private var settings: AgentSpeedSettings { AgentSpeedCenter.shared.model.settings }
    private var model: AgentSpeedModel { AgentSpeedCenter.shared.model }

    @State private var monitorEnabled = true
    @State private var barMode: SpeedBarDisplay = .quotaOnly
    @State private var effects: EffectsLevel = .standard
    @State private var metric: SpeedMetric = .output
    @State private var redline: Double = 2000
    @State private var orbsVisible = true
    @State private var orbNames: OrbNamesMode = .auto
    @State private var enabledSources: Set<SourceKind> = Set(SourceKind.allCases)
    @State private var trafficEnabled = true
    @State private var celebratePeaks = true
    @State private var responsePulses = true
    @State private var syncPrices = true
    @State private var currency = "USD"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            monitorSection
            sourceSection
            orbSection
            animationSection
            menuBarSection
            displaySection
            historySection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .agentSpeedSettingsDidReload)) { _ in
            reload()
        }
    }

    private func reload() {
        let s = settings
        monitorEnabled = s.monitorEnabled
        barMode = s.barSpeedDisplay
        effects = s.effects
        metric = s.metric
        redline = s.redline
        orbsVisible = s.orbsVisible
        orbNames = s.orbNames
        enabledSources = s.enabledSources
        trafficEnabled = s.trafficEnabled
        celebratePeaks = s.celebratePeaks
        responsePulses = s.responsePulses
        syncPrices = s.syncPrices
        currency = s.currency
    }

    // MARK: - 区块容器

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
        }
    }

    // MARK: - 监控

    private var monitorSection: some View {
        card("监控") {
            Toggle(isOn: Binding(
                get: { monitorEnabled },
                set: { newValue in
                    monitorEnabled = newValue
                    settings.monitorEnabled = newValue
                    AgentSpeedCenter.shared.applyMonitorEnabled()
                    NotificationCenter.default.post(name: .agentSpeedSettingsDidReload, object: nil)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("启用 AI 实时测速")
                        .font(.system(size: 13))
                    Text("关闭后停止读取本地 Agent 日志，悬浮仪表与菜单栏速度随之暂停；已保存的历史不受影响。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - 数据来源

    private var sourceSection: some View {
        card("数据来源") {
            Text("自动检测本机已安装或存在本地记录的 AI 工具；日志目录保持只读。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SourceKind.allCases, id: \.rawValue) { kind in
                    sourceRow(kind)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ kind: SourceKind) -> some View {
        let status = model.snapshot.sources.first { $0.kind == kind }
        let detected = status?.available ?? false
        HStack(spacing: 8) {
            Circle()
                .fill(kind.tint.color.opacity(detected ? 1 : 0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.l10n(kind.titleKey))
                    .font(.system(size: 12.5))
                Text(detected
                     ? "已检测到本地数据（\(status?.sessionCount ?? 0) 个会话）"
                     : "未检测到本地数据")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { enabledSources.contains(kind) },
                set: { on in
                    if on {
                        enabledSources.insert(kind)
                    } else {
                        enabledSources.remove(kind)
                    }
                    settings.enabledSources = enabledSources
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - 悬浮仪表

    private var orbSection: some View {
        card("悬浮仪表") {
            toggleRow("显示悬浮仪表", detail: "桌面常驻的速度仪表，可拖动、吸附边缘；右键仪表可调整样式与数据来源。", isOn: Binding(
                get: { orbsVisible },
                set: { newValue in
                    orbsVisible = newValue
                    AgentSpeedCenter.shared.setOrbsVisible(newValue)
                }
            ))
            Picker("铭牌", selection: Binding(
                get: { orbNames },
                set: { orbNames = $0; settings.orbNames = $0 }
            )) {
                Text("自动").tag(OrbNamesMode.auto)
                Text("始终显示").tag(OrbNamesMode.always)
                Text("从不显示").tag(OrbNamesMode.never)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240, alignment: .leading)
            HStack(spacing: 4) {
                Text("铭牌显示 Agent 名称与速度，自动模式在空闲时隐藏。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 动画

    private var animationSection: some View {
        card("动画") {
            HStack(spacing: 10) {
                Text("动画强度")
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Picker("", selection: Binding(
                    get: { effects },
                    set: { effects = $0; settings.effects = $0 }
                )) {
                    ForEach(EffectsLevel.allCases) { level in
                        Text(model.l10n(level.titleKey)).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }
            toggleRow("庆祝速度纪录", detail: "刷新今日峰值时播放庆祝特效。", isOn: Binding(
                get: { celebratePeaks },
                set: { celebratePeaks = $0; settings.celebratePeaks = $0 }
            ))
            toggleRow("响应完成脉冲", detail: "一次响应完成时仪表播放冲击波。", isOn: Binding(
                get: { responsePulses },
                set: { responsePulses = $0; settings.responsePulses = $0 }
            ))
            Text("系统「减弱动态效果」开启时，动画自动退化为直接状态切换。")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 菜单栏

    private var menuBarSection: some View {
        card("菜单栏") {
            HStack(spacing: 10) {
                Text("图标旁显示")
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Picker("", selection: Binding<SpeedBarDisplay>(
                    get: { barMode },
                    set: { newValue in
                        barMode = newValue
                        settings.barSpeedDisplay = newValue
                        NotificationCenter.default.post(name: .agentSpeedBarDisplayDidChange, object: nil)
                    }
                )) {
                    ForEach(SpeedBarDisplay.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
            }
            Text("速度数值使用等宽数字并延迟收窄，避免宽度频繁跳变。")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 显示

    private var displaySection: some View {
        card("速度显示") {
            HStack(spacing: 10) {
                Text("指标")
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Picker("", selection: Binding(
                    get: { metric },
                    set: { newValue in
                        metric = newValue
                        settings.metric = newValue
                        redline = settings.redline
                    }
                )) {
                    Text(model.l10n(SpeedMetric.output.titleKey)).tag(SpeedMetric.output)
                    Text(model.l10n(SpeedMetric.total.titleKey)).tag(SpeedMetric.total)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            HStack(spacing: 10) {
                Text("满档速度")
                    .font(.system(size: 13))
                Slider(value: Binding(
                    get: { SettingsLimits.position(ofRedline: redline, metric: metric) },
                    set: { newValue in
                        redline = SettingsLimits.redline(atPosition: newValue, metric: metric)
                        settings.redline = redline
                    }
                ), in: 0...1)
                .frame(width: 240)
                Text("\(SpeedFormat.speed(redline)) tok/s")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
            }
            Text("满档速度定义仪表的红线档位，各速度等级按其比例划分。")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 历史与成本

    private var historySection: some View {
        card("历史与成本") {
            toggleRow("网络同步价格表", detail: "从上游同步公开的模型价格表与汇率以估算成本；关闭时使用内置价格表。默认关闭。", isOn: Binding(
                get: { syncPrices },
                set: { newValue in
                    syncPrices = newValue
                    settings.networkEnabled = newValue
                    settings.syncPrices = newValue
                }
            ))
            HStack(spacing: 10) {
                Text("历史统计")
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Button("打开历史记录…") {
                    AgentSpeedCenter.shared.showHistory(source: nil)
                }
                Button("清除并重建…", role: .destructive) {
                    clearHistoryConfirmed()
                }
            }
            Text("每日聚合保存在 PasteDeck 自己的数据库中，不依赖原始日志长期存在；不会上传任何对话内容。")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    private func clearHistoryConfirmed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除 AI 测速历史？"
        alert.informativeText = "将删除已保存的每日统计并重新分析当前日志；此操作不可撤销。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearHistory()
        }
    }
}

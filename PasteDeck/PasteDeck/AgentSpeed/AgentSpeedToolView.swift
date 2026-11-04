//
//  AgentSpeedToolView.swift
//  PasteDeck
//
//  工具中心「AI 实时测速」的主面板：完整嵌入 Agent Speed 的原版仪表盘
//  （载具动画 Hero、实时曲线、来源与 Agent 列表、今日用量与悬浮球开关）。
//  布局数据全部来自 AgentSpeedKit 的实时监控，不伪造任何速度。
//

import AgentSpeedCore
import AgentSpeedOrbModel
import AgentSpeedKit
import SwiftUI

struct AgentSpeedToolView: View {
    private var model: AgentSpeedModel { AgentSpeedCenter.shared.model }

    @State private var monitorEnabled = true

    var body: some View {
        Group {
            if monitorEnabled {
                dashboard
            } else {
                disabledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .agentSpeedSettingsDidReload)) { _ in
            reload()
        }
    }

    private func reload() {
        monitorEnabled = model.settings.monitorEnabled
        // 工具窗口打开时确保监控已启动（幂等），并按需补一次历史分析。
        AgentSpeedCenter.shared.activate()
    }

    /// 原版仪表盘：固定 368pt 设计宽度，在工具窗口中水平居中。
    private var dashboard: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)
            DashboardView(model: model, maxHeight: nil, embedded: true)
            Spacer(minLength: 0)
        }
    }

    /// 监控被关闭时的说明状态，不留整片空白。
    private var disabledState: some View {
        VStack(spacing: 14) {
            Image(systemName: "speedometer")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text("AI 实时测速已关闭")
                .font(.system(size: 15, weight: .semibold))
            Text("在设置中开启监控后，这里将实时显示 AI Agent 的输出速度、\n活跃 Agent 与今日用量。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("打开设置…") {
                NotificationCenter.default.post(name: .openSettingsWindow, object: SettingsPane.agentSpeed)
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

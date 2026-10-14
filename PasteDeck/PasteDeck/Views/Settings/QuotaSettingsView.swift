//
//  QuotaSettingsView.swift
//  PasteDeck
//
//  额度设置页：仅提供配置项——菜单栏余额显示开关、Gemini 代理端点与密码、
//  workbuddy2api 网关连接配置。额度数据本身通过菜单栏「额度详情…」打开
//  独立的额度查看工具窗口呈现。
//

import SwiftUI
import SwiftData

/// Codex / Gemini / WorkBuddy 的品牌展示色。
enum QuotaBrandColor {
    static let codex = Color.teal
    static let gemini = Color(red: 0.28, green: 0.52, blue: 0.94)
    static let workBuddy = Color.yellow
}

struct QuotaSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeColors) private var themeColors
    @Query private var settings: [AppSettings]
    @ObservedObject private var quota = QuotaStatusManager.shared

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        SettingsContentStack {
            Text("Codex、Gemini 与 WorkBuddy 的余额与用量数据请通过菜单栏「额度详情…」或工作台搜索「额度查看」打开独立工具窗口查看，本页仅提供相关配置。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            menuBarCard
            geminiConfigCard
            workbuddyGatewayConfigCard
        }
    }

    // MARK: - 菜单栏开关

    private var menuBarCard: some View {
        SettingsCard(
            title: "菜单栏",
            icon: "menubar.rectangle",
            footer: "开启后菜单栏图标旁显示 Codex（C）、Gemini（G）与 WorkBuddy（W）余额，不足时自动变红。"
        ) {
            SettingsRow(
                title: "在菜单栏显示余额",
                subtitle: "无需打开菜单即可随时查看最新余额"
            ) {
                Toggle("", isOn: Binding(
                    get: { appSettings.showQuotaInMenuBar ?? false },
                    set: { enabled in
                        appSettings.showQuotaInMenuBar = enabled
                        try? modelContext.save()
                        NotificationCenter.default.post(
                            name: QuotaStatusManager.menuBarDisplayDidChange,
                            object: nil,
                            userInfo: [QuotaStatusManager.menuBarDisplayEnabledKey: enabled]
                        )
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    // MARK: - Gemini 代理配置

    private var geminiConfigCard: some View {
        SettingsCard(
            title: "Gemini 代理配置",
            icon: "slider.horizontal.3",
            footer: "直连本地 Antigravity-Manager 容器管理接口（默认 8045 端口），读取 Google 账号配额、模型速率限制与 Token 统计。"
        ) {
            SettingsRow(
                title: "启用 Gemini 额度查询",
                subtitle: "关闭后不再向本地代理发起 Gemini 额度请求"
            ) {
                Toggle("", isOn: Binding(
                    get: { appSettings.geminiQuotaEnabled ?? true },
                    set: { enabled in
                        appSettings.geminiQuotaEnabled = enabled
                        try? modelContext.save()
                        quota.refreshGemini(force: true)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsRow(
                title: "管理端点 (Base URL)",
                subtitle: "默认 http://127.0.0.1:8045"
            ) {
                TextField("http://127.0.0.1:8045", text: Binding(
                    get: { appSettings.geminiQuotaEndpoint ?? "" },
                    set: { val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        appSettings.geminiQuotaEndpoint = trimmed.isEmpty ? nil : trimmed
                        try? modelContext.save()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }

            SettingsRow(
                title: "管理密码 (WEB_PASSWORD)",
                subtitle: "Antigravity-Manager .env 中的 WEB_PASSWORD 密码"
            ) {
                SecureField("默认密码", text: Binding(
                    get: { appSettings.geminiQuotaToken ?? "" },
                    set: { val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        appSettings.geminiQuotaToken = trimmed.isEmpty ? nil : trimmed
                        try? modelContext.save()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }
        }
    }

    // MARK: - workbuddy2api 网关配置

    private var workbuddyGatewayConfigCard: some View {
        SettingsCard(
            title: "workbuddy2api 网关配置",
            icon: "server.rack",
            footer: "自托管网关（默认 http://127.0.0.1:17863），用于查看账号池健康度、多账号积分包与网关用量统计。"
        ) {
            SettingsRow(
                title: "启用网关监控",
                subtitle: "关闭后不再查询网关账号池与用量数据"
            ) {
                Toggle("", isOn: Binding(
                    get: { appSettings.workbuddyGatewayEnabled ?? true },
                    set: { enabled in
                        appSettings.workbuddyGatewayEnabled = enabled
                        try? modelContext.save()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            SettingsRow(
                title: "网关地址 (Base URL)",
                subtitle: "默认 http://127.0.0.1:17863"
            ) {
                TextField("http://127.0.0.1:17863", text: Binding(
                    get: { appSettings.workbuddyGatewayBaseURL ?? "" },
                    set: { val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        appSettings.workbuddyGatewayBaseURL = trimmed.isEmpty ? nil : trimmed
                        try? modelContext.save()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }

            SettingsRow(
                title: "API Key",
                subtitle: "网关鉴权 Token"
            ) {
                SecureField("默认 Key", text: Binding(
                    get: { appSettings.workbuddyGatewayApiKey ?? "" },
                    set: { val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        appSettings.workbuddyGatewayApiKey = trimmed.isEmpty ? nil : trimmed
                        try? modelContext.save()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }
        }
    }
}

// MARK: - 进度条与占位状态

struct QuotaProgressBar: View {
    let fraction: Double
    let color: Color
    var track: Color = Color.primary.opacity(0.08)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 8)
    }
}

struct QuotaHeroLoadingState: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(tint)
            Text("正在获取余额…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 18)
    }
}

struct QuotaHeroErrorState: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text("无法获取余额")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 8)
    }
}

struct QuotaHeroInactiveState: View {
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("—")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            Text("\(label)暂未激活，等待系统分配")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

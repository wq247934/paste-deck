//
//  QuotaSettingsView.swift
//  PasteDeck
//
//  额度设置页：双 hero 卡片（Codex / WorkBuddy）+ 账户订阅、合计可用、
//  积分包面板的仪表盘布局，并提供“在菜单栏显示余额”开关。
//  信息结构移植自 codex-quota-utools 插件。
//
//  Created on 2026-10-11.
//

import SwiftUI
import SwiftData

/// Codex / WorkBuddy 的品牌展示色。
private enum QuotaBrandColor {
    static let codex = Color.teal
    static let workBuddy = Color.yellow
}

struct QuotaSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeColors) private var themeColors
    @Query private var settings: [AppSettings]
    @ObservedObject private var quota = QuotaStatusManager.shared

    @State private var now = Date()
    @State private var isCodexExpanded = false
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
            Text("通过本机 ChatGPT / Codex 内置服务查询速率限制；WorkBuddy 读取本地桌面版凭证直连腾讯官方计费接口。数据不经过第三方。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 14) {
                codexHeroCard
                workbuddyHeroCard
            }

            accountCard
            totalsCard
            packagesCard
            menuBarCard

            HStack(spacing: 10) {
                Text(quota.lastUpdatedText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if quota.isRefreshingCodex || quota.isRefreshingWorkBuddy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    quota.refresh(force: true)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                .disabled(quota.isRefreshingCodex || quota.isRefreshingWorkBuddy)
            }
        }
        .onReceive(timer) { _ in
            now = Date()
        }
        .task {
            quota.refreshIfStale(maxAge: 120)
        }
    }

    // MARK: - Codex hero 卡片

    private var codexHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TranslationBrandLogoView(brand: .openAI, size: 34)
                Text("Codex")
                    .font(.system(size: 15, weight: .semibold))
                if let plan = quota.codexSnapshot?.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(QuotaBrandColor.codex))
                }
                Spacer()
                if quota.codexSnapshot != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isCodexExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isCodexExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }

            if quota.codexError != nil, quota.codexSnapshot == nil {
                QuotaHeroErrorState(text: quota.codexError ?? "查询失败")
            } else if let snapshot = quota.codexSnapshot {
                if snapshot.session.isAvailable {
                    let remaining = snapshot.isRateLimitReached ? 0 : snapshot.session.remainingPercent
                    let statusColor = QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Int(remaining.rounded()))%")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(snapshot.isRateLimitReached || remaining <= 15 ? .red : .primary)
                            Text(sessionResetLine(snapshot))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(snapshot.resetCreditsAvailableCount.map { "\($0) 张" } ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("可用重置卡")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    QuotaProgressBar(
                        fraction: remaining / 100,
                        color: statusColor,
                        track: QuotaBrandColor.codex.opacity(0.15)
                    )

                    if quota.codexError != nil {
                        Text("上次刷新失败，已展示缓存数据")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                } else {
                    QuotaHeroInactiveState(label: "5 小时额度", tint: QuotaBrandColor.codex)
                }
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.codex)
            }

            if isCodexExpanded, let snapshot = quota.codexSnapshot {
                codexExpandedDetail(snapshot)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(QuotaBrandColor.codex.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuotaBrandColor.codex.opacity(0.16), lineWidth: 1)
        )
    }

    /// Codex 卡片展开区：每周额度窗口与重置卡明细。
    @ViewBuilder
    private func codexExpandedDetail(_ snapshot: CodexQuotaService.Snapshot) -> some View {
        Divider()
            .overlay(QuotaBrandColor.codex.opacity(0.2))

        if snapshot.weekly.isAvailable {
            let remaining = snapshot.isRateLimitReached ? 0 : snapshot.weekly.remainingPercent
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每周额度")
                            .font(.system(size: 12, weight: .medium))
                        if let resetsAt = snapshot.weekly.resetsAt {
                            Text("\(QuotaFormat.dateTimeText(resetsAt)) 重置\(countdownSuffix(resetsAt))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(Int(remaining.rounded()))% 剩余")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(snapshot.isRateLimitReached || remaining <= 15 ? .red : .primary)
                }
                QuotaProgressBar(
                    fraction: remaining / 100,
                    color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex),
                    track: QuotaBrandColor.codex.opacity(0.15)
                )
            }
        } else {
            Text("每周额度暂未激活")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }

        if snapshot.resetCreditsAvailableCount != nil || !snapshot.resetCredits.isEmpty {
            Divider()
                .overlay(QuotaBrandColor.codex.opacity(0.2))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("重置卡")
                        .font(.system(size: 12, weight: .semibold))
                    if let count = snapshot.resetCreditsAvailableCount {
                        Text("可用 \(count) 张")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if snapshot.resetCredits.isEmpty {
                    Text("当前没有可用的速率重置卡。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(snapshot.resetCredits.enumerated()), id: \.offset) { _, credit in
                        compactResetCreditRow(credit)
                    }
                }
            }
        }
    }

    private func compactResetCreditRow(_ credit: CodexQuotaService.ResetCredit) -> some View {
        let daysLeft = credit.expiresAt.map { max(0, Int(ceil($0.timeIntervalSince(now) / 86400))) }
        let urgent = (daysLeft ?? Int.max) <= 2

        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(credit.title ?? "速率重置卡")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let expiresAt = credit.expiresAt {
                    Text("\(QuotaFormat.dateTimeText(expiresAt)) 过期")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            SettingsStatusPill(
                text: credit.status == "available" || credit.status == nil ? "可用" : (credit.status ?? "未知"),
                color: urgent ? .red : .green
            )
        }
    }

    private func sessionResetLine(_ snapshot: CodexQuotaService.Snapshot) -> String {
        guard snapshot.session.isAvailable else { return "额度暂未激活" }
        guard let resetsAt = snapshot.session.resetsAt else { return "重置时间未知" }
        var line = "\(QuotaFormat.clockText(resetsAt)) 重置"
        if let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) {
            line += " · \(countdown)"
        }
        return line
    }

    private func countdownSuffix(_ resetsAt: Date) -> String {
        guard let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) else { return "" }
        return " · \(countdown)"
    }

    // MARK: - WorkBuddy hero 卡片

    private var workbuddyHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("WorkBuddy")
                        .font(.system(size: 15, weight: .semibold))
                    Text("腾讯 CodeBuddy")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if quota.workbuddyError != nil, quota.workbuddySnapshot == nil {
                QuotaHeroErrorState(text: quota.workbuddyError ?? "查询失败")
            } else if let snapshot = quota.workbuddySnapshot {
                let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.total > 0 ? QuotaFormat.smartPercent(remainingPercent) : "—")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(remainingPercent <= 15 ? .red : .primary)
                        Text("剩余 \(QuotaFormat.groupedNumber(snapshot.remain)) 积分")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(QuotaFormat.compactCredits(snapshot.used)) / \(QuotaFormat.compactCredits(snapshot.total))")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("已使用")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                QuotaProgressBar(
                    fraction: remainingPercent / 100,
                    color: QuotaFormat.remainingColor(remainingPercent: remainingPercent, base: QuotaBrandColor.workBuddy),
                    track: QuotaBrandColor.workBuddy.opacity(0.18)
                )

                if quota.workbuddyError != nil {
                    Text("上次刷新失败，已展示缓存数据")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.workBuddy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(QuotaBrandColor.workBuddy.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuotaBrandColor.workBuddy.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 账户与订阅

    private var accountCard: some View {
        QuotaPanelCard(icon: "person.crop.circle", iconTint: .blue, title: "账户与订阅") {
            if let snapshot = quota.workbuddySnapshot {
                HStack(spacing: 8) {
                    Text(snapshot.accountName.map {
                        $0 + (snapshot.accountType.map { " · \($0)" } ?? "")
                    } ?? "未知")
                        .font(.system(size: 13))
                    SettingsStatusPill(
                        text: snapshot.isPaidUser ? "付费用户" : "免费用户",
                        color: snapshot.isPaidUser ? .green : .orange
                    )
                }
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        } content: {
            QuotaPanelRow(title: "订阅方案") {
                Text(quota.workbuddySnapshot?.subscriptionName ?? "—")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            QuotaPanelDivider()
            QuotaPanelRow(title: "凭证有效期") {
                Text(quota.workbuddySnapshot?.tokenExpiresAt.map { Self.longDateText($0) } ?? "—")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 合计可用

    private var totalsCard: some View {
        QuotaPanelCard(icon: "cylinder", iconTint: QuotaBrandColor.workBuddy, title: "合计可用") {
            EmptyView()
        } content: {
            if let snapshot = quota.workbuddySnapshot {
                let usedPercent = snapshot.total > 0 ? snapshot.used / snapshot.total * 100 : 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(QuotaFormat.groupedNumber(snapshot.remain))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("积分")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("已用 \(QuotaFormat.groupedNumber(snapshot.used))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("总额 \(QuotaFormat.groupedNumber(snapshot.total))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("消耗率 \(QuotaFormat.smartPercent(usedPercent))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(usedPercent >= 85 ? .red : (usedPercent >= 60 ? .orange : .secondary))
                        }
                    }
                    QuotaProgressBar(
                        fraction: usedPercent / 100,
                        color: QuotaFormat.usageColor(forUsedPercent: usedPercent),
                        track: QuotaBrandColor.workBuddy.opacity(0.18)
                    )
                }
            } else {
                Text(quota.workbuddyError ?? "正在获取…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 积分包

    private var packagesCard: some View {
        QuotaPanelCard(
            icon: "gift",
            iconTint: .pink,
            title: "积分包 · \(quota.workbuddySnapshot?.packages.count ?? 0) 个"
        ) {
            EmptyView()
        } content: {
            if let packages = quota.workbuddySnapshot?.packages, !packages.isEmpty {
                VStack(spacing: 10) {
                    ForEach(packages) { package in
                        packageRow(package)
                    }
                }
            } else if quota.workbuddySnapshot != nil {
                Text("暂无可用积分包，等待系统发放。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text("正在获取…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func packageRow(_ package: WorkBuddyQuotaService.Package) -> some View {
        let remainingPercent = package.total > 0 ? package.remain / package.total * 100 : 0

        return HStack(spacing: 12) {
            Text(package.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: 168, alignment: .leading)

            QuotaProgressBar(
                fraction: remainingPercent / 100,
                color: QuotaFormat.remainingColor(remainingPercent: remainingPercent, base: QuotaBrandColor.workBuddy),
                track: Color.primary.opacity(0.08)
            )

            Text("\(QuotaFormat.groupedNumber(package.used)) / \(QuotaFormat.groupedNumber(package.total)) credits")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 150, alignment: .trailing)
        }
    }

    // MARK: - 菜单栏开关

    private var menuBarCard: some View {
        SettingsCard(
            title: "菜单栏",
            icon: "menubar.rectangle",
            footer: "开启后菜单栏图标旁显示 Codex 剩余百分比（C）与 WorkBuddy 剩余积分（W），余额不足时自动变红。"
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

    private static func longDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 面板卡片

/// 设置页额度面板的统一卡片：彩色图标 + 标题行 + 分隔线 + 内容区。
private struct QuotaPanelCard<Trailing: View, Content: View>: View {
    let icon: String
    let iconTint: Color
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconTint)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(iconTint.opacity(0.12))
                    )

                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            content()
                .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct QuotaPanelRow<Value: View>: View {
    let title: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            value()
        }
        .padding(.vertical, 4)
    }
}

private struct QuotaPanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

// MARK: - 进度条与占位状态

private struct QuotaProgressBar: View {
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

private struct QuotaHeroLoadingState: View {
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

private struct QuotaHeroErrorState: View {
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

private struct QuotaHeroInactiveState: View {
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

//
//  QuotaToolView.swift
//  PasteDeck
//
//  额度查看工具：以独立窗口展示 Codex / WorkBuddy 余额。
//  完全复用 QuotaStatusManager 的缓存与刷新逻辑，以及设置页
//  开放出的共享展示组件，不重新实现任何查询接口。
//

import SwiftUI

struct QuotaToolView: View {
    @ObservedObject private var quota = QuotaStatusManager.shared
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Grid 行高取最高子项：让 Codex / WorkBuddy 两张卡在内容
                // 高度不同（如错误态）时仍保持底边对齐。
                Grid(alignment: .top, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        codexCard.gridCellColumns(1)
                        workbuddyCard
                    }
                }

                accountSummaryCard

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
                    .disabled(quota.isRefreshingCodex || quota.isRefreshingWorkBuddy)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(timer) { _ in
            now = Date()
        }
        .task {
            // 工具窗口打开时展示缓存并按需后台补一次，与设置页同一策略。
            quota.refreshIfStale(maxAge: 120)
        }
    }

    // MARK: - Codex

    private var codexCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TranslationBrandLogoView(brand: .openAI, size: 30)
                Text("Codex")
                    .font(.system(size: 14, weight: .semibold))
                if let plan = quota.codexSnapshot?.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(QuotaBrandColor.codex))
                }
                Spacer()
            }

            if quota.codexError != nil, quota.codexSnapshot == nil {
                QuotaHeroErrorState(text: quota.codexError ?? "查询失败")
            } else if let snapshot = quota.codexSnapshot {
                if snapshot.session.isAvailable {
                    let remaining = snapshot.isRateLimitReached ? 0 : snapshot.session.remainingPercent

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(snapshot.isRateLimitReached || remaining <= 15 ? .red : .primary)
                        Text(codexResetLine(snapshot))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    QuotaProgressBar(
                        fraction: remaining / 100,
                        color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex),
                        track: QuotaBrandColor.codex.opacity(0.15)
                    )

                    if snapshot.weekly.isAvailable {
                        let weeklyRemaining = snapshot.isRateLimitReached ? 0 : snapshot.weekly.remainingPercent
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("每周额度")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(Int(weeklyRemaining.rounded()))% 剩余")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            QuotaProgressBar(
                                fraction: weeklyRemaining / 100,
                                color: QuotaFormat.remainingColor(remainingPercent: weeklyRemaining, base: QuotaBrandColor.codex),
                                track: QuotaBrandColor.codex.opacity(0.15)
                            )
                        }
                    }
                } else {
                    QuotaHeroInactiveState(label: "5 小时额度", tint: QuotaBrandColor.codex)
                }
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.codex)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(QuotaBrandColor.codex.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuotaBrandColor.codex.opacity(0.16), lineWidth: 1)
        )
    }

    private func codexResetLine(_ snapshot: CodexQuotaService.Snapshot) -> String {
        guard snapshot.session.isAvailable else { return "额度暂未激活" }
        guard let resetsAt = snapshot.session.resetsAt else { return "重置时间未知" }
        var line = "\(QuotaFormat.clockText(resetsAt)) 重置"
        if let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) {
            line += " · \(countdown)"
        }
        return line
    }

    // MARK: - WorkBuddy

    private var workbuddyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("WorkBuddy")
                        .font(.system(size: 14, weight: .semibold))
                    Text("腾讯 CodeBuddy")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if quota.workbuddyError != nil, quota.workbuddySnapshot == nil {
                QuotaHeroErrorState(text: quota.workbuddyError ?? "查询失败")
            } else if let snapshot = quota.workbuddySnapshot {
                let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.total > 0 ? QuotaFormat.smartPercent(remainingPercent) : "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(remainingPercent <= 15 ? .red : .primary)
                    Text("剩余 \(QuotaFormat.groupedNumber(snapshot.remain)) / \(QuotaFormat.groupedNumber(snapshot.total)) 积分")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                QuotaProgressBar(
                    fraction: remainingPercent / 100,
                    color: QuotaFormat.remainingColor(remainingPercent: remainingPercent, base: QuotaBrandColor.workBuddy),
                    track: QuotaBrandColor.workBuddy.opacity(0.18)
                )
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.workBuddy)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(QuotaBrandColor.workBuddy.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuotaBrandColor.workBuddy.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 账户摘要

    private var accountSummaryCard: some View {
        QuotaPanelCard(icon: "person.crop.circle", iconTint: .blue, title: "账户") {
            EmptyView()
        } content: {
            if let snapshot = quota.workbuddySnapshot {
                QuotaPanelRow(title: "账户") {
                    Text(snapshot.accountName ?? "未知")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                QuotaPanelDivider()
                QuotaPanelRow(title: "用户类型") {
                    SettingsStatusPill(
                        text: snapshot.isPaidUser ? "付费用户" : "免费用户",
                        color: snapshot.isPaidUser ? .green : .orange
                    )
                }
                QuotaPanelDivider()
                QuotaPanelRow(title: "订阅方案") {
                    Text(snapshot.subscriptionName ?? "—")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else {
                Text(quota.workbuddyError ?? "正在获取…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

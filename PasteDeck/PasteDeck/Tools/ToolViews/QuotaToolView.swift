//
//  QuotaToolView.swift
//  PasteDeck
//
//  额度查看工具：独立窗口展示 Codex / Gemini / WorkBuddy 三大额度卡片。
//  概览页三张卡片各显示核心余量，点击下钻到对应服务的详细额度信息。
//  完全复用 QuotaStatusManager 的缓存与刷新逻辑，不重新实现任何查询接口。
//
//  Created on 2026-10-11.
//

import SwiftUI
import SwiftData

/// 额度服务提供方，用于概览 → 详情下钻导航。
enum QuotaProvider: String, CaseIterable, Identifiable {
    case codex
    case gemini
    case workbuddy

    var id: String { rawValue }
}

struct QuotaToolView: View {
    @Query private var settings: [AppSettings]
    @ObservedObject private var quota = QuotaStatusManager.shared
    @State private var now = Date()
    @State private var selectedProvider: QuotaProvider?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var appSettings: AppSettings? { settings.first }

    var body: some View {
        Group {
            if let provider = selectedProvider {
                detailView(for: provider)
            } else {
                overviewView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(timer) { _ in
            now = Date()
        }
        .task {
            // 工具窗口打开时展示缓存并按需后台补一次。
            quota.refreshIfStale(maxAge: 120)
        }
    }

    // MARK: - 概览页：三大卡片

    private var overviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBar

                providerCard(
                    provider: .codex,
                    title: "Codex",
                    subtitle: "ChatGPT / Codex 速率限制",
                    iconKind: .openAI,
                    brandColor: QuotaBrandColor.codex
                ) {
                    codexOverviewContent
                }

                providerCard(
                    provider: .gemini,
                    title: "Gemini",
                    subtitle: "Antigravity 代理配额",
                    iconKind: .sparkles,
                    brandColor: QuotaBrandColor.gemini
                ) {
                    geminiOverviewContent
                }

                providerCard(
                    provider: .workbuddy,
                    title: "WorkBuddy",
                    subtitle: "腾讯 CodeBuddy 积分",
                    iconKind: .sparkles,
                    brandColor: QuotaBrandColor.workBuddy
                ) {
                    workbuddyOverviewContent
                }

                footerBar
            }
            .padding(16)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            Text("额度")
                .font(.system(size: 16, weight: .bold))
            Spacer()
            if quota.isRefreshingCodex || quota.isRefreshingGemini || quota.isRefreshingWorkBuddy {
                ProgressView().controlSize(.small)
            }
            Button {
                quota.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(quota.isRefreshingCodex || quota.isRefreshingGemini || quota.isRefreshingWorkBuddy)
        }
    }

    /// 通用服务卡片：品牌图标 + 标题 + 概览内容 + 右侧下钻箭头。
    /// - Parameter iconKind: 品牌图标；`.sparkles` 用渐变色块 + SF Symbol，
    ///   `.openAI` 使用本地品牌 Logo。
    private enum BrandIconKind {
        case openAI
        case sparkles
    }

    private func providerCard<Content: View>(
        provider: QuotaProvider,
        title: String,
        subtitle: String,
        iconKind: BrandIconKind,
        brandColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedProvider = provider
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    switch iconKind {
                    case .openAI:
                        TranslationBrandLogoView(brand: .openAI, size: 32)
                    case .sparkles:
                        brandIcon(brandColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brandColor.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(brandColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func brandIcon(_ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - 概览内容

    private var codexOverviewContent: some View {
        Group {
            if let snapshot = quota.codexSnapshot, snapshot.session.isAvailable {
                let remaining = snapshot.session.displayRemainingPercent
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(snapshot.session.isLimitReached || remaining <= 15 ? .red : .primary)
                        Text("5 小时额度剩余")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let plan = snapshot.plan {
                            Text(plan.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(QuotaBrandColor.codex))
                        }
                    }
                    QuotaProgressBar(
                        fraction: remaining / 100,
                        color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex),
                        track: QuotaBrandColor.codex.opacity(0.15)
                    )
                    Text(codexOverviewResetLine(snapshot))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if quota.codexError != nil, quota.codexSnapshot == nil {
                QuotaHeroErrorState(text: quota.codexError ?? "查询失败")
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.codex)
            }
        }
    }

    private var geminiOverviewContent: some View {
        Group {
            if let snapshot = quota.geminiSnapshot, snapshot.session.isAvailable {
                let remaining = snapshot.session.displayRemainingPercent
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(remaining.rounded()))%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(snapshot.session.isLimitReached || remaining <= 15 ? .red : .primary)
                        Text("5 小时额度剩余")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let tier = snapshot.subscriptionTier {
                            Text(tier.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(QuotaBrandColor.gemini))
                        }
                    }
                    QuotaProgressBar(
                        fraction: remaining / 100,
                        color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.gemini),
                        track: QuotaBrandColor.gemini.opacity(0.15)
                    )
                    Text(geminiOverviewResetLine(snapshot))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if quota.geminiError != nil, quota.geminiSnapshot == nil {
                QuotaHeroErrorState(text: quota.geminiError ?? "查询失败")
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.gemini)
            }
        }
    }

    private var workbuddyOverviewContent: some View {
        Group {
            if let snapshot = quota.workbuddySnapshot {
                let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(QuotaFormat.compactCredits(snapshot.remain))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(snapshot.remain <= 0 ? .red : .primary)
                        Text("积分剩余")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if snapshot.isPaidUser {
                            Text("付费")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(QuotaBrandColor.workBuddy))
                        }
                    }
                    QuotaProgressBar(
                        fraction: remainingPercent / 100,
                        color: QuotaFormat.remainingColor(remainingPercent: remainingPercent, base: QuotaBrandColor.workBuddy),
                        track: QuotaBrandColor.workBuddy.opacity(0.18)
                    )
                    Text("已用 \(QuotaFormat.groupedNumber(snapshot.used)) / 共 \(QuotaFormat.groupedNumber(snapshot.total))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if quota.workbuddyError != nil, quota.workbuddySnapshot == nil {
                QuotaHeroErrorState(text: quota.workbuddyError ?? "查询失败")
            } else {
                QuotaHeroLoadingState(tint: QuotaBrandColor.workBuddy)
            }
        }
    }

    private func codexOverviewResetLine(_ snapshot: CodexQuotaService.Snapshot) -> String {
        guard let resetsAt = snapshot.session.resetsAt else { return "重置时间未知" }
        var line = "\(QuotaFormat.clockText(resetsAt)) 重置"
        if let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) {
            line += " · \(countdown)"
        }
        return line
    }

    private func geminiOverviewResetLine(_ snapshot: GeminiQuotaService.Snapshot) -> String {
        guard let resetsAt = snapshot.session.resetsAt else { return "重置时间未知" }
        var line = "\(QuotaFormat.clockText(resetsAt)) 重置"
        if let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) {
            line += " · \(countdown)"
        }
        return line
    }

    // MARK: - 详情页（下钻）

    @ViewBuilder
    private func detailView(for provider: QuotaProvider) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                detailHeader(provider)

                switch provider {
                case .codex:
                    codexDetailView
                case .gemini:
                    geminiDetailView
                case .workbuddy:
                    workbuddyDetailView
                }

                footerBar
            }
            .padding(16)
        }
    }

    private func detailHeader(_ provider: QuotaProvider) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedProvider = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("额度")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(providerTitle(provider))
                .font(.system(size: 15, weight: .bold))

            if quota.isRefreshingCodex || quota.isRefreshingGemini || quota.isRefreshingWorkBuddy {
                ProgressView().controlSize(.small)
            }
            Button {
                quota.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(quota.isRefreshingCodex || quota.isRefreshingGemini || quota.isRefreshingWorkBuddy)
        }
    }

    private func providerTitle(_ provider: QuotaProvider) -> String {
        switch provider {
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .workbuddy: return "WorkBuddy"
        }
    }

    // MARK: - Codex 详情

    private var codexDetailView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = quota.codexSnapshot {
                detailSectionCard(title: "5 小时额度", tint: QuotaBrandColor.codex) {
                    if snapshot.session.isAvailable {
                        let remaining = snapshot.session.displayRemainingPercent
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(remaining.rounded()))%")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(snapshot.session.isLimitReached || remaining <= 15 ? .red : .primary)
                                Text("剩余")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            QuotaProgressBar(
                                fraction: remaining / 100,
                                color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex),
                                track: QuotaBrandColor.codex.opacity(0.15)
                            )
                            if let resetsAt = snapshot.session.resetsAt {
                                detailMetaLine("重置时间", "\(QuotaFormat.dateTimeText(resetsAt))\(countdownSuffix(resetsAt))")
                            }
                            detailMetaLine("已用", "\(Int(snapshot.session.usedPercent.rounded()))%")
                        }
                    } else {
                        QuotaHeroInactiveState(label: "5 小时额度", tint: QuotaBrandColor.codex)
                    }
                }

                detailSectionCard(title: "每周额度", tint: QuotaBrandColor.codex) {
                    if snapshot.weekly.isAvailable {
                        let remaining = snapshot.weekly.displayRemainingPercent
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(remaining.rounded()))%")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(snapshot.weekly.isLimitReached || remaining <= 15 ? .red : .primary)
                                Text("剩余")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            QuotaProgressBar(
                                fraction: remaining / 100,
                                color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.codex),
                                track: QuotaBrandColor.codex.opacity(0.15)
                            )
                            if let resetsAt = snapshot.weekly.resetsAt {
                                detailMetaLine("重置时间", "\(QuotaFormat.dateTimeText(resetsAt))\(countdownSuffix(resetsAt))")
                            }
                        }
                    } else {
                        QuotaHeroInactiveState(label: "每周额度", tint: QuotaBrandColor.codex)
                    }
                }

                detailSectionCard(title: "速率重置卡", tint: QuotaBrandColor.codex) {
                    if snapshot.resetCredits.isEmpty {
                        Text("当前没有可用的速率重置卡。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(snapshot.resetCredits.enumerated()), id: \.offset) { _, credit in
                                HStack {
                                    Text(credit.title ?? "速率重置卡")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    if let expiresAt = credit.expiresAt {
                                        Text("\(QuotaFormat.dateTimeText(expiresAt)) 过期")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if let error = quota.codexError {
                detailSectionCard(title: "Codex", tint: QuotaBrandColor.codex) {
                    QuotaHeroErrorState(text: error)
                }
            } else {
                detailSectionCard(title: "Codex", tint: QuotaBrandColor.codex) {
                    QuotaHeroLoadingState(tint: QuotaBrandColor.codex)
                }
            }
        }
    }

    // MARK: - Gemini 详情

    private var geminiDetailView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = quota.geminiSnapshot {
                detailSectionCard(title: "5 小时额度", tint: QuotaBrandColor.gemini) {
                    if snapshot.session.isAvailable {
                        let remaining = snapshot.session.displayRemainingPercent
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(remaining.rounded()))%")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(snapshot.session.isLimitReached || remaining <= 15 ? .red : .primary)
                                Text("剩余")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            QuotaProgressBar(
                                fraction: remaining / 100,
                                color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.gemini),
                                track: QuotaBrandColor.gemini.opacity(0.15)
                            )
                            if let resetsAt = snapshot.session.resetsAt {
                                detailMetaLine("重置时间", "\(QuotaFormat.dateTimeText(resetsAt))\(countdownSuffix(resetsAt))")
                            }
                        }
                    } else {
                        QuotaHeroInactiveState(label: "5 小时额度", tint: QuotaBrandColor.gemini)
                    }
                }

                detailSectionCard(title: "每周额度", tint: QuotaBrandColor.gemini) {
                    if snapshot.weekly.isAvailable {
                        let remaining = snapshot.weekly.displayRemainingPercent
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(remaining.rounded()))%")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(snapshot.weekly.isLimitReached || remaining <= 15 ? .red : .primary)
                                Text("剩余")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            QuotaProgressBar(
                                fraction: remaining / 100,
                                color: QuotaFormat.remainingColor(remainingPercent: remaining, base: QuotaBrandColor.gemini),
                                track: QuotaBrandColor.gemini.opacity(0.15)
                            )
                            if let resetsAt = snapshot.weekly.resetsAt {
                                detailMetaLine("重置时间", "\(QuotaFormat.dateTimeText(resetsAt))\(countdownSuffix(resetsAt))")
                            }
                        }
                    } else {
                        QuotaHeroInactiveState(label: "每周额度", tint: QuotaBrandColor.gemini)
                    }
                }

                if !snapshot.models.isEmpty {
                    detailSectionCard(title: "模型额度", tint: QuotaBrandColor.gemini) {
                        VStack(spacing: 8) {
                            ForEach(snapshot.models) { model in
                                HStack(spacing: 8) {
                                    Text(model.name)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 150, alignment: .leading)
                                    Spacer()
                                    Text("\(Int(model.percentage.rounded()))%")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(model.percentage <= 15 ? .red : .primary)
                                    if let reset = model.resetTime {
                                        Text(QuotaFormat.dateTimeText(reset))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Token 消费统计（时段切换 + KPI + 表格）
                GeminiTokenStatsView(
                    endpoint: appSettings?.geminiQuotaEndpoint,
                    token: appSettings?.geminiQuotaToken
                )
            } else if let error = quota.geminiError {
                detailSectionCard(title: "Gemini", tint: QuotaBrandColor.gemini) {
                    QuotaHeroErrorState(text: error)
                }
            } else {
                detailSectionCard(title: "Gemini", tint: QuotaBrandColor.gemini) {
                    QuotaHeroLoadingState(tint: QuotaBrandColor.gemini)
                }
            }
        }
    }

    // MARK: - WorkBuddy 详情

    private var workbuddyDetailView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = quota.workbuddySnapshot {
                let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0
                let usedPercent = snapshot.total > 0 ? (snapshot.used / snapshot.total) * 100 : 0

                detailSectionCard(title: "合计可用", tint: QuotaBrandColor.workBuddy) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(QuotaFormat.groupedNumber(snapshot.remain))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(snapshot.remain <= 0 ? .red : .primary)
                            Text("积分")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        QuotaProgressBar(
                            fraction: (100 - remainingPercent) / 100,
                            color: usedPercent >= 85 ? .red : (usedPercent >= 60 ? .yellow : .green),
                            track: Color.primary.opacity(0.08)
                        )
                        HStack(spacing: 20) {
                            statColumn("已用", QuotaFormat.groupedNumber(snapshot.used), isBad: usedPercent >= 85)
                            statColumn("总额", QuotaFormat.groupedNumber(snapshot.total))
                            statColumn("消耗率", String(format: "%.1f%%", usedPercent), isBad: usedPercent >= 85)
                        }
                    }
                }

                detailSectionCard(title: "账户与订阅", tint: QuotaBrandColor.workBuddy) {
                    VStack(spacing: 8) {
                        detailMetaLine("账户", snapshot.accountName ?? "未知")
                        detailMetaLine("账户类型", snapshot.accountType ?? "—")
                        detailMetaLine("订阅方案", snapshot.subscriptionName ?? "—")
                        if let expiresAt = snapshot.tokenExpiresAt {
                            detailMetaLine("凭证有效期", QuotaFormat.dateTimeText(expiresAt))
                        }
                        HStack {
                            Text("用户类型")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            SettingsStatusPill(
                                text: snapshot.isPaidUser ? "付费用户" : "免费用户",
                                color: snapshot.isPaidUser ? .green : .orange
                            )
                        }
                    }
                }

                detailSectionCard(title: "积分包", tint: QuotaBrandColor.workBuddy) {
                    if snapshot.packages.isEmpty {
                        Text("暂无可用积分包，等待系统发放。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(snapshot.packages) { pkg in
                                let pkgPercent = pkg.total > 0 ? pkg.remain / pkg.total * 100 : 0
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(pkg.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text("\(QuotaFormat.groupedNumber(pkg.used)) / \(QuotaFormat.groupedNumber(pkg.total))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    QuotaProgressBar(
                                        fraction: pkgPercent / 100,
                                        color: QuotaFormat.remainingColor(remainingPercent: pkgPercent, base: QuotaBrandColor.workBuddy),
                                        track: Color.primary.opacity(0.08)
                                    )
                                }
                            }
                        }
                    }
                }

                // workbuddy2api 网关看板
                WorkBuddyGatewayView(
                    baseURL: appSettings?.workbuddyGatewayBaseURL,
                    apiKey: appSettings?.workbuddyGatewayApiKey
                )
            } else if let error = quota.workbuddyError {
                detailSectionCard(title: "WorkBuddy", tint: QuotaBrandColor.workBuddy) {
                    QuotaHeroErrorState(text: error)
                }
            } else {
                detailSectionCard(title: "WorkBuddy", tint: QuotaBrandColor.workBuddy) {
                    QuotaHeroLoadingState(tint: QuotaBrandColor.workBuddy)
                }
            }
        }
    }

    // MARK: - 详情通用组件

    private func detailSectionCard<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func detailMetaLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func statColumn(_ title: String, _ value: String, isBad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isBad ? .red : .primary)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func countdownSuffix(_ resetsAt: Date) -> String {
        guard let countdown = QuotaFormat.countdownText(until: resetsAt, now: now) else { return "" }
        return "（\(countdown)）"
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text(quota.lastUpdatedText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

//
//  WorkBuddyGatewayView.swift
//  PasteDeck
//
//  WorkBuddy 与 workbuddy2api 网关完整面板：
//  完整还原 /Users/wangqian/Documents/go-project/codex-quota-utools/index.html 的
//  WorkBuddy 体验，支持 6 个子视图（概览、账号、积分包、用量、模型、设置）
//  以及账号级与批量运维操作（签到、查余额、解冻、禁用）。
//
//  Created on 2026-10-13.
//

import SwiftUI

enum WorkBuddySubView: String, CaseIterable, Identifiable {
    case overview = "概览"
    case accounts = "账号"
    case packages = "积分包"
    case usage = "用量"
    case models = "模型"
    case settings = "设置"

    var id: String { rawValue }
}

struct WorkBuddyGatewayView: View {
    @ObservedObject private var quota = QuotaStatusManager.shared
    @State private var activeSubView: WorkBuddySubView = .overview

    // 网关状态数据
    @State private var overviewData: WorkBuddyGatewayService.GatewayOverview?
    @State private var packagesData: [WorkBuddyGatewayService.GatewayPackageAccount] = []
    @State private var usageData: WorkBuddyGatewayService.GatewayUsage?
    @State private var modelsData: [WorkBuddyGatewayService.GatewayModel] = []

    @State private var usageHours: Int = 72
    @State private var isLoading = false
    @State private var statusNotice: String?

    // 展开状态
    @State private var openAccounts: Set<String> = []
    @State private var openPkgAccounts: Set<String> = []

    // 确认态 (两步确认)
    @State private var armedAction: String?

    // 配置
    var baseURL: String?
    var apiKey: String?
    var onSaveConfig: ((String, String) -> Void)?

    @State private var inputBaseURL: String = ""
    @State private var inputApiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            subViewTabBar

            if let notice = statusNotice {
                noticeBanner(notice)
            }

            switch activeSubView {
            case .overview:
                overviewView
            case .accounts:
                accountsView
            case .packages:
                packagesView
            case .usage:
                usageView
            case .models:
                modelsView
            case .settings:
                settingsView
            }
        }
        .onAppear {
            inputBaseURL = baseURL ?? WorkBuddyGatewayService.defaultBaseURL
            inputApiKey = apiKey ?? WorkBuddyGatewayService.defaultApiKey
        }
        .task(id: activeSubView) {
            await loadSubViewData()
        }
    }

    // MARK: - 子视图导航胶囊

    private var subViewTabBar: some View {
        HStack(spacing: 6) {
            ForEach(WorkBuddySubView.allCases) { tab in
                Button {
                    activeSubView = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: activeSubView == tab ? .semibold : .regular))
                        .foregroundColor(activeSubView == tab ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(activeSubView == tab ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await loadSubViewData(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 2)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(text)
                .font(.system(size: 11))
            Spacer()
            Button("关闭") {
                statusNotice = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
    }

    // MARK: - 1. 概览视图

    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                localWorkbuddyCard
                gatewayPoolCard
            }

            gatewayActionButtonsRow
        }
    }

    /// 本机积分卡片 (复刻 codex-quota-utools 的 renderLocalWorkbuddyPanel)
    private var localWorkbuddyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本机积分 · 合计可用")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("CREDITS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.2)))
                    .foregroundColor(.orange)
            }

            if let snapshot = quota.workbuddySnapshot {
                let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0
                let usedPercent = snapshot.total > 0 ? (snapshot.used / snapshot.total) * 100 : 0

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(WorkBuddyGatewayService.fmtCredits(snapshot.remain))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
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
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WorkBuddyGatewayService.fmtCredits(snapshot.used))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("已用")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WorkBuddyGatewayService.fmtCredits(snapshot.total))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("总额")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f%%", usedPercent))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(usedPercent >= 85 ? .red : (usedPercent >= 60 ? .orange : .primary))
                        Text("消耗率")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                if let holder = snapshot.accountName {
                    Divider().opacity(0.4)
                    HStack(spacing: 6) {
                        Text(holder)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        if let expiry = snapshot.tokenExpiresAt {
                            Text("· 凭证至 \(formatDate(expiry))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(quota.workbuddyError ?? "正在获取本机积分…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    /// 网关账号池健康度卡片 (复刻 codex-quota-utools 的 renderGwOverview)
    private var gatewayPoolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("网关账号池")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let d = overviewData {
                    Text(d.version)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundColor(.blue)
                }
            }

            if let d = overviewData {
                HStack(spacing: 16) {
                    // 环形进度
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(d.healthPercentage) / 100)
                            .stroke(
                                d.healthPercentage >= 100 ? Color.green : (d.healthPercentage >= 50 ? Color.yellow : Color.red),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(d.healthPercentage)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(d.healthy) / \(d.total)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("健康账号")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Text("运行 \(WorkBuddyGatewayService.fmtUptime(d.uptimeSec)) · 粘性 \(d.stickySessions) · Redis \(d.redisMode ?? "-")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        if d.cooling > 0 {
                            Text("冷却中账号: \(d.cooling)")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            } else {
                Text(isLoading ? "正在读取网关状态…" : "未连接网关或网关未就绪")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    /// 快捷操作按钮行
    private var gatewayActionButtonsRow: some View {
        HStack(spacing: 8) {
            Button("全部签到") {
                executeBulk("checkin_all", label: "全部签到")
            }
            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))

            Button("全部查余额") {
                executeBulk("balance_all", label: "全部查余额")
            }
            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))

            Button("全部保活") {
                executeBulk("keepalive_all", label: "全部保活")
            }
            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))

            Spacer()
        }
    }

    // MARK: - 2. 账号视图

    private var accountsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = overviewData, !d.accounts.isEmpty {
                ForEach(d.accounts) { acc in
                    accountCard(acc)
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Text("暂无账号数据").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }

    private func accountCard(_ a: WorkBuddyGatewayService.GatewayAccount) -> some View {
        let st = WorkBuddyGatewayService.accountStatus(a)
        let isOpen = openAccounts.contains(a.uid)

        return VStack(alignment: .leading, spacing: 0) {
            // 卡片头部
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isOpen { openAccounts.remove(a.uid) } else { openAccounts.insert(a.uid) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(a.avatarInitial)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.blue))

                    Text(a.displayName)
                        .font(.system(size: 13, weight: .semibold))

                    if let realm = a.realm {
                        Text(realm.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }

                    SettingsStatusPill(
                        text: st.text,
                        color: st.pill == "ok" ? .green : (st.pill == "warn" ? .orange : (st.pill == "bad" ? .red : .gray))
                    )

                    Spacer()

                    HStack(spacing: 4) {
                        Text(WorkBuddyGatewayService.fmtCredits(a.credits))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if let total = a.creditsTotal {
                            Text("/ \(WorkBuddyGatewayService.fmtCredits(total))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Text("积分")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开内容
            if isOpen {
                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        metricItem("成功率", a.successRateText, isBad: a.isRateBad)
                        metricItem("成功", WorkBuddyGatewayService.fmtBig(Double(a.successCount)))
                        if a.errTotal > 0 {
                            metricItem("失败", WorkBuddyGatewayService.fmtBig(Double(a.errTotal)), isBad: true)
                        }
                        if a.consecutiveFails > 0 {
                            metricItem("连败", "\(a.consecutiveFails)", isBad: true)
                        }
                        if a.inFlight > 0 {
                            metricItem("在途", "\(a.inFlight)")
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(WorkBuddyGatewayService.fmtRelTime(a.lastSuccess))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("最近成功")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let r = a.reason, !r.isEmpty {
                        Text(r)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    // 运维操作按钮
                    HStack(spacing: 8) {
                        Button("签到") { executeAccountAction(a.uid, "checkin") }
                            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))
                        Button("查余额") { executeAccountAction(a.uid, "balance") }
                            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))
                        Button("解冻") { executeAccountAction(a.uid, "revive") }
                            .buttonStyle(SettingsActionButtonStyle(tone: .secondary))
                        if !a.disabled {
                            Button("禁用") { executeAccountAction(a.uid, "disable") }
                                .buttonStyle(SettingsActionButtonStyle(tone: .secondary))
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricItem(_ title: String, _ value: String, isBad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(isBad ? .red : .primary)
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 3. 积分包视图

    private var packagesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if packagesData.isEmpty && isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else if packagesData.isEmpty {
                Text("暂无积分包数据").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(packagesData) { acc in
                    packageAccountCard(acc)
                }
            }
        }
    }

    private func packageAccountCard(_ acc: WorkBuddyGatewayService.GatewayPackageAccount) -> some View {
        let isOpen = openPkgAccounts.contains(acc.uid)
        let activeCount = acc.packages.filter { $0.tier == 0 }.count
        let untouchedCount = acc.packages.filter { $0.tier == 1 }.count
        let exhaustedCount = acc.packages.filter { $0.tier == 2 }.count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isOpen { openPkgAccounts.remove(acc.uid) } else { openPkgAccounts.insert(acc.uid) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(acc.avatarInitial)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.orange))

                    Text(acc.displayName)
                        .font(.system(size: 13, weight: .semibold))

                    Text("\(acc.packages.count) 个包 · 使用中 \(activeCount) · 未动 \(untouchedCount) · 已耗尽 \(exhaustedCount)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(WorkBuddyGatewayService.fmtCredits(acc.remain)) 积分")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider().opacity(0.4)

                VStack(spacing: 6) {
                    ForEach(acc.packages) { p in
                        HStack(spacing: 8) {
                            Text(p.name)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)

                            QuotaProgressBar(
                                fraction: p.usedPercentage / 100,
                                color: p.tier == 2 ? .red : (p.usedPercentage >= 85 ? .red : (p.usedPercentage >= 60 ? .yellow : .green)),
                                track: Color.primary.opacity(0.08)
                            )

                            HStack(spacing: 4) {
                                Text("\(WorkBuddyGatewayService.fmtCredits(p.remain)) / \(WorkBuddyGatewayService.fmtCredits(p.size))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                if let end = p.endTime {
                                    Text("· \(formatDate(end)) 到期")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 180, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - 4. 用量视图

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            usageChipsView

            if let u = usageData {
                usageTotalsCard(u)
                usageModelTable(u)
                usageAccountTable(u)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Text("暂无用量数据").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }

    private var usageChipsView: some View {
        HStack(spacing: 6) {
            ForEach([6, 24, 72, 168, 720], id: \.self) { (h: Int) in
                Button("\(h)h") {
                    usageHours = h
                    Task { await loadSubViewData() }
                }
                .font(.system(size: 11, weight: usageHours == h ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(usageHours == h ? Color.blue.opacity(0.15) : Color.clear)
                )
                .foregroundColor(usageHours == h ? .blue : .secondary)
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func usageTotalsCard(_ u: WorkBuddyGatewayService.GatewayUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("总计 · 近 \(usageHours)h")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 16) {
                metricItem("请求", WorkBuddyGatewayService.fmtBig(Double(u.totals.requests)))
                metricItem("成功率", u.totals.successRateText)
                metricItem("错误", WorkBuddyGatewayService.fmtBig(Double(u.totals.errors)), isBad: u.totals.errors > 0)
                metricItem("总 Tokens", WorkBuddyGatewayService.fmtBig(u.totals.totalTokens))
                metricItem("输入 Tokens", WorkBuddyGatewayService.fmtBig(u.totals.promptTokens))
                metricItem("输出 Tokens", WorkBuddyGatewayService.fmtBig(u.totals.completionTokens))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    private func usageModelTable(_ u: WorkBuddyGatewayService.GatewayUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按模型 · TOP 12")
                .font(.system(size: 12, weight: .semibold))

            HStack {
                Text("模型").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("请求").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Text("Tokens").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
                Text("延迟").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
            }

            ForEach(u.byModel.prefix(12)) { m in
                HStack {
                    Text(m.key).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text("\(m.requests)").font(.system(size: 11, design: .monospaced)).frame(width: 60, alignment: .trailing)
                    Text(WorkBuddyGatewayService.fmtBig(m.totalTokens)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(m.latencyText).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    private func usageAccountTable(_ u: WorkBuddyGatewayService.GatewayUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按账号")
                .font(.system(size: 12, weight: .semibold))

            ForEach(u.byAccount) { a in
                HStack {
                    Text(a.key).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text("\(a.requests) 请求").font(.system(size: 11)).foregroundColor(.secondary)
                    Text(WorkBuddyGatewayService.fmtBig(a.totalTokens)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    // MARK: - 5. 模型视图

    private var modelsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modelsData.isEmpty && isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack {
                    Text("模型 ID").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("倍率").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                    Text("上下文").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 70, alignment: .trailing)
                    Text("能力").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 4)

                ForEach(modelsData) { m in
                    HStack {
                        Text(m.id)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text(m.credits)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                            .frame(width: 60, alignment: .trailing)

                        Text(m.contextLengthText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)

                        HStack(spacing: 3) {
                            if m.supportsImages { tagBadge("图") }
                            if m.supportsReasoning { tagBadge("思") }
                            if m.supportsToolCall { tagBadge("工具") }
                        }
                        .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    private func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.15)))
            .foregroundColor(.blue)
    }

    // MARK: - 6. 设置视图

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("workbuddy2api 自托管网关连接")
                .font(.system(size: 13, weight: .semibold))

            SettingsRow(title: "网关地址 (Base URL)", subtitle: "例如 http://127.0.0.1:17863") {
                TextField("http://127.0.0.1:17863", text: $inputBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            SettingsRow(title: "API Key", subtitle: "网关 API 鉴权 Token") {
                SecureField("Token", text: $inputApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            HStack(spacing: 10) {
                Button("保存配置") {
                    onSaveConfig?(inputBaseURL, inputApiKey)
                    statusNotice = "网关配置已保存"
                    Task { await loadSubViewData(force: true) }
                }
                .buttonStyle(SettingsActionButtonStyle(tone: .primary))

                Button("测试连接") {
                    Task {
                        do {
                            let res = try await WorkBuddyGatewayService.getOverview(baseURL: inputBaseURL, apiKey: inputApiKey)
                            statusNotice = "连接成功！版本 \(res.version)，账号池 \(res.healthy)/\(res.total)"
                        } catch {
                            statusNotice = "连接失败：\(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(SettingsActionButtonStyle(tone: .secondary))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    // MARK: - 数据加载与运维调用

    private func loadSubViewData(force: Bool = false) async {
        isLoading = true
        do {
            switch activeSubView {
            case .overview:
                let res = try await WorkBuddyGatewayService.getOverview(baseURL: baseURL, apiKey: apiKey)
                self.overviewData = res
            case .accounts:
                let res = try await WorkBuddyGatewayService.getOverview(baseURL: baseURL, apiKey: apiKey)
                self.overviewData = res
            case .packages:
                let res = try await WorkBuddyGatewayService.getPackages(baseURL: baseURL, apiKey: apiKey)
                self.packagesData = res
            case .usage:
                let res = try await WorkBuddyGatewayService.getUsage(hours: usageHours, baseURL: baseURL, apiKey: apiKey)
                self.usageData = res
            case .models:
                let res = try await WorkBuddyGatewayService.getModels(baseURL: baseURL, apiKey: apiKey)
                self.modelsData = res
            case .settings:
                break
            }
            isLoading = false
        } catch {
            isLoading = false
            statusNotice = "加载失败：\(error.localizedDescription)"
        }
    }

    private func executeAccountAction(_ uid: String, _ act: String) {
        Task {
            do {
                try await WorkBuddyGatewayService.accountAction(uid: uid, action: act, baseURL: baseURL, apiKey: apiKey)
                statusNotice = "操作成功：\(act)"
                await loadSubViewData(force: true)
            } catch {
                statusNotice = "操作失败：\(error.localizedDescription)"
            }
        }
    }

    private func executeBulk(_ act: String, label: String) {
        Task {
            do {
                try await WorkBuddyGatewayService.bulkAction(action: act, baseURL: baseURL, apiKey: apiKey)
                statusNotice = "批量执行成功：\(label)"
                await loadSubViewData(force: true)
            } catch {
                statusNotice = "批量执行失败：\(error.localizedDescription)"
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

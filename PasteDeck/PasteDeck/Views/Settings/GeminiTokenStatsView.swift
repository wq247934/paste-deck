//
//  GeminiTokenStatsView.swift
//  PasteDeck
//
//  Gemini Token 消费统计面板：
//  - 6 个 Summary KPI 卡片（总 Token、输入、输出、缓存命中、活跃账号、使用模型）
//  - 时段切换（小时、日、周）
//  - Token 使用趋势柱状图与分账号分布
//  - 分模型详细统计表格（请求数、输入、输出、缓存命中、合计、占比）
//
//  Created on 2026-10-13.
//

import SwiftUI

struct GeminiTokenStatsView: View {
    @State private var period: GeminiQuotaService.TokenStatsPeriod = .daily
    @State private var snapshot: GeminiQuotaService.TokenStatsSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var endpoint: String?
    var token: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            if isLoading && snapshot == nil {
                loadingPlaceholder
            } else if let error = errorMessage, snapshot == nil {
                errorPlaceholder(error)
            } else if let data = snapshot {
                kpiCardsGrid(data.summary)
                trendAndAccountRow(data)
                modelDetailsTable(data)
            }
        }
        .task(id: period) {
            await loadData()
        }
    }

    // MARK: - 顶栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.blue)

            Text("Token 消费统计")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Picker("", selection: $period) {
                ForEach(GeminiQuotaService.TokenStatsPeriod.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            Button {
                Task { await loadData(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - 6 KPI 概览卡片

    private func kpiCardsGrid(_ summary: GeminiQuotaService.TokenStatsSummary) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                kpiCard(
                    title: "总 Token",
                    value: formatTokens(summary.totalTokens),
                    icon: "bolt.fill",
                    color: Color(red: 0.38, green: 0.35, blue: 0.95)
                )
                kpiCard(
                    title: "输入 Token",
                    value: formatTokens(summary.totalInputTokens),
                    icon: "arrow.down.right",
                    color: Color(red: 0.20, green: 0.55, blue: 0.95)
                )
                kpiCard(
                    title: "输出 Token",
                    value: formatTokens(summary.totalOutputTokens),
                    icon: "arrow.up.right",
                    color: Color(red: 0.75, green: 0.35, blue: 0.90)
                )
                kpiCard(
                    title: "缓存命中",
                    value: formatTokens(summary.totalCachedTokens),
                    icon: "bolt.badge.checkmark",
                    color: Color(red: 0.15, green: 0.70, blue: 0.85)
                )
                kpiCard(
                    title: "活跃账号",
                    value: "\(summary.uniqueAccounts)",
                    icon: "person.2.fill",
                    color: Color(red: 0.20, green: 0.75, blue: 0.45)
                )
                kpiCard(
                    title: "使用模型",
                    value: "\(summary.modelsCount)",
                    icon: "cpu",
                    color: Color(red: 0.95, green: 0.55, blue: 0.20)
                )
            }
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - 趋势图与分账号分布

    private func trendAndAccountRow(_ data: GeminiQuotaService.TokenStatsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：Token 使用趋势
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Token 使用趋势")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    HStack(spacing: 8) {
                        legendItem(color: Color(red: 0.15, green: 0.70, blue: 0.85), label: "缓存命中")
                        legendItem(color: Color(red: 0.20, green: 0.55, blue: 0.95), label: "未缓存输入")
                        legendItem(color: Color(red: 0.75, green: 0.35, blue: 0.90), label: "输出")
                    }
                }

                if data.trends.isEmpty {
                    Text("暂无趋势数据")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 110, alignment: .center)
                } else {
                    trendBarsView(data.trends)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // 右侧：分账号统计
            VStack(alignment: .leading, spacing: 10) {
                Text("分账号统计")
                    .font(.system(size: 13, weight: .semibold))

                if data.accounts.isEmpty {
                    Text("暂无账号统计")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 110, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(data.accounts.prefix(4)) { acct in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                Text(acct.accountEmail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatTokens(acct.totalTokens))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                    .frame(maxHeight: 110, alignment: .top)
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func trendBarsView(_ points: [GeminiQuotaService.TokenTrendPoint]) -> some View {
        let maxVal = points.map(\.totalTokens).max() ?? 1.0
        let safeMax = maxVal > 0 ? maxVal : 1.0

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(points.suffix(10)) { p in
                VStack(spacing: 4) {
                    // 堆叠柱条
                    GeometryReader { geo in
                        let height = geo.size.height
                        let totalHeight = CGFloat(p.totalTokens / safeMax) * height

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(spacing: 0) {
                                // 输出
                                let outRatio = p.totalTokens > 0 ? p.outputTokens / p.totalTokens : 0
                                Rectangle()
                                    .fill(Color(red: 0.75, green: 0.35, blue: 0.90))
                                    .frame(height: max(1, totalHeight * CGFloat(outRatio)))

                                // 未缓存输入
                                let uncached = max(0, p.inputTokens - p.cachedTokens)
                                let uncachedRatio = p.totalTokens > 0 ? uncached / p.totalTokens : 0
                                Rectangle()
                                    .fill(Color(red: 0.20, green: 0.55, blue: 0.95))
                                    .frame(height: max(1, totalHeight * CGFloat(uncachedRatio)))

                                // 缓存命中
                                let cachedRatio = p.totalTokens > 0 ? p.cachedTokens / p.totalTokens : 0
                                Rectangle()
                                    .fill(Color(red: 0.15, green: 0.70, blue: 0.85))
                                    .frame(height: max(1, totalHeight * CGFloat(cachedRatio)))
                            }
                            .cornerRadius(3)
                        }
                    }
                    .frame(height: 80)

                    // X 轴时间标签
                    Text(shortPeriodLabel(p.period))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 105)
    }

    private func shortPeriodLabel(_ p: String) -> String {
        if p.contains(" ") {
            return String(p.split(separator: " ").last ?? "")
        }
        if p.contains("-") {
            let parts = p.split(separator: "-")
            if parts.count >= 3 {
                return "\(parts[1])/\(parts[2])"
            }
        }
        return p
    }

    // MARK: - 分模型详细统计表格

    private func modelDetailsTable(_ data: GeminiQuotaService.TokenStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分模型详细统计")
                .font(.system(size: 13, weight: .semibold))

            // 表头
            HStack(spacing: 8) {
                Text("模型")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("请求数")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Text("输入")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
                Text("输出")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 65, alignment: .trailing)
                Text("缓存命中")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 75, alignment: .trailing)
                Text("合计")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 75, alignment: .trailing)
                Text("占比")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 4)

            Divider()
                .opacity(0.4)

            // 表格行
            ForEach(Array(data.models.enumerated()), id: \.element.id) { index, m in
                HStack(spacing: 8) {
                    // 模型名 + 颜色点
                    HStack(spacing: 6) {
                        Circle()
                            .fill(modelColor(index))
                            .frame(width: 6, height: 6)
                        Text(m.model)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 请求数
                    Text(formatNumberWithCommas(m.requestCount))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 60, alignment: .trailing)

                    // 输入
                    Text(formatTokens(m.inputTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.55, blue: 0.95))
                        .frame(width: 70, alignment: .trailing)

                    // 输出
                    Text(formatTokens(m.outputTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.90))
                        .frame(width: 65, alignment: .trailing)

                    // 缓存命中
                    Text(formatTokens(m.cachedTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 0.70, blue: 0.85))
                        .frame(width: 75, alignment: .trailing)

                    // 合计
                    Text(formatTokens(m.totalTokens))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 75, alignment: .trailing)

                    // 占比胶囊
                    HStack(spacing: 4) {
                        QuotaProgressBar(
                            fraction: m.percentage / 100,
                            color: Color.blue,
                            track: Color.primary.opacity(0.08)
                        )
                        .frame(width: 42)
                        Text(String(format: "%.1f%%", m.percentage))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
        }
        .padding(12)
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

    private func modelColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Color.blue,
            Color.purple,
            Color.pink,
            Color.orange,
            Color.teal,
            Color.green
        ]
        return palette[index % palette.count]
    }

    // MARK: - 辅助占位与工具

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在读取 Token 统计...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private func errorPlaceholder(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("重试") {
                Task { await loadData(force: true) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private func loadData(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await GeminiQuotaService.queryTokenStats(
                endpoint: endpoint,
                token: token,
                period: period
            )
            self.snapshot = res
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    private func formatTokens(_ n: Double) -> String {
        let absVal = abs(n)
        if absVal >= 1_000_000_000 {
            return String(format: "%.1fB", n / 1_000_000_000)
        } else if absVal >= 1_000_000 {
            return String(format: "%.1fM", n / 1_000_000)
        } else if absVal >= 1_000 {
            return String(format: "%.1fK", n / 1_000)
        } else {
            return String(format: "%.0f", n)
        }
    }

    private func formatNumberWithCommas(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

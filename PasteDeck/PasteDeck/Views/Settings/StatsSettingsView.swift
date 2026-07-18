//
//  StatsSettingsView.swift
//  PasteDeck
//
//  Created on 2026-07-07.
//

import SwiftUI
import Charts

struct StatsSettingsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @State private var hoveredTrendDate: Date?
    @State private var hoveredTrendLocation: CGPoint?
    @State private var hoveredType: ClipboardContentType?
    @State private var hoveredTranslationTrendDate: Date?
    @State private var hoveredTranslationTrendLocation: CGPoint?
    @State private var hoveredTranslationServiceID: String?
    @State private var hoveredTranslationServiceLocation: CGPoint?
    @State private var showsTranslationDetails = false

    private let hoverAnimation = Animation.easeOut(duration: 0.14)
    private let chartTooltipWidth: CGFloat = 132
    private let translationTooltipWidth: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isLoading {
                loadingState
            } else {
                overviewGrid
                trendCard
                distributionAndInsights
                translationUsageCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDataChanged)) { _ in
            viewModel.handleClipboardChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationUsageDidChange)) { _ in
            viewModel.handleTranslationUsageChanged()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在生成使用概览")
                .font(.system(size: 15, weight: .semibold))
            Text("聚合数据加载完成后会自动刷新")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
    }

    // MARK: - Overview

    private var overviewGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 130), spacing: 12), count: 3),
            spacing: 12
        ) {
            metricCard(
                title: "今日复制",
                value: (viewModel.overview?.todayCount ?? 0).formatted(),
                unit: "次",
                detail: "今日实时累计",
                icon: "bolt.fill",
                color: .blue
            )
            metricCard(
                title: "历史条目",
                value: (viewModel.overview?.totalItems ?? 0).formatted(),
                unit: "条",
                detail: "当前保留记录",
                icon: "square.stack.3d.up.fill",
                color: .purple
            )
            metricCard(
                title: "缓存占用",
                value: StatsService.formatBytes(viewModel.overview?.cacheBytes ?? 0),
                unit: nil,
                detail: "图片与本地资源",
                icon: "internaldrive.fill",
                color: .orange
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        unit: String?,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.35), radius: 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .padding(15)
        .background(
            LinearGradient(
                colors: [color.opacity(0.14), Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Clipboard Trend

    private var trendCard: some View {
        dashboardCard(
            title: "复制趋势",
            subtitle: trendSummary,
            icon: "chart.xyaxis.line"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                        Text("每日复制")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("趋势范围", selection: $viewModel.trendDays) {
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 142)
                    .onChange(of: viewModel.trendDays) { _, _ in
                        hoveredTrendDate = nil
                        hoveredTrendLocation = nil
                        viewModel.reloadTrend()
                    }
                }

                if viewModel.trend.isEmpty {
                    emptyState(
                        title: "暂无趋势数据",
                        detail: "复制内容后，这里会展示每日变化",
                        icon: "chart.line.flattrend.xyaxis"
                    )
                    .frame(height: 210)
                } else {
                    trendChart
                }
            }
        }
    }

    private var trendSummary: String {
        let total = viewModel.trend.reduce(0) { partialResult, point in
            partialResult + point.count
        }
        let average = viewModel.trend.isEmpty ? 0 : Double(total) / Double(viewModel.trend.count)
        return "近 \(viewModel.trendDays) 天共 \(total.formatted()) 次，日均 \(average.formatted(.number.precision(.fractionLength(1)))) 次"
    }

    private var trendChart: some View {
        let maximumCount = max(5, viewModel.trend.map(\.count).max() ?? 0)
        let average = viewModel.trend.isEmpty
            ? 0
            : Double(viewModel.trend.reduce(0) { $0 + $1.count }) / Double(viewModel.trend.count)

        return Chart {
            ForEach(viewModel.trend) { point in
                AreaMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("复制次数", point.count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("复制次数", point.count)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.accentColor.gradient)

                if hoveredTrendDate == point.date {
                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("复制次数", point.count)
                    )
                    .symbolSize(58)
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .top, spacing: 10) {
                        trendTooltip(for: point)
                    }
                }
            }

            RuleMark(y: .value("日均", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .foregroundStyle(Color.secondary.opacity(0.38))
                .annotation(position: .top, alignment: .trailing) {
                    Text("日均 \(average.formatted(.number.precision(.fractionLength(1))))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: viewModel.trendDays == 7 ? 7 : 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(StatsService.formatShortDate(date))
                    }
                }
                .foregroundStyle(Color.secondary.opacity(0.72))
                AxisTick().foregroundStyle(Color.clear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
                    .foregroundStyle(Color.secondary.opacity(0.72))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.14))
                AxisTick().foregroundStyle(Color.clear)
            }
        }
        .chartYScale(domain: 0...maximumCount)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.primary.opacity(0.012))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleTrendHover(location: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredTrendDate = nil
                            hoveredTrendLocation = nil
                        }
                    }
            }
        }
        .frame(height: 228)
        .animation(hoverAnimation, value: hoveredTrendDate)
        .accessibilityLabel("复制趋势")
        .accessibilityValue(trendSummary)
    }

    private func handleTrendHover(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotAnchor = proxy.plotFrame else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        let plotFrame = geometry[plotAnchor]
        guard plotFrame.contains(location) else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        let relativeX = location.x - plotFrame.origin.x
        guard let date = proxy.value(atX: relativeX, as: Date.self) else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        guard viewModel.trend.contains(where: { $0.date == day }) else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        hoveredTrendDate = day
        hoveredTrendLocation = location
    }

    private func trendTooltip(for point: DailyTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(StatsService.formatDate(point.date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(point.count.formatted()) 次复制")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: chartTooltipWidth, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    // MARK: - Distribution And Insights

    private var distributionAndInsights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                typeDistributionCard
                    .frame(minWidth: 300, maxWidth: .infinity)
                insightCard
                    .frame(minWidth: 300, maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                typeDistributionCard
                insightCard
            }
        }
    }

    private var typeDistributionCard: some View {
        dashboardCard(
            title: "内容构成",
            subtitle: "按当前保留记录统计",
            icon: "square.stack.3d.down.right"
        ) {
            if viewModel.typeDistribution.isEmpty {
                emptyState(
                    title: "暂无内容数据",
                    detail: "复制不同内容后可查看类型占比",
                    icon: "chart.bar.xaxis"
                )
                .frame(height: 220)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    distributionStrip

                    ForEach(viewModel.typeDistribution) { item in
                        distributionRow(item)
                    }
                }
                .animation(hoverAnimation, value: hoveredType)
            }
        }
    }

    private var distributionStrip: some View {
        let total = max(1, viewModel.typeDistribution.reduce(0) { $0 + $1.count })

        return Chart(viewModel.typeDistribution) { item in
            BarMark(
                x: .value("数量", item.count),
                y: .value("全部内容", "全部内容")
            )
            .foregroundStyle(
                typeColor(for: item.type)
                    .opacity(hoveredType == nil || hoveredType == item.type ? 1 : 0.25)
            )
        }
        .chartXScale(domain: 0...total)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityLabel("内容类型分布")
        .accessibilityValue("共 \(total.formatted()) 条记录")
    }

    private func distributionRow(_ item: TypeDistributionItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon(for: item.type))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(typeColor(for: item.type))
                .frame(width: 25, height: 25)
                .background(typeColor(for: item.type).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            Text(item.type.displayName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 48, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.055))
                    Capsule()
                        .fill(typeColor(for: item.type).gradient)
                        .frame(width: max(4, geometry.size.width * item.percentage / 100))
                }
            }
            .frame(height: 6)

            Text("\(item.count.formatted())")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .trailing)

            Text(item.percentage.formatted(.number.precision(.fractionLength(0))) + "%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            hoveredType == item.type ? Color.primary.opacity(0.045) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(hoverAnimation) {
                hoveredType = isHovered ? item.type : nil
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var insightCard: some View {
        dashboardCard(
            title: "使用洞察",
            subtitle: "常用来源与数据极值",
            icon: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                sourceAppsSection
                Divider().opacity(0.55)
                extremesGrid
            }
        }
    }

    private var sourceAppsSection: some View {
        let maximumCount = max(1, viewModel.topSourceApps.map(\.count).max() ?? 0)

        return VStack(alignment: .leading, spacing: 9) {
            Text("高频来源")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if viewModel.topSourceApps.isEmpty {
                Text("暂无来源应用数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(viewModel.topSourceApps.enumerated()), id: \.element.id) { index, stat in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.primary.opacity(0.05), in: Circle())

                        Text(stat.appName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 78, alignment: .leading)

                        GeometryReader { geometry in
                            Capsule()
                                .fill(Color.primary.opacity(0.055))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(index == 0 ? 0.9 : 0.42))
                                        .frame(
                                            width: max(
                                                4,
                                                geometry.size.width * CGFloat(stat.count) / CGFloat(maximumCount)
                                            )
                                        )
                                }
                        }
                        .frame(height: 5)

                        Text(stat.count.formatted())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var extremesGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 100), spacing: 8), count: 2),
            spacing: 8
        ) {
            insightTile(
                title: "最长文本",
                value: viewModel.extremes?.longestTextChars.map { "\($0.formatted()) 字符" } ?? "无",
                icon: "text.alignleft"
            )
            insightTile(
                title: "最大图片",
                value: viewModel.extremes?.largestImageSize ?? "无",
                icon: "photo"
            )
            insightTile(
                title: "累计收藏",
                value: "\((viewModel.extremes?.totalFavorites ?? 0).formatted()) 条",
                icon: "star.fill"
            )
            insightTile(
                title: "累计置顶",
                value: "\((viewModel.extremes?.totalPinned ?? 0).formatted()) 条",
                icon: "pin.fill"
            )
            insightTile(
                title: "最大文件",
                value: viewModel.extremes?.largestFileDisplay ?? "无",
                icon: "doc.fill"
            )
            insightTile(
                title: "最早记录",
                value: viewModel.extremes?.earliestRecordDate.map { StatsService.formatDate($0) } ?? "无",
                icon: "calendar"
            )
        }
    }

    private func insightTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Translation Usage

    private var translationUsageCard: some View {
        dashboardCard(
            title: "翻译活动",
            subtitle: "调用量、稳定性与服务消耗",
            icon: "character.bubble.fill"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                translationFilters

                if viewModel.filteredTranslationUsage.isEmpty {
                    emptyState(
                        title: "所选范围暂无翻译记录",
                        detail: "完成翻译后会按服务和日期聚合展示",
                        icon: "character.bubble"
                    )
                    .frame(height: 190)
                } else {
                    translationMetricGrid
                    translationCharts
                    translationDetails
                }

                Label(
                    "密钥仅显示不可逆指纹；大模型 Token 以服务返回结果为准。",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var translationFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                translationDaysPicker
                Spacer(minLength: 12)
                translationTypePicker
            }

            VStack(alignment: .leading, spacing: 10) {
                translationDaysPicker
                translationTypePicker
            }
        }
    }

    private var translationDaysPicker: some View {
        Picker("翻译统计范围", selection: $viewModel.translationUsageDays) {
            Text("今天").tag(1)
            Text("7 天").tag(7)
            Text("30 天").tag(30)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 196)
        .onChange(of: viewModel.translationUsageDays) { _, _ in
            clearTranslationChartHover()
            viewModel.reloadTranslationUsage()
        }
    }

    private var translationTypePicker: some View {
        Picker("翻译调用类型", selection: $viewModel.translationUsageFilter) {
            ForEach(TranslationUsageFilter.allCases) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 196)
        .onChange(of: viewModel.translationUsageFilter) { _, _ in
            clearTranslationChartHover()
        }
    }

    @ViewBuilder
    private var translationMetricGrid: some View {
        let summary = viewModel.translationUsageSummary

        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 92), spacing: 8), count: 4),
            spacing: 8
        ) {
            translationMetric(
                title: "调用",
                value: summary.requestCount.formatted(),
                detail: "失败 \(summary.failedCount.formatted())",
                color: .blue
            )
            translationMetric(
                title: "成功率",
                value: (summary.successRate * 100).formatted(.number.precision(.fractionLength(0))) + "%",
                detail: "成功 \(summary.successCount.formatted())",
                color: summary.failedCount == 0 ? .green : .orange
            )

            switch viewModel.translationUsageFilter {
            case .api:
                translationMetric(
                    title: "输入字符",
                    value: summary.sourceCharacterCount.formatted(),
                    detail: "原文",
                    color: .cyan
                )
                translationMetric(
                    title: "输出字符",
                    value: summary.translatedCharacterCount.formatted(),
                    detail: "译文",
                    color: .teal
                )
            case .llm:
                translationMetric(
                    title: "输入 Token",
                    value: summary.promptTokenCount > 0 ? summary.promptTokenCount.formatted() : "—",
                    detail: summary.promptTokenCount > 0 ? "服务返回" : "暂无数据",
                    color: .indigo
                )
                translationMetric(
                    title: "输出 Token",
                    value: summary.completionTokenCount > 0 ? summary.completionTokenCount.formatted() : "—",
                    detail: summary.completionTokenCount > 0 ? "服务返回" : "暂无数据",
                    color: .purple
                )
            case .all:
                let apiSummary = viewModel.translationAPIUsageSummary
                let modelSummary = viewModel.translationLLMUsageSummary
                let apiCharacters = apiSummary.sourceCharacterCount + apiSummary.translatedCharacterCount
                let modelTokens = modelSummary.promptTokenCount + modelSummary.completionTokenCount

                translationMetric(
                    title: "API 字符",
                    value: apiCharacters.formatted(),
                    detail: "输入 + 输出",
                    color: .cyan
                )
                translationMetric(
                    title: "模型 Token",
                    value: modelTokens > 0 ? modelTokens.formatted() : "—",
                    detail: modelTokens > 0 ? "输入 + 输出" : "暂无数据",
                    color: .purple
                )
            }
        }
    }

    private func translationMetric(
        title: String,
        value: String,
        detail: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var translationCharts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                translationTrendPanel
                    .frame(minWidth: 300, maxWidth: .infinity)
                translationServicePanel
                    .frame(minWidth: 300, maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                translationTrendPanel
                translationServicePanel
            }
        }
    }

    private var translationTrendPanel: some View {
        chartPanel(title: "调用趋势", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 8) {
                translationUsageLegend
                translationUsageTrendChart
            }
        }
    }

    private var translationServicePanel: some View {
        chartPanel(title: "服务排行", icon: "chart.bar.xaxis") {
            translationUsageServiceChart
        }
    }

    private var translationUsageLegend: some View {
        HStack(spacing: 12) {
            if viewModel.translationUsageFilter != .llm {
                translationUsageLegendItem(
                    title: "API",
                    color: translationUsageKindColor(TranslationUsageKind.api.rawValue)
                )
            }
            if viewModel.translationUsageFilter != .api {
                translationUsageLegendItem(
                    title: "大模型",
                    color: translationUsageKindColor(TranslationUsageKind.llm.rawValue)
                )
            }
        }
    }

    private func translationUsageLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 4)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var translationUsageTrendChart: some View {
        let points = viewModel.translationUsageDailyPoints
        let maximumRequestCount = max(5, points.map(\.requestCount).max() ?? 0)

        return Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("调用", point.requestCount),
                    series: .value("类型", translationUsageKindLabel(point.usageKind))
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(
                    translationUsageKindColor(point.usageKind)
                        .opacity(
                            hoveredTranslationTrendDate == nil || hoveredTranslationTrendDate == point.date
                                ? 1
                                : 0.25
                        )
                )

                if hoveredTranslationTrendDate == point.date {
                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("调用", point.requestCount)
                    )
                    .symbolSize(42)
                    .foregroundStyle(translationUsageKindColor(point.usageKind))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: viewModel.translationUsageDays == 30 ? 5 : 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(StatsService.formatShortDate(date))
                    }
                }
                .foregroundStyle(Color.secondary.opacity(0.68))
                AxisTick().foregroundStyle(Color.clear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.68))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.12))
                AxisTick().foregroundStyle(Color.clear)
            }
        }
        .chartYScale(domain: 0...maximumRequestCount)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleTranslationTrendHover(
                                location: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        case .ended:
                            hoveredTranslationTrendDate = nil
                            hoveredTranslationTrendLocation = nil
                        }
                    }

                if let hoveredDate = hoveredTranslationTrendDate,
                   let location = hoveredTranslationTrendLocation {
                    let hoveredPoints = points.filter { $0.date == hoveredDate }
                    let tooltipHeight = CGFloat(44 + hoveredPoints.count * 40)
                    translationUsageTrendTooltip(date: hoveredDate, points: hoveredPoints)
                        .frame(width: translationTooltipWidth)
                        .position(
                            x: tooltipX(for: location, in: geometry, width: translationTooltipWidth),
                            y: tooltipY(for: location, in: geometry, height: tooltipHeight)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .frame(height: 176)
        .animation(hoverAnimation, value: hoveredTranslationTrendDate)
        .accessibilityLabel("翻译调用趋势")
    }

    private var translationUsageServiceChart: some View {
        let points = viewModel.translationUsageServicePoints
        let maximumRequestCount = max(1, points.map(\.requestCount).max() ?? 1)

        return Chart(points) { point in
            BarMark(
                x: .value("调用", point.requestCount),
                y: .value("服务", point.id)
            )
            .foregroundStyle(
                translationUsageKindColor(point.usageKind)
                    .opacity(
                        hoveredTranslationServiceID == nil || hoveredTranslationServiceID == point.id
                            ? 0.9
                            : 0.22
                    )
                    .gradient
            )
            .cornerRadius(4)
            .annotation(position: .trailing, spacing: 5) {
                Text(point.requestCount.formatted())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...Double(maximumRequestCount + max(1, maximumRequestCount / 4)))
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 3)) {
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.68))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.12))
                AxisTick().foregroundStyle(Color.clear)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let identifier = value.as(String.self),
                       let point = points.first(where: { $0.id == identifier }) {
                        Text(point.displayName)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleTranslationServiceHover(
                                location: location,
                                proxy: proxy,
                                geometry: geometry,
                                points: points
                            )
                        case .ended:
                            hoveredTranslationServiceID = nil
                            hoveredTranslationServiceLocation = nil
                        }
                    }

                if let identifier = hoveredTranslationServiceID,
                   let point = points.first(where: { $0.id == identifier }),
                   let location = hoveredTranslationServiceLocation {
                    translationUsageServiceTooltip(point)
                        .frame(width: translationTooltipWidth)
                        .position(
                            x: tooltipX(for: location, in: geometry, width: translationTooltipWidth),
                            y: tooltipY(for: location, in: geometry, height: 86)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .frame(height: max(176, CGFloat(points.count) * 29))
        .animation(hoverAnimation, value: hoveredTranslationServiceID)
        .accessibilityLabel("翻译服务调用排行")
    }

    private var translationDetails: some View {
        DisclosureGroup(isExpanded: $showsTranslationDetails) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredTranslationUsage) { usage in
                    translationUsageRow(usage)
                    if usage.id != viewModel.filteredTranslationUsage.last?.id {
                        Divider().opacity(0.45)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("调用明细", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(viewModel.translationUsageSummary.requestCount.formatted()) 次")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func handleTranslationTrendHover(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotAnchor = proxy.plotFrame else {
            hoveredTranslationTrendDate = nil
            hoveredTranslationTrendLocation = nil
            return
        }
        let plotFrame = geometry[plotAnchor]
        guard plotFrame.contains(location) else {
            hoveredTranslationTrendDate = nil
            hoveredTranslationTrendLocation = nil
            return
        }
        let relativeX = location.x - plotFrame.origin.x
        guard let date = proxy.value(atX: relativeX, as: Date.self) else {
            hoveredTranslationTrendDate = nil
            hoveredTranslationTrendLocation = nil
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        guard viewModel.translationUsageDailyPoints.contains(where: { $0.date == day }) else {
            hoveredTranslationTrendDate = nil
            hoveredTranslationTrendLocation = nil
            return
        }
        hoveredTranslationTrendDate = day
        hoveredTranslationTrendLocation = location
    }

    private func handleTranslationServiceHover(
        location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [TranslationUsageServicePoint]
    ) {
        guard let plotAnchor = proxy.plotFrame else {
            hoveredTranslationServiceID = nil
            hoveredTranslationServiceLocation = nil
            return
        }
        let plotFrame = geometry[plotAnchor]
        guard plotFrame.contains(location) else {
            hoveredTranslationServiceID = nil
            hoveredTranslationServiceLocation = nil
            return
        }
        let relativeY = location.y - plotFrame.origin.y
        guard let identifier = proxy.value(atY: relativeY, as: String.self),
              points.contains(where: { $0.id == identifier }) else {
            hoveredTranslationServiceID = nil
            hoveredTranslationServiceLocation = nil
            return
        }
        hoveredTranslationServiceID = identifier
        hoveredTranslationServiceLocation = location
    }

    private func translationUsageTrendTooltip(
        date: Date,
        points: [TranslationUsageDailyPoint]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(StatsService.formatDate(date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(translationUsageKindColor(point.usageKind))
                            .frame(width: 6, height: 6)
                        Text(translationUsageKindLabel(point.usageKind))
                            .font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text("\(point.requestCount.formatted()) 次")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    Text("成功 \(point.successCount.formatted()) · 失败 \(point.failedCount.formatted())")
                        .font(.system(size: 9, design: .monospaced))
                    Text(translationUsageUnitDetail(
                        usageKind: point.usageKind,
                        sourceCharacterCount: point.sourceCharacterCount,
                        translatedCharacterCount: point.translatedCharacterCount,
                        promptTokenCount: point.promptTokenCount,
                        completionTokenCount: point.completionTokenCount
                    ))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    private func translationUsageServiceTooltip(_ point: TranslationUsageServicePoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(translationUsageKindColor(point.usageKind))
                    .frame(width: 6, height: 6)
                Text(point.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(translationUsageKindLabel(point.usageKind))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("调用 \(point.requestCount.formatted()) · 成功 \(point.successCount.formatted()) · 失败 \(point.failedCount.formatted())")
                .font(.system(size: 9, design: .monospaced))
            Text(translationUsageUnitDetail(
                usageKind: point.usageKind,
                sourceCharacterCount: point.sourceCharacterCount,
                translatedCharacterCount: point.translatedCharacterCount,
                promptTokenCount: point.promptTokenCount,
                completionTokenCount: point.completionTokenCount
            ))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    private func translationUsageRow(_ usage: TranslationUsageStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StatsService.formatShortDate(usage.date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(usage.providerName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(translationUsageKindLabel(usage.usageKind))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(translationUsageKindColor(usage.usageKind))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        translationUsageKindColor(usage.usageKind).opacity(0.1),
                        in: Capsule()
                    )
                Spacer()
                Text("\(usage.requestCount.formatted()) 次 · 成功 \(usage.successCount.formatted())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("密钥 \(usage.credentialFingerprint)")
                if !usage.modelName.isEmpty {
                    Text("模型 \(usage.modelName)")
                }
                Text(translationUsageUnitDetail(
                    usageKind: usage.usageKind,
                    sourceCharacterCount: usage.sourceCharacterCount,
                    translatedCharacterCount: usage.translatedCharacterCount,
                    promptTokenCount: usage.promptTokenCount,
                    completionTokenCount: usage.completionTokenCount
                ))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func translationUsageUnitDetail(
        usageKind: String,
        sourceCharacterCount: Int,
        translatedCharacterCount: Int,
        promptTokenCount: Int,
        completionTokenCount: Int
    ) -> String {
        if usageKind == TranslationUsageKind.llm.rawValue {
            guard promptTokenCount + completionTokenCount > 0 else { return "Token 服务未返回" }
            return "Token \(promptTokenCount.formatted()) 入 / \(completionTokenCount.formatted()) 出"
        }
        return "字符 \(sourceCharacterCount.formatted()) 入 / \(translatedCharacterCount.formatted()) 出"
    }

    private func tooltipX(for location: CGPoint, in geometry: GeometryProxy, width: CGFloat) -> CGFloat {
        min(max(location.x, width / 2 + 4), geometry.size.width - width / 2 - 4)
    }

    private func tooltipY(for location: CGPoint, in geometry: GeometryProxy, height: CGFloat) -> CGFloat {
        if location.y > height + 12 {
            return location.y - height / 2 - 8
        }
        return min(location.y + height / 2 + 8, geometry.size.height - height / 2 - 4)
    }

    private func clearTranslationChartHover() {
        hoveredTranslationTrendDate = nil
        hoveredTranslationTrendLocation = nil
        hoveredTranslationServiceID = nil
        hoveredTranslationServiceLocation = nil
    }

    // MARK: - Shared Presentation

    private func dashboardCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 29, height: 29)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.76),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 1)
        }
    }

    private func chartPanel<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.023), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyState(title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func typeIcon(for type: ClipboardContentType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .markdown: return "text.badge.checkmark"
        case .json: return "curlybraces"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    private func typeColor(for type: ClipboardContentType) -> Color {
        switch type {
        case .text: return .blue
        case .link: return .green
        case .markdown: return .purple
        case .json: return .orange
        case .image: return .pink
        case .file: return .brown
        case .color: return .yellow
        }
    }

    private func translationUsageKindLabel(_ usageKind: String) -> String {
        usageKind == TranslationUsageKind.llm.rawValue ? "大模型" : "API"
    }

    private func translationUsageKindColor(_ usageKind: String) -> Color {
        usageKind == TranslationUsageKind.llm.rawValue ? .purple : .accentColor
    }
}

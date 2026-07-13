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

    var body: some View {
        SettingsContentStack {
            if viewModel.isLoading {
                loadingState
            } else {
                overviewSection
                trendSection
                typeDistributionSection
                insightsSection
                translationUsageSection
            }
        }
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

    // MARK: - Hover Animation Helpers

    private var hoverAnimation: Animation {
        .easeOut(duration: 0.15)
    }

    private let tooltipWidth: CGFloat = 100
    private let tooltipHeight: CGFloat = 36
    private let translationTooltipWidth: CGFloat = 220

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在加载统计数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text("正在从聚合表中读取数据")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Section 1: Overview

    private var overviewSection: some View {
        SettingsCard(title: "概览", icon: "chart.bar") {
            HStack(spacing: 0) {
                overviewCell(
                    title: "今日复制",
                    value: "\(viewModel.overview?.todayCount ?? 0)",
                    subtitle: "次"
                )
                verticalDivider
                overviewCell(
                    title: "总条数",
                    value: "\(viewModel.overview?.totalItems ?? 0)",
                    subtitle: "条"
                )
                verticalDivider
                overviewCell(
                    title: "缓存占用",
                    value: StatsService.formatBytes(viewModel.overview?.cacheBytes ?? 0),
                    subtitle: nil
                )
            }
        }
    }

    private func overviewCell(title: String, value: String, subtitle: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    // MARK: - Section 2: Trend

    private var trendSection: some View {
        SettingsCard(title: "复制趋势", icon: "chart.line.uptrend.xy") {
            VStack(spacing: 12) {
                HStack {
                    Picker("", selection: $viewModel.trendDays) {
                        Text("近 7 天").tag(7)
                        Text("近 30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: viewModel.trendDays) { _, _ in
                        viewModel.reloadTrend()
                    }
                    Spacer()
                }

                if viewModel.trend.isEmpty {
                    emptyChartPlaceholder
                } else {
                    trendChart
                }
            }
        }
    }

    private var trendChart: some View {
        let maxValue = viewModel.trend.map(\.count).max() ?? 1

        return Chart(viewModel.trend) { point in
            BarMark(
                x: .value("日期", point.date, unit: .day),
                y: .value("次数", point.count)
            )
            .foregroundStyle(
                hoveredTrendDate == point.date
                    ? Color.accentColor.opacity(1.0).gradient
                    : (hoveredTrendDate == nil
                        ? Color.accentColor.gradient
                        : Color.accentColor.opacity(0.25).gradient)
            )
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(StatsService.formatShortDate(date))
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartYScale(domain: 0...max(maxValue, 5))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleTrendHover(location: location, proxy: proxy, geo: geo)
                            hoveredTrendLocation = location
                        case .ended:
                            hoveredTrendDate = nil
                            hoveredTrendLocation = nil
                        }
                    }

                if let date = hoveredTrendDate,
                   let point = viewModel.trend.first(where: { $0.date == date }),
                   let loc = hoveredTrendLocation,
                   let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    let tipX = min(max(loc.x, tooltipWidth / 2), plotFrame.width - tooltipWidth / 2)
                    let tipY = max(loc.y - tooltipHeight - 6, 4)
                    trendTooltip(for: point)
                        .frame(width: tooltipWidth)
                        .position(x: tipX, y: tipY)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .frame(height: 180)
        .animation(hoverAnimation, value: hoveredTrendDate)
        .animation(hoverAnimation, value: hoveredTrendLocation)
    }

    private func handleTrendHover(location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        let origin = geo[plotFrame].origin
        let relX = location.x - origin.x
        guard relX >= 0, relX <= geo[plotFrame].width else {
            hoveredTrendDate = nil
            hoveredTrendLocation = nil
            return
        }
        if let date: Date = proxy.value(atX: relX, as: Date.self) {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            if viewModel.trend.contains(where: { $0.date == dayStart }) {
                hoveredTrendDate = dayStart
            } else {
                hoveredTrendDate = nil
            }
        } else {
            hoveredTrendDate = nil
        }
    }

    private func trendTooltip(for point: DailyTrendPoint) -> some View {
        VStack(spacing: 2) {
            Text(StatsService.formatDate(point.date))
                .font(.system(size: 11, weight: .medium))
            Text("\(point.count) 次复制")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .padding(.top, 4)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("暂无趋势数据")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    // MARK: - Section 3: Type Distribution

    private var typeDistributionSection: some View {
        SettingsCard(title: "内容类型分布", icon: "chart.pie") {
            if viewModel.typeDistribution.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("暂无类型数据")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                HStack(spacing: 20) {
                    pieChart
                    typeLegend
                }
                .animation(hoverAnimation, value: hoveredType)
            }
        }
    }

    private var pieChart: some View {
        let total = viewModel.typeDistribution.reduce(0) { $0 + $1.count }

        return Chart(viewModel.typeDistribution) { item in
            SectorMark(
                angle: .value("数量", item.count),
                innerRadius: .ratio(0.5),
                outerRadius: hoveredType == item.type ? .ratio(1.0) : .ratio(0.92),
                angularInset: 1.5
            )
            .foregroundStyle(
                typeColor(for: item.type)
                    .opacity(hoveredType == nil || hoveredType == item.type ? 1.0 : 0.3)
            )
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handlePieHover(location: location, proxy: proxy, geo: geo, total: total)
                        case .ended:
                            hoveredType = nil
                        }
                    }
            }
        }
        .frame(width: 140, height: 140)
        .overlay {
            if let hovered = hoveredType,
               let item = viewModel.typeDistribution.first(where: { $0.type == hovered }) {
                pieTooltip(for: item)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(hoverAnimation, value: hoveredType)
    }

    private func handlePieHover(location: CGPoint, proxy: ChartProxy, geo: GeometryProxy, total: Int) {
        guard total > 0,
              let plotFrame = proxy.plotFrame else {
            hoveredType = nil
            return
        }
        let frame = geo[plotFrame]
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        let outerR = min(frame.width, frame.height) / 2
        let innerR = outerR * 0.5

        guard dist >= innerR, dist <= outerR else {
            hoveredType = nil
            return
        }

        // Compute angle: 0 at top (12 o'clock), clockwise
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }

        // Find which sector this angle falls into
        var cumulative: Double = 0
        for item in viewModel.typeDistribution {
            let fraction = Double(item.count) / Double(total)
            let sectorAngle = fraction * 2 * .pi
            if angle >= cumulative && angle < cumulative + sectorAngle {
                hoveredType = item.type
                return
            }
            cumulative += sectorAngle
        }
        hoveredType = nil
    }

    private func pieTooltip(for item: TypeDistributionItem) -> some View {
        VStack(spacing: 2) {
            Text(item.type.displayName)
                .font(.system(size: 11, weight: .medium))
            Text("\(item.count) · \(String(format: "%.1f%%", item.percentage))")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }

    private var typeLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.typeDistribution) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(typeColor(for: item.type))
                        .frame(width: 8, height: 8)
                    Text(item.type.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.0f%%", item.percentage))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(item.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    hoveredType == item.type
                        ? Color.primary.opacity(0.06)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onHover { isHovered in
                    withAnimation(hoverAnimation) {
                        hoveredType = isHovered ? item.type : nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Section 4: Insights

    private var insightsSection: some View {
        SettingsCard(title: "使用洞察", icon: "lightbulb") {
            HStack(alignment: .top, spacing: 20) {
                sourceAppsColumn
                extremesColumn
            }
        }
    }

    private var sourceAppsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("来源 Top 5")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            if viewModel.topSourceApps.isEmpty {
                Text("暂无来源数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(viewModel.topSourceApps) { stat in
                    HStack(spacing: 8) {
                        Text(stat.appName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text("\(stat.count)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var extremesColumn: some View {
        let ext = viewModel.extremes

        return VStack(alignment: .leading, spacing: 8) {
            Text("极值与累计")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            insightRow(
                title: "最长文本",
                value: ext?.longestTextChars.map { "\($0) 字符" } ?? "无"
            )
            insightRow(
                title: "最大图片",
                value: ext?.largestImageSize ?? "无"
            )
            insightRow(
                title: "最大文件",
                value: ext?.largestFileDisplay ?? "无"
            )
            insightRow(
                title: "最早记录",
                value: ext?.earliestRecordDate.map { StatsService.formatDate($0) } ?? "无"
            )
            insightRow(
                title: "累计收藏",
                value: "\(ext?.totalFavorites ?? 0) 条"
            )
            insightRow(
                title: "累计置顶",
                value: "\(ext?.totalPinned ?? 0) 条"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insightRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Section 5: Translation Usage

    private var translationUsageSection: some View {
        SettingsCard(
            title: "翻译调用统计",
            icon: "chart.bar.doc.horizontal",
            footer: "调用按日期、服务配置和模型聚合。大模型 Token 来自服务响应；密钥仅显示不可逆指纹，不会暴露完整凭据。"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Picker("", selection: $viewModel.translationUsageDays) {
                        Text("今天").tag(1)
                        Text("近 7 天").tag(7)
                        Text("近 30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: viewModel.translationUsageDays) { _, _ in
                        clearTranslationChartHover()
                        viewModel.reloadTranslationUsage()
                    }

                    Spacer()

                    Picker("", selection: $viewModel.translationUsageFilter) {
                        ForEach(TranslationUsageFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: viewModel.translationUsageFilter) { _, _ in
                        clearTranslationChartHover()
                    }
                }

                if viewModel.filteredTranslationUsage.isEmpty {
                    Text("所选时段暂无翻译调用记录")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                } else {
                    translationUsageSummaryStrip

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("调用趋势", systemImage: "chart.xyaxis.line")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            translationUsageLegend
                        }
                        translationUsageTrendChart
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("服务调用排行", systemImage: "chart.bar.xaxis")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("最多展示 6 项")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        translationUsageServiceChart
                    }

                    Divider()

                    HStack {
                        Text("调用明细")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(viewModel.translationUsageSummary.requestCount) 次")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.filteredTranslationUsage) { usage in
                        translationUsageRow(usage)
                        if usage.id != viewModel.filteredTranslationUsage.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var translationUsageSummaryStrip: some View {
        let summary = viewModel.translationUsageSummary

        return HStack(spacing: 0) {
            translationUsageSummaryCell(
                title: "调用",
                value: summary.requestCount.formatted(),
                subtitle: "次"
            )
            verticalDivider
            translationUsageSummaryCell(
                title: "成功率",
                value: String(format: "%.0f%%", summary.successRate * 100),
                subtitle: "失败 \(summary.failedCount)"
            )
            translationUsageUnitSummaryCells
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }

    private func translationUsageSummaryCell(
        title: String,
        value: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var translationUsageUnitSummaryCells: some View {
        switch viewModel.translationUsageFilter {
        case .api:
            verticalDivider
            translationUsageSummaryCell(
                title: "输入字符",
                value: viewModel.translationUsageSummary.sourceCharacterCount.formatted(),
                subtitle: "字符"
            )
            verticalDivider
            translationUsageSummaryCell(
                title: "输出字符",
                value: viewModel.translationUsageSummary.translatedCharacterCount.formatted(),
                subtitle: "字符"
            )
        case .llm:
            verticalDivider
            translationUsageSummaryCell(
                title: "输入 Token",
                value: viewModel.translationUsageSummary.promptTokenCount > 0
                    ? viewModel.translationUsageSummary.promptTokenCount.formatted()
                    : "—",
                subtitle: viewModel.translationUsageSummary.promptTokenCount > 0 ? "服务返回" : "服务未返回"
            )
            verticalDivider
            translationUsageSummaryCell(
                title: "输出 Token",
                value: viewModel.translationUsageSummary.completionTokenCount > 0
                    ? viewModel.translationUsageSummary.completionTokenCount.formatted()
                    : "—",
                subtitle: viewModel.translationUsageSummary.completionTokenCount > 0 ? "服务返回" : "服务未返回"
            )
        case .all:
            let apiSummary = viewModel.translationAPIUsageSummary
            let llmSummary = viewModel.translationLLMUsageSummary
            let apiCharacterCount = apiSummary.sourceCharacterCount + apiSummary.translatedCharacterCount
            let llmTokenCount = llmSummary.promptTokenCount + llmSummary.completionTokenCount

            verticalDivider
            translationUsageSummaryCell(
                title: "API 字符",
                value: apiCharacterCount.formatted(),
                subtitle: "入 \(apiSummary.sourceCharacterCount.formatted()) / 出 \(apiSummary.translatedCharacterCount.formatted())"
            )
            verticalDivider
            translationUsageSummaryCell(
                title: "大模型 Token",
                value: llmTokenCount > 0 ? llmTokenCount.formatted() : "—",
                subtitle: llmTokenCount > 0
                    ? "入 \(llmSummary.promptTokenCount.formatted()) / 出 \(llmSummary.completionTokenCount.formatted())"
                    : "服务未返回"
            )
        }
    }

    private var translationUsageLegend: some View {
        HStack(spacing: 10) {
            if viewModel.translationUsageFilter != .llm {
                translationUsageLegendItem(title: "API", color: translationUsageKindColor(TranslationUsageKind.api.rawValue))
            }
            if viewModel.translationUsageFilter != .api {
                translationUsageLegendItem(title: "大模型", color: translationUsageKindColor(TranslationUsageKind.llm.rawValue))
            }
        }
    }

    private func translationUsageLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var translationUsageTrendChart: some View {
        let points = viewModel.translationUsageDailyPoints
        let maximumRequestCount = max(1, points.map(\.requestCount).max() ?? 1)

        return Chart(points) { point in
            BarMark(
                x: .value("日期", point.date, unit: .day),
                y: .value("调用", point.requestCount)
            )
            .position(by: .value("类型", translationUsageKindLabel(point.usageKind)))
            .foregroundStyle(
                translationUsageKindColor(point.usageKind)
                    .opacity(
                        hoveredTranslationTrendDate == nil || hoveredTranslationTrendDate == point.date
                            ? 1.0
                            : 0.25
                    )
                    .gradient
            )
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(StatsService.formatShortDate(date))
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartYScale(domain: 0...max(maximumRequestCount, 5))
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            handleTranslationTrendHover(location: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredTranslationTrendDate = nil
                            hoveredTranslationTrendLocation = nil
                        }
                    }

                if let hoveredDate = hoveredTranslationTrendDate,
                   let location = hoveredTranslationTrendLocation {
                    let hoveredPoints = points.filter { $0.date == hoveredDate }
                    let tooltipHeight = CGFloat(40 + hoveredPoints.count * 42)
                    translationUsageTrendTooltip(date: hoveredDate, points: hoveredPoints)
                        .frame(width: translationTooltipWidth)
                        .position(
                            x: tooltipX(for: location, in: geometry, width: translationTooltipWidth),
                            y: tooltipY(for: location, in: geometry, height: tooltipHeight)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .frame(height: 168)
        .animation(hoverAnimation, value: hoveredTranslationTrendDate)
        .animation(hoverAnimation, value: hoveredTranslationTrendLocation)
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
                            ? 1.0
                            : 0.25
                    )
                    .gradient
            )
            .cornerRadius(2)
            .annotation(position: .trailing) {
                Text(point.requestCount.formatted())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(
                        Color.secondary.opacity(
                            hoveredTranslationServiceID == nil || hoveredTranslationServiceID == point.id
                                ? 1.0
                                : 0.25
                        )
                    )
            }
        }
        .chartXScale(domain: 0...Double(maximumRequestCount + max(1, maximumRequestCount / 5)))
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let identifier = value.as(String.self),
                       let point = points.first(where: { $0.id == identifier }) {
                        Text(point.displayName)
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
                            y: tooltipY(for: location, in: geometry, height: 82)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .frame(height: max(120, CGFloat(points.count) * 31))
        .animation(hoverAnimation, value: hoveredTranslationServiceID)
        .animation(hoverAnimation, value: hoveredTranslationServiceLocation)
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
                .font(.system(size: 11, weight: .medium))
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(translationUsageKindColor(point.usageKind))
                            .frame(width: 6, height: 6)
                        Text(translationUsageKindLabel(point.usageKind))
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("调用 \(point.requestCount) · 成功 \(point.successCount) · 失败 \(point.failedCount)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    Text(translationUsageUnitDetail(
                        usageKind: point.usageKind,
                        sourceCharacterCount: point.sourceCharacterCount,
                        translatedCharacterCount: point.translatedCharacterCount,
                        promptTokenCount: point.promptTokenCount,
                        completionTokenCount: point.completionTokenCount
                    ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }

    private func translationUsageServiceTooltip(_ point: TranslationUsageServicePoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(translationUsageKindColor(point.usageKind))
                    .frame(width: 6, height: 6)
                Text(point.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(translationUsageKindLabel(point.usageKind))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text("调用 \(point.requestCount) · 成功 \(point.successCount) · 失败 \(point.failedCount)")
                .font(.system(size: 10, design: .monospaced))
            Text(translationUsageUnitDetail(
                usageKind: point.usageKind,
                sourceCharacterCount: point.sourceCharacterCount,
                translatedCharacterCount: point.translatedCharacterCount,
                promptTokenCount: point.promptTokenCount,
                completionTokenCount: point.completionTokenCount
            ))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
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

    private func translationUsageRow(_ usage: TranslationUsageStat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StatsService.formatShortDate(usage.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .leading)
                Text(usage.providerName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(translationUsageKindLabel(usage.usageKind))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                Spacer()
                Text("\(usage.requestCount) 次 · 成功 \(usage.successCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Text("密钥 \(usage.credentialFingerprint)")
                if !usage.modelName.isEmpty {
                    Text("模型 \(usage.modelName)")
                }
                if usage.usageKind == TranslationUsageKind.llm.rawValue {
                    Text(
                        usage.promptTokenCount + usage.completionTokenCount > 0
                            ? "Token \(usage.promptTokenCount) 入 / \(usage.completionTokenCount) 出"
                            : "Token 服务未返回"
                    )
                } else {
                    Text("字符 \(usage.sourceCharacterCount) 入 / \(usage.translatedCharacterCount) 出")
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }

    private func translationUsageKindLabel(_ usageKind: String) -> String {
        usageKind == TranslationUsageKind.llm.rawValue ? "大模型" : "API"
    }

    private func translationUsageKindColor(_ usageKind: String) -> Color {
        usageKind == TranslationUsageKind.llm.rawValue ? .purple : .accentColor
    }
}

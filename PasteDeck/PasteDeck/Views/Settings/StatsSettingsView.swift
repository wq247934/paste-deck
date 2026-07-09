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

    // Hover state for interactive charts
    @State private var hoveredTrendIndex: Int? = nil
    @State private var hoveredType: ClipboardContentType? = nil

    var body: some View {
        SettingsContentStack {
            if viewModel.isLoading {
                loadingState
            } else {
                overviewSection
                trendSection
                typeDistributionSection
                insightsSection
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardDataChanged)) { _ in
            viewModel.handleClipboardChanged()
        }
    }

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
        let data = viewModel.trend

        return Chart(data) { point in
            let isHovered = hoveredTrendIndex == data.firstIndex(where: { $0.date == point.date })

            BarMark(
                x: .value("日期", point.date, unit: .day),
                y: .value("次数", point.count)
            )
            .foregroundStyle(isHovered ? Color.accentColor : Color.accentColor.opacity(0.7))
            .cornerRadius(2)
            .opacity(isHovered ? 1.0 : 0.85)
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
        .frame(height: 180)
        .chartBackground { chartProxy in
            trendChartBackground(data: data, chartProxy: chartProxy)
        }
        .overlay {
            trendChartOverlay(data: data)
        }
    }

    private func trendChartBackground(data: [DailyTrendPoint], chartProxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    handleTrendHover(phase: phase, geometry: geometry, chartProxy: chartProxy, data: data)
                }
        }
    }

    private func handleTrendHover(phase: HoverPhase, geometry: GeometryProxy, chartProxy: ChartProxy, data: [DailyTrendPoint]) {
        switch phase {
        case .active(let location):
            if let date: Date = chartProxy.value(atX: location.x, as: Date.self) {
                let calendar = Calendar.current
                hoveredTrendIndex = data.firstIndex { calendar.isDate($0.date, inSameDayAs: date) }
            }
        case .ended:
            hoveredTrendIndex = nil
        }
    }

    private func trendChartOverlay(data: [DailyTrendPoint]) -> some View {
        Group {
            if let index = hoveredTrendIndex, index < data.count {
                trendTooltip(for: data[index])
            }
        }
    }

    private func trendTooltip(for point: DailyTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StatsService.formatDate(point.date))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            Text("\(point.count) 次复制")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
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
            }
        }
    }

    private var pieChart: some View {
        let data = viewModel.typeDistribution

        return Chart(data) { item in
            let isHovered = hoveredType == item.type
            let outerRadius: CGFloat = isHovered ? 1.05 : 1.0
            let opacity: Double = isHovered ? 1.0 : (hoveredType == nil ? 1.0 : 0.5)

            SectorMark(
                angle: .value("数量", item.count),
                innerRadius: .ratio(0.5),
                outerRadius: .ratio(outerRadius),
                angularInset: 1.5
            )
            .foregroundStyle(typeColor(for: item.type))
            .opacity(opacity)
        }
        .chartLegend(.hidden)
        .frame(width: 140, height: 140)
        .chartBackground { chartProxy in
            pieChartBackground(data: data)
        }
        .overlay {
            pieChartOverlay(data: data)
        }
    }

    private func pieChartBackground(data: [TypeDistributionItem]) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Circle())
                .onContinuousHover { phase in
                    handlePieHover(phase: phase, geometry: geometry, data: data)
                }
        }
    }

    private func handlePieHover(phase: HoverPhase, geometry: GeometryProxy, data: [TypeDistributionItem]) {
        switch phase {
        case .active(let location):
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let dx = location.x - center.x
            let dy = location.y - center.y
            let distance = sqrt(dx * dx + dy * dy)
            let radius = min(geometry.size.width, geometry.size.height) / 2

            guard distance <= radius else {
                hoveredType = nil
                return
            }

            var angle = atan2(dy, dx)
            if angle < 0 { angle += 2 * .pi }
            angle = (angle + .pi / 2)
            if angle < 0 { angle += 2 * .pi }
            if angle >= 2 * .pi { angle -= 2 * .pi }
            let degrees = angle * 180 / .pi

            let total = data.map(\.count).reduce(0, +)
            var currentAngle: Double = 0
            for item in data {
                let itemAngle = Double(item.count) / Double(total) * 360
                if degrees >= currentAngle && degrees < currentAngle + itemAngle {
                    hoveredType = item.type
                    break
                }
                currentAngle += itemAngle
            }
        case .ended:
            hoveredType = nil
        }
    }

    private func pieChartOverlay(data: [TypeDistributionItem]) -> some View {
        Group {
            if let type = hoveredType, let item = data.first(where: { $0.type == type }) {
                pieTooltip(for: item)
            }
        }
    }

    private func pieTooltip(for item: TypeDistributionItem) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(item.type.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            Text("\(item.count) 条")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(typeColor(for: item.type))
            Text(String(format: "%.1f%%", item.percentage))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

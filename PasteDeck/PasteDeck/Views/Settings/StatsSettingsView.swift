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

    // MARK: - Hover Animation Helpers

    private var hoverAnimation: Animation {
        .easeOut(duration: 0.15)
    }

    private let tooltipWidth: CGFloat = 100
    private let tooltipHeight: CGFloat = 36

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
}

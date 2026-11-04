import Accessibility
import AgentSpeedCore
import SwiftUI

/// Audio graph of the daily chart: output per day with the average speed as a second series, or cost per day in the
/// display currency (DESIGN 9).
struct HistoryChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let dayTitle: String
    let outputTitle: String
    let speedTitle: String
    let labels: [String]
    let outputs: [Double]
    let speeds: [Double?]
    let outputMax: Double
    let language: AppLanguage
    /// Cost values read as amounts (`12.34 美元`).
    let money: HistoryMoney?
    /// Traffic values read as bytes (↓ + ↑ per day).
    var bytes = false

    @MainActor
    init(chart: HistoryChartModel, l10n: Localizer) {
        let cost = chart.metric == .cost
        title = l10n(chart.metric.titleKey)
        summary = HistoryText.rangeSubtitle(chart.range, l10n)
        dayTitle = l10n("history.table.date")
        let traffic = chart.metric == .traffic
        bytes = traffic
        outputTitle = l10n(traffic ? "history.table.traffic" : cost ? "history.table.cost" : "history.table.output")
        speedTitle = "\(l10n("history.chart.speed")) (\(l10n("unit.tokS")))"
        labels = chart.range.days.map { HistoryText.longDate($0, l10n) }
        outputs = chart.range.days.map { day in
            if traffic { return Double(chart.traffic[day]?.shown.sum ?? 0) }
            guard let summary = chart.days[day] else { return 0 }
            return cost ? (chart.money?.value(summary.cost.microUsd) ?? 0) : Double(summary.output)
        }
        speeds = chart.speeds
        outputMax = max(chart.outputTicks.max + (chart.lowerTicks?.max ?? 0), cost ? 0.000001 : 1)
        language = l10n.language
        money = cost ? chart.money : nil
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: dayTitle, categoryOrder: labels)
        let money = money
        let bytes = bytes
        let yAxis = AXNumericDataAxisDescriptor(title: outputTitle, range: 0...outputMax, gridlinePositions: []) { value in
            if bytes { return TrafficFormat.total(value) }
            if let money, let micro = money.microUsd(fromValue: value) { return money.spoken(micro) }
            return SpeedFormat.tokens(Int(value.rounded()))
        }
        let output = AXDataSeriesDescriptor(
            name: outputTitle,
            isContinuous: false,
            dataPoints: zip(labels, outputs).map { AXDataPoint(x: $0, y: $1) }
        )
        let speed = AXDataSeriesDescriptor(
            name: speedTitle,
            isContinuous: true,
            dataPoints: zip(labels, speeds).compactMap { label, value in value.map { AXDataPoint(x: label, y: $0) } }
        )
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: money == nil ? [output, speed] : [output]
        )
    }
}

/// Audio graph of a single day's breakdown: output per source or model, most first.
struct HistoryBreakdownDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let nameTitle: String
    let outputTitle: String
    let names: [String]
    let outputs: [Double]

    /// Cost values read as amounts.
    let money: HistoryMoney?

    @MainActor
    init(breakdown: DayBreakdown, money: HistoryMoney, l10n: Localizer) {
        let cost = breakdown.metric == .cost
        title = l10n(breakdown.titleKey)
        summary = HistoryText.longDate(breakdown.day, l10n)
        nameTitle = l10n(breakdown.kind == .bySource ? "dashboard.sources" : "history.table.models")
        outputTitle = l10n(cost ? "history.table.cost" : "history.table.output")
        names = breakdown.items.map { HistoryText.breakdownName($0.subject, l10n) }
        outputs = breakdown.items.map { cost ? money.value($0.cost.microUsd) : Double($0.output) }
        self.money = cost ? money : nil
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: nameTitle, categoryOrder: names)
        let money = money
        let yAxis = AXNumericDataAxisDescriptor(title: outputTitle, range: 0...max(outputs.max() ?? 0, money == nil ? 1 : 0.000001), gridlinePositions: []) { value in
            if let money, let micro = money.microUsd(fromValue: value) { return money.spoken(micro) }
            return SpeedFormat.tokens(Int(value.rounded()))
        }
        let output = AXDataSeriesDescriptor(
            name: outputTitle,
            isContinuous: false,
            dataPoints: zip(names, outputs).map { AXDataPoint(x: $0, y: $1) }
        )
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [output])
    }
}

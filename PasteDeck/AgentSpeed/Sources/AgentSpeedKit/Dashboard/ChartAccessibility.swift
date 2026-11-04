import Accessibility
import AgentSpeedCore
import SwiftUI

/// Audio-graph description of the live chart for VoiceOver.
struct LiveChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let timeTitle: String
    let valueTitle: String
    let language: AppLanguage
    let span: TimeInterval
    let top: Double
    /// (seconds relative to now, ≤ 0; value in tok/s)
    let points: [(Double, Double)]

    init(series: ChartSeries, domain: Double, title: String, summary: String, timeTitle: String, valueTitle: String, language: AppLanguage) {
        self.title = title
        self.summary = summary
        self.timeTitle = timeTitle
        self.valueTitle = valueTitle
        self.language = language
        span = series.end - series.start
        top = max(domain, 1)
        points = series.samples
            .filter { $0.time >= series.start }
            .map { (($0.time - series.end).rounded(), $0.total) }
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let language = language
        let xAxis = AXNumericDataAxisDescriptor(
            title: timeTitle,
            range: -span...0,
            gridlinePositions: []
        ) { value in
            let seconds = Int((-value).rounded())
            if seconds <= 0 { return Localizer.string("mac.dashboard.now", language: language) }
            return String(format: Localizer.string("time.secondsAgo", language: language), locale: language.locale, seconds)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: valueTitle,
            range: 0...top,
            gridlinePositions: []
        ) { value in
            String(format: Localizer.string("mac.settings.speedValue", language: language), locale: language.locale, SpeedFormat.speed(value))
        }
        let series = AXDataSeriesDescriptor(
            name: valueTitle,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) }
        )
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

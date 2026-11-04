import AgentSpeedCore
import Charts
import SwiftUI

/// The chart card: title and legend over one bar per day with the average-speed line (DESIGN 4b, item 3).
struct HistoryChartCard: View {
    let model: HistoryViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let chart = model.content.chart
        let l10n = model.l10n
        VStack(alignment: .leading, spacing: Spacing.s) {
            ChartLegend(chart: chart, l10n: l10n, dark: colorScheme == .dark, increasedContrast: contrast == .increased,
                        metric: Binding(get: { model.chartMetric }, set: { model.select(metric: $0) }),
                        metrics: model.offersTraffic ? HistoryChartMetric.allCases : [.output, .cost],
                        trafficTotal: model.content.trafficTotal.map { TrafficText(l10n: l10n, bits: false).pair($0) })
            HistoryChartView(
                chart: chart,
                interaction: model.interaction,
                l10n: l10n,
                motion: model.motion,
                reduceMotion: model.accessibility.reduceMotion
            )
            .frame(height: HistoryLayout.chartHeight)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, 14)
        .padding(.bottom, Spacing.s)
        .historyCard()
    }
}

/// The metric control (`每日輸出` | `費用`, DESIGN 9) with the source swatches in stacking order, and the speed line key on
/// the right (output only). When the swatches do not fit on the title line they wrap onto their own lines below it.
private struct ChartLegend: View {
    let chart: HistoryChartModel
    let l10n: Localizer
    let dark: Bool
    let increasedContrast: Bool
    @Binding var metric: HistoryChartMetric
    var metrics: [HistoryChartMetric] = HistoryChartMetric.allCases
    /// The range's traffic total (`traffic.pair`) on the right of the traffic chart's header.
    var trafficTotal: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                title
                swatches
                    .fixedSize()
                Spacer(minLength: Spacing.s)
                speedKey
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    title
                    Spacer(minLength: Spacing.s)
                    speedKey
                }
                if !chart.isSingleSource {
                    FlowLayout(spacing: Spacing.s, lineSpacing: 6) {
                        swatchItems
                    }
                    .font(HistoryFont.legend)
                    .foregroundStyle(.historySecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Picker(l10n(chart.metric.titleKey), selection: $metric) {
            ForEach(metrics) { metric in
                Text(l10n(metric.titleKey)).tag(metric)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(l10n(chart.metric.titleKey))
    }

    @ViewBuilder
    private var swatches: some View {
        if !chart.isSingleSource {
            HStack(spacing: Spacing.s) {
                swatchItems
            }
            .font(HistoryFont.legend)
            .foregroundStyle(.historySecondary)
        }
    }

    private var swatchItems: some View {
        ForEach(chart.stack, id: \.self) { source in
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(source.tint(dark: dark))
                    .frame(width: 8, height: 8)
                Text(l10n(source.titleKey))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var speedKey: some View {
        if chart.metric == .output {
            speedLineKey
        } else if chart.metric == .traffic, let trafficTotal {
            Text(trafficTotal)
                .font(HistoryFont.legend.monospacedDigit())
                .foregroundStyle(.historySecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var speedLineKey: some View {
        HStack(spacing: 6) {
            ZStack {
                Capsule()
                    .fill(HistoryPalette.ink(dark: dark, increasedContrast: increasedContrast))
                    .frame(width: 16, height: 1.5)
                Circle()
                    .fill(HistoryPalette.ink(dark: dark, increasedContrast: increasedContrast))
                    .frame(width: 5, height: 5)
            }
            Text("\(l10n("history.chart.speed")) (\(l10n("unit.tokS")))")
                .lineLimit(1)
                .fixedSize()
        }
        .font(HistoryFont.legend)
        .foregroundStyle(.historySecondary)
    }
}

/// Places its children left to right and wraps onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// The plot. Marks only depend on the chart model, so hovering never re-renders them: the crosshair, hover band,
/// tooltip and today's hatching live in overlay layers that read the interaction state.
struct HistoryChartView: View {
    let chart: HistoryChartModel
    let interaction: HistoryInteraction
    let l10n: Localizer
    let motion: Animation?
    let reduceMotion: Bool

    @State private var plotWidth: CGFloat = 640
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    static let monthLabelSpace: CGFloat = 18

    var body: some View {
        let dark = colorScheme == .dark
        let increasedContrast = contrast == .increased
        let geometry = ChartDayGeometry(chart: chart, plotWidth: plotWidth)
        // Bars spring to their new heights; under Reduce Motion the whole plot crossfades instead.
        let identity = reduceMotion ? "\(chart.range.start)-\(chart.range.end)-\(chart.stack.map(\.rawValue))" : "chart"
        ZStack {
            plot(geometry: geometry, dark: dark, increasedContrast: increasedContrast)
                .id(identity)
                .transition(.opacity)
                .animation(reduceMotion ? nil : motion, value: chart)
        }
        .animation(reduceMotion ? HistoryMotion.fade : nil, value: identity)
        .background {
            // Outside both animations: the measured width never follows the axes while they spring.
            ChartPlotWidthReader(chart: chart) { width in
                if abs(width - plotWidth) > 0.5 { plotWidth = width }
            }
        }
        .padding(.top, Self.monthLabelSpace)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.55 : 0), lineWidth: 2)
                .padding(-6)
                .animation(HistoryMotion.fade, value: focused)
                .allowsHitTesting(false)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                interaction.keyboardDay = interaction.hoveredDay ?? chart.days.keys.max() ?? chart.today
            } else {
                interaction.keyboardDay = nil
            }
        }
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.home) { jump(to: chart.range.start) }
        .onKeyPress(.end) { jump(to: chart.range.end) }
        .onKeyPress(.return) { revealKeyboardDay() }
        .onKeyPress(.space) { revealKeyboardDay() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n(chart.metric.titleKey))
        .accessibilityHint(l10n("mac.history.chart.hint"))
        .accessibilityChartDescriptor(HistoryChartDescriptor(chart: chart, l10n: l10n))
        .accessibilityChildren {
            if chart.metric == .traffic {
                // Each day with traffic, read as its traffic (DESIGN 10, Accessibility), as on Windows.
                ForEach(chart.traffic.filter { !$0.value.shown.isZero || !($0.value.machine ?? .zero).isZero }.keys.sorted(), id: \.self) { day in
                    Rectangle()
                        .accessibilityLabel(HistoryText.dayTitle(day, today: chart.today, l10n))
                        .accessibilityValue(HistoryText.accessibleTraffic(day, traffic: chart.traffic[day], today: chart.today, l10n))
                        .accessibilityAction { interaction.revealInTable(day) }
                }
            } else {
                ForEach(chart.days.values.sorted { $0.day < $1.day }) { day in
                    Rectangle()
                        .accessibilityLabel(HistoryText.dayTitle(day.day, today: chart.today, l10n))
                        .accessibilityValue(HistoryText.accessible(day, today: chart.today, money: chart.money, l10n))
                        .accessibilityAction { interaction.revealInTable(day.day) }
                }
            }
        }
    }

    private func plot(geometry: ChartDayGeometry, dark: Bool, increasedContrast: Bool) -> some View {
        let calendar = HistoryDates.calendar
        let ink = HistoryPalette.ink(dark: dark, increasedContrast: increasedContrast)
        let grid = HistoryPalette.grid(dark: dark, increasedContrast: increasedContrast)
        let showsDots = geometry.slot >= 7
        let barWidth = geometry.barWidth
        let speeds = chart.speeds
        let marks = geometry.marks(weekStart: calendar.firstWeekday)
        let bars = chart.segments.map { segment in
            // Every segment is rounded; an inner one reaches just under the next one out so its rounded corners never
            // leave a notch in the stack. Upload (traffic) stacks downward in the same colors at 55 %.
            let overlap = geometry.overlap(below: segment.above)
            return ChartBar(
                id: segment.id + (segment.upload ? "/up" : ""),
                date: segment.day.date(in: calendar),
                lower: segment.upload ? segment.lower : segment.lower,
                upper: segment.upload ? segment.upper : segment.upper + overlap,
                extendDown: segment.upload ? overlap : 0,
                style: AnyShapeStyle(barStyle(segment.source, dark: dark)
                    .opacity((segment.day == chart.today ? 0.5 : 1) * (segment.upload ? 0.55 : 1)))
            )
        }
        var line: [ChartPoint] = []
        var dots: [ChartPoint] = []
        for (run, indices) in chart.speedRuns.enumerated() {
            for index in indices {
                let point = ChartPoint(
                    index: index,
                    date: chart.range.day(at: index).date(in: calendar),
                    value: chart.scaledSpeed(speeds[index] ?? 0),
                    run: run
                )
                line.append(point)
                if showsDots || indices.count == 1 { dots.append(point) }
            }
        }
        return Chart {
            ChartBarsContent(bars: bars, width: barWidth, radius: geometry.cornerRadius)
            ChartLineContent(points: line, color: ink)
            ChartDotsContent(points: dots, color: ink)
        }
        .modifier(HistoryChartAxes(chart: chart, grid: grid))
        .chartBackground { proxy in
            GeometryReader { reader in
                ChartBackdrop(chart: chart, interaction: interaction, proxy: proxy, frame: reader[proxy.plotFrame!],
                              geometry: geometry, marks: marks, l10n: l10n, dark: dark, increasedContrast: increasedContrast)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { reader in
                let frame = reader[proxy.plotFrame!]
                ChartPointerLayer(
                    chart: chart, interaction: interaction, proxy: proxy, frame: frame, geometry: geometry, l10n: l10n,
                    dark: dark, increasedContrast: increasedContrast, reduceMotion: reduceMotion
                )
            }
        }
    }

    private func barStyle(_ source: SourceKind, dark: Bool) -> AnyShapeStyle {
        let tint = source.tint(dark: dark)
        guard chart.isSingleSource else { return AnyShapeStyle(tint) }
        return AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .top, endPoint: .bottom))
    }

    private func move(by delta: Int) -> KeyPress.Result {
        let current = interaction.keyboardDay ?? chart.days.keys.max() ?? chart.today
        let next = current.adding(days: delta).clamped(to: chart.range.start...chart.range.end)
        interaction.keyboardDay = next
        return .handled
    }

    private func jump(to day: DayKey) -> KeyPress.Result {
        interaction.keyboardDay = day
        return .handled
    }

    private func revealKeyboardDay() -> KeyPress.Result {
        guard let day = interaction.keyboardDay, chart.days[day] != nil else { return .ignored }
        interaction.revealInTable(day)
        return .handled
    }
}

/// The plot's scales and axes, shared by the plot and the copy its width is measured on.
private struct HistoryChartAxes: ViewModifier {
    let chart: HistoryChartModel
    let grid: Color

    func body(content: Content) -> some View {
        let calendar = HistoryDates.calendar
        let domainStart = chart.range.start.date(in: calendar)
        let domainEnd = chart.range.end.adding(days: 1).date(in: calendar)
        content
            .chartXScale(domain: domainStart...domainEnd)
            .chartYScale(domain: chart.yDomain)
            .chartLegend(.hidden)
            .chartXAxis {
                // The day labels are drawn by the backdrop, centred under their bars (label anchors behave differently
                // across SDKs); this only keeps their row free.
                AxisMarks(values: [domainStart]) { _ in
                    AxisValueLabel { Text(verbatim: "0").font(HistoryFont.axis).hidden() }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: chart.axisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(grid)
                    AxisValueLabel {
                        if let output = value.as(Double.self) {
                            Text(chart.leadingAxisLabel(output))
                                .font(HistoryFont.axis)
                                .foregroundStyle(.historySecondary)
                        }
                    }
                }
                // The cost metric has no speed line, so no right axis (DESIGN 9).
                AxisMarks(position: .trailing, values: chart.metric == .output ? chart.outputTicks.values : []) { value in
                    AxisValueLabel {
                        if let output = value.as(Double.self) {
                            Text(chart.trailingAxisLabel(output))
                                .font(HistoryFont.axis)
                                .foregroundStyle(.historySecondary)
                        }
                    }
                }
            }
    }
}

/// The width the marks are sized for, measured on a copy of the plot with the same size, scales and axes but no marks
/// and no animation (macOS issue #28). The plot's width follows only those; measured on the plot itself, it would also
/// follow every frame of the axes' spring and could answer the marks it sizes, writing state on every layout pass.
private struct ChartPlotWidthReader: View {
    let chart: HistoryChartModel
    let onChange: (CGFloat) -> Void

    var body: some View {
        Chart { ChartBarsContent(bars: [], width: 0, radius: 0) }
            .modifier(HistoryChartAxes(chart: chart, grid: .clear))
            .chartOverlay { proxy in
                GeometryReader { reader in
                    let width = reader[proxy.plotFrame!].width
                    Color.clear
                        .onGeometryChange(for: CGFloat.self) { _ in width } action: { onChange($0) }
                }
            }
            .transaction { $0.animation = nil }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Horizontal geometry of one bar per day inside the plot.
struct ChartDayGeometry {
    let chart: HistoryChartModel
    let plotWidth: CGFloat

    var slot: CGFloat { chart.range.count > 0 ? plotWidth / CGFloat(chart.range.count) : 0 }

    var barWidth: CGFloat {
        let slot = slot
        guard slot > 0 else { return 1 }
        var bar = slot * 0.7
        if slot >= 3 { bar = min(bar, slot - 1) } else { bar = slot }
        return bar.clamped(to: min(slot, 1)...28)
    }

    var cornerRadius: CGFloat { min(4, barWidth / 3) }

    /// How far a segment reaches under the next one: enough to fill its rounded corners, never past its top.
    func overlap(below above: Double) -> Double {
        guard above > 0 else { return 0 }
        let perPoint = chart.outputTicks.max / Double(HistoryLayout.chartHeight)
        return min(Double(cornerRadius + 0.5) * perPoint, above)
    }

    func centerX(_ day: DayKey) -> CGFloat {
        (CGFloat(chart.range.index(of: day)) + 0.5) * slot
    }

    func index(atX x: CGFloat) -> Int {
        guard slot > 0 else { return 0 }
        return Int(floor(x / slot)).clamped(to: 0...max(chart.range.count - 1, 0))
    }

    func marks(weekStart: Int) -> ChartAxisMarks {
        HistoryChartMath.marks(chart.range, slot: Double(slot), weekStart: weekStart, minSpacing: 48)
    }
}

private struct ChartBar: Identifiable {
    let id: String
    let date: Date
    let lower: Double
    let upper: Double
    /// An upload segment reaches this far past its lower end, under the next one out.
    var extendDown: Double = 0
    let style: AnyShapeStyle
}

private struct ChartPoint: Identifiable {
    var id: Int { index }
    let index: Int
    let date: Date
    let value: Double
    let run: Int
}

private struct ChartBarsContent: ChartContent {
    let bars: [ChartBar]
    let width: CGFloat
    let radius: CGFloat

    var body: some ChartContent {
        ForEach(bars) { bar in
            BarMark(
                x: .value("Day", bar.date, unit: .day),
                yStart: .value("Output", bar.lower - bar.extendDown),
                yEnd: .value("Output", bar.upper),
                width: .fixed(width)
            )
            .foregroundStyle(bar.style)
            .cornerRadius(radius)
            .accessibilityHidden(true)
        }
    }
}

/// The average-speed line; each run of measured days is its own series, so unmeasured days break it.
private struct ChartLineContent: ChartContent {
    let points: [ChartPoint]
    let color: Color

    var body: some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Speed", point.value),
                series: .value("Run", point.run)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
            .accessibilityHidden(true)
        }
    }
}

private struct ChartDotsContent: ChartContent {
    let points: [ChartPoint]
    let color: Color

    var body: some ChartContent {
        ForEach(points) { point in
            PointMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Speed", point.value)
            )
            .symbol {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
            }
            .accessibilityHidden(true)
        }
    }
}

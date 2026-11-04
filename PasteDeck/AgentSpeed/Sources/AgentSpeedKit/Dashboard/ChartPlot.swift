import AgentSpeedCore
import SwiftUI

/// Appearance inputs of the chart, resolved once per render.
struct ChartStyle: Equatable {
    var redline: Double
    var isDark: Bool
    var increasedContrast: Bool

    var lineWidth: CGFloat { increasedContrast ? 2 : 1.5 }

    /// Vertical heat ramp: the color at height y is the heat of the value y stands for.
    func gradient(domain: Double, graphic: Bool, alpha: (Double) -> Double) -> Gradient {
        let count = 12
        let stops = (0...count).map { index in
            let fraction = Double(index) / Double(count)
            let heat = HeatPalette.heat(value: fraction * domain, redline: redline)
            let color = graphic
                ? DashboardPalette.heatGraphic(heat, dark: isDark, increasedContrast: increasedContrast)
                : HeatPalette.color(heat)
            return Gradient.Stop(color: color.opacity(alpha(fraction)).color, location: fraction)
        }
        return Gradient(stops: stops)
    }

    /// Fades to nothing at the baseline so the slate end of the ramp never muddies the fill.
    func fillAlpha(_ fraction: Double) -> Double {
        let ramp = pow(fraction, 1.35)
        return isDark ? 0.01 + 0.44 * ramp : 0.02 + 0.34 * ramp
    }

    func heatColor(of value: Double) -> RGBColor {
        DashboardPalette.heatGraphic(HeatPalette.heat(value: value, redline: redline), dark: isDark, increasedContrast: increasedContrast)
    }
}

/// The live area chart. Animatable in its y-domain so rescales glide instead of jumping.
struct ChartPlot: View, Animatable {
    var series: ChartSeries
    var domain: Double
    var peak: Double
    var peakLabel: String
    /// A small unit caption under the top axis value, while the hero shows money instead of token speed.
    var axisUnit: String?
    var style: ChartStyle

    nonisolated var animatableData: Double {
        get { domain }
        set { domain = newValue }
    }

    var body: some View {
        Canvas { context, size in
            render(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func render(in context: inout GraphicsContext, size: CGSize) {
        let geometry = ChartGeometry(size: size, start: series.start, end: series.end, domain: domain)
        let floor = geometry.baseline
        let bottom = CGPoint(x: 0, y: floor)
        let top = CGPoint(x: 0, y: geometry.plotTop)
        let rule = DashboardPalette.rule(dark: style.isDark, increasedContrast: style.increasedContrast)

        drawGrid(in: &context, geometry: geometry, rule: rule)

        var plot = context
        plot.clip(to: Path(CGRect(x: 0, y: 0, width: geometry.plotWidth, height: size.height)))

        let samples = series.samples
        if !samples.isEmpty {
            let measured = geometry.points(samples) { $0.measured }
            let totals = geometry.points(samples) { $0.total }
            let fill = style.gradient(domain: domain, graphic: false, alpha: style.fillAlpha)

            plot.fill(ChartPath.area(measured, floor: floor), with: .linearGradient(fill, startPoint: bottom, endPoint: top))
            let line = style.gradient(domain: domain, graphic: true) { _ in 1 }
            if series.hasEstimate {
                let bandPath = ChartPath.band(upper: totals, lower: measured, floor: floor)
                var band = plot
                band.opacity = 0.45
                band.fill(bandPath, with: .linearGradient(fill, startPoint: bottom, endPoint: top))
                let first = series.estimatedRuns.first.map { max($0.lowerBound - 1, 0) } ?? 0
                let last = series.estimatedRuns.last?.upperBound ?? samples.count - 1
                drawHatch(
                    in: plot,
                    clippedTo: bandPath,
                    span: geometry.x(samples[first].time)...geometry.x(samples[last].time),
                    geometry: geometry,
                    shading: .linearGradient(line, startPoint: bottom, endPoint: top)
                )
            }

            drawPeak(in: &plot, geometry: geometry)

            let stroke = GraphicsContext.Shading.linearGradient(line, startPoint: bottom, endPoint: top)
            let solid = StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)
            var dashed = solid
            dashed.dash = [3.5, 2.5]
            for segment in Self.lineSegments(count: samples.count, estimatedRuns: series.estimatedRuns) {
                plot.stroke(
                    ChartPath.line(totals, over: segment.range, floor: floor),
                    with: stroke,
                    style: segment.estimated ? dashed : solid
                )
            }
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: floor))
        baseline.addLine(to: CGPoint(x: geometry.plotWidth, y: floor))
        context.stroke(baseline, with: .color(rule), lineWidth: 1)

        drawPeakLabel(in: &context, geometry: geometry)

        if let live = series.live {
            drawNow(in: &context, at: CGPoint(x: geometry.x(live.time), y: geometry.y(live.total)), value: live.total)
        }
    }

    /// Axis values are always round numbers; drop the decimal SpeedFormat keeps for small live readings.
    static func axisLabel(_ value: Double) -> String {
        guard value >= 1000 else {
            return value.rounded() == value ? String(Int(value)) : SpeedFormat.speed(value)
        }
        let thousands = (value / 100).rounded() / 10
        return thousands.rounded() == thousands ? "\(Int(thousands))k" : String(format: "%.1fk", locale: Locale(identifier: "en_US_POSIX"), thousands)
    }

    /// The top line follows the total: solid where measured, dashed across in-flight estimates.
    static func lineSegments(count: Int, estimatedRuns: [ClosedRange<Int>]) -> [(range: ClosedRange<Int>, estimated: Bool)] {
        guard count > 1 else { return [] }
        var segments: [(range: ClosedRange<Int>, estimated: Bool)] = []
        var cursor = 0
        for run in estimatedRuns {
            let lower = max(run.lowerBound - 1, 0)
            let upper = min(run.upperBound, count - 1)
            guard upper > lower else { continue }
            if lower > cursor { segments.append((cursor...lower, false)) }
            segments.append((max(lower, cursor)...upper, true))
            cursor = upper
        }
        if cursor < count - 1 { segments.append((cursor...(count - 1), false)) }
        return segments
    }

    /// Fine diagonal hatching marks the in-flight estimate as provisional rather than missing.
    private func drawHatch(
        in context: GraphicsContext,
        clippedTo region: Path,
        span: ClosedRange<CGFloat>,
        geometry: ChartGeometry,
        shading: GraphicsContext.Shading
    ) {
        var hatch = context
        hatch.clip(to: region)
        hatch.opacity = style.isDark ? 0.22 : 0.2
        let height = geometry.size.height
        var lines = Path()
        // Only the stripes that can cross the band; aligned to a fixed grid so they never crawl as data scrolls.
        var x = ((span.lowerBound - height) / 5).rounded(.down) * 5
        while x < min(span.upperBound, geometry.plotWidth) {
            lines.move(to: CGPoint(x: x, y: height))
            lines.addLine(to: CGPoint(x: x + height, y: 0))
            x += 5
        }
        hatch.stroke(lines, with: shading, lineWidth: 0.75)
    }

    private func drawGrid(in context: inout GraphicsContext, geometry: ChartGeometry, rule: Color) {
        let secondary = DashboardPalette.secondary(dark: style.isDark, increasedContrast: style.increasedContrast)
        for value in [domain, domain / 2] {
            let y = geometry.y(value)
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: geometry.plotWidth, y: y))
            context.stroke(grid, with: .color(rule), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            let label = Text(Self.axisLabel(value))
                .font(DashboardFont.chartLabel)
                .foregroundStyle(secondary)
            context.draw(label, at: CGPoint(x: geometry.size.width, y: y), anchor: .trailing)
        }
        if let axisUnit {
            let caption = Text(axisUnit)
                .font(DashboardFont.chartUnit)
                .foregroundStyle(secondary.opacity(0.75))
            context.draw(caption, at: CGPoint(x: geometry.size.width, y: geometry.y(domain) + 11), anchor: .trailing)
        }
    }

    private func drawPeak(in context: inout GraphicsContext, geometry: ChartGeometry) {
        guard peak > 0, peak <= domain * 1.001 else { return }
        let y = geometry.y(peak)
        let heat = HeatPalette.heat(value: peak, redline: style.redline)
        let color = DashboardPalette.heatGraphic(heat, dark: style.isDark, increasedContrast: style.increasedContrast)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: geometry.plotWidth, y: y))
        context.stroke(line, with: .color(color.opacity(0.75).color), style: StrokeStyle(lineWidth: 1, dash: [7, 4]))
    }

    private func drawPeakLabel(in context: inout GraphicsContext, geometry: ChartGeometry) {
        guard peak > 0, peak <= domain * 1.001 else { return }
        let y = geometry.y(peak)
        let heat = HeatPalette.heat(value: peak, redline: style.redline)
        let color = DashboardPalette.heatGraphic(heat, dark: style.isDark, increasedContrast: style.increasedContrast)
        let text = context.resolve(
            Text(peakLabel)
                .font(DashboardFont.chartLabel)
                .foregroundStyle(DashboardPalette.heatText(heat, dark: style.isDark, increasedContrast: style.increasedContrast))
        )
        let textSize = text.measure(in: CGSize(width: geometry.plotWidth, height: 20))
        let pill = CGSize(width: textSize.width + 10, height: textSize.height + 3)
        let above = y - pill.height - 2 >= 0
        let origin = CGPoint(x: 4, y: above ? y - pill.height - 2 : y + 2)
        let shape = Path(roundedRect: CGRect(origin: origin, size: pill), cornerRadius: pill.height / 2, style: .continuous)
        context.fill(shape, with: .style(.background.opacity(0.92)))
        context.stroke(shape, with: .color(color.opacity(0.35).color), lineWidth: 0.75)
        context.draw(text, at: CGPoint(x: origin.x + pill.width / 2, y: origin.y + pill.height / 2), anchor: .center)
    }

    private func drawNow(in context: inout GraphicsContext, at point: CGPoint, value: Double) {
        let color = style.heatColor(of: value).color
        let halo = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.22)))
        let dot = CGRect(x: point.x - 2.75, y: point.y - 2.75, width: 5.5, height: 5.5)
        context.fill(Path(ellipseIn: dot), with: .color(color))
    }
}

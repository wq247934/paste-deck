import AgentSpeedCore
import SwiftUI

/// Hover / drag inspection layer above the plot. Owns the pointer state so tracking never redraws the plot.
struct ChartCrosshair: View, Animatable {
    var series: ChartSeries
    var domain: Double
    var style: ChartStyle
    var labels: Labels

    struct Labels {
        var locale: Locale
        var now: String
        var estimated: String
        var speed: (String) -> String
    }

    @State private var location: CGPoint?
    @Environment(\.displayScale) private var displayScale

    nonisolated var animatableData: Double {
        get { domain }
        set { domain = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = ChartGeometry(size: proxy.size, start: series.start, end: series.end, domain: domain)
            ZStack(alignment: .topLeading) {
                Color.clear
                if let location, let index = series.nearestIndex(to: geometry.time(atX: location.x)) {
                    marker(for: series.samples[index], geometry: geometry)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): location = point
                case .ended: location = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { location = $0.location }
            )
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func marker(for sample: ChartSample, geometry: ChartGeometry) -> some View {
        let x = geometry.x(sample.time)
        let y = geometry.y(sample.total)
        let color = style.heatColor(of: sample.total).color
        let width = geometry.size.width
        let height = geometry.size.height
        let bubbleBelow = y < 34

        Rectangle()
            .fill(DashboardPalette.secondary(dark: style.isDark, increasedContrast: style.increasedContrast).opacity(0.55))
            .frame(width: 1 / max(displayScale, 1), height: height)
            .offset(x: x)

        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            .frame(width: 7, height: 7)
            .offset(x: x - 3.5, y: y - 3.5)

        bubble(for: sample)
            .alignmentGuide(.leading) { dimensions in
                let left = (x - dimensions.width / 2).clamped(to: 0...max(0, width - dimensions.width))
                return -left
            }
            .alignmentGuide(.top) { dimensions in
                bubbleBelow ? -(height - dimensions.height) : 0
            }
    }

    private func bubble(for sample: ChartSample) -> some View {
        let time = sample.isLive
            ? labels.now
            : Date(timeIntervalSince1970: sample.time.rounded(.down))
                .formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(labels.locale))
        return HStack(spacing: 6) {
            Text(time)
                .foregroundStyle(.dashboardSecondary)
            Text(labels.speed(SpeedFormat.speed(sample.total)))
                .fontWeight(.semibold)
            if sample.estimated > max(0.05, sample.total * 0.02) {
                Text(labels.estimated)
                    .foregroundStyle(.dashboardSecondary)
            }
        }
        .font(DashboardFont.caption)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(style.isDark ? 0.4 : 0.14), radius: 3, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }
}

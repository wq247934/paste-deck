import AgentSpeedCore
import SwiftUI

/// The menu bar dashboard (DESIGN section 4): hero, live chart, sources, agents, today and footer.
public struct DashboardView: View {
    public let model: AgentSpeedModel
    /// Tallest the popover may be on its screen; beyond it the sections under the hero scroll.
    public var maxHeight: CGFloat?
    /// 宿主嵌入（PasteDeck 工具窗口）时隐藏退出按钮。
    public var embedded = false

    public init(model: AgentSpeedModel, maxHeight: CGFloat?, embedded: Bool = false) {
        self.model = model
        self.maxHeight = maxHeight
        self.embedded = embedded
    }

    private static let topPadding = DashboardLayout.padding
    private static let bottomPadding = Spacing.s

    public var body: some View {
        DashboardColumn(maxHeight: maxHeight.map { $0 - Self.topPadding - Self.bottomPadding }) {
            if model.isPreviewing {
                PreviewBanner(model: model)
                    .padding(.bottom, DashboardLayout.sectionSpacing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            DashboardContent(model: model)
                .dashboardFlexible()
            Hairline()
                .padding(.top, DashboardLayout.sectionSpacing)
                .padding(.bottom, Spacing.xs)
            DashboardFooter(model: model, showsQuit: !embedded)
                .padding(.trailing, -6)
        }
        .padding(.horizontal, DashboardLayout.padding)
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .frame(width: DashboardController.width, alignment: .top)
        .animation(model.dashboardMotion, value: model.isPreviewing)
    }
}

/// Switches between startup, missing-sources and live layouts.
private struct DashboardContent: View {
    let model: AgentSpeedModel

    public var body: some View {
        Group {
            switch model.snapshot.state {
            case .starting(let progress):
                LoadingState(model: model, progress: progress)
                    .transition(.opacity)
            case .noSources:
                NoSourcesState(model: model)
                    .transition(.opacity)
            case .running:
                DashboardSections(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: StateKind(model.snapshot.state))
    }

    private enum StateKind: Equatable {
        case starting, noSources, running

        init(_ state: MonitorState) {
            switch state {
            case .starting: self = .starting
            case .noSources: self = .noSources
            case .running: self = .running
            }
        }
    }
}

private struct DashboardSections: View {
    let model: AgentSpeedModel

    @State private var contentFrame: CGRect = .zero

    private nonisolated static let space = "dashboardDetails"

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroSection(model: model)
            SectionDivider()
            ScrollView(.vertical) {
                DashboardDetails(model: model)
                    .padding(.horizontal, DashboardLayout.padding)
                    .onGeometryChange(for: CGRect.self, of: Self.overflowingFrame) { contentFrame = $0 }
            }
            .coordinateSpace(.named(Self.space))
            // A legacy system scroller would take width and shift the columns away from the hero; the knob floats.
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .overlay { OverlayScrollIndicator(content: contentFrame) }
            .padding(.horizontal, -DashboardLayout.padding)
        }
    }

    /// The content's frame while it overflows, else zero, so a layout that animates within the screen does not
    /// update this view on every frame.
    private nonisolated static func overflowingFrame(_ proxy: GeometryProxy) -> CGRect {
        let frame = proxy.frame(in: .named(space))
        guard let viewport = proxy.bounds(of: .named(space)), frame.height > viewport.height + 0.5 else { return .zero }
        return frame
    }
}

/// Everything under the hero; the part that scrolls on short screens.
private struct DashboardDetails: View {
    let model: AgentSpeedModel

    public var body: some View {
        let warnings = model.snapshot.warnings
        VStack(alignment: .leading, spacing: 0) {
            LiveChartSection(model: model)
            SectionDivider()
            SourcesSection(model: model)
            SectionDivider()
            AgentsSection(model: model)
            SectionDivider()
            TodaySection(model: model)
            if model.settings.trafficEnabled {
                SectionDivider()
                TrafficSection(model: model)
                    .transition(.opacity)
            }
            if !warnings.isEmpty {
                WarningsFootnote(model: model, warnings: warnings)
                    .padding(.top, DashboardLayout.sectionSpacing)
                    .transition(.opacity)
            }
        }
        .animation(model.dashboardMotion, value: warnings.isEmpty)
        .animation(model.dashboardMotion, value: model.settings.trafficEnabled)
    }
}

//
//  WorkbenchSidebarView.swift
//  PasteDeck
//
//  Native macOS sidebar navigation for PasteDeck 2.0 workbench.
//

import SwiftUI

struct WorkbenchSidebarView: View {
    @Binding var selectedDestination: WorkbenchDestination
    let historyCount: Int
    let favoritesCount: Int
    let categoryCounts: [ClipboardContentType: Int]
    let onOpenSettings: () -> Void

    @Environment(\.workbenchReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var hoveredDestination: WorkbenchDestination?

    // MARK: Sliding Capsule State

    @State private var rowFrames: [WorkbenchDestination: CGRect] = [:]
    @State private var pillFrame: CGRect?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()
                .overlay(Color.primary.opacity(0.06))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            // Navigation items list
            //
            // The capsule and the rows must share ONE coordinate space, otherwise
            // the capsule never lines up with the selected row. Both live inside
            // the ScrollView's ZStack; rows report their anchors in that same
            // local space via a named coordinate space declared on the ZStack.
            ScrollView {
                ZStack(alignment: .topLeading) {
                    if pillFrame != nil {
                        selectionCapsule
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // Main navigation group
                        sidebarItem(
                            destination: .history,
                            badgeCount: historyCount
                        )

                        sidebarItem(
                            destination: .favorites,
                            badgeCount: favoritesCount
                        )

                        sidebarItem(
                            destination: .toolCenter,
                            badgeCount: nil
                        )

                        sidebarItem(
                            destination: .recentTools,
                            badgeCount: nil
                        )

                        // Smart group section
                        sectionHeader("智能分组")
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        sidebarItem(
                            destination: .smartCategory(.text),
                            badgeCount: categoryCounts[.text] ?? 0
                        )

                        sidebarItem(
                            destination: .smartCategory(.link),
                            badgeCount: categoryCounts[.link] ?? 0
                        )

                        sidebarItem(
                            destination: .smartCategory(.image),
                            badgeCount: categoryCounts[.image] ?? 0
                        )

                        sidebarItem(
                            destination: .smartCategory(.file),
                            badgeCount: categoryCounts[.file] ?? 0
                        )

                        sidebarItem(
                            destination: .smartCategory(.color),
                            badgeCount: categoryCounts[.color] ?? 0
                        )

                        sidebarItem(
                            destination: .smartCategory(.markdown),
                            badgeCount: (categoryCounts[.markdown] ?? 0) + (categoryCounts[.json] ?? 0)
                        )
                    }
                    .padding(.horizontal, 8)
                }
                .coordinateSpace(name: Self.frameSpace)
            }
            .scrollIndicators(.hidden)
            .onPreferenceChange(WorkbenchSidebarRowFramesKey.self) { frames in
                rowFrames = frames
                if pillFrame == nil, let initial = frames[selectedDestination] {
                    pillFrame = initial
                }
            }
            .onChange(of: selectedDestination) { _, newDest in
                guard let target = rowFrames[newDest] else { return }
                guard target != pillFrame else { return }
                if reduceMotion {
                    pillFrame = target
                } else {
                    withAnimation(WorkbenchMotion.pillSpring) {
                        pillFrame = target
                    }
                }
            }

            Spacer(minLength: 8)

            Divider()
                .overlay(Color.primary.opacity(0.06))
                .padding(.horizontal, 12)

            // Bottom settings button
            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Text("设置")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredDestination == nil ? Color.clear : Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 190, idealWidth: 205, maxWidth: 220)
        // 侧栏保持通透，让底层环境渐变透上来。
        .background(Color.white.opacity(0.04))
        // 首次定位由 handleRowFramesChange 在收到第一帧偏好时完成并吸附，不播放滑动。
    }

    // MARK: - Selection Capsule

    // MARK: - Selection Capsule

    /// 半透明玻璃胶囊：浅色模式下为柔和纯白半透，深色模式下为暗白半透，
    /// 带有极细内高光与中性柔和阴影，硬件加速平滑滑动。
    private var selectionCapsule: some View {
        let frame = pillFrame ?? .zero
        let isDark = colorScheme == .dark

        return ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.10)
                        ] : [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 外圈微弱描边
            Capsule(style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.06), lineWidth: 1)

            // 内圈极细高光
            Capsule(style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.80), lineWidth: 1)
                .padding(0.5)
        }
        .shadow(
            color: isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.06),
            radius: 6,
            x: 0,
            y: 2
        )
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .animation(reduceMotion ? nil : WorkbenchMotion.pillSpring, value: pillFrame)
        .allowsHitTesting(false)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08))
                    .frame(width: 32, height: 32)

                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("PasteDeck 2.0")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("更智能的剪贴板")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary.opacity(0.8))
            .padding(.horizontal, 12)
    }

    // MARK: - Sidebar Item

    @ViewBuilder
    private func sidebarItem(
        destination: WorkbenchDestination,
        badgeCount: Int?
    ) -> some View {
        let isSelected = selectedDestination == destination
        let isHovered = hoveredDestination == destination

        Button {
            select(destination)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: destination.iconName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.45, blue: 0.08) : (isHovered ? .primary : .secondary))
                    .frame(width: 18)

                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))

                Spacer()

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isSelected ? Color(red: 1.0, green: 0.45, blue: 0.08) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12) : Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Hover only: the selected row's glass capsule is drawn behind all rows.
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isHovered && !isSelected
                            ? Color.primary.opacity(0.05)
                            : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkbenchSidebarRowFramesKey.self,
                    value: [destination: proxy.frame(in: .named(Self.frameSpace)).standardized]
                )
            }
        )
        .onHover { hovering in
            if hovering {
                hoveredDestination = destination
            } else if hoveredDestination == destination {
                hoveredDestination = nil
            }
        }
    }

    /// 点击选中：先定位胶囊目标，再更新绑定值。
    private func select(_ destination: WorkbenchDestination) {
        selectedDestination = destination
    }

    /// 行锚点与胶囊整体的坐标系命名空间。
    static let frameSpace = "PasteDeck.Workbench.Sidebar"
}

// MARK: - Frame Preference Key

/// 汇总各导航行上报的锚点矩形。
private struct WorkbenchSidebarRowFramesKey: PreferenceKey {
    static var defaultValue: [WorkbenchDestination: CGRect] = [:]

    static func reduce(
        value: inout [WorkbenchDestination: CGRect],
        nextValue: () -> [WorkbenchDestination: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

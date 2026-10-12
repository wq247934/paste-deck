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

    @State private var hoveredDestination: WorkbenchDestination?

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
            ScrollView {
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
            .scrollIndicators(.hidden)

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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
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
            selectedDestination = destination
        } label: {
            HStack(spacing: 9) {
                Image(systemName: destination.iconName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
                    .frame(width: 18)

                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(isSelected ? Color.white.opacity(0.9) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 1.0, green: 0.45, blue: 0.08)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredDestination = destination
            } else if hoveredDestination == destination {
                hoveredDestination = nil
            }
        }
    }
}

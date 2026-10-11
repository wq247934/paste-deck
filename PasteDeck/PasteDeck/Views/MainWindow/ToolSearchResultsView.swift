//
//  ToolSearchResultsView.swift
//  PasteDeck
//
//  统一搜索结果中的「工具」分组：展示命中的内置工具，
//  支持鼠标点击与键盘（↑↓ + Enter）选择。剪贴板历史分组仍由
//  VirtualizedCardList 呈现，两者互不依赖。
//

import SwiftUI

struct ToolSearchResultsView: View {
    let results: [ToolSearchService.Result]
    /// 键盘当前高亮的工具下标；nil 表示尚未用键盘选择。
    let highlightedIndex: Int?
    /// 鼠标悬停某一行时同步键盘高亮，保证视觉与 Enter 行为一致。
    let onHoverHighlight: (Int?) -> Void
    /// 打开工具（弹出独立工具窗口）。
    let onOpen: (ToolSearchService.Result) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("工具")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\(results.count) 个")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))

                Spacer()

                Text("↑↓ 选择 · Enter 打开")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            VStack(spacing: 6) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    resultRow(index: index, result: result)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func resultRow(index: Int, result: ToolSearchService.Result) -> some View {
        let isHighlighted = highlightedIndex == index
        let descriptor = result.tool.descriptor

        Button {
            onOpen(result)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: descriptor.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHighlighted ? themeColors.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isHighlighted
                                    ? themeColors.accent.opacity(0.14)
                                    : Color.primary.opacity(0.05)
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(descriptor.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        if result.reason == .contentSuggestion {
                            Text("内容识别")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(themeColors.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(themeColors.accent.opacity(0.12))
                                )
                        }
                    }

                    Text(descriptor.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isHighlighted {
                    HStack(spacing: 3) {
                        Text("打开")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(themeColors.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? themeColors.accent.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHighlighted ? themeColors.accent.opacity(0.45) : Color.primary.opacity(0.05), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHoverHighlight(hovering ? index : nil)
        }
    }
}

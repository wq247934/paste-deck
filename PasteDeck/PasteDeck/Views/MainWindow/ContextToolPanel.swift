//
//  ContextToolPanel.swift
//  PasteDeck
//
//  主面板右侧的上下文工具面板：选中剪贴板卡片时按内容识别自动推荐
//  工具，并内嵌展示该工具的完整界面（与独立工具窗口共用实现）。
//

import SwiftUI

struct ContextToolPanel: View {
    /// 当前选中的卡片快照。
    let snapshot: ClipboardItemSnapshot
    /// 内容识别命中的工具与预填文本；空数组时由父视图隐藏面板。
    let matches: [ContentRecognizer.Match]
    let onClose: () -> Void

    @Environment(\.themeColors) private var themeColors

    private var activeMatch: ContentRecognizer.Match? {
        matches.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.primary.opacity(0.08))

            if let match = activeMatch {
                toolContent(match)
            } else {
                noToolHint
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(themeColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 2)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeColors.accent)

            Text("智能工具")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text("随选中内容自动切换")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("关闭智能工具面板")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 工具内容

    private func toolContent(_ match: ContentRecognizer.Match) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: match.tool.descriptor.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeColors.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(themeColors.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(match.tool.descriptor.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(match.tool.descriptor.summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            match.tool.makeContentView(
                context: .forContextCard(snapshot, prefilledText: match.prefilledText)
            )
        }
    }

    // MARK: - 无匹配提示

    private var noToolHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.6))
            Text("该内容暂无匹配工具")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

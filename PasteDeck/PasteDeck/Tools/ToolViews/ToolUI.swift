//
//  ToolUI.swift
//  PasteDeck
//
//  工具窗口与上下文面板共用的小型 UI 组件：结果行、复制按钮、区块标题。
//  复制只写 NSPasteboard，绝不触发 PasteService 的模拟粘贴。
//

import AppKit
import SwiftUI

/// 一行「标签 + 等宽值 + 复制按钮」的工具结果。
struct ToolResultRow: View {
    let label: String
    let value: String
    /// 值使用的字体设计；数字类结果用等宽更易读。
    var monospaced: Bool = true

    @State private var showsCopiedFeedback = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(minWidth: 92, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 6)

            copyButton
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            ToolClipboard.copy(value)
            showsCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showsCopiedFeedback = false
            }
        } label: {
            Image(systemName: showsCopiedFeedback ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showsCopiedFeedback ? .green : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help("复制 \(label)")
    }
}

/// 工具内容的小节标题。
struct ToolSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
    }
}

/// 工具内容的统一卡片容器。
struct ToolCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// 工具结果的复制目标。只写入系统剪贴板，让 ClipboardMonitor 按正常
/// 剪贴板变化记录；不调用 PasteService，避免触发模拟粘贴。
enum ToolClipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

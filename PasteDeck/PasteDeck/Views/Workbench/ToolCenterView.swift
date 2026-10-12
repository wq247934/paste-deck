//
//  ToolCenterView.swift
//  PasteDeck
//
//  Tool Center view in PasteDeck 2.0 workbench, dynamically discovering
//  and presenting tools registered in ToolRegistry.
//

import SwiftUI

struct ToolCenterView: View {
    let onOpenTool: (BuiltinTool) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("工具中心")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text("效率工具箱：开箱即用，支持快捷换算、网络分析与额度监控")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Tool Cards Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ToolRegistry.allTools, id: \.id) { descriptor in
                        if let builtin = ToolRegistry.tool(withID: descriptor.id) {
                            toolCard(descriptor: descriptor, tool: builtin)
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func toolCard(descriptor: ToolDescriptor, tool: BuiltinTool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: descriptor.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(toolCategoryName(tool))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text(descriptor.summary)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)

            // Keywords chips
            HStack(spacing: 6) {
                ForEach(descriptor.keywords.prefix(4), id: \.self) { kw in
                    Text(kw)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
                Spacer()
            }

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Action footer
            HStack {
                Spacer()
                Button {
                    onOpenTool(tool)
                } label: {
                    HStack(spacing: 6) {
                        Text("打开工具")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private func toolCategoryName(_ tool: BuiltinTool) -> String {
        switch tool {
        case .timestampConversion: return "时间与日期"
        case .ipv4Subnet: return "网络与 IP"
        case .quotaOverview: return "AI 额度"
        }
    }
}

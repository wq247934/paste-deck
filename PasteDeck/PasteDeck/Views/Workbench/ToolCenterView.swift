//
//  ToolCenterView.swift
//  PasteDeck
//
//  Tool Center view in PasteDeck 2.0 workbench, dynamically discovering
//  and presenting tools registered in ToolRegistry.
//
//  交互（需求②③）：
//  - 网格模块卡为磨砂玻璃材质，悬停时跟随光标显示柔和光斑、
//    靠近光标的边框局部提亮、卡片轻微 3D 倾斜，移出后平滑复原。
//  - 点击模块卡原位放大为详情视图（内嵌工具界面），其余模块缩为
//    底部玻璃缩略条；点击缩略图切换放大对象；关闭时原路收回。
//

import SwiftUI

struct ToolCenterView: View {
    @Binding var expandedTool: BuiltinTool?
    let onOpenTool: (BuiltinTool) -> Void

    @Environment(\.workbenchReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)
    ]

    init(expandedTool: Binding<BuiltinTool?>, onOpenTool: @escaping (BuiltinTool) -> Void) {
        self._expandedTool = expandedTool
        self.onOpenTool = onOpenTool
    }

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

            // The grid stays mounted while a module is expanded so the
            // expand/collapse transition has both endpoints on screen.
            ZStack(alignment: .top) {
                toolGrid
                    .opacity(expandedTool == nil ? 1 : 0)
                    .allowsHitTesting(expandedTool == nil)

                if let expandedTool {
                    expandedDetail(for: expandedTool)
                        .transition(expandTransition)
                }
            }
        }
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Transitions

    private var expandTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .scale(scale: 0.94).combined(with: .opacity)
            )
    }

    // MARK: - Grid State (需求②)

    private var toolGrid: some View {
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

    /// 磨砂玻璃模块卡：悬停光斑 + 局部提亮边框 + 轻微 3D 倾斜由
    /// `WorkbenchGlassCard` 统一提供；点击卡片主体原位放大为详情，点击右下角打开独立工具窗口。
    private func toolCard(descriptor: ToolDescriptor, tool: BuiltinTool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 点击卡片上半部分（图标、标题、简介与标签）原位放大为详情
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                expand(tool)
            }

            Divider()
                .overlay(Color.primary.opacity(0.06))

            // Action footer
            HStack {
                Button {
                    expand(tool)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                        Text("内嵌详情")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
                .help("在工作台内原位展开")

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
                .help("打开独立工具窗口")
            }
        }
        .padding(16)
        // Frosted glass shell + hover light spot + border glow + 3D tilt.
        .modifier(
            WorkbenchGlassCardChrome(
                cornerRadius: 12
            )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: - Expanded Detail State (需求③)

    /// 原位放大的详情：把被点模块展开成内嵌工具界面的详情视图，
    /// 其余模块沉到底部玻璃缩略条。关闭时原路收回。
    private func expandedDetail(for tool: BuiltinTool) -> some View {
        VStack(spacing: 0) {
            WorkbenchGlassCard(cornerRadius: 16, interactive: false) {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader(for: tool)

                    Divider()
                        .overlay(Color.primary.opacity(0.06))

                    // Embedded tool UI. The container width is bounded so that
                    // TimestampToolView can use its >= 520pt side navigation and
                    // QuotaToolView's two-column grid stays uncrowded.
                    tool.makeContentView(context: .standalone)
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Sibling modules collapse into a bottom glass thumbnail strip.
            thumbnailStrip(excluding: tool)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.85)
        )
        .onExitCommand {
            collapse()
        }
    }

    /// 详情头部：图标 + 名称 + 关闭按钮（点击原路收回网格）。
    private func detailHeader(for tool: BuiltinTool) -> some View {
        let descriptor = tool.descriptor
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: descriptor.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text(descriptor.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("收起，返回模块网格")
            .accessibilityLabel("收起详情")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    /// 底部玻璃缩略条：其余模块收缩为小胶囊，点击切换当前放大对象。
    private func thumbnailStrip(excluding current: BuiltinTool) -> some View {
        let siblings = BuiltinTool.allCases.filter { $0 != current }
        return HStack(spacing: 10) {
            ForEach(siblings) { sibling in
                Button {
                    switchExpanded(to: sibling)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sibling.descriptor.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.08))

                        Text(sibling.descriptor.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Expand / Collapse Actions

    /// 原位放大某个工具。
    private func expand(_ tool: BuiltinTool) {
        setExpanded(tool)
    }

    /// 原路收回网格。
    private func collapse() {
        setExpanded(nil)
    }

    /// 点击缩略图切换当前放大对象。
    private func switchExpanded(to tool: BuiltinTool) {
        setExpanded(tool)
    }

    /// Reduce Motion 下直接切换状态，不播放放大 / 收回动画。
    private func setExpanded(_ tool: BuiltinTool?) {
        let apply = { expandedTool = tool }
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        } else {
            withAnimation(WorkbenchMotion.expandSpring, apply)
        }
    }

    private func toolCategoryName(_ tool: BuiltinTool) -> String {
        switch tool {
        case .timestampConversion: return "时间与日期"
        case .ipv4Subnet: return "网络与 IP"
        case .quotaOverview: return "AI 额度"
        }
    }
}

// MARK: - Glass Card Chrome Wrapper

/// 把 `WorkbenchGlassCard` 的玻璃壳包成一个 modifier，
/// 让 `toolCard` 保持声明式。
private struct WorkbenchGlassCardChrome: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        WorkbenchGlassCard(cornerRadius: cornerRadius, interactive: true) {
            content
        }
    }
}

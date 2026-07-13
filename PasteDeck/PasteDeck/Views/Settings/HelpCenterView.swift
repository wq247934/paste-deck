//
//  HelpCenterView.swift
//  PasteDeck
//
//  A guided, scenario-based feature map that helps people discover PasteDeck
//  without turning the settings window into a dense reference manual.
//

import SwiftUI

struct HelpCenterView: View {
    @State private var selectedTopic: HelpTopic = .getStarted

    var body: some View {
        SettingsContentStack {
            hero
            topicPicker
            guide
            shortcuts
            tip
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(systemName: selectedTopic.icon)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(selectedTopic.tint.gradient))

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTopic.headline)
                    .font(.system(size: 19, weight: .bold))
                Text(selectedTopic.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(selectedTopic.badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selectedTopic.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(selectedTopic.tint.opacity(0.12)))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(selectedTopic.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selectedTopic.tint.opacity(0.15), lineWidth: 1)
        )
    }

    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想完成什么？")
                .font(.system(size: 14, weight: .semibold))

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(HelpTopic.allCases) { topic in
                    HelpTopicButton(
                        topic: topic,
                        isSelected: selectedTopic == topic
                    ) {
                        selectedTopic = topic
                    }
                }
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("跟着做，只要三步")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(selectedTopic.actionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selectedTopic.tint)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(selectedTopic.steps.indices, id: \.self) { index in
                    HelpStepCard(
                        index: index + 1,
                        step: selectedTopic.steps[index],
                        tint: selectedTopic.tint
                    )
                }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedTopic.shortcutTitle)
                .font(.system(size: 14, weight: .semibold))

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 8
            ) {
                ForEach(selectedTopic.shortcuts) { shortcut in
                    HelpShortcutCard(shortcut: shortcut)
                }
            }
        }
    }

    private var tip: some View {
        Label(selectedTopic.tip, systemImage: "sparkles")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }
}

private struct HelpTopicButton: View {
    let topic: HelpTopic
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: topic.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(topic.tint)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(topic.tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(topic.shortDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(topic.tint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? topic.tint.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? topic.tint.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HelpStepCard: View {
    let index: Int
    let step: HelpStep
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint))

            Image(systemName: step.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            Text(step.title)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(step.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }
}

private struct HelpShortcutCard: View {
    let shortcut: HelpShortcut

    var body: some View {
        HStack(spacing: 9) {
            Text(shortcut.keys)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))

            Text(shortcut.action)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.025)))
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case getStarted
    case findAndOrganize
    case previewAndEdit
    case translate
    case understandUsage
    case customizeAndMaintain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .getStarted: return "快速开始"
        case .findAndOrganize: return "查找与整理"
        case .previewAndEdit: return "预览与编辑"
        case .translate: return "翻译中心"
        case .understandUsage: return "统计洞察"
        case .customizeAndMaintain: return "个性化与维护"
        }
    }

    var shortDescription: String {
        switch self {
        case .getStarted: return "从复制到粘贴"
        case .findAndOrganize: return "找到并留住重要内容"
        case .previewAndEdit: return "先确认，再使用"
        case .translate: return "文本、截图与输入翻译"
        case .understandUsage: return "看见你的使用习惯"
        case .customizeAndMaintain: return "让 PasteDeck 更适合你"
        }
    }

    var icon: String {
        switch self {
        case .getStarted: return "bolt.fill"
        case .findAndOrganize: return "magnifyingglass"
        case .previewAndEdit: return "eye"
        case .translate: return "character.book.closed"
        case .understandUsage: return "chart.bar.xaxis"
        case .customizeAndMaintain: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .getStarted: return .accentColor
        case .findAndOrganize: return .indigo
        case .previewAndEdit: return .orange
        case .translate: return .purple
        case .understandUsage: return .teal
        case .customizeAndMaintain: return .pink
        }
    }

    var headline: String {
        switch self {
        case .getStarted: return "从一次复制开始，三秒回到需要的内容"
        case .findAndOrganize: return "让常用内容不再淹没在历史里"
        case .previewAndEdit: return "打开前先看清，必要时直接修改"
        case .translate: return "把翻译放进你正在进行的工作里"
        case .understandUsage: return "用数据看见真正高频的工作流"
        case .customizeAndMaintain: return "按你的习惯管理外观、历史与权限"
        }
    }

    var summary: String {
        switch self {
        case .getStarted: return "PasteDeck 会在本机自动记录复制内容；用全局快捷键呼出，再选择需要的一项。"
        case .findAndOrganize: return "全文搜索、来源应用筛选、收藏夹、置顶和多选操作，让历史保持可控。"
        case .previewAndEdit: return "文本、代码、Markdown、JSON、图片、文件、链接和颜色，都有适合它们的预览方式。"
        case .translate: return "支持划词、截图 OCR、输入翻译和预览内翻译；结果可保存到“翻译”分类后再次打开。"
        case .understandUsage: return "菜单栏先给你即时概览，统计页再展示趋势、内容类型、来源应用和翻译用量。"
        case .customizeAndMaintain: return "在设置中调整快捷键、面板样式、记录规则、过滤范围、权限与预览偏好。"
        }
    }

    var badge: String {
        switch self {
        case .getStarted: return "先试这个"
        case .findAndOrganize: return "越用越省时"
        case .previewAndEdit: return "看得更安心"
        case .translate: return "随手可用"
        case .understandUsage: return "了解习惯"
        case .customizeAndMaintain: return "按需调整"
        }
    }

    var actionLabel: String {
        switch self {
        case .getStarted: return "最快工作流"
        case .findAndOrganize: return "找回重点内容"
        case .previewAndEdit: return "先看再操作"
        case .translate: return "选择合适入口"
        case .understandUsage: return "从概览到细节"
        case .customizeAndMaintain: return "一次配置，长期受益"
        }
    }

    var shortcutTitle: String {
        switch self {
        case .getStarted: return "记住这 4 个快捷键"
        case .findAndOrganize: return "检索与整理操作"
        case .previewAndEdit: return "预览窗口操作"
        case .translate: return "翻译快捷入口"
        case .understandUsage: return "从哪里查看"
        case .customizeAndMaintain: return "设置页入口"
        }
    }

    var tip: String {
        switch self {
        case .getStarted: return "第一次使用时，先复制几条不同内容，就能直观看到卡片和预览的差异。"
        case .findAndOrganize: return "把会反复使用的内容置顶或放入收藏夹，下一次几乎不用搜索。"
        case .previewAndEdit: return "富文本会保留原有格式；选择“纯文本粘贴”可避免把样式带进目标应用。"
        case .translate: return "自动划词默认关闭。需要时在“翻译”设置中开启并按提示授予所需系统权限。"
        case .understandUsage: return "菜单栏数字每次展开都会刷新，适合快速确认今天的使用量和缓存占用。"
        case .customizeAndMaintain: return "翻译凭据保存在本机 macOS 钥匙串；历史和图片缓存也只保留在你的设备上。"
        }
    }

    var steps: [HelpStep] {
        switch self {
        case .getStarted:
            return [
                HelpStep(icon: "doc.on.clipboard", title: "复制内容", detail: "文本、图片、文件、链接和颜色会自动进入历史。"),
                HelpStep(icon: "rectangle.stack.fill", title: "呼出面板", detail: "按 Command + Shift + V，或点菜单栏图标。"),
                HelpStep(icon: "return", title: "选择并粘贴", detail: "选中卡片后按 Enter；双击卡片也可以直接粘贴。")
            ]
        case .findAndOrganize:
            return [
                HelpStep(icon: "magnifyingglass", title: "输入关键词", detail: "搜索正文、链接网站名和图片 OCR 识别出的文字。"),
                HelpStep(icon: "line.3.horizontal.decrease.circle", title: "缩小范围", detail: "按来源应用或收藏夹筛选，快速排除无关内容。"),
                HelpStep(icon: "star.fill", title: "留下重点", detail: "把重要卡片收藏、置顶，或加入自定义收藏夹。")
            ]
        case .previewAndEdit:
            return [
                HelpStep(icon: "space", title: "按 Space 预览", detail: "先确认内容，再决定复制、修改或粘贴。"),
                HelpStep(icon: "rectangle.and.pencil.and.ellipsis", title: "按类型查看", detail: "Markdown、JSON、图片、文件与颜色都有专用呈现。"),
                HelpStep(icon: "pencil.line", title: "需要时编辑", detail: "文本、代码和颜色可在预览内调整后再使用。")
            ]
        case .translate:
            return [
                HelpStep(icon: "text.cursor", title: "翻译所选文本", detail: "选中文本后按 Option + D，获得即时翻译结果。"),
                HelpStep(icon: "viewfinder", title: "截图或输入", detail: "Option + S 截图 OCR 翻译；Option + A 打开输入翻译。"),
                HelpStep(icon: "text.bubble", title: "在预览里深入翻译", detail: "普通文本预览中按 T，比较多个服务的结果并保存。")
            ]
        case .understandUsage:
            return [
                HelpStep(icon: "menubar.rectangle", title: "先看菜单栏", detail: "展开菜单即可看到今日复制、总条数和缓存占用。"),
                HelpStep(icon: "chart.line.uptrend.xyaxis", title: "打开统计面板", detail: "进入设置的“统计”，查看趋势、内容类型和来源应用。"),
                HelpStep(icon: "arrow.triangle.2.circlepath", title: "观察变化", detail: "切换日期范围和翻译用量筛选，找到高频使用方式。")
            ]
        case .customizeAndMaintain:
            return [
                HelpStep(icon: "keyboard", title: "设定入口", detail: "在“快捷键”修改主面板和翻译操作的唤起方式。"),
                HelpStep(icon: "rectangle.split.3x1", title: "调整面板", detail: "在“外观”选择主题、横向或竖向布局及卡片样式。"),
                HelpStep(icon: "internaldrive", title: "管理历史", detail: "设置保留规则、缓存上限、过滤应用与预览偏好。")
            ]
        }
    }

    var shortcuts: [HelpShortcut] {
        switch self {
        case .getStarted:
            return [
                HelpShortcut(keys: "⌘ ⇧ V", action: "打开或关闭面板"),
                HelpShortcut(keys: "⌘ F", action: "聚焦搜索框"),
                HelpShortcut(keys: "↩", action: "粘贴选中内容"),
                HelpShortcut(keys: "⇧ ↩", action: "纯文本粘贴")
            ]
        case .findAndOrganize:
            return [
                HelpShortcut(keys: "Tab", action: "切换收藏夹筛选"),
                HelpShortcut(keys: "⇧ 方向键", action: "扩展连续多选"),
                HelpShortcut(keys: "⌘ 点击", action: "逐项加入或移出多选"),
                HelpShortcut(keys: "⌫", action: "删除选中内容")
            ]
        case .previewAndEdit:
            return [
                HelpShortcut(keys: "Space", action: "打开选中内容预览"),
                HelpShortcut(keys: "T", action: "打开文本翻译工作区"),
                HelpShortcut(keys: "Esc", action: "关闭预览或返回面板"),
                HelpShortcut(keys: "⌘ W", action: "关闭预览窗口")
            ]
        case .translate:
            return [
                HelpShortcut(keys: "⌥ D", action: "翻译所选文本"),
                HelpShortcut(keys: "⌥ S", action: "截图 OCR 翻译"),
                HelpShortcut(keys: "⌥ A", action: "打开输入翻译"),
                HelpShortcut(keys: "T", action: "预览内翻译")
            ]
        case .understandUsage:
            return [
                HelpShortcut(keys: "菜单栏", action: "查看即时统计概览"),
                HelpShortcut(keys: "设置", action: "打开“统计”面板"),
                HelpShortcut(keys: "7 天", action: "查看短期使用趋势"),
                HelpShortcut(keys: "30 天", action: "回顾长期使用趋势")
            ]
        case .customizeAndMaintain:
            return [
                HelpShortcut(keys: "通用", action: "开机启动与权限"),
                HelpShortcut(keys: "历史记录", action: "保留与清理策略"),
                HelpShortcut(keys: "过滤", action: "排除不需记录的应用"),
                HelpShortcut(keys: "高级", action: "预览与数据维护")
            ]
        }
    }
}

private struct HelpStep: Identifiable {
    /// 与动作对应的 SF Symbol，让用户可以先通过图形快速扫描步骤意图。
    let icon: String
    /// 用户需要执行的最短动作描述，保持标题可在卡片上快速阅读。
    let title: String
    /// 解释该动作会产生的结果，帮助用户理解功能价值而非只记住按钮位置。
    let detail: String

    /// 使用内容生成稳定标识，避免页面状态更新时为静态帮助卡片反复分配 UUID。
    var id: String { "\(icon)-\(title)" }
}

private struct HelpShortcut: Identifiable {
    /// 在键帽样式中展示的实际按键或应用入口，优先使用 macOS 符号而不是冗长文字。
    let keys: String
    /// 说明对应按键或入口执行的用户可见操作。
    let action: String

    /// 由按键和动作生成稳定标识，保持场景切换期间的列表更新轻量。
    var id: String { "\(keys)-\(action)" }
}

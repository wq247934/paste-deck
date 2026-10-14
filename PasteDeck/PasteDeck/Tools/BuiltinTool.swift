//
//  BuiltinTool.swift
//  PasteDeck
//
//  内置工具枚举：每个 case 对应一个稳定 ID 与一份独立界面。
//  新增工具只需扩展该枚举并在注册表中自然收录。
//

import Foundation
import SwiftUI

enum BuiltinTool: String, CaseIterable, Identifiable, Equatable {
    /// Unix 时间戳双向转换。
    case timestampConversion = "com.pastedeck.tool.timestamp"
    /// IPv4 地址与子网计算。
    case ipv4Subnet = "com.pastedeck.tool.ipv4-subnet"
    /// Codex / WorkBuddy 额度查看（复用现有额度服务）。
    case quotaOverview = "com.pastedeck.tool.quota"

    var id: String { rawValue }

    var descriptor: ToolDescriptor {
        switch self {
        case .timestampConversion:
            return ToolDescriptor(
                id: id,
                name: "时间转换",
                symbolName: "clock.badge.checkmark",
                summary: "时间戳转换、日期差、推算日期、工作日、日期格式、世界时间、秒表",
                keywords: ["时间", "时间戳", "转换", "日期", "时区", "iso", "unix", "秒表", "工作日", "日期差", "万年历", "日历"],
                aliases: ["timestamp", "ts", "时间转换", "时间戳转换", "时间日期计算"],
                preferredWindowSize: CGSize(width: 760, height: 580)
            )
        case .ipv4Subnet:
            return ToolDescriptor(
                id: id,
                name: "IP / 子网",
                symbolName: "network",
                summary: "IPv4 校验、地址类型判断与子网掩码计算",
                keywords: ["ip", "ipv4", "子网", "掩码", "cidr", "网络", "网段"],
                aliases: ["ip", "ipv4", "subnet", "子网计算", "ip工具"],
                preferredWindowSize: CGSize(width: 560, height: 640)
            )
        case .quotaOverview:
            return ToolDescriptor(
                id: id,
                name: "额度查看",
                symbolName: "gauge.with.needle",
                summary: "Codex / Gemini / WorkBuddy 余额与用量",
                keywords: ["额度", "余额", "配额", "积分", "用量", "quota", "codex", "gemini", "workbuddy"],
                aliases: ["codex", "workbuddy", "gemini", "额度查看", "余额查询", "额度详情"],
                preferredWindowSize: CGSize(width: 720, height: 720)
            )
        }
    }

    /// 该工具是否依赖剪贴板内容识别触发（上下文面板与搜索内容建议）。
    var supportsContentRecognition: Bool {
        switch self {
        case .timestampConversion, .ipv4Subnet:
            return true
        case .quotaOverview:
            return false
        }
    }
}

// MARK: - View Factory

extension BuiltinTool {
    /// 工具的主界面。独立窗口与上下文面板共用同一实现，
    /// 通过容器宽度自适应布局。
    @ViewBuilder
    func makeContentView(context: ToolContext) -> some View {
        switch self {
        case .timestampConversion:
            TimestampToolView(context: context)
        case .ipv4Subnet:
            IPv4SubnetToolView(context: context)
        case .quotaOverview:
            QuotaToolView()
        }
    }
}

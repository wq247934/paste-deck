//
//  QuotaFormat.swift
//  PasteDeck
//
//  Codex / WorkBuddy 余额展示用的纯格式化辅助，供菜单栏、下拉菜单与设置页共用。
//
//  Created on 2026-10-11.
//

import AppKit
import SwiftUI

enum QuotaFormat {

    // MARK: - 数字

    /// 把积分数量压缩成菜单栏可用的短文本：987、2.3k、12.5M。
    static func compactCredits(_ value: Double) -> String {
        let bounded = max(0, value)
        if bounded >= 1_000_000 {
            return scaledText(bounded / 1_000_000, unit: "M")
        }
        if bounded >= 1_000 {
            return scaledText(bounded / 1_000, unit: "k")
        }
        return String(Int(bounded.rounded()))
    }

    /// 带千分位的完整数字，用于设置页的总额 / 已用展示。
    static func groupedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// 缩放后的数值：整数不带小数位，否则保留一位小数。
    private static func scaledText(_ scaled: Double, unit: String) -> String {
        if abs(scaled.rounded() - scaled) < 0.05 {
            return "\(Int(scaled.rounded()))\(unit)"
        }
        return String(format: "%.1f%@", scaled, unit)
    }

    // MARK: - 时间

    /// 仅时间 "HH:mm"，用于 5 小时窗口的重置时间。
    static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 日期 + 时间 "MM-dd HH:mm"，用于每周窗口的重置时间。
    static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// "HH:mm 更新"，用于菜单和设置页的最后刷新时间。
    static func updatedText(_ date: Date) -> String {
        "\(clockText(date)) 更新"
    }

    /// 距离重置时间的自然语言倒计时；已过期返回 nil。
    static func countdownText(until resetsAt: Date, now: Date) -> String? {
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        let minutes = Int(ceil(interval / 60))
        if minutes >= 60 * 24 {
            let days = Int(round(Double(minutes) / (60 * 24)))
            return days > 1 ? "还剩 \(days) 天" : "还剩 1 天"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let restMinutes = minutes % 60
            return restMinutes > 0 ? "还剩 \(hours) 小时 \(restMinutes) 分" : "还剩 \(hours) 小时"
        }
        return "还剩 \(minutes) 分钟"
    }

    // MARK: - 用量配色

    /// 用量进度条颜色：>=85% 红、>=60% 黄、其余绿，与 codex-quota-utools 的阈值一致。
    static func usageNSColor(forUsedPercent used: Double) -> NSColor {
        if used >= 85 { return .systemRed }
        if used >= 60 { return .systemYellow }
        return .systemGreen
    }

    /// 用量进度条颜色的 SwiftUI 版本，供设置页使用。
    static func usageColor(forUsedPercent used: Double) -> Color {
        if used >= 85 { return .red }
        if used >= 60 { return .yellow }
        return .green
    }

    /// 按剩余健康度返回进度条颜色：正常时用品牌色，余量不足转橙、告急转红。
    static func remainingNSColor(remainingPercent: Double, base: NSColor) -> NSColor {
        if remainingPercent <= 15 { return .systemRed }
        if remainingPercent <= 40 { return .systemOrange }
        return base
    }

    /// 剩余健康度配色的 SwiftUI 版本，供设置页使用。
    static func remainingColor(remainingPercent: Double, base: Color) -> Color {
        if remainingPercent <= 15 { return .red }
        if remainingPercent <= 40 { return .orange }
        return base
    }

    /// 智能百分比文本：整数不带小数位，否则保留一位小数（96% / 79.5%）。
    static func smartPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.05 {
            return "\(Int(rounded.rounded()))%"
        }
        return String(format: "%.1f%%", rounded)
    }
}

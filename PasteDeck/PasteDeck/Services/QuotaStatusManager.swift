//
//  QuotaStatusManager.swift
//  PasteDeck
//
//  Codex / Gemini / WorkBuddy 余额的中央缓存与刷新调度：
//  - 下拉菜单打开、设置页进入、菜单栏显示开启时按需刷新
//  - 菜单栏显示开启后周期性后台刷新
//  - 汇总出菜单栏图标旁的余额文本
//
//  Created on 2026-10-11.
//

import AppKit
import Foundation
import SwiftData

@MainActor
final class QuotaStatusManager: ObservableObject {

    static let shared = QuotaStatusManager()

    /// 快照或错误状态变化后发出；菜单视图与状态栏文本据此更新。
    static let statusDidChange = Notification.Name("PasteDeck.quotaStatusDidChange")
    /// 设置页切换“菜单栏显示余额”后发出，AppDelegate 负责应用。
    static let menuBarDisplayDidChange = Notification.Name("PasteDeck.quotaMenuBarDisplayDidChange")
    /// menuBarDisplayDidChange 的 userInfo 中记录目标开关状态。
    static let menuBarDisplayEnabledKey = "enabled"

    @Published private(set) var codexSnapshot: CodexQuotaService.Snapshot?
    @Published private(set) var codexError: String?
    /// 菜单等窄空间使用的精简失败原因。
    @Published private(set) var codexShortError: String?
    @Published private(set) var codexRefreshedAt: Date?
    @Published private(set) var isRefreshingCodex = false

    @Published private(set) var geminiSnapshot: GeminiQuotaService.Snapshot?
    @Published private(set) var geminiError: String?
    @Published private(set) var geminiShortError: String?
    @Published private(set) var geminiRefreshedAt: Date?
    @Published private(set) var isRefreshingGemini = false

    @Published private(set) var workbuddySnapshot: WorkBuddyQuotaService.Snapshot?
    @Published private(set) var workbuddyError: String?
    @Published private(set) var workbuddyShortError: String?
    @Published private(set) var workbuddyRefreshedAt: Date?
    @Published private(set) var isRefreshingWorkBuddy = false

    /// 下拉菜单 / 设置页的常规过期时间。
    private let interactiveMaxAge: TimeInterval = 300
    /// 菜单栏显示开启时的后台刷新间隔。
    private let menuBarRefreshInterval: TimeInterval = 900

    private var codexTask: Task<Void, Never>?
    private var geminiTask: Task<Void, Never>?
    private var workbuddyTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var isMenuBarDisplayEnabled = false

    private init() {}

    // MARK: - 刷新入口

    /// 强制刷新全部余额（设置页手动刷新按钮）。
    func refresh(force: Bool) {
        refreshCodex(maxAge: force ? nil : interactiveMaxAge)
        refreshGemini(maxAge: force ? nil : interactiveMaxAge)
        refreshWorkBuddy(maxAge: force ? nil : interactiveMaxAge)
    }

    /// 数据比 maxAge 旧才刷新；nil refreshedAt 视为从未刷新。
    func refreshIfStale(maxAge: TimeInterval) {
        refreshCodex(maxAge: maxAge)
        refreshGemini(maxAge: maxAge)
        refreshWorkBuddy(maxAge: maxAge)
    }

    /// 仅刷新 Codex（设置页单个刷新按钮）。
    func refreshCodex(force: Bool) {
        refreshCodex(maxAge: force ? nil : interactiveMaxAge)
    }

    /// 仅刷新 Gemini（设置页单个刷新按钮）。
    func refreshGemini(force: Bool) {
        refreshGemini(maxAge: force ? nil : interactiveMaxAge)
    }

    /// 仅刷新 WorkBuddy（设置页单个刷新按钮）。
    func refreshWorkBuddy(force: Bool) {
        refreshWorkBuddy(maxAge: force ? nil : interactiveMaxAge)
    }

    // MARK: - 菜单栏显示

    /// 由 AppDelegate 在启动与设置变化时调用，控制后台周期刷新。
    func setMenuBarDisplayEnabled(_ enabled: Bool) {
        guard isMenuBarDisplayEnabled != enabled else { return }
        isMenuBarDisplayEnabled = enabled

        refreshTimer?.invalidate()
        refreshTimer = nil

        guard enabled else { return }

        // 开启后立即补一次数据，之后按固定间隔后台刷新。
        refreshIfStale(maxAge: 60)
        let timer = Timer(timeInterval: menuBarRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIfStale(maxAge: Self.menuBarRefreshIntervalStaleness)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private static let menuBarRefreshIntervalStaleness: TimeInterval = 840

    /// 菜单栏图标旁的余额文本；两类余额都不可用时返回 nil（仅显示图标）。
    /// 刷新失败时继续展示最近一次成功的快照，避免余额数字闪断。
    var menuBarAttributedTitle: NSAttributedString? {
        var segments: [(text: String, color: NSColor)] = []

        if let snapshot = codexSnapshot, snapshot.session.isAvailable {
            let remaining = snapshot.session.displayRemainingPercent
            let color: NSColor
            if snapshot.session.isLimitReached || remaining <= 15 {
                color = .systemRed
            } else if remaining <= 40 {
                color = .systemOrange
            } else {
                color = .labelColor
            }
            segments.append(("C \(Int(remaining.rounded()))%", color))
        }

        if let snapshot = geminiSnapshot, snapshot.session.isAvailable {
            let remaining = snapshot.session.displayRemainingPercent
            let color: NSColor
            if snapshot.session.isLimitReached || remaining <= 15 {
                color = .systemRed
            } else if remaining <= 40 {
                color = .systemOrange
            } else {
                color = .labelColor
            }
            segments.append(("G \(Int(remaining.rounded()))%", color))
        }

        if let snapshot = workbuddySnapshot {
            let color: NSColor
            if snapshot.remain <= 0 {
                color = .systemRed
            } else if snapshot.total > 0, snapshot.remain <= snapshot.total * 0.15 {
                color = .systemOrange
            } else {
                color = .labelColor
            }
            segments.append(("W \(QuotaFormat.compactCredits(snapshot.remain))", color))
        }

        guard !segments.isEmpty else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(
                    string: " · ",
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: segment.color]
            ))
        }
        return title
    }

    /// 菜单栏余额的悬停提示。
    var menuBarToolTip: String {
        var lines: [String] = []

        if let snapshot = codexSnapshot {
            if snapshot.session.isAvailable {
                var sessionLine = "Codex 5 小时额度：剩余 \(Int(snapshot.session.displayRemainingPercent.rounded()))%"
                if let resetsAt = snapshot.session.resetsAt {
                    sessionLine += "（\(QuotaFormat.clockText(resetsAt)) 重置）"
                }
                lines.append(sessionLine)
            } else {
                lines.append("Codex：5 小时额度暂未激活")
            }

            // 每周窗口独立于 5 小时窗口，两者互不影响。
            if snapshot.weekly.isAvailable {
                var weeklyLine = "Codex 每周额度：剩余 \(Int(snapshot.weekly.displayRemainingPercent.rounded()))%"
                if let resetsAt = snapshot.weekly.resetsAt {
                    weeklyLine += "（\(QuotaFormat.dateTimeText(resetsAt)) 重置）"
                }
                lines.append(weeklyLine)
            }
        } else if let codexError {
            lines.append("Codex：\(codexError)")
        } else {
            lines.append("Codex：正在获取…")
        }

        if let snapshot = geminiSnapshot {
            if snapshot.session.isAvailable {
                var sessionLine = "Gemini 5 小时额度：剩余 \(Int(snapshot.session.displayRemainingPercent.rounded()))%"
                if let resetsAt = snapshot.session.resetsAt {
                    sessionLine += "（\(QuotaFormat.clockText(resetsAt)) 重置）"
                }
                lines.append(sessionLine)
            } else {
                lines.append("Gemini：5 小时额度暂未激活")
            }

            if snapshot.weekly.isAvailable {
                var weeklyLine = "Gemini 每周额度：剩余 \(Int(snapshot.weekly.displayRemainingPercent.rounded()))%"
                if let resetsAt = snapshot.weekly.resetsAt {
                    weeklyLine += "（\(QuotaFormat.dateTimeText(resetsAt)) 重置）"
                }
                lines.append(weeklyLine)
            }
        } else if let geminiError {
            lines.append("Gemini：\(geminiError)")
        } else {
            lines.append("Gemini：正在获取…")
        }

        if let snapshot = workbuddySnapshot {
            lines.append(
                "WorkBuddy：剩余 \(QuotaFormat.groupedNumber(snapshot.remain)) / \(QuotaFormat.groupedNumber(snapshot.total)) 积分"
            )
        } else if let workbuddyError {
            lines.append("WorkBuddy：\(workbuddyError)")
        } else {
            lines.append("WorkBuddy：正在获取…")
        }

        lines.append("上次更新 \(lastUpdatedText)")
        return lines.joined(separator: "\n")
    }

    /// 各侧数据中最近一次刷新动作的时间。
    var lastRefreshedAt: Date? {
        [codexRefreshedAt, geminiRefreshedAt, workbuddyRefreshedAt].compactMap { $0 }.max()
    }

    var lastUpdatedText: String {
        lastRefreshedAt.map { QuotaFormat.updatedText($0) } ?? "尚未刷新"
    }

    /// 下拉菜单打开时的刷新策略：展示缓存数据，过期则后台补一次。
    func refreshForMenuDisplay() {
        refreshIfStale(maxAge: interactiveMaxAge)
    }

    // MARK: - 私有刷新实现

    private func refreshCodex(maxAge: TimeInterval?) {
        guard codexTask == nil else { return }
        if let maxAge, let refreshedAt = codexRefreshedAt,
           Date().timeIntervalSince(refreshedAt) < maxAge {
            return
        }

        isRefreshingCodex = true
        codexTask = Task { [weak self] in
            defer { self?.codexTask = nil }
            do {
                let snapshot = try await CodexQuotaService.query()
                guard let self else { return }
                self.codexSnapshot = snapshot
                self.codexError = nil
                self.codexShortError = nil
                self.codexRefreshedAt = Date()
                self.isRefreshingCodex = false
                self.notifyStatusChange()
            } catch {
                guard let self else { return }
                self.codexError = error.localizedDescription
                self.codexShortError = (error as? QuotaShortErrorProviding)?.shortDescription ?? "查询失败"
                self.codexRefreshedAt = Date()
                self.isRefreshingCodex = false
                self.notifyStatusChange()
            }
        }
    }

    private func refreshGemini(maxAge: TimeInterval?) {
        guard geminiTask == nil else { return }
        if let maxAge, let refreshedAt = geminiRefreshedAt,
           Date().timeIntervalSince(refreshedAt) < maxAge {
            return
        }

        let geminiSettings = fetchGeminiSettings()
        guard geminiSettings.enabled else {
            geminiSnapshot = nil
            geminiError = nil
            geminiShortError = nil
            geminiRefreshedAt = Date()
            isRefreshingGemini = false
            notifyStatusChange()
            return
        }

        isRefreshingGemini = true
        geminiTask = Task { [weak self] in
            defer { self?.geminiTask = nil }
            do {
                let snapshot = try await GeminiQuotaService.query(
                    endpoint: geminiSettings.endpoint,
                    token: geminiSettings.token
                )
                guard let self else { return }
                self.geminiSnapshot = snapshot
                self.geminiError = nil
                self.geminiShortError = nil
                self.geminiRefreshedAt = Date()
                self.isRefreshingGemini = false
                self.notifyStatusChange()
            } catch {
                guard let self else { return }
                self.geminiError = error.localizedDescription
                self.geminiShortError = (error as? QuotaShortErrorProviding)?.shortDescription ?? "查询失败"
                self.geminiRefreshedAt = Date()
                self.isRefreshingGemini = false
                self.notifyStatusChange()
            }
        }
    }

    private func fetchGeminiSettings() -> (endpoint: String?, token: String?, enabled: Bool) {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first else {
            return (nil, nil, true)
        }
        return (
            settings.geminiQuotaEndpoint,
            settings.geminiQuotaToken,
            settings.geminiQuotaEnabled ?? true
        )
    }

    private func refreshWorkBuddy(maxAge: TimeInterval?) {
        guard workbuddyTask == nil else { return }
        if let maxAge, let refreshedAt = workbuddyRefreshedAt,
           Date().timeIntervalSince(refreshedAt) < maxAge {
            return
        }

        isRefreshingWorkBuddy = true
        workbuddyTask = Task { [weak self] in
            defer { self?.workbuddyTask = nil }
            do {
                let snapshot = try await WorkBuddyQuotaService.query()
                guard let self else { return }
                self.workbuddySnapshot = snapshot
                self.workbuddyError = nil
                self.workbuddyShortError = nil
                self.workbuddyRefreshedAt = Date()
                self.isRefreshingWorkBuddy = false
                self.notifyStatusChange()
            } catch {
                guard let self else { return }
                self.workbuddyError = error.localizedDescription
                self.workbuddyShortError = (error as? QuotaShortErrorProviding)?.shortDescription ?? "查询失败"
                self.workbuddyRefreshedAt = Date()
                self.isRefreshingWorkBuddy = false
                self.notifyStatusChange()
            }
        }
    }

    private func notifyStatusChange() {
        NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
    }
}

// MARK: - 窄空间错误摘要

/// 余额查询错误的精简描述，用于菜单区块等窄空间展示。
protocol QuotaShortErrorProviding {
    var shortDescription: String { get }
}

extension CodexQuotaService.CodexQuotaError: QuotaShortErrorProviding {
    var shortDescription: String {
        switch self {
        case .cliNotFound: return "未检测到 ChatGPT"
        case .timeout: return "查询超时"
        case .launchFailed: return "启动失败"
        case .exitedWithoutData: return "未安装或未登录"
        case .rpcError: return "接口错误"
        case .noRateLimits: return "无额度数据"
        }
    }
}

extension WorkBuddyQuotaService.WorkBuddyQuotaError: QuotaShortErrorProviding {
    var shortDescription: String {
        switch self {
        case .credentialMissing: return "未登录 WorkBuddy"
        case .credentialUnreadable: return "凭证损坏"
        case .credentialMissingToken: return "请重新登录"
        case .credentialInvalid: return "凭证已失效"
        case .requestFailed: return "网络异常"
        case .apiError: return "接口错误"
        }
    }
}

extension GeminiQuotaService.GeminiQuotaError: QuotaShortErrorProviding {
    var shortDescription: String {
        switch self {
        case .serviceUnavailable: return "服务未启动"
        case .unauthorized: return "密码错误"
        case .requestFailed: return "连接失败"
        case .invalidResponse: return "解析失败"
        case .apiError: return "接口错误"
        case .noAccountData: return "无数据"
        }
    }
}


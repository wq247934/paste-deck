//
//  StatusMenuBuilder.swift
//  PasteDeck
//
//  Builds the custom status bar dropdown menu with a refined style,
//  a stats overview header, and a quota dashboard block.
//
//  Created on 2026-07-08.
//

import AppKit
import SwiftData

/// 统计概览 header 的自定义视图，展示今日复制 / 总条数 / 缓存占用。
final class StatsOverviewMenuItemView: NSView {

    private let todayLabel = NSTextField(labelWithString: "—")
    private let totalLabel = NSTextField(labelWithString: "—")
    private let cacheLabel = NSTextField(labelWithString: "—")

    private let todayCaption = NSTextField(labelWithString: "今日复制")
    private let totalCaption = NSTextField(labelWithString: "总条数")
    private let cacheCaption = NSTextField(labelWithString: "缓存")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let numbers: [NSTextField] = [todayLabel, totalLabel, cacheLabel]
        let captions: [NSTextField] = [todayCaption, totalCaption, cacheCaption]

        for label in numbers {
            label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
            label.alignment = .center
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.preferredMaxLayoutWidth = 80
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        for caption in captions {
            caption.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            caption.alignment = .center
            caption.textColor = .secondaryLabelColor
            caption.preferredMaxLayoutWidth = 80
            caption.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let columns = zip(numbers, captions).map { number, caption -> NSStackView in
            let stack = NSStackView(views: [number, caption])
            stack.orientation = .vertical
            stack.spacing = 3
            stack.alignment = .centerX
            return stack
        }

        let container = NSStackView(views: columns)
        container.orientation = .horizontal
        container.distribution = .fillEqually
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    /// 用最新数据刷新显示。在菜单弹出前调用。
    func refresh() {
        let overview = Self.fetchOverview()
        todayLabel.stringValue = "\(overview.todayCount)"
        totalLabel.stringValue = "\(overview.totalItems)"
        cacheLabel.stringValue = Self.formatBytes(overview.cacheBytes)
    }

    private static func fetchOverview() -> (todayCount: Int, totalItems: Int, cacheBytes: Int) {
        let context = ModelContext(AppModelContainer.container)

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayDescriptor = FetchDescriptor<DailyStatsSnapshot>(
            predicate: #Predicate { $0.date == todayStart }
        )
        let todayCount = ((try? context.fetch(todayDescriptor).first)?.totalCount) ?? 0

        let totalItems = (try? context.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
        let cacheBytes = CacheManager().getTotalCacheSize()

        return (todayCount, totalItems, cacheBytes)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// 用量迷你进度条，菜单额度区块使用。
final class MiniQuotaBarView: NSView {

    private let fillLayer = CALayer()
    private var fraction: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        fillLayer.cornerRadius = 3
        fillLayer.backgroundColor = NSColor.systemTeal.cgColor
        layer?.addSublayer(fillLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(fraction: Double, color: NSColor) {
        self.fraction = min(1, max(0, fraction))
        fillLayer.backgroundColor = color.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width * CGFloat(fraction),
            height: bounds.height
        )
        CATransaction.commit()
    }
}

/// 菜单里的 Codex / WorkBuddy 余额区块：品牌色进度条 + 额度详情按钮。
/// 打开菜单时展示缓存快照，数据过期则在后台补一次刷新并原地更新。
final class QuotaOverviewMenuItemView: NSView {

    fileprivate struct Row {
        let label: NSTextField
        let bar: MiniQuotaBarView
        let detail: NSTextField
    }

    /// Codex 与 WorkBuddy 的品牌展示色，与设置页额度卡片保持一致。
    private static let codexAccent = NSColor.systemTeal
    private static let workbuddyAccent = NSColor.systemYellow

    private var rows: [Row] = []
    private let updatedLabel = NSTextField(labelWithString: "尚未刷新")
    private let openQuotaSettings: () -> Void
    private weak var detailButton: QuotaDetailButtonView?

    private var statusObserver: NSObjectProtocol?

    init(frame frameRect: NSRect, openQuotaSettings: @escaping () -> Void) {
        self.openQuotaSettings = openQuotaSettings
        super.init(frame: frameRect)
        setupUI()
        statusObserver = NotificationCenter.default.addObserver(
            forName: QuotaStatusManager.statusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplay()
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let rowNames = ["Codex 5h", "Codex 每周", "WorkBuddy"]
        rows = rowNames.map { name in
            let label = NSTextField(labelWithString: name)
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.setContentCompressionResistancePriority(.required, for: .horizontal)

            let bar = MiniQuotaBarView(frame: NSRect(x: 0, y: 0, width: 96, height: 6))
            bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
            bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
            bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            bar.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let detail = NSTextField(labelWithAttributedString: NSAttributedString(string: "获取中…"))
            detail.alignment = .right
            detail.lineBreakMode = .byTruncatingTail
            detail.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

            return Row(label: label, bar: bar, detail: detail)
        }

        for row in rows {
            row.label.widthAnchor.constraint(equalToConstant: 62).isActive = true
        }

        let rowStacks = rows.map { row -> NSStackView in
            let stack = NSStackView(views: [row.label, row.bar, row.detail])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            return stack
        }

        let refreshButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新额度")!,
            target: self,
            action: #selector(refreshClicked)
        )
        refreshButton.isBordered = false
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.toolTip = "刷新额度数据"

        let header = NSStackView(views: [
            NSTextField(labelWithString: "额度"),
            NSView(),
            updatedLabel,
            refreshButton
        ])
        header.orientation = .horizontal
        header.spacing = 6

        if let headerTitle = header.arrangedSubviews.first as? NSTextField {
            headerTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            headerTitle.textColor = .labelColor
        }
        updatedLabel.font = NSFont.systemFont(ofSize: 10)
        updatedLabel.textColor = .secondaryLabelColor
        updatedLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let detailButton = QuotaDetailButtonView(
            title: "额度详情…",
            systemImage: "gauge.with.needle",
            action: { [weak self] in
                self?.openQuotaSettings()
            }
        )
        self.detailButton = detailButton

        let container = NSStackView(views: [header] + rowStacks + [detailButton])
        container.orientation = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    /// 菜单弹出前调用：先展示缓存数据，再让管理器按需后台刷新。
    func refresh() {
        refreshDisplay()
        QuotaStatusManager.shared.refreshForMenuDisplay()
    }

    /// 注入所属菜单，供“额度详情”按钮点击后结束菜单跟踪。
    func attachToMenu(_ menu: NSMenu) {
        detailButton?.owningMenu = menu
    }

    @objc private func refreshClicked() {
        QuotaStatusManager.shared.refresh(force: true)
    }

    private func refreshDisplay() {
        let manager = QuotaStatusManager.shared

        updatedLabel.stringValue = (manager.isRefreshingCodex || manager.isRefreshingWorkBuddy)
            ? "刷新中…"
            : manager.lastUpdatedText

        guard rows.count == 3 else { return }

        let codexSnapshot = manager.codexSnapshot
        let isCodexFetching = manager.codexError == nil && codexSnapshot == nil

        // 第一行：Codex 5 小时额度
        rows[0].configure(
            window: codexSnapshot?.session,
            resetText: codexSnapshot?.session.resetsAt.map { QuotaFormat.clockText($0) },
            accent: Self.codexAccent,
            errorText: manager.codexShortError,
            isFetching: isCodexFetching
        )

        // 第二行：Codex 每周额度
        rows[1].configure(
            window: codexSnapshot?.weekly,
            resetText: codexSnapshot?.weekly.resetsAt.map { QuotaFormat.dateTimeText($0) },
            accent: Self.codexAccent,
            errorText: manager.codexShortError,
            isFetching: isCodexFetching
        )

        // 第三行：WorkBuddy 剩余积分
        configureWorkBuddyRow(rows[2], manager: manager)
    }

    private func configureWorkBuddyRow(_ row: Row, manager: QuotaStatusManager) {
        if let snapshot = manager.workbuddySnapshot {
            let remainingPercent = snapshot.total > 0 ? snapshot.remain / snapshot.total * 100 : 0
            row.bar.update(
                fraction: remainingPercent / 100,
                color: QuotaFormat.remainingNSColor(
                    remainingPercent: remainingPercent,
                    base: Self.workbuddyAccent
                )
            )
            let remainText = "\(QuotaFormat.compactCredits(snapshot.remain)) / \(QuotaFormat.compactCredits(snapshot.total))"
            row.detail.attributedStringValue = Self.quotaDetailAttributed(
                main: remainText,
                mainColor: snapshot.remain <= 0 ? .systemRed : .labelColor,
                suffix: " 积分"
            )
        } else if let shortError = manager.workbuddyShortError {
            row.bar.update(fraction: 0, color: .systemRed)
            row.detail.attributedStringValue = Self.quotaDetailAttributed(
                main: shortError,
                mainColor: .secondaryLabelColor,
                suffix: nil
            )
        } else {
            row.bar.update(fraction: 0, color: Self.workbuddyAccent)
            row.detail.attributedStringValue = Self.quotaDetailAttributed(
                main: "获取中…",
                mainColor: .secondaryLabelColor,
                suffix: nil
            )
        }
    }

    /// 右侧详情的富文本：主数值醒目，后缀说明弱化。
    fileprivate static func quotaDetailAttributed(
        main: String,
        mainColor: NSColor,
        suffix: String?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: main,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: mainColor,
            ]
        )
        if let suffix {
            result.append(NSAttributedString(
                string: suffix,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }
        return result
    }
}

private extension QuotaOverviewMenuItemView.Row {
    /// 单行额度窗口展示：进度条按剩余比例着色，右侧显示剩余百分比与重置时间。
    /// 触顶与否只读该窗口自身的状态，全局限流标志不参与百分比计算。
    func configure(
        window: CodexQuotaService.Window?,
        resetText: String?,
        accent: NSColor,
        errorText: String?,
        isFetching: Bool
    ) {
        if let window, window.isAvailable {
            let remaining = window.displayRemainingPercent
            bar.update(
                fraction: remaining / 100,
                color: QuotaFormat.remainingNSColor(remainingPercent: remaining, base: accent)
            )
            let percentText = "\(Int(remaining.rounded()))%"
            let percentColor = QuotaFormat.remainingNSColor(remainingPercent: remaining, base: accent)
            detail.attributedStringValue = QuotaOverviewMenuItemView.quotaDetailAttributed(
                main: percentText,
                mainColor: percentColor,
                suffix: resetText.map { " · \($0)" }
            )
            return
        }

        bar.update(fraction: 0, color: accent)
        if window != nil {
            detail.attributedStringValue = QuotaOverviewMenuItemView.quotaDetailAttributed(
                main: "暂未激活",
                mainColor: .secondaryLabelColor,
                suffix: nil
            )
        } else {
            detail.attributedStringValue = QuotaOverviewMenuItemView.quotaDetailAttributed(
                main: errorText ?? (isFetching ? "获取中…" : "查询失败"),
                mainColor: .secondaryLabelColor,
                suffix: nil
            )
        }
    }
}

/// 菜单底部的“额度详情…”按钮行：浅色圆角底、悬停加深，点击后关闭菜单并打开额度设置页。
final class QuotaDetailButtonView: NSView {

    weak var owningMenu: NSMenu?

    private let action: () -> Void
    private var isHovered = false {
        didSet { updateFill() }
    }
    private var trackingArea: NSTrackingArea?

    init(title: String, systemImage: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        updateFill()

        let configuredIcon = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        let icon = NSImageView(image: configuredIcon ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateFill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        // 结束菜单跟踪后再打开设置页，避免菜单继续保持展开。
        owningMenu?.cancelTracking()
        let performAction = action
        DispatchQueue.main.async(execute: performAction)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateFill() {
        let alpha: CGFloat = isHovered ? 0.22 : 0.10
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }
}

/// 菜单栏下拉菜单构建器。
enum StatusMenuBuilder {

    /// 构建完整的菜单栏下拉菜单。
    /// - Parameters:
    ///   - openMainPanel: 打开主面板回调
    ///   - openStats: 打开统计设置页回调
    ///   - openQuotaSettings: 打开额度设置页回调
    ///   - openSettings: 打开设置页回调
    ///   - openHelp: 打开功能指南回调
    ///   - quit: 退出应用回调
    /// - Returns: 配置好的 NSMenu 和它的 delegate（delegate 需由调用方持有强引用以防释放）。
    static func buildMenu(
        openWorkbench: @escaping () -> Void,
        openMainPanel: @escaping () -> Void,
        openStats: @escaping () -> Void,
        translateSelection: @escaping () -> Void,
        translateScreenshot: @escaping () -> Void,
        translateInput: @escaping () -> Void,
        openTranslationSettings: @escaping () -> Void,
        openQuotaSettings: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openHelp: @escaping () -> Void,
        quit: @escaping () -> Void
    ) -> (menu: NSMenu, delegate: MenuRefreshDelegate) {
        let delegate = MenuRefreshDelegate(
            onOpenWorkbench: openWorkbench,
            onOpenMainPanel: openMainPanel,
            onOpenStats: openStats,
            onTranslateSelection: translateSelection,
            onTranslateScreenshot: translateScreenshot,
            onTranslateInput: translateInput,
            onOpenTranslationSettings: openTranslationSettings,
            onOpenSettings: openSettings,
            onOpenHelp: openHelp,
            quit: quit
        )

        let menu = NSMenu()
        menu.delegate = delegate

        // 统计概览 header
        let overviewView = StatsOverviewMenuItemView(frame: NSRect(x: 0, y: 0, width: 300, height: 62))
        let overviewItem = NSMenuItem()
        overviewItem.view = overviewView
        overviewItem.target = nil
        menu.addItem(overviewItem)

        menu.addItem(NSMenuItem.separator())

        // 额度区块：Codex 5 小时 / 每周窗口与 WorkBuddy 剩余积分 + 额度详情按钮
        let quotaView = QuotaOverviewMenuItemView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 150),
            openQuotaSettings: openQuotaSettings
        )
        quotaView.attachToMenu(menu)
        let quotaItem = NSMenuItem()
        quotaItem.view = quotaView
        quotaItem.target = nil
        menu.addItem(quotaItem)

        menu.addItem(NSMenuItem.separator())

        let workbenchItem = NSMenuItem(
            title: "打开工作台",
            action: #selector(MenuRefreshDelegate.performOpenWorkbench(_:)),
            keyEquivalent: "k"
        )
        workbenchItem.keyEquivalentModifierMask = [.command]
        workbenchItem.target = delegate
        workbenchItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(workbenchItem)

        let openItem = NSMenuItem(
            title: "快速粘贴面板",
            action: #selector(MenuRefreshDelegate.performOpenMainPanel(_:)),
            keyEquivalent: "v"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = delegate
        openItem.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(openItem)

        let statsItem = NSMenuItem(
            title: "统计面板",
            action: #selector(MenuRefreshDelegate.performOpenStats(_:)),
            keyEquivalent: ""
        )
        statsItem.target = delegate
        statsItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(statsItem)

        let translationItem = NSMenuItem(title: "翻译", action: nil, keyEquivalent: "")
        translationItem.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        let translationMenu = NSMenu(title: "翻译")

        let selectionItem = NSMenuItem(
            title: "翻译所选文本",
            action: #selector(MenuRefreshDelegate.performTranslateSelection(_:)),
            keyEquivalent: "d"
        )
        selectionItem.keyEquivalentModifierMask = [.option]
        selectionItem.target = delegate
        translationMenu.addItem(selectionItem)

        let screenshotItem = NSMenuItem(
            title: "截图 OCR 翻译",
            action: #selector(MenuRefreshDelegate.performTranslateScreenshot(_:)),
            keyEquivalent: "s"
        )
        screenshotItem.keyEquivalentModifierMask = [.option]
        screenshotItem.target = delegate
        translationMenu.addItem(screenshotItem)

        let inputItem = NSMenuItem(
            title: "输入翻译",
            action: #selector(MenuRefreshDelegate.performTranslateInput(_:)),
            keyEquivalent: "a"
        )
        inputItem.keyEquivalentModifierMask = [.option]
        inputItem.target = delegate
        translationMenu.addItem(inputItem)
        translationMenu.addItem(NSMenuItem.separator())

        let translationSettingsItem = NSMenuItem(
            title: "翻译设置…",
            action: #selector(MenuRefreshDelegate.performOpenTranslationSettings(_:)),
            keyEquivalent: ""
        )
        translationSettingsItem.target = delegate
        translationMenu.addItem(translationSettingsItem)
        translationItem.submenu = translationMenu
        menu.addItem(translationItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(MenuRefreshDelegate.performOpenSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = delegate
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(
            title: "功能指南…",
            action: #selector(MenuRefreshDelegate.performOpenHelp(_:)),
            keyEquivalent: ""
        )
        helpItem.target = delegate
        helpItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 PasteDeck",
            action: #selector(MenuRefreshDelegate.performQuit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = delegate
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        menu.addItem(quitItem)

        return (menu, delegate)
    }
}

/// 菜单代理，在弹出前刷新统计概览与额度区块，并响应菜单项点击。
final class MenuRefreshDelegate: NSObject, NSMenuDelegate {
    let onOpenWorkbench: () -> Void
    let onOpenMainPanel: () -> Void
    let onOpenStats: () -> Void
    let onTranslateSelection: () -> Void
    let onTranslateScreenshot: () -> Void
    let onTranslateInput: () -> Void
    let onOpenTranslationSettings: () -> Void
    let onOpenSettings: () -> Void
    let onOpenHelp: () -> Void
    let onQuit: () -> Void

    init(
        onOpenWorkbench: @escaping () -> Void,
        onOpenMainPanel: @escaping () -> Void,
        onOpenStats: @escaping () -> Void,
        onTranslateSelection: @escaping () -> Void,
        onTranslateScreenshot: @escaping () -> Void,
        onTranslateInput: @escaping () -> Void,
        onOpenTranslationSettings: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.onOpenWorkbench = onOpenWorkbench
        self.onOpenMainPanel = onOpenMainPanel
        self.onOpenStats = onOpenStats
        self.onTranslateSelection = onTranslateSelection
        self.onTranslateScreenshot = onTranslateScreenshot
        self.onTranslateInput = onTranslateInput
        self.onOpenTranslationSettings = onOpenTranslationSettings
        self.onOpenSettings = onOpenSettings
        self.onOpenHelp = onOpenHelp
        self.onQuit = quit
        super.init()
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if let view = item.view as? StatsOverviewMenuItemView {
                view.refresh()
            }
            if let view = item.view as? QuotaOverviewMenuItemView {
                view.refresh()
            }
        }
    }

    @objc func performOpenWorkbench(_ sender: NSMenuItem) {
        onOpenWorkbench()
    }

    @objc func performOpenMainPanel(_ sender: NSMenuItem) {
        onOpenMainPanel()
    }

    @objc func performOpenStats(_ sender: NSMenuItem) {
        onOpenStats()
    }

    @objc func performTranslateSelection(_ sender: NSMenuItem) {
        onTranslateSelection()
    }

    @objc func performTranslateScreenshot(_ sender: NSMenuItem) {
        onTranslateScreenshot()
    }

    @objc func performTranslateInput(_ sender: NSMenuItem) {
        onTranslateInput()
    }

    @objc func performOpenTranslationSettings(_ sender: NSMenuItem) {
        onOpenTranslationSettings()
    }

    @objc func performOpenSettings(_ sender: NSMenuItem) {
        onOpenSettings()
    }

    @objc func performOpenHelp(_ sender: NSMenuItem) {
        onOpenHelp()
    }

    @objc func performQuit(_ sender: NSMenuItem) {
        onQuit()
    }
}

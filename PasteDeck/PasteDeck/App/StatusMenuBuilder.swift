//
//  StatusMenuBuilder.swift
//  PasteDeck
//
//  Builds the custom status bar dropdown menu with a refined style
//  and an embedded stats overview header.
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

/// 菜单栏下拉菜单构建器。
enum StatusMenuBuilder {

    /// 构建完整的菜单栏下拉菜单。
    /// - Parameters:
    ///   - openMainPanel: 打开主面板回调
    ///   - openStats: 打开统计设置页回调
    ///   - openSettings: 打开设置页回调
    ///   - openHelp: 打开功能指南回调
    ///   - quit: 退出应用回调
    /// - Returns: 配置好的 NSMenu 和它的 delegate（delegate 需由调用方持有强引用以防释放）。
    static func buildMenu(
        openMainPanel: @escaping () -> Void,
        openStats: @escaping () -> Void,
        translateSelection: @escaping () -> Void,
        translateScreenshot: @escaping () -> Void,
        translateInput: @escaping () -> Void,
        openTranslationSettings: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openHelp: @escaping () -> Void,
        quit: @escaping () -> Void
    ) -> (menu: NSMenu, delegate: MenuRefreshDelegate) {
        let delegate = MenuRefreshDelegate(
            onOpenMainPanel: openMainPanel,
            onOpenStats: openStats,
            onTranslateSelection: translateSelection,
            onTranslateScreenshot: translateScreenshot,
            onTranslateInput: translateInput,
            onOpenTranslationSettings: openTranslationSettings,
            onOpenSettings: openSettings,
            onOpenHelp: openHelp,
            onQuit: quit
        )

        let menu = NSMenu()
        menu.delegate = delegate

        // 统计概览 header
        let overviewView = StatsOverviewMenuItemView(frame: NSRect(x: 0, y: 0, width: 280, height: 62))
        let overviewItem = NSMenuItem()
        overviewItem.view = overviewView
        overviewItem.target = nil
        menu.addItem(overviewItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(
            title: "打开 PasteDeck",
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

/// 菜单代理，在弹出前刷新统计概览数据，并响应菜单项点击。
final class MenuRefreshDelegate: NSObject, NSMenuDelegate {
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
        onOpenMainPanel: @escaping () -> Void,
        onOpenStats: @escaping () -> Void,
        onTranslateSelection: @escaping () -> Void,
        onTranslateScreenshot: @escaping () -> Void,
        onTranslateInput: @escaping () -> Void,
        onOpenTranslationSettings: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenMainPanel = onOpenMainPanel
        self.onOpenStats = onOpenStats
        self.onTranslateSelection = onTranslateSelection
        self.onTranslateScreenshot = onTranslateScreenshot
        self.onTranslateInput = onTranslateInput
        self.onOpenTranslationSettings = onOpenTranslationSettings
        self.onOpenSettings = onOpenSettings
        self.onOpenHelp = onOpenHelp
        self.onQuit = onQuit
        super.init()
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if let view = item.view as? StatsOverviewMenuItemView {
                view.refresh()
            }
        }
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

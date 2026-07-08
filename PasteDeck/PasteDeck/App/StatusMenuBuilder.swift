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
        }

        for caption in captions {
            caption.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            caption.alignment = .center
            caption.textColor = .secondaryLabelColor
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
    ///   - quit: 退出应用回调
    /// - Returns: 配置好的 NSMenu 和它的 delegate（delegate 需由调用方持有强引用以防释放）。
    static func buildMenu(
        openMainPanel: @escaping () -> Void,
        openStats: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) -> (menu: NSMenu, delegate: MenuRefreshDelegate) {
        let delegate = MenuRefreshDelegate(
            onOpenMainPanel: openMainPanel,
            onOpenStats: openStats,
            onOpenSettings: openSettings,
            onQuit: quit
        )

        let menu = NSMenu()
        menu.delegate = delegate

        // 统计概览 header
        let overviewView = StatsOverviewMenuItemView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
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
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    init(
        onOpenMainPanel: @escaping () -> Void,
        onOpenStats: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenMainPanel = onOpenMainPanel
        self.onOpenStats = onOpenStats
        self.onOpenSettings = onOpenSettings
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

    @objc func performOpenSettings(_ sender: NSMenuItem) {
        onOpenSettings()
    }

    @objc func performQuit(_ sender: NSMenuItem) {
        onQuit()
    }
}

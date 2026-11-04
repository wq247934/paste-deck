import AppKit

/// An `NSMenuItem` that runs a closure.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: key)
        target = self
        self.state = state
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func invoke() {
        handler()
    }
}

/// Native menus shared by the orb's context menu. Built on demand so they are always in the current language
/// and state. 上游的 quickMenu 属于独立应用的菜单栏，PasteDeck 用自己的 StatusMenuBuilder，因此不再移植。
@MainActor
enum MenuFactory {
    /// The orb's context menu (DESIGN 2b, Context menu).
    static func orbContextMenu(model: AgentSpeedModel, orbId: String) -> NSMenu {
        OrbMenus.contextMenu(model: model, orbId: orbId)
    }

    static func effectsItem(model: AgentSpeedModel) -> NSMenuItem {
        let item = NSMenuItem(title: model.l10n("menu.effects"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for level in EffectsLevel.allCases {
            let state: NSControl.StateValue = model.settings.effects == level ? .on : .off
            submenu.addItem(ActionMenuItem(model.l10n(level.titleKey), state: state) { [weak model] in
                model?.settings.effects = level
            })
        }
        item.submenu = submenu
        return item
    }

    /// The master switch (DESIGN 2b): `menu.showOrb` / `menu.hideOrb` with one orb, the plural with several.
    static func orbVisibilityItem(model: AgentSpeedModel) -> NSMenuItem {
        let visible = model.orbs.masterVisible
        let plural = model.orbs.orbs.count > 1
        let key = visible ? (plural ? "menu.hideOrbs" : "menu.hideOrb") : (plural ? "menu.showOrbs" : "menu.showOrb")
        return ActionMenuItem(model.l10n(key)) { [weak model] in
            model?.commands?.setOrbsVisible(!visible)
        }
    }

    static func historyItem(model: AgentSpeedModel) -> NSMenuItem {
        ActionMenuItem(model.l10n("history.open"), key: "y") { [weak model] in model?.commands?.showHistory(source: nil) }
    }

    static func settingsItem(model: AgentSpeedModel) -> NSMenuItem {
        ActionMenuItem(model.l10n("menu.settings"), key: ",") { [weak model] in model?.commands?.showAgentSpeedSettings() }
    }

    static func quitItem(model: AgentSpeedModel) -> NSMenuItem {
        ActionMenuItem(model.l10n("menu.quit"), key: "q") { [weak model] in model?.commands?.quit() }
    }
}

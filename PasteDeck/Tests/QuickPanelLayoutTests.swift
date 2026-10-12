import AppKit
import XCTest
@testable import PasteDeck

/// 速贴面板的尺寸与搜索框标识回归测试。
final class QuickPanelLayoutTests: XCTestCase {

    func testQuickPanelSizesMatchCompactDesign() {
        XCTAssertEqual(MainPanelWindowLayout.quickPanelDefaultContentSize.width, 480)
        XCTAssertEqual(MainPanelWindowLayout.quickPanelDefaultContentSize.height, 560)
        XCTAssertEqual(MainPanelWindowLayout.quickPanelMinimumContentSize.width, 420)
        XCTAssertEqual(MainPanelWindowLayout.quickPanelMinimumContentSize.height, 480)
    }

    func testQuickPanelMinimumFitsInsideDefault() {
        let min = MainPanelWindowLayout.quickPanelMinimumContentSize
        let def = MainPanelWindowLayout.quickPanelDefaultContentSize
        XCTAssertLessThanOrEqual(min.width, def.width)
        XCTAssertLessThanOrEqual(min.height, def.height)
    }

    func testOriginalPanelSizesUnchangedForBackwardCompatibility() {
        // 旧版横竖布局常量被既有几何测试与持久化帧恢复依赖，不能因速贴面板改动而漂移。
        XCTAssertEqual(MainPanelWindowLayout.defaultContentSize(for: .horizontal).width, 800)
        XCTAssertEqual(MainPanelWindowLayout.defaultContentSize(for: .horizontal).height, 400)
    }

    /// 搜索框必须带稳定标识：AppKit 层聚焦依赖它在视图树中被可靠定位，
    /// 缺失标识时只能靠类型遍历猜测，易命中其它输入框。
    func testSearchFieldIdentifierIsStable() {
        XCTAssertEqual(
            QuickPanelSearchFieldIdentifier.rawValue,
            "PasteDeck.QuickPanel.SearchField"
        )
    }

    /// 双焦点模式：卡片区模式（默认）支持空格预览，搜索模式支持文本输入。
    func testQuickPanelFocusZoneHasDistinctModes() {
        let cardMode = QuickPanelFocusZone.cards
        let searchMode = QuickPanelFocusZone.search
        XCTAssertNotEqual(cardMode, searchMode)
    }

    /// 工作台双焦点与窗口标识测试：确保键盘分流能精确锁定工作台窗口并支持空格预览。
    func testWorkbenchFocusZoneAndWindowIdentifier() {
        XCTAssertEqual(
            WorkbenchWindowController.windowIdentifier.rawValue,
            "PasteDeckWorkbenchWindow"
        )
        XCTAssertEqual(
            WorkbenchSearchFieldIdentifier.rawValue,
            "PasteDeck.Workbench.SearchField"
        )
        let listMode = WorkbenchFocusZone.list
        let searchMode = WorkbenchFocusZone.search
        XCTAssertNotEqual(listMode, searchMode)
    }

    /// 子窗口关闭冷却保护：触发记录后立即可检测到处于冷却期，防止误关底层父窗口。
    func testWindowCloseCooldownDetection() {
        WindowCloseCooldown.recordChildWindowClosed()
        XCTAssertTrue(WindowCloseCooldown.isInCooldown)
    }

    /// 统一关闭分发器：记录关闭后进入冷却保护，确保 ⌘W 与 Esc 严格单层消费。
    func testCloseWindowDispatcherCooldown() {
        CloseWindowDispatcher.recordClose()
        XCTAssertTrue(CloseWindowDispatcher.isInCooldown)
    }
}

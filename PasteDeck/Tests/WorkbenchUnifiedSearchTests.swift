import XCTest
@testable import PasteDeck
import SwiftData

@MainActor
final class WorkbenchUnifiedSearchTests: XCTestCase {

    func testUnifiedSearchCoordinatesToolsAndHistory() {
        let coordinator = UnifiedSearchCoordinator()

        // 搜索 "ip" 时应匹配到 IP / 子网工具
        coordinator.searchText = "ip"
        XCTAssertTrue(coordinator.isSearching)
        XCTAssertFalse(coordinator.toolMatches.isEmpty)

        let firstTool = coordinator.toolMatches.first
        XCTAssertEqual(firstTool?.tool, .ipv4Subnet)

        // 统一结果中包含工具
        XCTAssertFalse(coordinator.unifiedEntries.isEmpty)
        if case .tool(let match) = coordinator.unifiedEntries.first {
            XCTAssertEqual(match.tool, .ipv4Subnet)
        } else {
            XCTFail("首个条目应为工具")
        }
    }

    func testUnifiedSearchNavigationBounds() {
        let coordinator = UnifiedSearchCoordinator()
        coordinator.searchText = "时间"

        XCTAssertTrue(coordinator.isSearching)
        XCTAssertFalse(coordinator.unifiedEntries.isEmpty)

        coordinator.select(index: 0)
        XCTAssertEqual(coordinator.selectedIndex, 0)

        // 向上越界保持为 0
        coordinator.moveUp()
        XCTAssertEqual(coordinator.selectedIndex, 0)

        // 向下移动
        if coordinator.unifiedEntries.count > 1 {
            coordinator.moveDown()
            XCTAssertEqual(coordinator.selectedIndex, 1)
        }
    }

    func testWorkbenchDestinationsProvideValidMetadata() {
        let destinations: [WorkbenchDestination] = [
            .history,
            .favorites,
            .toolCenter,
            .recentTools,
            .smartCategory(.text),
            .smartCategory(.image),
            .smartCategory(.markdown)
        ]

        for dest in destinations {
            XCTAssertFalse(dest.id.isEmpty)
            XCTAssertFalse(dest.title.isEmpty)
            XCTAssertFalse(dest.iconName.isEmpty)
        }
    }

    func testToolRegistryDiscoversAllBuiltinTools() {
        let tools = ToolRegistry.allTools
        XCTAssertEqual(tools.count, 3)

        let ids = Set(tools.map(\.id))
        XCTAssertTrue(ids.contains(BuiltinTool.timestampConversion.id))
        XCTAssertTrue(ids.contains(BuiltinTool.ipv4Subnet.id))
        XCTAssertTrue(ids.contains(BuiltinTool.quotaOverview.id))
    }
}

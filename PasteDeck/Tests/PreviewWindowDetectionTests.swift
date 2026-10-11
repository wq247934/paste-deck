//
//  PreviewWindowDetectionTests.swift
//  PasteDeck
//
//  记录预览窗口检测的根因：themeStyled() 之后 hosting view 的泛型类型
//  不再是 NSHostingView<PreviewWindow>，旧的类型检测必然失败，
//  必须改用窗口 identifier 检测。
//

import AppKit
import SwiftUI
import XCTest
@testable import PasteDeck

@MainActor
final class PreviewWindowDetectionTests: XCTestCase {

    func testThemedPreviewHostingViewDoesNotMatchLegacyTypeCheck() {
        let item = ClipboardItem(contentType: .text, textContent: "x")
        let view = PreviewWindow(item: item, windowSize: CGSize(width: 10, height: 10), allowsResizing: true, onClose: nil)
        let controller = NSHostingController(rootView: view.themeStyled())
        _ = controller.view // 触发 AppKit 加载 hosting view

        XCTAssertFalse(
            controller.view is NSHostingView<PreviewWindow>,
            "themeStyled() 包裹后运行时类型是 NSHostingView<ModifiedContent<...>>，旧类型检测恒为 false"
        )
    }

    func testPreviewWindowIdentifierIsStable() {
        XCTAssertEqual(
            previewWindowIdentifier,
            NSUserInterfaceItemIdentifier("PasteDeckPreviewWindow"),
            "identifier 被主面板失焦保护依赖，值必须保持稳定"
        )
    }
}

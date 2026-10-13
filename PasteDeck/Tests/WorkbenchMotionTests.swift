//
//  WorkbenchMotionTests.swift
//  PasteDeckTests
//
//  工作台玻璃动效的纯几何数学测试：胶囊拉伸与指标数字滚动。
//  动效本身由 SwiftUI 驱动无法断言，因此把数学抽成纯函数后在此验证。
//

import XCTest
import SwiftData
@testable import PasteDeck

final class PillStretchMetricsTests: XCTestCase {

    // MARK: - Direction

    func testDirectionDetectsDownwardMove() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 60, width: 180, height: 28)

        XCTAssertEqual(PillStretchMetrics.direction(from: start, to: end), .forward)
    }

    func testDirectionDetectsUpwardMove() {
        let start = CGRect(x: 0, y: 120, width: 180, height: 28)
        let end = CGRect(x: 0, y: 20, width: 180, height: 28)

        XCTAssertEqual(PillStretchMetrics.direction(from: start, to: end), .backward)
    }

    func testDirectionIsNoneWhenRowDoesNotMove() {
        let row = CGRect(x: 0, y: 40, width: 180, height: 28)

        XCTAssertEqual(PillStretchMetrics.direction(from: row, to: row), .none)
    }

    func testDirectionIsNoneForHorizontalAxis() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 28)
        let end = CGRect(x: 80, y: 0, width: 100, height: 28)

        // Stretch applies to the vertical axis; a horizontal capsule never stretches.
        XCTAssertEqual(PillStretchMetrics.direction(from: start, to: end, axis: .horizontal), .none)
    }

    // MARK: - Scale

    func testScaleIsNeutralAtBothEndsOfTravel() {
        XCTAssertEqual(PillStretchMetrics.scale(along: .forward, progress: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(PillStretchMetrics.scale(along: .forward, progress: 1), 1, accuracy: 1e-9)
    }

    func testScalePeaksAtMidTravel() {
        let mid = PillStretchMetrics.scale(along: .forward, progress: 0.5)

        XCTAssertEqual(mid, 1 + WorkbenchMotion.pillMaxStretch, accuracy: 1e-9)
    }

    func testScaleIsAlwaysGreaterMidTravelThanAtEnds() {
        let start = PillStretchMetrics.scale(along: .backward, progress: 0)
        let quarter = PillStretchMetrics.scale(along: .backward, progress: 0.25)
        let mid = PillStretchMetrics.scale(along: .backward, progress: 0.5)

        XCTAssertGreaterThan(quarter, start)
        XCTAssertGreaterThan(mid, quarter)
    }

    func testScaleIsNeutralWhenNotMoving() {
        XCTAssertEqual(PillStretchMetrics.scale(along: .none, progress: 0.5), 1, accuracy: 1e-9)
    }

    func testScaleClampsProgressOutsideUnitRange() {
        let before = PillStretchMetrics.scale(along: .forward, progress: -3)
        let after = PillStretchMetrics.scale(along: .forward, progress: 4)

        XCTAssertEqual(before, 1, accuracy: 1e-9)
        XCTAssertEqual(after, 1, accuracy: 1e-9)
    }

    // MARK: - Resolved Frame

    func testResolvedFrameMatchesTargetWhenTravelCompletes() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let settled = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 1,
            direction: .forward
        )

        XCTAssertEqual(settled.minY, end.minY, accuracy: 1e-9)
        XCTAssertEqual(settled.height, end.height, accuracy: 1e-9)
    }

    func testResolvedFrameStretchesTallestAtMidTravel() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let mid = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.5,
            direction: .forward
        )
        let quarter = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.25,
            direction: .forward
        )

        XCTAssertGreaterThan(mid.height, quarter.height)
        XCTAssertGreaterThan(mid.height, start.height)
    }

    func testResolvedFrameKeepsWidthUnchangedWhileStretchingVertically() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let mid = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.5,
            direction: .forward
        )

        XCTAssertEqual(mid.width, start.width, accuracy: 1e-9)
    }

    func testResolvedFrameStretchesSymmetricallyAroundInterpolatedCentre() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let mid = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.5,
            direction: .forward
        )

        // Symmetric stretch must not shift the centre away from the linear path.
        let linearMidY = start.midY + (end.midY - start.midY) * 0.5
        XCTAssertEqual(mid.midY, linearMidY, accuracy: 1e-9)
    }

    func testResolvedFrameExtendsBothEdgesEquallyWhileStretching() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let linear = CGRect(
            x: 0,
            y: start.minY + (end.minY - start.minY) * 0.5,
            width: 180,
            height: 28
        )
        let stretched = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.5,
            direction: .forward
        )

        let topGrowth = linear.minY - stretched.minY
        let bottomGrowth = stretched.maxY - linear.maxY
        XCTAssertGreaterThan(topGrowth, 0)
        XCTAssertEqual(topGrowth, bottomGrowth, accuracy: 1e-9)
    }

    func testResolvedFrameDoesNotStretchWithoutDirection() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        let mid = PillStretchMetrics.resolvedFrame(
            start: start,
            end: end,
            progress: 0.5,
            direction: .none
        )

        // With no direction there is no stretch; the frame is the plain
        // interpolated rect. Both rows are 28pt tall, so height stays 28.
        XCTAssertEqual(mid.midY, 50, accuracy: 1e-9)
        XCTAssertEqual(mid.height, 28, accuracy: 1e-9)
    }

    func testResolvedFrameStaysMonotonicBetweenConsecutiveTravelSteps() {
        let start = CGRect(x: 0, y: 0, width: 180, height: 28)
        let end = CGRect(x: 0, y: 72, width: 180, height: 28)

        var previousY: CGFloat = -.greatestFiniteMagnitude
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let frame = PillStretchMetrics.resolvedFrame(
                start: start,
                end: end,
                progress: progress,
                direction: .forward
            )
            XCTAssertGreaterThanOrEqual(frame.midY, previousY - 1e-9)
            previousY = frame.midY
        }
    }
}

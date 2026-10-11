// Regression test for the context-panel resize handle.
//
// Reproduces the exact failure: on a fresh install the width key is never
// written, so UserDefaults returns 0. The old hitTest guard rejected that and
// returned nil everywhere => the handle was permanently dead.
import XCTest
@testable import PasteDeck

@MainActor
final class PanelResizeHandleTests: XCTestCase {

    private func withCleanDefaults(_ body: () -> Void) {
        let key = PanelResizeHandleState.widthDefaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            // The singleton outlives each test; restore a known-good state so
            // ordering never leaks a width from a previous case.
            PanelResizeHandleState.shared.setEnabled(false)
            PanelResizeHandleState.shared.updateWidthDuringDrag(PanelResizeHandleState.defaultWidth)
        }
        body()
    }

    /// Puts the shared state into a deterministic starting condition:
    /// no persisted key, sidebar enabled at the default width.
    private func primeSharedState() {
        let state = PanelResizeHandleState.shared
        state.setEnabled(true)
        state.updateWidthDuringDrag(PanelResizeHandleState.defaultWidth)
    }

    /// The regression: with no persisted width, the handle must still be active
    /// and must claim the strip at the sidebar's left edge.
    func testStripIsHitTestableWhenWidthKeyWasNeverPersisted() {
        withCleanDefaults {
            primeSharedState()

            let overlay = PanelResizeHandleOverlayView()
            overlay.frame = NSRect(x: 0, y: 0, width: 800, height: 400)

            let sidebarLeftEdge = 800 - 10 - PanelResizeHandleState.defaultWidth
            let onEdge = overlay.hitTest(NSPoint(x: sidebarLeftEdge, y: 200))

            XCTAssertTrue(
                onEdge === overlay,
                "handle must claim the sidebar left edge even with no persisted width"
            )
        }
    }

    /// Outside the strip the overlay must not intercept, so the rest of the
    /// panel keeps receiving clicks.
    func testHitTestPassesThroughOutsideTheStrip() {
        withCleanDefaults {
            primeSharedState()

            let overlay = PanelResizeHandleOverlayView()
            overlay.frame = NSRect(x: 0, y: 0, width: 800, height: 400)

            XCTAssertNil(overlay.hitTest(NSPoint(x: 100, y: 200)))
            // Middle of the sidebar body must not be a handle.
            XCTAssertNil(overlay.hitTest(NSPoint(x: sidebarLeftEdge() + 150, y: 200)))
        }
    }

    private func sidebarLeftEdge() -> CGFloat {
        800 - 10 - PanelResizeHandleState.defaultWidth
    }

    /// A hidden sidebar must not swallow any clicks.
    func testHitTestIsNilWhenSidebarHidden() {
        withCleanDefaults {
            let state = PanelResizeHandleState.shared
            state.setEnabled(false)
            state.updateWidthDuringDrag(PanelResizeHandleState.defaultWidth)

            let overlay = PanelResizeHandleOverlayView()
            overlay.frame = NSRect(x: 0, y: 0, width: 800, height: 400)

            XCTAssertNil(overlay.hitTest(NSPoint(x: sidebarLeftEdge(), y: 200)))
            state.setEnabled(true)
        }
    }

    /// Width is clamped to the supported range.
    func testWidthIsClampedToSupportedRange() {
        withCleanDefaults {
            let state = PanelResizeHandleState.shared
            state.updateWidthDuringDrag(100)
            XCTAssertEqual(state.width, PanelResizeHandleState.widthRange.lowerBound)

            state.updateWidthDuringDrag(5000)
            XCTAssertEqual(state.width, PanelResizeHandleState.widthRange.upperBound)

            state.updateWidthDuringDrag(320)
            XCTAssertEqual(state.width, 320)
        }
    }

    /// Dragging updates memory live and only persists on mouseUp.
    func testDragWritesOnlyOnMouseUp() {
        withCleanDefaults {
            let state = PanelResizeHandleState.shared
            state.setEnabled(true)
            state.refreshPersistedWidth()

            state.updateWidthDuringDrag(400)
            XCTAssertEqual(state.width, 400)
            XCTAssertNil(
                UserDefaults.standard.object(forKey: PanelResizeHandleState.widthDefaultsKey),
                "drag must not write to UserDefaults on every mouseDragged"
            )

            state.persistWidth()
            XCTAssertEqual(
                UserDefaults.standard.double(forKey: PanelResizeHandleState.widthDefaultsKey),
                400
            )
        }
    }

    /// An out-of-range persisted value must fall back to the default rather
    /// than poisoning the strip geometry.
    func testRestoredWidthFallsBackWhenOutOfRange() {
        let key = PanelResizeHandleState.widthDefaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            PanelResizeHandleState.shared.setEnabled(false)
        }

        UserDefaults.standard.set(9_999.0, forKey: key)
        XCTAssertEqual(
            PanelResizeHandleState.restoredWidth(),
            PanelResizeHandleState.defaultWidth
        )

        UserDefaults.standard.set(300.0, forKey: key)
        XCTAssertEqual(PanelResizeHandleState.restoredWidth(), 300.0)
    }

    /// The singleton only initialises once, so a width persisted in a previous
    /// run must be re-read when the panel is shown again. Regression guard for
    /// a stale in-memory width silently overriding the persisted one.
    func testRefreshPersistedWidthPicksUpExternalChanges() {
        withCleanDefaults {
            let state = PanelResizeHandleState.shared

            state.updateWidthDuringDrag(300)
            UserDefaults.standard.set(380.0, forKey: PanelResizeHandleState.widthDefaultsKey)
            XCTAssertEqual(state.width, 300,
                           "before refresh the singleton keeps its in-memory value")

            state.refreshPersistedWidth()
            XCTAssertEqual(state.width, 380.0,
                           "refreshPersistedWidth must adopt the persisted width")
        }
    }
}

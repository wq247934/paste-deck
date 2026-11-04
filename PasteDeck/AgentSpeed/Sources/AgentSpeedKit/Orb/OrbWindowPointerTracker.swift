import AppKit

/// Event-driven pointer tracking for the orb: global monitors see the pointer while the panel ignores the mouse
/// (events go to other apps), local monitors while it is over our own windows. No timers, no polling.
@MainActor
final class OrbWindowPointerTracker {
    /// Pointer location in screen coordinates, and whether the event was a plain move (no button held).
    var onMove: ((NSPoint, Bool) -> Void)?

    /// True while another app is tracking a mouse drag, so the disc must not grab the pointer mid-drag.
    private(set) var isForeignDragActive = false

    private static let events: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp,
    ]

    nonisolated(unsafe) private var monitors: [Any] = []

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, foreign: true) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, foreign: false) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isForeignDragActive = false
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func handle(_ event: NSEvent, foreign: Bool) {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: isForeignDragActive = foreign
        case .mouseMoved: isForeignDragActive = false
        default: isForeignDragActive = foreign && NSEvent.pressedMouseButtons != 0
        }
        onMove?(NSEvent.mouseLocation, event.type == .mouseMoved)
    }
}

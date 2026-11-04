import AppKit

/// Reports whether the system currently lets the panel be seen: not fully occluded, displays awake and the user
/// session active. The renderer pauses whenever this is false.
@MainActor
final class OrbWindowVisibilityMonitor {
    var onChange: (() -> Void)?

    /// Read live: a window shown while already covered gets no occlusion notification, because its state does not
    /// change.
    var isOccluded: Bool {
        guard let window, window.isVisible else { return false }
        return !window.occlusionState.contains(.visible)
    }
    private(set) var screensAsleep = false
    private(set) var sessionInactive = false

    private weak var window: NSWindow?
    nonisolated(unsafe) private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(window: NSWindow) {
        self.window = window
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(center, NSWindow.didChangeOcclusionStateNotification, object: window) { _ in }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    var allowsVisibility: Bool { !isOccluded && !screensAsleep && !sessionInactive }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        update: @escaping @MainActor (OrbWindowVisibilityMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        tokens.append((center, token))
    }
}

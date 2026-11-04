import AppKit
import Observation

/// Mirrors the system display accessibility options and updates live.
@MainActor
@Observable
public final class AccessibilityState {
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    #if DEBUG
    /// `AGENT_SPEED_REDUCE_MOTION=1` (debug builds): behave as if Reduce Motion were on, for the motion harness.
    private static let forcesReduceMotion = ProcessInfo.processInfo.environment["AGENT_SPEED_REDUCE_MOTION"] == "1"
    #else
    private static let forcesReduceMotion = false
    #endif

    /// Effects level after applying Reduce Motion (caps at Soft).
    func effectiveLevel(_ level: EffectsLevel) -> EffectsLevel {
        reduceMotion ? min(level, .soft) : level
    }

    private func refresh() {
        let workspace = NSWorkspace.shared
        let shouldReduceMotion = workspace.accessibilityDisplayShouldReduceMotion || Self.forcesReduceMotion
        if reduceMotion != shouldReduceMotion {
            reduceMotion = shouldReduceMotion
        }
        if reduceTransparency != workspace.accessibilityDisplayShouldReduceTransparency {
            reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        }
        if increaseContrast != workspace.accessibilityDisplayShouldIncreaseContrast {
            increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        }
    }
}

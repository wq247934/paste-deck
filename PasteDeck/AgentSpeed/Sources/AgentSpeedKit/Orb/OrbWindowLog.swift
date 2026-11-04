import Foundation

/// Opt-in diagnostics for window placement: run with `AGENT_SPEED_DEBUG_ORB=1` to print to stderr.
enum OrbWindowLog {
    static let isEnabled = ProcessInfo.processInfo.environment["AGENT_SPEED_DEBUG_ORB"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        FileHandle.standardError.write(Data(("[orb] " + message() + "\n").utf8))
    }

    static func describe(_ rect: CGRect) -> String {
        String(format: "(%.1f, %.1f, %.1f × %.1f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func describe(_ point: CGPoint) -> String {
        String(format: "(%.1f, %.1f)", point.x, point.y)
    }
}

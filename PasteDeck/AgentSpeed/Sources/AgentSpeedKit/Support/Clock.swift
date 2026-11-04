import Foundation

enum Clock {
    /// Shared time base for springs, animations and timeline frames.
    static var now: TimeInterval { Date().timeIntervalSinceReferenceDate }
}

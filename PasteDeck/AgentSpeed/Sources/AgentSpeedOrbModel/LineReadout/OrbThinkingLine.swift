import Foundation

/// The intelligence readout's thinking line, shown only while its rate reads above 0 (DESIGN 10, Thinking hidden at
/// zero): at `0` it stays drawn for 3 s, then fades out (0.25 s) while the intelligence line glides (0.3 s) to the
/// single-line position; a rate above 0 brings it back at once, in reverse. A reversal part-way starts each motion
/// from where it stands, so neither jumps. Times are monotonic seconds (the app clock).
public struct OrbThinkingLine: Equatable, Sendable {
    public static let hold: TimeInterval = 3
    public static let fade: TimeInterval = 0.25
    public static let glide: TimeInterval = 0.3

    /// Going toward the single line, or holding before it.
    public private(set) var hiding = false
    /// Starts of the fade and the glide toward the current side; −∞ while the line has always been shown.
    public private(set) var fadeFrom = -TimeInterval.infinity
    public private(set) var glideFrom = -TimeInterval.infinity

    public init() {}

    /// A rate as shown (METRICS 7) that reads 0: `0`, `0.0`.
    public static func readsZero(_ shown: String) -> Bool {
        !shown.isEmpty && shown.allSatisfy { $0 == "0" || $0 == "." }
    }

    /// Applies the shown rate at `time`; returns whether anything changed.
    @discardableResult
    public mutating func update(zero: Bool, at time: TimeInterval) -> Bool {
        guard zero != hiding else { return false }
        hiding = zero
        if zero {
            fadeFrom = time + Self.hold
            glideFrom = fadeFrom
        } else if time < fadeFrom {
            // Back within the hold: nothing moved.
            fadeFrom = -.infinity
            glideFrom = -.infinity
        } else {
            fadeFrom = time - (1 - Self.progress(time, from: fadeFrom, over: Self.fade)) * Self.fade
            glideFrom = time - (1 - Self.progress(time, from: glideFrom, over: Self.glide)) * Self.glide
        }
        return true
    }

    /// The thinking line's opacity; Reduce Motion makes the fade instant.
    public func alpha(at time: TimeInterval, reduceMotion: Bool) -> Double {
        let done = Self.progress(time, from: fadeFrom, over: reduceMotion ? 0 : Self.fade)
        return hiding ? 1 - done : done
    }

    /// How far the intelligence line has glided toward the single-line position, linear 0...1 (ease with smoothstep);
    /// Reduce Motion moves it at once.
    public func single(at time: TimeInterval, reduceMotion: Bool) -> Double {
        let done = Self.progress(time, from: glideFrom, over: reduceMotion ? 0 : Self.glide)
        return hiding ? done : 1 - done
    }

    /// Past the hold: the line is going or gone, and accessibility reads the intelligence alone.
    public func isHidden(at time: TimeInterval) -> Bool { hiding && time >= fadeFrom }

    /// The fade or the glide runs at `time`; under Reduce Motion each step still takes `step` for its frame.
    public func isMoving(at time: TimeInterval, step: TimeInterval? = nil) -> Bool {
        (time >= fadeFrom && time < fadeFrom + (step ?? Self.fade)) || (time >= glideFrom && time < glideFrom + (step ?? Self.glide))
    }

    /// When the hold ends, for a still surface to wake; nil when nothing is due after `time`.
    public func holdEnd(after time: TimeInterval) -> TimeInterval? { hiding && time < fadeFrom ? fadeFrom : nil }

    private static func progress(_ time: TimeInterval, from start: TimeInterval, over duration: TimeInterval) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }
}

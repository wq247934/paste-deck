import Foundation

/// The pure numbers of the `needle` style (DESIGN 2a.2): the dial, the needle's spring with its stop pins, the tremble,
/// the wake, the shift lights, the peg sparks and the new-peak sweep. Dial positions `n` use the LED's 270° scale.
public enum NeedleMath {
    /// The red zone starts at the redline-tier threshold: `0.75^0.6`.
    public static let redZoneStart = pow(0.75, 0.6)
    /// The stop pins the needle's edge touches.
    public static let zeroStop = -0.012
    public static let pegStop = 1.012
    /// Where the stop pins are drawn.
    public static let zeroPin = -0.034
    public static let pegPin = 1.034
    /// Where peg sparks start: the contact point between the needle and the peg pin.
    public static let contact = 1.024
    /// The needle lights the shift lamps one by one from here; the last one is the red-zone start.
    public static let lampThresholds: [Double] = [0.70, 0.735, 0.77, 0.805, redZoneStart]
    /// Lamp angles (degrees, clockwise from 3 o'clock).
    public static let lampAngles: [Double] = [-110, -100, -90, -80, -70]
    public static let graduationCount = 41
    public static let wakeThreshold = 12.0
    /// Above this angular speed (°/s) the needle needs 60 fps even at cruise.
    public static let fastTurn = 90.0
    public static let trembleFrequencies = (11.3, 17.9, 26.1)
    public static let lampFlashHz = 3.0
    public static let peakSweepDuration = 1.0
    public static let tipFlareDuration = 0.35

    /// Angle (degrees, clockwise from 3 o'clock in screen space) of dial position `n`.
    public static func angle(_ n: Double) -> Double { 135 + 270 * n }

    /// Dial position of graduation `k` (0...40); every 5th is major.
    public static func graduation(_ k: Int) -> Double { Double(k) / 40 }
    public static func isMajor(_ k: Int) -> Bool { k % 5 == 0 }

    /// The spring's target: `h_raw` (0 at idle), plus `0.02 + 0.05 o_raw` while `o_raw > 0` so it presses into the peg.
    public static func target(rawHeat: Double, rawOverdrive: Double, idle: Bool) -> Double {
        guard !idle else { return 0 }
        return rawHeat + (rawOverdrive > 0 ? 0.02 + 0.05 * rawOverdrive : 0)
    }

    /// Off and Reduce Motion: the needle follows the smoothed `h` (and presses the peg beyond the redline).
    public static func direct(heat: Double, overdrive: Double) -> Double {
        min(pegStop, max(zeroStop, heat + (overdrive > 0 ? 0.02 + 0.05 * overdrive : 0)))
    }

    /// The needle's underdamped spring: 1.5 Hz, damping ratio 0.55 (≈ 12 % overshoot on a step), integrated in
    /// sub-steps of at most 1/480 s; hitting a stop reverses the velocity × −0.32.
    public struct Spring: Equatable, Sendable {
        public static let frequency = 1.5
        public static let damping = 0.55
        public static let bounce = -0.32
        public static let maximumStep = 1.0 / 480

        public var position: Double
        public var velocity: Double

        public init(position: Double = 0, velocity: Double = 0) {
            self.position = position
            self.velocity = velocity
        }

        public mutating func step(toward target: Double, dt: Double) {
            guard dt > 0 else { return }
            let omega = 2 * Double.pi * Self.frequency
            let count = max(1, Int((dt / Self.maximumStep).rounded(.up)))
            let h = dt / Double(count)
            for _ in 0..<count {
                let acceleration = -omega * omega * (position - target) - 2 * Self.damping * omega * velocity
                velocity += acceleration * h
                position += velocity * h
                if position > NeedleMath.pegStop {
                    position = NeedleMath.pegStop
                    if velocity > 0 { velocity *= Self.bounce }
                }
                if position < NeedleMath.zeroStop {
                    position = NeedleMath.zeroStop
                    if velocity < 0 { velocity *= Self.bounce }
                }
            }
        }

        /// Snaps to a position at rest.
        public mutating func reset(to position: Double) {
            self.position = min(NeedleMath.pegStop, max(NeedleMath.zeroStop, position))
            velocity = 0
        }

        public func isSettled(at target: Double) -> Bool {
            let clampedTarget = min(NeedleMath.pegStop, max(NeedleMath.zeroStop, target))
            return abs(position - clampedTarget) < 0.0008 && abs(velocity) < 0.004
        }
    }

    /// Tremble amplitude in degrees: `smoothstep(0.55, 1, h) × (0.3° + 1.0° o)`, × 1.4 at Max.
    public static func trembleAmplitude(heat: Double, overdrive: Double, max: Bool) -> Double {
        smoothstep(0.55, 1, heat) * (0.3 + 1.0 * overdrive) * (max ? 1.4 : 1)
    }

    /// Tremble offset in degrees for accumulated phases (radians) at 11.3 / 17.9 / 26.1 Hz.
    public static func trembleOffset(amplitude: Double, phases: (Double, Double, Double)) -> Double {
        amplitude * (0.5 * sin(phases.0) + 0.3 * sin(phases.1 + 1.3) + 0.2 * sin(phases.2 + 2.1))
    }

    /// The displayed needle: spring plus tremble, clamped by the stops.
    public static func displayed(spring: Double, trembleDegrees: Double) -> Double {
        min(pegStop, max(zeroStop, spring + trembleDegrees / 270))
    }

    /// The wake trails the needle by `4° + 0.085 s × |ω|`, at most 55°, while it turns faster than 12°/s.
    public static func wakeLength(angularSpeed: Double) -> Double {
        abs(angularSpeed) > wakeThreshold ? min(55, 4 + 0.085 * abs(angularSpeed)) : 0
    }

    /// Pinned against the peg: the needle at the peg while the target presses beyond it.
    public static func isPinned(needle: Double, target: Double) -> Bool {
        needle >= 1.0105 && target > pegStop
    }

    /// Peg sparks per second while pinned (Standard and up): `25 + 70 o`, × 1.6 at Max.
    public static func pegSparkRate(overdrive: Double, max: Bool) -> Double {
        (25 + 70 * overdrive) * (max ? 1.6 : 1)
    }

    public static func pegSparkPool(max: Bool) -> Int { max ? 80 : 48 }

    /// Shift lamp `index` is lit once the needle passes its threshold.
    public static func lampLit(_ index: Int, needle: Double) -> Bool {
        needle >= lampThresholds[index]
    }

    /// Brightness of the lamps flashing together at the redline: 28 → 100 % through `smoothstep(−0.35, 0.35, sin φ)`.
    public static func lampFlash(phase: Double) -> Double {
        0.28 + 0.72 * smoothstep(-0.35, 0.35, sin(phase))
    }

    /// The new-peak gauge sweep: the needle swings to the peg and back over 1 s, like an instrument cluster start-up.
    public static func peakSweep(_ n: Double, age: Double) -> Double {
        guard age >= 0, age < peakSweepDuration else { return n }
        return n + (pegStop - n) * (smoothstep(0, 0.38, age) - smoothstep(0.5, 1.0, age))
    }

    /// Red-zone pulse frequency at the redline (Hz).
    public static func redZonePulseHz(overdrive: Double) -> Double { 2 + overdrive }

    /// Red-zone glow σ in diameters (Standard and Max, redline tier).
    public static func redZoneGlowSigma(overdrive: Double, max: Bool) -> Double {
        0.025 * (0.6 + 0.4 * overdrive) * (max ? 1.3 : 1)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

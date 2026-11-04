import Foundation

/// Rolling-digit state of the value readout: the shown string and the transition from the previous one.
struct OrbRollingReadout {
    static let duration: TimeInterval = 0.24

    private(set) var current = "0"
    private(set) var previous: String?
    private(set) var changedAt: TimeInterval = -.infinity
    private(set) var rising = true
    private var value = 0.0

    mutating func update(_ text: String, value: Double, at time: TimeInterval) {
        guard text != current else {
            self.value = value
            return
        }
        previous = current
        rising = value >= self.value
        current = text
        changedAt = time
        self.value = value
    }

    mutating func reset(_ text: String, value: Double) {
        current = text
        previous = nil
        changedAt = -.infinity
        self.value = value
    }

    /// 0 at the change, 1 when settled (critically damped ease).
    func progress(at time: TimeInterval) -> Double {
        let t = (time - changedAt) / Self.duration
        guard t < 1 else { return 1 }
        guard t > 0 else { return 0 }
        let x = t * 5.5
        return min(1, 1 - (1 + x) * exp(-x))
    }
}

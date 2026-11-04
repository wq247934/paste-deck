import Foundation

/// A board's history of `live_A` (DESIGN 2c Hero): one value per second, the latest of that second, oldest first,
/// at most 60. Seconds without a tick (sleep, a stalled engine) repeat the value that follows them.
public struct BoardHistory: Equatable, Sendable {
    public static let capacity = 60

    public private(set) var values: [Double] = []
    private var second: Int64?

    public init() {}

    public mutating func record(_ value: Double, atMs ms: Int64) {
        let value = value.isFinite ? max(0, value) : 0
        let now = Int64((Double(ms) / 1000).rounded(.down))
        defer { second = now }
        guard let second, now >= second else {
            values = [value]
            return
        }
        if now == second, !values.isEmpty {
            values[values.count - 1] = value
            return
        }
        let missed = min(Int(now - second), Self.capacity)
        values.append(contentsOf: repeatElement(value, count: missed))
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }

    public mutating func reset() {
        values.removeAll()
        second = nil
    }
}

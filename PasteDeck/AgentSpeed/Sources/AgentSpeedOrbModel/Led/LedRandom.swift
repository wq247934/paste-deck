import Foundation

/// The random source of every `led` effect: an xorshift64* generator, or a fixed sequence replayed in a loop (tests).
public struct LedRandom: Sendable {
    private var state: UInt64
    private let sequence: [Double]
    private var index = 0

    public init(seed: UInt64) {
        state = Self.scramble(seed)
        sequence = []
    }

    /// Replays `sequence` (values clamped into 0..<1) in a loop; an empty sequence falls back to a seeded generator.
    public init(sequence: [Double]) {
        let largest = 1.0.nextDown
        state = Self.scramble(0)
        self.sequence = sequence.map { $0.isFinite ? min(max($0, 0), largest) : 0 }
    }

    /// A value in 0..<1.
    public mutating func next() -> Double {
        if !sequence.isEmpty {
            let value = sequence[index]
            index = index + 1 == sequence.count ? 0 : index + 1
            return value
        }
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) * 0x1p-53
    }

    public mutating func range(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + (r.upperBound - r.lowerBound) * next()
    }

    /// splitmix64 finalizer, so nearby seeds start far apart and the state is never zero.
    private static func scramble(_ seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return z == 0 ? 0x9E37_79B9_7F4A_7C15 : z
    }
}

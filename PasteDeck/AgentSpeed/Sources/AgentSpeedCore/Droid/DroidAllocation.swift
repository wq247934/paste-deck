import Foundation

/// The five counters of a sidecar's `tokenUsage`, each a token value of METRICS 3.2 (so at most 10^12).
struct DroidCounters: Equatable, Sendable {
    var input: Int64 = 0
    var cacheCreation: Int64 = 0
    var cacheRead: Int64 = 0
    var output: Int64 = 0
    var thinking: Int64 = 0

    static let zero = DroidCounters()

    /// In the order of METRICS 4.16; the first three are split by the input weight, the last two by the output weight.
    static var fields: [WritableKeyPath<DroidCounters, Int64>] { [\.input, \.cacheCreation, \.cacheRead, \.output, \.thinking] }
    static let inputFieldCount = 3

    var isZero: Bool { self == .zero }

    /// Field by field `max(0, self − other)`.
    func subtracting(_ other: DroidCounters) -> DroidCounters {
        var result = DroidCounters()
        for field in Self.fields { result[keyPath: field] = max(0, self[keyPath: field] - other[keyPath: field]) }
        return result
    }

    /// The normalized usage of a share (METRICS 4.16 Tokens): cache reads and writes count as input, reasoning inside
    /// output.
    var tokens: TokenUsage {
        TokenUsage(
            input: TokenCount.sum(Int(input), Int(cacheCreation), Int(cacheRead)),
            cachedInput: Int(cacheRead),
            cacheWriteInput: Int(cacheCreation),
            cacheWrite1hInput: 0,
            output: Int(output),
            reasoning: Int(thinking)
        )
    }
}

/// Splits counter growth over calls by their weights (METRICS 4.16 Allocation).
enum DroidAllocation {
    /// Both weights are capped here, so a share's product `total · weight` stays below 2^63.
    static let maxWeight: Int64 = 8_388_608
    /// Stands in for droid's system prompt and tool schemas, which the transcript does not hold.
    static let contextBase: Int64 = 65_536

    /// Largest-remainder rounding in exact integers: `⌊total · w_i / W⌋` each, then one unit each to the largest
    /// remainders `total · w_i mod W`, ties to the earlier weight.
    static func shares(of total: Int64, weights: [Int64]) -> [Int64] {
        let whole = weights.reduce(0, +)
        guard total > 0, whole > 0 else { return weights.map { _ in 0 } }
        var shares: [Int64] = []
        var remainders: [Int64] = []
        shares.reserveCapacity(weights.count)
        remainders.reserveCapacity(weights.count)
        for weight in weights {
            let product = total * weight
            shares.append(product / whole)
            remainders.append(product % whole)
        }
        let left = Int(total - shares.reduce(0, +))
        guard left > 0 else { return shares }
        let ranked = weights.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for index in ranked.prefix(left) { shares[index] += 1 }
        return shares
    }

    /// `growth` split over calls with the given input and output weights, one share per call.
    static func allocate(_ growth: DroidCounters, inputWeights: [Int64], outputWeights: [Int64]) -> [DroidCounters] {
        var result = Array(repeating: DroidCounters(), count: inputWeights.count)
        for (position, field) in DroidCounters.fields.enumerated() {
            let weights = position < DroidCounters.inputFieldCount ? inputWeights : outputWeights
            for (index, share) in shares(of: growth[keyPath: field], weights: weights).enumerated() {
                result[index][keyPath: field] = share
            }
        }
        return result
    }
}

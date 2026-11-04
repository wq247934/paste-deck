import Foundation

/// Why responses have no price (METRICS 9.10). Computed with the current table whenever it is shown, never stored.
public enum UnpricedReason: String, CaseIterable, Sendable {
    case noModel
    case notInTable
    case noFastPrice
    case unpriceable
    /// Live only: the response's `endMs` has no date (METRICS 8).
    case noDate
}

/// The reason of one unpriced fact with the key the resolver stopped at and, for `unpriceable`, the table's rule text.
public struct UnpricedDiagnosis: Equatable, Sendable {
    public var reason: UnpricedReason
    public var canonical: String?
    public var rule: String?

    public init(reason: UnpricedReason, canonical: String? = nil, rule: String? = nil) {
        self.reason = reason
        self.canonical = canonical
        self.rule = rule
    }
}

/// An unpriced fact without its count (METRICS 9.10): the trimmed model (empty when none), the provider (nil when
/// missing or empty), the fast flag and, live only, whether the response had no date.
public struct UnpricedFactKey: Hashable, Sendable {
    public var model: String
    public var provider: String?
    public var fast: Bool
    public var noDate: Bool

    public init(model: String?, provider: String?, fast: Bool, noDate: Bool = false) {
        self.model = Self.trimmed(model)
        self.provider = provider.flatMap { $0.isEmpty ? nil : $0 }
        self.fast = fast
        self.noDate = noDate
    }

    /// *Trimmed* of METRICS 4.9: Python's `str.isspace()` whitespace removed at both ends; nil is empty.
    static func trimmed(_ text: String?) -> String {
        guard let text else { return "" }
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last,
              ModelResolver.isSpace(first) || ModelResolver.isSpace(last) else { return text }
        return String(String.UnicodeScalarView(ModelResolver.strip(scalars)))
    }

    /// The fact order of METRICS 9.10: the model's UTF-8 bytes, provider (nil first, then UTF-8 bytes), fast false
    /// first, then noDate false first.
    public static func precedes(_ lhs: UnpricedFactKey, _ rhs: UnpricedFactKey) -> Bool {
        if lhs.model != rhs.model { return lhs.model.utf8.lexicographicallyPrecedes(rhs.model.utf8) }
        if lhs.provider != rhs.provider {
            guard let left = lhs.provider else { return true }
            guard let right = rhs.provider else { return false }
            return left.utf8.lexicographicallyPrecedes(right.utf8)
        }
        if lhs.fast != rhs.fast { return !lhs.fast }
        return !lhs.noDate && rhs.noDate
    }
}

/// One unpriced fact with the requests it counts.
public struct UnpricedFact: Equatable, Sendable {
    public var key: UnpricedFactKey
    public var requests: Int

    public init(key: UnpricedFactKey, requests: Int) {
        self.key = key
        self.requests = requests
    }

    public var model: String { key.model }
    public var provider: String? { key.provider }
    public var fast: Bool { key.fast }
    public var noDate: Bool { key.noDate }

    /// The facts of a tally with a positive count, in the fact order.
    public static func list(_ tally: [UnpricedFactKey: Int]) -> [UnpricedFact] {
        tally.filter { $0.value > 0 }
            .map { UnpricedFact(key: $0.key, requests: $0.value) }
            .sorted { UnpricedFactKey.precedes($0.key, $1.key) }
    }
}

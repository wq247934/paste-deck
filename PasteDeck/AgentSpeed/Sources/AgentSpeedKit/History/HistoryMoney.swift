import AgentSpeedCore
import Foundation

/// What the daily chart and the single-day breakdown measure (DESIGN 9, Usage history: `history.chart.output` |
/// `history.chart.cost`).
public enum HistoryChartMetric: String, CaseIterable, Identifiable, Sendable {
    case output, cost, traffic

    public var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .output: "history.chart.output"
        case .cost: "history.chart.cost"
        case .traffic: "history.chart.traffic"
        }
    }
}

/// How costs count in the window (METRICS 9.4, DESIGN 9): the sources left out as subscriptions and the chart metric.
struct HistoryCostOptions: Equatable, Sendable {
    /// Sources marked as subscriptions in Settings.
    var marked: Set<SourceKind> = []
    /// The window's own `history.includeSubscriptions` choice.
    var includeSubscriptions = false
    var metric: HistoryChartMetric = .output

    /// Sources whose costs add nothing for `source` (every source when nil). A source selected directly always shows
    /// its own API-equivalent cost.
    func excluded(for source: SourceKind?) -> Set<SourceKind> {
        guard source == nil, !includeSubscriptions else { return [] }
        return marked
    }
}

/// Money of the window in the display currency, as a value so the content rebuilds when the currency, the language
/// or the rate changes. Every amount converts with the one rate in use (METRICS 9.8).
struct HistoryMoney: Equatable, Sendable {
    let currency: Currency
    let usd: Currency
    /// `zh-Hant`, `zh-Hans`, `en`, `ja`.
    let language: String
    /// Units of `currency` per US dollar.
    let rate: Decimal
    /// The currency's localized name (amounts read as `12.34 美元`).
    let currencyName: String

    init(currency: Currency, usd: Currency, language: String, rate: Decimal, currencyName: String) {
        self.currency = currency
        self.usd = usd
        self.language = language
        self.rate = rate
        self.currencyName = currencyName
    }

    @MainActor
    init(_ display: CostDisplay) {
        self.init(
            currency: display.currency,
            usd: display.currencies.currencyOrUSD(Currency.usdCode),
            language: display.language,
            rate: display.rate,
            currencyName: display.currencyName
        )
    }

    var isUSD: Bool { currency.code == Currency.usdCode }

    func formatted(_ microUsd: Int64) -> FormattedMoney {
        MoneyFormat.format(MoneyFormat.amount(microUsd: microUsd, rate: rate), currency: currency, language: language, form: .amount)
    }

    /// `$12.34`, `NT$1,235`.
    func amount(_ microUsd: Int64) -> String { formatted(microUsd).text }

    /// The amount in US dollars.
    func usdAmount(_ microUsd: Int64) -> String {
        MoneyFormat.format(MoneyFormat.amount(microUsd: microUsd, rate: 1), currency: usd, language: language, form: .amount).text
    }

    /// Tooltips: `NT$1,235（US$37.94）` for a non-USD currency (DESIGN 9).
    func amountWithUSD(_ microUsd: Int64) -> String {
        let text = amount(microUsd)
        guard !isUSD else { return text }
        return language == "en" ? "\(text) (\(usdAmount(microUsd)))" : "\(text)（\(usdAmount(microUsd))）"
    }

    /// The value in display units, for chart scales only (amounts are always formatted from decimals).
    func value(_ microUsd: Int64) -> Double {
        NSDecimalNumber(decimal: MoneyFormat.amount(microUsd: microUsd, rate: rate)).doubleValue
    }

    /// micro-USD for a value in display units (axis ticks back to the money they stand for).
    func microUsd(fromValue value: Double) -> Int64? {
        guard value.isFinite, value >= 0, rate > 0 else { return nil }
        let display = NSDecimalNumber(value: value).decimalValue
        let micro = display * Decimal(1_000_000) / rate
        return Int64(truncating: NSDecimalNumber(decimal: micro))
    }

    /// An axis value with the symbol, as few digits as the step needs: `$0`, `$2.5`, `NT$1.5k`, `¥120`.
    func axisLabel(_ value: Double, step: Double) -> String {
        guard value.isFinite, value > 0 else { return MoneyFormat.withSymbol(currency.symbol(language: language), "0") }
        let number: String
        if value >= 1000 {
            number = HistoryText.axisNumber(value)
        } else {
            let places = step >= 1 ? (step.rounded() == step ? 0 : 1) : min(6, Int(ceil(-log10(step))) + (Self.needsExtraDigit(step) ? 1 : 0))
            var text = String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
            if text.contains(".") {
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
            }
            number = text
        }
        return MoneyFormat.withSymbol(currency.symbol(language: language), number)
    }

    /// Steps such as 0.25 or 0.025 need one digit more than their magnitude.
    private static func needsExtraDigit(_ step: Double) -> Bool {
        let magnitude = pow(10, floor(log10(step)))
        let mantissa = step / magnitude
        return abs(mantissa - mantissa.rounded()) > 1e-9
    }

    /// How a day's or a range's cost reads in cards, cells and tooltips; `subscriptionTag` is `cost.subscription.tag`.
    func display(_ cost: HistoryCost, subscriptionTag: String) -> String {
        switch cost.kind {
        case .unavailable, .unknown: "–"
        case .subscription: subscriptionTag
        case .priced(let micro, let partial): partial ? "≥" + amount(micro) : amount(micro)
        }
    }

    /// The number as accessibility reads it: `12.34 美元`.
    func spoken(_ microUsd: Int64) -> String {
        "\(formatted(microUsd).number) \(currencyName)"
    }
}

/// A day's (or a range's) cost as the window shows it: a known amount (with `≥` when some responses are unpriced),
/// nothing priced, no cost data (logs gone before costs existed), or only excluded subscription sources.
struct HistoryCost: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case priced(microUsd: Int64, partial: Bool)
        /// Requests, but none with a known price.
        case unknown
        /// Days kept from a store without cost data.
        case unavailable
        /// Every request came from sources left out as subscriptions.
        case subscription([SourceKind])
    }

    /// Σ known cost of the counted sources (null-free merge of METRICS 9.7 contributions); nil without cost data.
    let tally: CostTally?
    /// Requests of the counted sources.
    let requests: Int
    /// Sources with usage that were left out as subscriptions.
    let excluded: [SourceKind]

    static let none = HistoryCost(tally: nil, requests: 0, excluded: [])

    var kind: Kind {
        if requests == 0, !excluded.isEmpty { return .subscription(excluded) }
        guard let tally else { return requests == 0 ? .priced(microUsd: 0, partial: false) : .unavailable }
        if tally.isUnknown(requests: requests) { return .unknown }
        return .priced(microUsd: tally.costMicroUsd, partial: tally.unpricedRequests > 0)
    }

    /// The known micro-USD that adds to totals, bars and sorting (0 for anything not priced).
    var microUsd: Int64 { tally?.costMicroUsd ?? 0 }
    var unpriced: Int { tally?.unpricedRequests ?? 0 }

    /// For sorting: nil when the day has nothing priced to compare.
    var sortValue: Double? {
        if case .priced(let micro, _) = kind { return Double(micro) }
        return nil
    }

    /// Adds another day or source (the store's rule: a part without cost data counts its requests as unpriced).
    func adding(_ other: HistoryCost) -> HistoryCost {
        HistoryCost(
            tally: HistoryCostMath.merged(tally, requests: requests, other.tally, requests: other.requests),
            requests: requests + other.requests,
            excluded: SourceKind.allCases.filter { excluded.contains($0) || other.excluded.contains($0) }
        )
    }
}

enum HistoryCostMath {
    /// The merge rule of the history store (METRICS 8, 9.7): all-nil stays nil; a nil part beside known parts adds its
    /// requests as unpriced.
    static func merged(_ lhs: CostTally?, requests lhsRequests: Int, _ rhs: CostTally?, requests rhsRequests: Int) -> CostTally? {
        if lhsRequests == 0, lhs == nil || lhs == .zero { return rhs }
        if rhsRequests == 0, rhs == nil || rhs == .zero { return lhs }
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (var sum?, nil):
            sum.unpricedRequests += rhsRequests
            return sum
        case (nil, var sum?):
            sum.unpricedRequests += lhsRequests
            return sum
        case (var sum?, let other?):
            sum.add(other)
            return sum
        }
    }
}

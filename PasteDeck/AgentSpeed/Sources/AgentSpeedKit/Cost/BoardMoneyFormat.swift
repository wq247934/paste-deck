import AgentSpeedCore
import Foundation

/// A cost per second as a board draws it (DESIGN 2c Live metrics, *Values*; DESIGN 9 rate form): the number, its
/// unit, `≥` when part is unpriced, `–` when nothing is priced, the subscription tag when every source is excluded.
struct BoardMoney: Hashable {
    enum State: Hashable {
        case value
        /// Nothing priced: `–`, no unit.
        case unknown
        /// Every source excluded as a subscription: `cost.subscription.tag`, no unit.
        case tag
    }

    var number: String
    /// `US$/s` (empty for `–` and the tag).
    var unit: String
    /// A small `≥` precedes the number.
    var atLeast = false
    var state = State.value

    static let zero = BoardMoney(number: "0", unit: "")

    /// `–`, a real `0` and the tag are drawn quietly (ink-3, no glow).
    var isQuiet: Bool { state != .value || number == "0" }
}

/// Formats board costs in the display currency (METRICS 9.8) for the UI language.
struct BoardMoneyFormat {
    let currency: Currency
    /// Units of the display currency per US dollar.
    let rate: Decimal
    let language: String
    /// `cost.unitPerSecond` with the symbol.
    let unit: String
    /// `cost.subscription.tag`.
    let tag: String

    @MainActor
    init(currency: Currency, rate: Decimal, l10n: Localizer) {
        self.currency = currency
        self.rate = rate
        language = l10n.language.rawValue
        unit = l10n("cost.unitPerSecond", currency.symbol(language: l10n.language.rawValue))
        tag = l10n("cost.subscription.tag")
    }

    /// The rate of `microUsdPerSecond` in `state` (METRICS 9.5): a partial value gets `≥` unless it shows 0.
    func money(_ microUsdPerSecond: Double, state: CostReading.State) -> BoardMoney {
        switch state {
        case .subscriptionOnly:
            return BoardMoney(number: tag, unit: "", state: .tag)
        case .nothingPriced:
            return BoardMoney(number: "–", unit: "", state: .unknown)
        case .priced, .partial:
            let number = MoneyFormat.format(MoneyFormat.rate(microUsdPerSecond: max(0, microUsdPerSecond), rate: rate),
                                            currency: currency, language: language, form: .rate).number
            return BoardMoney(number: number, unit: unit, atLeast: state == .partial && number != "0")
        }
    }

    func money(_ reading: CostReading) -> BoardMoney {
        money(reading.microUsdPerSecond, state: reading.state)
    }
}

import AgentSpeedCore
import AppKit
import Observation

/// The exchange rates in use (METRICS 9.8, NETWORK 4). Requests run only while a non-USD currency is selected and
/// the network master switch is on: 30 s after launch or at once on selection (when the stored rates are missing
/// or older than 24 h), then daily; a failed round retries after 1 h. Selecting USD stops every request. The UI
/// never waits: it converts with the last accepted or the bundled rates at once.
@MainActor
@Observable
public final class ExchangeRateController {
    /// How long a failed manual refresh replaces the status line (DESIGN 9).
    static let failureDisplay: TimeInterval = 6

    private(set) var rates: RatesInUse
    private(set) var isRefreshing = false
    /// The reason of a failed manual refresh, shown as `rates.failed` for 6 s.
    private(set) var failureReason: String?
    private(set) var currency = Currency.usdCode
    private(set) var networkEnabled = true

    @ObservationIgnored let currencies: CurrencyTable
    @ObservationIgnored private let store: ExchangeRateStore
    @ObservationIgnored private let sync: ExchangeRateSync
    /// The launch, or the moment the network was turned back on (NETWORK 1: scheduled as after a launch).
    @ObservationIgnored private var launchedAt = Date()
    /// False until the first `update`, which restores the stored choice rather than selecting a currency.
    @ObservationIgnored private var hasSelection = false
    @ObservationIgnored private var lastFailure: Date?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var round: Task<Void, Never>?
    @ObservationIgnored private var failureTimer: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(
        userAgent: String,
        appDataDirectory: URL = PriceSyncController.defaultAppDataDirectory,
        transport: any HTTPTransport = URLSessionTransport(),
        currencies: CurrencyTable = .bundled
    ) {
        self.currencies = currencies
        store = ExchangeRateStore(appDataDirectory: appDataDirectory)
        sync = ExchangeRateSync(store: store, transport: transport, userAgent: userAgent, currencies: currencies)
        rates = RatesInUse(stored: store.load()?.rateSet, fallback: currencies.fallbackRates)
    }

    /// Units of `code` per 1 USD, from the rates in use.
    public func rate(for code: String) -> Decimal { rates.rate(for: code) }

    /// The selected currency's rate.
    var selectedRate: Decimal { rates.rate(for: currency) }

    var isStale: Bool { rates.isStale(nowMs: Int64(Date().timeIntervalSince1970 * 1000)) }

    /// The rates' own date, for `rates.status` and `rates.historyNote`.
    var ratesDate: Date { Date(timeIntervalSince1970: TimeInterval(rates.dateMs) / 1000) }

    var canRefresh: Bool { networkEnabled && currency != Currency.usdCode && !isRefreshing }

    public func start() {
        guard !started else { return }
        started = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        }
        reschedule()
    }

    func stop() {
        started = false
        timer?.cancel()
        timer = nil
        round?.cancel()
        round = nil
        failureTimer?.cancel()
        failureTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// The master switch and the display currency. Selecting a non-USD currency without fresh rates fetches at once.
    public func update(networkEnabled: Bool, currency: String) {
        let code = currencies.currency(currency)?.code ?? Currency.usdCode
        let isUserSelection = hasSelection && code != self.currency
        hasSelection = true
        guard networkEnabled != self.networkEnabled || code != self.currency else { return }
        if networkEnabled, !self.networkEnabled { launchedAt = Date() }
        self.networkEnabled = networkEnabled
        self.currency = code
        if !networkEnabled || code == Currency.usdCode {
            round?.cancel()
            round = nil
            isRefreshing = false
        }
        if isUserSelection, started, networkEnabled, code != Currency.usdCode,
           ExchangeRateSync.fetchesOnSelection(fetchedAt: fetchedAt, lastFailure: lastFailure, now: Date()) {
            runRound(manual: false)
            return
        }
        reschedule()
    }

    /// Settings' `rates.refresh`: tries now.
    func refreshNow() {
        guard canRefresh else { return }
        runRound(manual: true)
    }

    private var fetchedAt: Date? {
        rates.fetchedMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    // MARK: - Schedule

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard started, networkEnabled, currency != Currency.usdCode, round == nil else { return }
        let now = Date()
        let due = ExchangeRateSync.nextAttempt(launchedAt: launchedAt, fetchedAt: fetchedAt, lastFailure: lastFailure, now: now)
        let delay = min(max(0, due.timeIntervalSince(now)), ExchangeRateSync.checkInterval)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if Date() >= due {
                self.runRound(manual: false)
            } else {
                self.reschedule()
            }
        }
    }

    private func runRound(manual: Bool) {
        guard networkEnabled, currency != Currency.usdCode, round == nil else { return }
        timer?.cancel()
        timer = nil
        isRefreshing = true
        let sync = self.sync
        let selected = currency
        round = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { await sync.run(selected: selected) }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(outcome, manual: manual)
        }
    }

    private func apply(_ outcome: ExchangeRateOutcome, manual: Bool) {
        round = nil
        isRefreshing = false
        switch outcome {
        case .updated(let set), .unchanged(let set):
            lastFailure = nil
            rates = RatesInUse(stored: set, fallback: currencies.fallbackRates)
            failureReason = nil
        case .failed(let reason):
            lastFailure = Date()
            if manual { showFailure(reason) }
        }
        reschedule()
    }

    private func showFailure(_ reason: String) {
        failureReason = reason
        failureTimer?.cancel()
        failureTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.failureDisplay))
            guard !Task.isCancelled else { return }
            self?.failureReason = nil
        }
    }

    // MARK: - Previews

    func preview(rates: ExchangeRateSet?, currency: String, refreshing: Bool = false, failure: String? = nil, networkEnabled: Bool = true) {
        self.rates = RatesInUse(stored: rates, fallback: currencies.fallbackRates)
        self.currency = currency
        isRefreshing = refreshing
        failureReason = failure
        self.networkEnabled = networkEnabled
    }
}

import AgentSpeedCore
import AppKit
import Observation

// PasteDeck 集成门面。源自上游 AgentSpeed 的 AppModel（MIT，见 AgentSpeedKit 同级 LICENSE-AgentSpeed），
// 按宿主需要裁剪：移除独立应用专属的更新系统、排行榜面板（boards）与实时上报，
// 保留监控、测速、悬浮球、标题主题、成本、网络流量与历史统计的完整数据链路。

/// Commands the host app can trigger; implemented by the PasteDeck glue layer.
@MainActor
public protocol AgentSpeedCommands: AnyObject {
    /// Shows the live speed dashboard window.
    func showDashboard()
    func closeDashboard()
    /// Opens the usage history window filtered to `source` (all sources when nil).
    func showHistory(source: SourceKind?)
    /// Opens the usage history window on `metric` (the dashboard's traffic rows open the traffic chart).
    func showHistory(source: SourceKind?, metric: HistoryChartMetric)
    /// The floating orbs' master switch (DESIGN 2b).
    func setOrbsVisible(_ visible: Bool)
    func resetOrbPosition(_ id: String)
    /// Opens the AI speed settings with orb `id` selected.
    func showOrbSettings(_ id: String?)
    /// Opens the AI speed settings.
    func showAgentSpeedSettings()
    func quit()
}

/// The shared state: one store, the settings, the live gauge, the data monitor and the daily history.
@MainActor
@Observable
public final class AgentSpeedModel {
    public let store: SpeedStore
    /// Daily usage (METRICS 8) for the history window, filled by `HistoryService`.
    public let history: HistoryStore
    public let settings: AgentSpeedSettings
    public let l10n: Localizer
    public let gauge: LiveGauge
    /// The all-sources orb feed: the dashboard hero and every orb tracking all sources read it.
    public let mainFeed: OrbFeed
    /// The floating orbs (DESIGN 2b).
    public let orbs: OrbsController
    /// The title themes and custom title sets (DESIGN 1).
    public let titles: TitleThemesController
    public let accessibility: AccessibilityState
    /// Price tables and day bindings shared by the live engine and the history (METRICS 9.7).
    public let priceBook: PriceBook
    /// Price-table sync and exchange rates (NETWORK 3, 4) and the money formatting built on them (DESIGN 9).
    public let prices: PriceSyncController
    public let rates: ExchangeRateController
    public let cost: CostDisplay
    /// Network traffic (METRICS 10): the live snapshot and the stored days.
    public let traffic: TrafficStore

    /// True while the 20 s effects preview drives the store.
    public private(set) var isPreviewing = false
    /// The dashboard window is open (traffic samples every second while it shows per-source traffic).
    public var isDashboardShown = false

    @ObservationIgnored public weak var commands: AgentSpeedCommands?
    @ObservationIgnored public private(set) var monitor: LiveMonitor?
    @ObservationIgnored public private(set) var historyService: HistoryService?
    /// Network traffic measuring (METRICS 10); live runs only.
    @ObservationIgnored private var trafficController: TrafficController?
    @ObservationIgnored private var historyStartTimer: Timer?
    @ObservationIgnored private var demo: DemoDriver?
    @ObservationIgnored private var demoLoops = false
    @ObservationIgnored private var loops: [ObservationLoop] = []
    @ObservationIgnored private var appliedConfiguration: MonitorConfiguration?
    @ObservationIgnored private var orbSubsets: Set<SourceSet> = []

    public init(
        store: SpeedStore = SpeedStore(),
        settings: AgentSpeedSettings = AgentSpeedSettings(),
        history: HistoryStore = HistoryStore()
    ) {
        self.store = store
        self.history = history
        self.settings = settings
        l10n = Localizer(preference: settings.language)
        gauge = LiveGauge()
        mainFeed = OrbFeed(gauge: gauge)
        orbs = OrbsController(defaults: settings.storage)
        titles = TitleThemesController(defaults: settings.storage)
        accessibility = AccessibilityState()
        priceBook = PriceBook()
        prices = PriceSyncController(book: priceBook, userAgent: "PasteDeck")
        rates = ExchangeRateController(userAgent: "PasteDeck")
        cost = CostDisplay(settings: settings, l10n: l10n, rates: rates, prices: prices)
        traffic = TrafficStore()
        gauge.redline = settings.redline
    }

    /// The stored history database location: inside PasteDeck's own Application Support folder, so the
    /// history layer is fully owned by this app (METRICS 8). Debug runs may use an isolated folder so a
    /// development build never touches the installed app's data.
    public static var historyStoreURL: URL {
        #if DEBUG
        if let folder = ProcessInfo.processInfo.environment["PASTEDECK_STORE_URL"], !folder.isEmpty {
            return URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent("AgentSpeedHistory.sqlite")
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("com.pastedeck.app", isDirectory: true)
            .appendingPathComponent("AgentSpeed", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }

    public var snapshot: SpeedSnapshot { store.snapshot }

    /// Effects level after Reduce Motion.
    public var effectsLevel: EffectsLevel { accessibility.effectiveLevel(settings.effects) }

    public func value(of rate: Rate) -> Double { rate.value(for: settings.metric) }

    /// Starts reacting to settings and data. `live` starts reading transcripts.
    public func activate(live: Bool) {
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            self.l10n.apply(self.settings.language)
        })
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            self.gauge.redline = self.settings.redline
            let snapshot = self.store.snapshot
            self.gauge.ingest(self.value(of: snapshot.live), now: Clock.now)
        })
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            let snapshot = self.store.snapshot
            let today = self.settings.metric == .output ? snapshot.today.output : snapshot.today.total
            self.mainFeed.set(
                generating: snapshot.agents.filter { $0.phase == .generating }.map(\.source),
                todayTokens: today,
                agentCount: snapshot.agents.count
            )
            self.mainFeed.redlineOutput = self.settings.redline(for: .output)
        })
        store.addEventListener { [weak self] event in
            guard let feed = self?.mainFeed else { return }
            switch event {
            case .responseCompleted(let response): feed.emit(.response(output: response.outputTokens, speed: response.speed))
            case .newPeak: feed.emit(.newPeak)
            }
        }
        loops.append(ObservationLoop { [weak self] in
            // The effects preview sweeps every title; it must not replace the vehicle the agents last reached.
            guard let self, let key = self.gauge.title.vehicleKey, !self.store.isPreviewing else { return }
            if self.settings.heroLastTitle != key { self.settings.heroLastTitle = key }
        })
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            let previewing = self.store.isPreviewing
            if self.isPreviewing != previewing { self.isPreviewing = previewing }
        })
        orbs.activate(model: self)
        titles.activate(model: self)
        guard live else { return }
        // Stored day bindings first, so the engine never re-binds a day that was priced before (METRICS 9.7).
        HistoryService.restorePricing(into: priceBook, storeURL: Self.historyStoreURL)
        activateNetwork()
        let traffic = TrafficController(model: self, storeURL: Self.historyStoreURL)
        trafficController = traffic
        traffic.start()
        let monitor = LiveMonitor(store: store, configuration: settings.monitorConfiguration, pricing: priceBook)
        self.monitor = monitor
        appliedConfiguration = settings.monitorConfiguration
        monitor.setSubsets(orbSubsets)
        monitor.start()
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            let configuration = self.settings.monitorConfiguration
            guard configuration != self.appliedConfiguration else { return }
            self.appliedConfiguration = configuration
            self.monitor?.update(configuration: configuration)
            self.historyService?.update(configuration: configuration)
        })
        scheduleHistory()
    }

    /// The history analysis reads every log, so it starts only once the live monitor has read today's transcripts
    /// (or after a grace period, or as soon as the history window asks for it), never slowing the live start.
    private func scheduleHistory() {
        let timer = Timer(timeInterval: Self.historyGracePeriod, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startHistory() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        historyStartTimer = timer
        loops.append(ObservationLoop { [weak self] in
            guard let self, self.historyService == nil else { return }
            if case .starting = self.store.snapshot.state { return }
            DispatchQueue.main.async { [weak self] in self?.startHistory() }
        })
    }

    private static let historyGracePeriod: TimeInterval = 20

    /// The price-table sync and exchange rates follow the master switch, the sync setting and the currency
    /// (NETWORK 1, 3, 4); a newly accepted table re-prices what no table could price (METRICS 9.7).
    /// PasteDeck 默认关闭网络同步（settings.networkEnabled = false），只读内核内置价格表。
    private func activateNetwork() {
        prices.onTableAccepted = { [weak self] _ in self?.historyService?.refresh(showsProgress: false) }
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            let network = self.settings.networkEnabled
            self.prices.update(networkEnabled: network, autoSync: self.settings.syncPrices)
            self.rates.update(networkEnabled: network, currency: self.settings.currency)
        })
        prices.start()
        rates.start()
    }

    /// Starts the daily history analysis if it is not running yet.
    public func startHistory() {
        guard historyService == nil, monitor != nil else { return }
        historyStartTimer?.invalidate()
        historyStartTimer = nil
        let service = HistoryService(store: history, configuration: settings.monitorConfiguration, liveStore: store,
                                     storeURL: Self.historyStoreURL, pricing: priceBook)
        // The stored performance records give the score card its baselines (METRICS 6.11).
        history.perfRecordsHandler = { [weak self] records in self?.monitor?.setPerfHistory(records) }
        historyService = service
        service.start()
    }

    /// Settings → traffic retry: starts the per-process sampler again after it gave up (METRICS 10.3).
    public func retryTraffic() {
        trafficController?.retry()
    }

    /// Deletes the stored daily statistics and analyses the current logs again (Settings → Data Sources).
    public func clearHistory() {
        startHistory()
        // Traffic history cannot be rebuilt from logs: today's totals start over with the deleted store (METRICS 10.9).
        trafficController?.clearHistory()
        history.clear()
    }

    /// The source sets of the orbs tracking a subset, whose peaks the engine reports (METRICS 6.8).
    public func setOrbSubsets(_ sets: Set<SourceSet>) {
        guard sets != orbSubsets else { return }
        orbSubsets = sets
        monitor?.setSubsets(orbSubsets)
    }

    public func shutdown() {
        trafficController?.stop()
        trafficController = nil
        orbs.shutdown()
        demo?.stop()
        historyStartTimer?.invalidate()
        historyService?.stop()
        monitor?.stop()
        loops.forEach { $0.cancel() }
        loops.removeAll()
    }

    /// Runs the scripted sweep through every tier (DESIGN section 5, Preview effects).
    public func previewEffects(duration: TimeInterval = 20) {
        let driver = demo ?? DemoDriver(store: store)
        demo = driver
        driver.onFinish = { [weak self] in
            guard let self, self.demoLoops else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.demoLoops else { return }
                self.demo?.start(redline: self.demoRedline, duration: duration)
            }
        }
        driver.start(redline: demoRedline, duration: duration)
    }

    /// `DemoDriver` scales output speed to the redline it gets and reports total throughput as 24× output, so the
    /// total metric needs a proportionally smaller input to sweep through the same tiers.
    private var demoRedline: Double {
        settings.metric == .output ? settings.redline : settings.redline / DemoDriverRatio.totalPerOutput
    }

    public func stopPreview() {
        demoLoops = false
        demo?.stop()
    }
}

enum DemoDriverRatio {
    static let totalPerOutput = 24.0
}

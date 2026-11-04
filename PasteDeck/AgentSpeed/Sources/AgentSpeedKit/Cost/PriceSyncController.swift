import AgentSpeedCore
import AppKit
import Observation

/// Keeps the price table current (NETWORK 3): adds the stored copy to the book at launch, syncs 60 s after launch
/// and then daily while `syncPrices` and the network master switch are on, and runs Settings' manual check. The
/// network round runs off the main thread; a validated table is applied in one step.
@MainActor
@Observable
public final class PriceSyncController {
    enum CheckState: Equatable {
        case idle
        case checking
        case finished(PriceSyncOutcome)
    }

    /// What Settings → Cost shows in `prices.status`.
    struct TableStatus: Equatable {
        var version: Int
        var updated: String
        var modelCount: Int
        /// The bundled table is current (`prices.bundled`).
        var isBundled: Bool
    }

    private(set) var table: TableStatus
    /// The last successful sync (`prices.lastSync`; nil → `prices.never`).
    private(set) var lastSync: Date?
    /// The inline result of the manual check.
    private(set) var checkState: CheckState = .idle
    private(set) var isSyncing = false
    /// The last round offered only a newer schema (`prices.newerSchema`).
    private(set) var newerSchemaAvailable = false
    private(set) var networkEnabled = true
    private(set) var autoSync = true

    /// Called after a newer table became current (the book already has it).
    @ObservationIgnored var onTableAccepted: (@MainActor (PriceTable) -> Void)?

    @ObservationIgnored let book: PriceBook
    @ObservationIgnored private let store: PriceTableStore
    @ObservationIgnored private let sync: PriceTableSync
    /// The launch, or the moment the network was turned back on (NETWORK 1: scheduled as after a launch).
    @ObservationIgnored private var launchedAt = Date()
    @ObservationIgnored private var state: PriceSyncState
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var round: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    /// Create it before the live monitor prices anything, so a stored newer table is current from the start.
    init(
        book: PriceBook,
        userAgent: String,
        appDataDirectory: URL = PriceSyncController.defaultAppDataDirectory,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.book = book
        store = PriceTableStore(appDataDirectory: appDataDirectory)
        sync = PriceTableSync(store: store, transport: transport, userAgent: userAgent)
        if let stored = store.loadTable() { book.add(stored) }
        state = store.loadState()
        lastSync = state.lastSuccessMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        table = Self.status(of: book)
    }

    /// `~/Library/Application Support/AgentSpeed`.
    nonisolated static var defaultAppDataDirectory: URL {
        HistoryService.defaultStoreURL.deletingLastPathComponent()
    }

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
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// The master switch and `syncPrices`; turning either on schedules the sync as after a launch.
    public func update(networkEnabled: Bool, autoSync: Bool) {
        guard networkEnabled != self.networkEnabled || autoSync != self.autoSync else { return }
        if networkEnabled, !self.networkEnabled { launchedAt = Date() }
        self.networkEnabled = networkEnabled
        self.autoSync = autoSync
        if !networkEnabled {
            round?.cancel()
            round = nil
            isSyncing = false
            if checkState == .checking { checkState = .idle }
        }
        reschedule()
    }

    /// Settings' `prices.check`: tries now and reports the outcome inline. Disabled while the network is off.
    func checkNow() {
        guard networkEnabled else { return }
        checkState = .checking
        runRound(manual: true)
    }

    var canCheck: Bool { networkEnabled && !isSyncing }

    // MARK: - Schedule

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard started, networkEnabled, autoSync else { return }
        let now = Date()
        let due = PriceTableSync.nextAttempt(launchedAt: launchedAt, state: state, now: now)
        // Re-checked at least hourly, so a long sleep or a clock change cannot delay the round by more than that.
        let delay = min(max(0, due.timeIntervalSince(now)), PriceTableSync.checkInterval)
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
        guard networkEnabled, round == nil else { return }
        isSyncing = true
        let sync = self.sync
        let current = book.currentVersion
        round = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { await sync.run(currentVersion: current) }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result, manual: manual)
        }
    }

    private func apply(_ result: PriceSyncResult, manual: Bool) {
        round = nil
        isSyncing = false
        state = result.state
        lastSync = state.lastSuccessMs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        if let accepted = result.table, book.add(accepted) {
            onTableAccepted?(accepted)
        }
        switch result.outcome {
        case .newerSchema: newerSchemaAvailable = true
        case .updated, .upToDate: newerSchemaAvailable = false
        case .failed: break
        }
        table = Self.status(of: book)
        if manual || checkState == .checking { checkState = .finished(result.outcome) }
        reschedule()
    }

    private static func status(of book: PriceBook) -> TableStatus {
        let current = book.current
        return TableStatus(
            version: current.version, updated: current.updated, modelCount: current.models.count,
            isBundled: current.version == PriceBook.bundled.version
        )
    }

    // MARK: - Previews

    func preview(lastSync: Date?, checkState: CheckState = .idle, newerSchema: Bool = false, networkEnabled: Bool = true) {
        self.lastSync = lastSync
        self.checkState = checkState
        newerSchemaAvailable = newerSchema
        self.networkEnabled = networkEnabled
    }
}

import AgentSpeedCore
import AgentSpeedOrbModel
import AppKit

/// Runs network traffic measuring for the app (METRICS 10): starts and stops the monitor with the setting, hands it the
/// agents of every snapshot, tells it when a visible surface shows per-source or per-agent traffic (the dashboard, the
/// menu bar's agents block, an orb whose readout is showing) so it samples every second, and writes before sleep.
@MainActor
final class TrafficController {
    private let model: AgentSpeedModel
    private let monitor: TrafficMonitor
    private var loops: [ObservationLoop] = []
    private var sleepObserver: NSObjectProtocol?
    private var demandTimer: Timer?

    init(model: AgentSpeedModel, storeURL: URL = HistoryService.defaultStoreURL) {
        self.model = model
        monitor = TrafficMonitor(store: model.traffic, storeURL: storeURL)
    }

    func start() {
        monitor.start(enabled: model.settings.trafficEnabled)
        #if DEBUG
        // Measurements: `AGENT_SPEED_TRAFFIC_INTERVAL=1|5` fixes nettop's interval (0: standby).
        if let interval = ProcessInfo.processInfo.environment["AGENT_SPEED_TRAFFIC_INTERVAL"].flatMap(Int.init) {
            monitor.setForcedInterval(interval)
        }
        #endif
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            self.monitor.setEnabled(self.model.settings.trafficEnabled)
        })
        loops.append(ObservationLoop { [weak self] in
            guard let self else { return }
            // The effects preview publishes made-up agents; the monitor only ever sees the real ones.
            let snapshot = self.model.snapshot
            guard !self.model.store.isPreviewing else { return }
            self.monitor.update(agents: snapshot.agents)
        })
        loops.append(ObservationLoop { [weak self] in self?.updateDemand() })
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor.flush() }
        }
    }

    func retry() { monitor.retry() }

    /// "Clear history": today's traffic starts over with the deleted store.
    func clearHistory() { monitor.clearHistory() }

    func stop() {
        loops.forEach { $0.cancel() }
        loops.removeAll()
        demandTimer?.invalidate()
        demandTimer = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
        monitor.stop()
    }

    /// METRICS 10.10: per-source traffic is on screen while the dashboard is open, while the menu bar shows the agents'
    /// block, or while an orb's sources readout is showing (until it has faded out).
    private func updateDemand() {
        let settings = model.settings
        let now = Clock.now
        var shown = model.isDashboardShown || (settings.barTraffic == .agents && settings.barMode != .glyph)
        var nextChange = TimeInterval.infinity
        if model.orbs.masterVisible {
            for orb in model.orbs.orbs where orb.visible && orb.traffic == .sources {
                guard let reading = model.orbs.runtime(orb.id)?.feed.lines?.reading else { continue }
                let gone = reading.quietAt + OrbLineReading.fadeOut
                if now < gone {
                    shown = true
                    nextChange = min(nextChange, gone)
                }
            }
        }
        monitor.setDetailDemand(shown)
        demandTimer?.invalidate()
        demandTimer = nil
        guard nextChange.isFinite else { return }
        let timer = Timer(timeInterval: max(0.1, nextChange - now + 0.05), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDemand() }
        }
        RunLoop.main.add(timer, forMode: .common)
        demandTimer = timer
    }
}

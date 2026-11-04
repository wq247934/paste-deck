import Observation

/// Re-runs `body` whenever any observable value it read changes, until cancelled.
@MainActor
final class ObservationLoop {
    private var isActive = true
    private let body: @MainActor () -> Void

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
        run()
    }

    func cancel() {
        isActive = false
    }

    private func run() {
        guard isActive else { return }
        withObservationTracking {
            body()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.run() }
        }
    }
}

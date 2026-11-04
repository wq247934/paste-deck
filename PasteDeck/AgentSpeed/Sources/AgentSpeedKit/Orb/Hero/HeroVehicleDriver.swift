import AgentSpeedCore
import AgentSpeedHero
import Foundation
import os

/// Runs the dashboard hero's vehicle (DESIGN 4c) for one embedded orb: reads the gauge and settings, steps the stage
/// once per rendered frame and rebuilds its draw list in place. Exists only while the dashboard is open.
@MainActor
final class HeroVehicleDriver {
    /// Debug and harness overrides of the effects level and Reduce Motion.
    struct Overrides {
        var level: HeroLevel?
        var reduceMotion: Bool?
        var increaseContrast: Bool?
    }

    /// CPU time of `layer(…)` (stage step and draw list), for the frame harness.
    struct Stats {
        var frames = 0
        var totalNanoseconds: UInt64 = 0
        var maxNanoseconds: UInt64 = 0
        var samples: [UInt64] = []
    }

    /// The light band crosses the vehicle while the gauge's idle sweep passes the top of the ring.
    static let sweepOffset: TimeInterval = 0.63
    /// Frames built by every driver since launch and their CPU time (verifies that a closed dashboard renders nothing).
    private(set) static var framesBuilt = 0
    private(set) static var totalNanoseconds: UInt64 = 0

    private static let signposter = OSSignposter(subsystem: "io.github.zoefix.agentspeed", category: "hero")
    private static let reportedLoadError: Void = {
        if let error = HeroLibrary.loadError {
            Logger(subsystem: "io.github.zoefix.agentspeed", category: "hero").error("Vehicle art failed validation: \(error, privacy: .public)")
        }
    }()

    let library: HeroLibrary
    let stage: HeroStage
    var overrides = Overrides()
    /// The gauge the vehicle follows; nil = the app's all-sources gauge (Settings previews pass their own).
    weak var gauge: LiveGauge?
    var collectsSamples = false
    private(set) var stats = Stats()
    private let builder: HeroFrameBuilder
    private let list = HeroDrawList()
    private var palette = HeroPalette()
    private var primed = false

    init?() {
        _ = Self.reportedLoadError
        guard let library = HeroLibrary.shared else { return nil }
        self.library = library
        stage = HeroStage(library: library)
        builder = HeroFrameBuilder(library: library)
    }

    /// Next frame starts from the steady state again (previews).
    func reset() {
        primed = false
    }

    func demand() -> HeroFrameDemand {
        primed ? stage.demand() : .full
    }

    func input(model: AgentSpeedModel, time: TimeInterval, sweepEpoch: TimeInterval) -> HeroInput {
        let gauge = self.gauge ?? model.gauge
        let redline = gauge.redline
        let title = gauge.title
        let reduceMotion = overrides.reduceMotion ?? model.accessibility.reduceMotion
        return HeroInput(
            time: time,
            title: title.vehicleKey.flatMap(library.index(of:)),
            titleChangedAt: gauge.titleChangedAt,
            threshold: title.enterSpeed(redline: redline),
            nextThreshold: title.next?.enterSpeed(redline: redline),
            redline: redline,
            heat: gauge.heat(at: time),
            overdrive: gauge.overdrive(at: time),
            tier: gauge.tier.rawValue,
            level: overrides.level ?? HeroLevel(model.settings.effects),
            reduceMotion: reduceMotion,
            sweepEpoch: sweepEpoch + Self.sweepOffset
        )
    }

    /// Steps the stage to `time` and returns this frame's layer, centered on the orb.
    func layer(model: AgentSpeedModel, content: OrbContent, geometry: OrbGeometry, time: TimeInterval, sweepEpoch: TimeInterval) -> OrbVehicleLayer {
        let state = Self.signposter.beginInterval("HeroFrame")
        let start = DispatchTime.now().uptimeNanoseconds
        let input = input(model: model, time: time, sweepEpoch: sweepEpoch)
        if !primed { prime(input, model: model) }
        stage.update(input)
        let paint = palette.paint(heat: stage.heat, overdrive: stage.overdrive, wake: stage.wake.value,
                                  dark: content.tokens.isDark,
                                  increaseContrast: overrides.increaseContrast ?? content.increaseContrast)
        builder.build(stage: stage, paint: paint, into: list)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        Self.signposter.endInterval("HeroFrame", state)
        Self.framesBuilt += 1
        Self.totalNanoseconds += elapsed
        stats.frames += 1
        stats.totalNanoseconds += elapsed
        stats.maxNanoseconds = max(stats.maxNanoseconds, elapsed)
        if collectsSamples { stats.samples.append(elapsed) }

        let side = library.orbFraction * geometry.diameter
        return OrbVehicleLayer(
            list: list,
            origin: CGPoint(x: geometry.center.x - side / 2, y: geometry.center.y - side / 2),
            unit: side / 100
        )
    }

    /// Starts in the steady state of the current title (or parked on the last vehicle) and runs 1.2 s of motion so the
    /// dashboard opens onto a vehicle already under way.
    private func prime(_ input: HeroInput, model: AgentSpeedModel) {
        let warmup = 1.2
        var warm = input
        warm.time = input.time - warmup
        stage.prime(warm, parkedVehicle: model.settings.heroLastTitle.flatMap(library.index(of:)))
        var time = warm.time
        while time < input.time - 1e-6 {
            time = min(input.time, time + 1.0 / 60)
            warm.time = time
            stage.update(warm)
        }
        primed = true
    }
}

extension HeroLevel {
    init(_ level: EffectsLevel) {
        switch level {
        case .off: self = .off
        case .soft: self = .soft
        case .standard: self = .standard
        case .max: self = .max
        }
    }
}

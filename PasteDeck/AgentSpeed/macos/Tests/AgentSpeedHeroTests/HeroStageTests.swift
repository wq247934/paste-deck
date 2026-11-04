import Foundation
import simd
import Testing
@testable import AgentSpeedHero

/// Feeds a stage like the app does: a title (with its change time) and the smoothed heat of a value, 60 frames a second.
struct HeroDrive {
    static let fractions = [0.0, 0.02, 0.03, 0.04, 0.06, 0.08, 0.12, 0.17, 0.24, 0.34, 0.5, 0.7, 1.0]
    static let redline = 400.0

    let stage: HeroStage
    var time = 1000.0
    var title: Int?
    var changedAt = -Double.infinity
    var value = 0.0
    var level = HeroLevel.standard
    var reduceMotion = false

    init(library: HeroLibrary, seed: UInt32 = 7) {
        stage = HeroStage(library: library, seed: seed)
    }

    static func threshold(_ index: Int) -> Double { index == 0 ? 0.5 : fractions[index] * redline }

    var input: HeroInput {
        let heat = min(1, pow(max(value, 0) / Self.redline, 0.6))
        let overdrive = min(1, max(0, (value - Self.redline) / Self.redline))
        let index = title ?? 0
        let tier = value < 0.5 ? 0 : value >= 0.75 * Self.redline ? 4 : value >= 0.375 * Self.redline ? 3 : value >= 0.15 * Self.redline ? 2 : 1
        return HeroInput(
            time: time, title: title, titleChangedAt: changedAt, threshold: Self.threshold(index),
            nextThreshold: index < 12 ? Self.threshold(index + 1) : nil, redline: Self.redline, heat: heat, overdrive: overdrive,
            tier: tier, level: level, reduceMotion: reduceMotion, sweepEpoch: 0
        )
    }

    mutating func prime(title: Int?, value: Double, parked: Int? = nil) {
        self.title = title
        self.value = value
        stage.prime(input, parkedVehicle: parked)
    }

    mutating func change(to title: Int?, value: Double) {
        self.title = title
        self.value = value
        changedAt = time
    }

    mutating func run(_ seconds: Double, every frame: (HeroStage) -> Void = { _ in }) {
        let end = time + seconds
        while time < end - 1e-9 {
            time = min(end, time + 1.0 / 60)
            stage.update(input)
            frame(stage)
        }
    }
}

@Test func primingParksTheFallbackOrTheLastVehicle() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: nil, value: 0)
    #expect(drive.stage.parked && drive.stage.current.vehicle == library.fallback)
    #expect(drive.stage.wake.value == 0 && drive.stage.stand == 1 && drive.stage.ground.value == 0)
    drive.prime(title: nil, value: 0, parked: 5)
    #expect(drive.stage.current.vehicle == 5)
    drive.prime(title: 3, value: 18)
    #expect(!drive.stage.parked && drive.stage.wake.value == 1 && drive.stage.outgoing == nil)
    #expect(drive.stage.ground.value == drive.stage.groundTarget())
}

@Test func groundSpeedFollowsBandAndCoasting() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    let car = 4
    drive.prime(title: car, value: HeroDrive.threshold(car))
    #expect(abs(drive.stage.band) < 1e-6)
    #expect(abs(drive.stage.groundTarget() - library.vehicles[car].speed.lo) < 1e-6)
    drive.value = (HeroDrive.threshold(car) * HeroDrive.threshold(car + 1)).squareRoot()
    drive.run(0.1)
    #expect(abs(drive.stage.band - 0.5) < 1e-6)
    let lo = library.vehicles[car].speed.lo, hi = library.vehicles[car].speed.hi
    #expect(abs(drive.stage.groundTarget() - (lo + hi) / 2) < 1e-6)
    drive.value = HeroDrive.threshold(car) / 4
    drive.run(0.1)
    #expect(abs(drive.stage.coast - 0.25) < 1e-6)
    #expect(abs(drive.stage.groundTarget() - lo * 0.5) < 1e-6, "√c slows the vehicle while the title holds")
}

@Test func distanceIntegratesGroundSpeedAndDrivesEverySpin() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: 1, value: 10)
    var expected = drive.stage.distance
    drive.run(2) { stage in expected += stage.ground.value / 60 }
    #expect(abs(drive.stage.distance - expected) < 1e-9)
    drive.level = .off
    drive.run(0.1)
    #expect(drive.stage.distance == library.vehicles[1].rest, "Off freezes D at the rest pose")
}

@Test func upgradeChoreography() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: 1, value: 10)
    drive.run(1)
    drive.change(to: 2, value: 13)
    drive.run(1.0 / 60)
    let stage = drive.stage
    #expect(stage.outgoing?.vehicle == 1 && stage.outgoing?.transition == .upgrade)
    #expect(stage.current.vehicle == 2 && stage.current.transition == .upgrade)
    let flash = try #require(stage.flash)
    #expect(abs(flash.start - (drive.changedAt + 0.32)) < 1e-9 && flash.strength == 1)
    #expect(stage.lines.pool.filter(\.alive).count >= 4, "four burst speed lines")

    var lastOut = -Double.infinity
    drive.run(0.3) { stage in
        guard let leaving = stage.outgoing else { return }
        let out = stage.placement(of: leaving, outgoing: true)
        #expect(out.offset.x >= lastOut, "the old vehicle accelerates away")
        lastOut = out.offset.x
    }
    let incoming = stage.placement(of: stage.current, outgoing: false)
    #expect(incoming.offset.x > -62 && incoming.offset.x < 0 && incoming.alpha > 0.9)
    drive.run(0.6)
    #expect(stage.outgoing == nil, "transitions end before the next title can change")
    #expect(abs(stage.placement(of: stage.current, outgoing: false).offset.x) < 0.2)
}

@Test func titleJumpsFlashBrighterAndGoStraightToTheFinalVehicle() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: 5, value: 34)
    drive.change(to: 8, value: 100)
    drive.run(1.0 / 60)
    #expect(drive.stage.current.vehicle == 8 && drive.stage.outgoing?.vehicle == 5)
    #expect(abs((drive.stage.flash?.strength ?? 0) - 1.4) < 1e-9)
}

@Test func downgradeFallsBackWithoutFlash() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: 5, value: 34)
    drive.change(to: 4, value: 25)
    drive.run(0.3)
    let stage = drive.stage
    #expect(stage.flash == nil)
    let leaving = try #require(stage.outgoing)
    #expect(stage.placement(of: leaving, outgoing: true).offset.x < 0)
    #expect(stage.placement(of: stage.current, outgoing: false).offset.x > 0)
}

@Test func startUpFromIdleOntoAnotherVehicle() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: nil, value: 0)
    drive.run(1)
    drive.change(to: 1, value: 10)
    drive.run(1.0 / 60)
    let stage = drive.stage
    #expect(!stage.parked)
    #expect(stage.outgoing?.vehicle == 0 && stage.outgoing?.transition == .wake)
    #expect(stage.current.transition == .wake)
    #expect(abs(stage.startupStart - (drive.changedAt + 0.3)) < 1e-9)
    drive.run(0.7)
    #expect(stage.particles.pool.contains { $0.alive && $0.kind == .puff }, "dust at the rear tire")
    drive.run(1.5)
    #expect(stage.wake.value > 0.99 && stage.ground.value > 40)
}

@Test func startUpOnTheSameVehicleStartsWhereItStands() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: nil, value: 0, parked: 1)
    drive.run(0.5)
    drive.change(to: 1, value: 10)
    drive.run(1.0 / 60)
    #expect(drive.stage.outgoing == nil && drive.stage.current.transition == .stay)
    #expect(abs(drive.stage.startupStart - (drive.changedAt + 0.15)) < 1e-9)
}

@Test func parkingCoastsToAStandstill() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: 0, value: 3)
    drive.run(1)
    drive.value = 0
    drive.run(3)
    #expect(drive.stage.ground.value < 1, "coasting brings the walker almost to a stop before idle")
    drive.change(to: nil, value: 0)
    drive.run(2)
    let stage = drive.stage
    #expect(stage.parked && stage.current.vehicle == 0)
    #expect(stage.wake.value < 0.01 && stage.stand > 0.99)
    #expect(stage.lines.isEmpty)
    if case .idle = stage.demand() {} else { Issue.record("a parked vehicle breathes at an idle frame rate") }
}

@Test func idleFrameRateRisesForTheLightBand() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.prime(title: nil, value: 0)
    var rates: Set<Int> = []
    drive.run(6) { stage in
        if case .idle(let fps) = stage.demand() { rates.insert(fps) }
    }
    #expect(rates == [10, 30])
}

@Test func reduceMotionCrossfadesAndStaysStill() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.reduceMotion = true
    drive.prime(title: 1, value: 10)
    drive.change(to: 2, value: 13)
    drive.run(0.15)
    let stage = drive.stage
    #expect(stage.current.transition == .fade && stage.outgoing?.transition == .fade)
    #expect(stage.placement(of: stage.current, outgoing: false).offset == .zero)
    #expect(stage.distance == library.vehicles[2].rest && stage.particles.isEmpty && stage.lines.isEmpty)
    #expect(stage.demand() == .full)
    drive.run(1.5)
    #expect(stage.demand() == .still)
    #expect(stage.level == .soft, "Reduce Motion caps the layer at Soft")
}

@Test func offCutsBetweenVehicles() throws {
    let library = try HeroFixtures.library
    var drive = HeroDrive(library: library)
    drive.level = .off
    drive.prime(title: 4, value: 26)
    drive.change(to: 5, value: 34)
    drive.run(1.0 / 60)
    let stage = drive.stage
    #expect(stage.current.transition == .cut)
    #expect(stage.placement(of: try #require(stage.outgoing), outgoing: true).alpha == 0)
    #expect(stage.placement(of: stage.current, outgoing: false).alpha == 1)
    #expect(stage.demand() == .still)
}

@Test func poolsStayWithinTheirCapsAtEveryLevel() throws {
    let library = try HeroFixtures.library
    for level in HeroLevel.allCases {
        var drive = HeroDrive(library: library)
        drive.level = level
        drive.prime(title: 12, value: 780)
        var maxLines = 0
        drive.run(4) { stage in
            maxLines = max(maxLines, stage.lines.pool.filter(\.alive).count)
            #expect(stage.particles.pool.count == HeroParticles.capacity)
        }
        let cap = [0, 5, 9, 14][level.rawValue]
        #expect(maxLines <= max(cap, 0) + 4, "\(level): \(maxLines) lines")
        if level < .standard { #expect(drive.stage.particles.isEmpty, "no particle streams below Standard") }
        if level >= .standard { #expect(!drive.stage.particles.isEmpty, "rocket sparks at Standard and Max") }
    }
}

@Test func stageIsDeterministic() throws {
    let library = try HeroFixtures.library
    func run() -> (Double, [HeroParticle], [HeroSpeedLine]) {
        var drive = HeroDrive(library: library)
        drive.prime(title: nil, value: 0)
        drive.run(0.5)
        drive.change(to: 12, value: 600)
        drive.run(2)
        return (drive.stage.distance, drive.stage.particles.pool, drive.stage.lines.pool)
    }
    let a = run(), b = run()
    #expect(a.0 == b.0 && a.1 == b.1 && a.2 == b.2)
}

import Foundation
import simd
import Testing
@testable import AgentSpeedHero

@Test func criticalSpringMatchesItsClosedForm() {
    var spring = HeroCriticalSpring(settle: 0.9, value: 0)
    let omega = 6.2 / 0.9
    var time = 0.0
    for _ in 0..<90 {
        spring.step(toward: 100, dt: 1.0 / 60)
        time += 1.0 / 60
        let exact = 100 - 100 * (1 + omega * time) * exp(-omega * time)
        #expect(abs(spring.value - exact) < 1e-9)
    }
    var settled = HeroCriticalSpring(settle: 0.9, value: 0)
    for _ in 0..<6 { settled.step(toward: 100, dt: 0.15) }
    #expect(abs(settled.value - 100) < 1.5, "within 1.5 % after the settle time (ω t = 6.2)")
    let exact = 100 - 100 * (1 + omega * 0.9) * exp(-omega * 0.9)
    #expect(abs(settled.value - exact) < 1e-9, "exact per step, independent of the frame rate")
}

@Test func upgradeSwoopOvershootsAboutOneUnit() {
    var peak = -Double.infinity
    var t = 0.0
    while t < 1.2 {
        peak = max(peak, HeroMath.spring(at: t, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8))
        t += 0.002
    }
    #expect(peak > 0.5 && peak < 1.6, "≈ 1 unit overshoot, got \(peak)")
    let v = HeroMath.springVelocity(at: 0.1, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8)
    let numeric = (HeroMath.spring(at: 0.1001, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8)
        - HeroMath.spring(at: 0.0999, from: -62, to: 0, velocity: 140, response: 0.5, damping: 0.8)) / 0.0002
    #expect(abs(v - numeric) < 1e-3)
}

@Test func afterburnerLightOffOvershoots() {
    var peak = 0.0
    for step in 0...350 {
        peak = max(peak, HeroStartup.effects(kind: .fighterJet, tau: Double(step) / 1000).flame)
    }
    // DESIGN 4c says "≈ 25 %"; its spring constants (v 9/s, response 0.32 s, damping 0.55) give 14.5 %.
    #expect(abs(peak - 1.145) < 0.01)
    #expect(HeroStartup.effects(kind: .fighterJet, tau: -0.1).flame == 0, "no flame before the choreography starts")
}

@Test func bumpRisesAndFalls() {
    #expect(HeroMath.bump(0, 0, 0.18, 0.6) == 0)
    #expect(HeroMath.bump(0.18, 0, 0.18, 0.6) == 1)
    #expect(HeroMath.bump(0.6, 0, 0.18, 0.6) == 0)
    #expect(HeroStartup.effects(kind: .bicycle, tau: 0.18).hipLift == 1.3)
    #expect(abs(HeroStartup.effects(kind: .motorcycle, tau: 0.34).pitch + 3) < 1e-9, "−3° wheelie at its peak")
}

@Test func kneesBendForward() {
    let hip = SIMD2(50.0, 40.0)
    for x in stride(from: 40.0, through: 60, by: 2.5) {
        let foot = SIMD2(x, 66.0)
        let knee = HeroRig.knee(hip: hip, foot: foot, upper: 14.4, lower: 14.4)
        let cross = (foot.x - hip.x) * (knee.point.y - hip.y) - (foot.y - hip.y) * (knee.point.x - hip.x)
        #expect(cross < 0, "knee on the +x side at foot x \(x)")
        #expect(abs(simd_length(knee.point - hip) - 14.4) < 1e-9)
        #expect(abs(simd_length(foot - knee.point) - 14.4) < 1e-6)
    }
    #expect(HeroRig.knee(hip: hip, foot: SIMD2(50, 80), upper: 14.4, lower: 14.4).stretched)
}

@Test func walkerFeetNeverSlide() throws {
    let library = try HeroFixtures.library
    guard case .walk(let rig)? = library.vehicles[0].rig, let ground = library.vehicles[0].groundY else {
        Issue.record("no walker")
        return
    }
    let step = 0.05
    var distance = 0.0
    var planted = 0
    while distance < rig.cycle * 2 {
        let a = HeroRig.walk(rig, distance: distance, ground: ground, stand: 0).pose
        let b = HeroRig.walk(rig, distance: distance + step, ground: ground, stand: 0).pose
        for (footA, footB) in [(a.near1[2], b.near1[2]), (a.far0[2], b.far0[2])] where footA.y == ground - 0.6 && footB.y == ground - 0.6 {
            // A planted foot moves back at exactly ground speed, so it stays put on the scrolling road.
            #expect(abs((footB.x - footA.x) + step) < 1e-9)
            planted += 1
        }
        distance += step
    }
    #expect(planted > 0)
    let standing = HeroRig.walk(rig, distance: 17, ground: ground, stand: 1).pose
    #expect(abs(standing.near1[2].x - (rig.hip.x + 1.6)) < 1e-9 && abs(standing.far0[2].x - (rig.hip.x - 1.6)) < 1e-9)
    #expect(abs(standing.hip.y - (ground - 0.6 - 0.97 * (rig.thigh + rig.shin))) < 1e-9)
}

@Test func pedalsRideTheCrankCircle() throws {
    let library = try HeroFixtures.library
    for index in [1, 2] {
        guard case .pedal(let rig)? = library.vehicles[index].rig else {
            Issue.record("no pedal rig")
            return
        }
        for k in 0..<72 {
            let distance = 2 * Double.pi * rig.crankRadius * Double(k) / 72
            let solved = HeroRig.pedal(rig, distance: distance, lift: 0)
            #expect(!solved.stretched)
            let near = solved.pose.near0[2], far = solved.pose.far0[2]
            #expect(abs(simd_length(near - rig.crankPivot) - rig.crankLength) < 1e-9)
            #expect(abs(simd_length((near + far) / 2 - rig.crankPivot)) < 1e-9, "pedals opposite each other")
            let pedal = try #require(solved.pose.nearPedal)
            #expect(pedal.p0.y == pedal.p1.y, "pedals stay level")
        }
    }
}

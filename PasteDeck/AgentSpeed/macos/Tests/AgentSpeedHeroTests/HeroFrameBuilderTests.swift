import Foundation
import simd
import Testing
@testable import AgentSpeedHero

enum HeroPaints {
    static func paint(dark: Bool, increaseContrast: Bool = false) -> HeroPaint {
        HeroPaint(stroke: HeroColor.rgb(0x38BDF8), hot: HeroColor.rgb(0xD8F2FF), core: HeroColor.whiteHot,
                  sweep: HeroColor.withAlpha(HeroColor.whiteHot, 0.75), dark: dark, increaseContrast: increaseContrast)
    }
}

/// Exact farthest reach of the strokes of `sections` from the canvas center (no glow).
private func strokeReach(_ list: HeroDrawList, _ sections: Set<HeroDrawSection>) -> Float {
    var reach: Float = 0
    let center = SIMD2<Float>(50, 50)
    for (item, section) in zip(list.items, list.sections) where sections.contains(section) {
        switch item.kind {
        case .polyline:
            let first = Int(item.header.y), count = Int(item.header.z)
            for point in list.points[first..<(first + count)] {
                reach = max(reach, simd_length(SIMD2(point.x, point.y) - center) + item.stroke.x)
            }
        case .circle:
            reach = max(reach, simd_length(SIMD2(item.shape.x, item.shape.y) - center) + item.shape.z + item.stroke.x)
        case .radial:
            break
        }
    }
    return reach
}

private func hasBleed(_ vehicle: HeroVehicle) -> Bool { vehicle.parts.contains { $0.bleed } }

@Test func cruisingVehiclesStayInsideTheSoftFade() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    for (index, vehicle) in library.vehicles.enumerated() where !hasBleed(vehicle) {
        for band in [0.0, 0.5, 1.0] {
            var drive = HeroDrive(library: library)
            drive.level = .max
            let low = HeroDrive.threshold(index), high = index < 12 ? HeroDrive.threshold(index + 1) : HeroDrive.redline * 2
            drive.prime(title: index, value: low * pow(high / low, band))
            var worst: Float = 0
            drive.run(2.5) { stage in
                builder.build(stage: stage, paint: HeroPaints.paint(dark: true), into: list)
                worst = max(worst, strokeReach(list, [.vehicle]))
            }
            // The safe circle (42) plus the lurch, pitch, float and redline shake allowance (DESIGN 4c).
            #expect(worst <= 43.9, "\(vehicle.key) at band \(band) reaches \(worst)")
            #expect(list.overflow == 0)
        }
    }
}

@Test func startUpsAndTransitionsNeverReachTheClearRadius() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    for index in 0..<13 where !hasBleed(library.vehicles[index]) {
        var drive = HeroDrive(library: library)
        drive.prime(title: nil, value: 0, parked: index)
        drive.run(0.5)
        drive.change(to: index, value: HeroDrive.threshold(index) * 1.2)
        var worst: Float = 0
        drive.run(1.6) { stage in
            builder.build(stage: stage, paint: HeroPaints.paint(dark: false), into: list)
            worst = max(worst, strokeReach(list, [.vehicle]))
        }
        #expect(worst <= 45, "\(library.vehicles[index].key) start-up reaches \(worst)")
    }
}

@Test func drawListNeverGrowsOrOverflowsAcrossATour() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    let itemCapacity = list.items.capacity, pointCapacity = list.points.capacity
    var drive = HeroDrive(library: library)
    drive.level = .max
    drive.prime(title: nil, value: 0)
    var most = (items: 0, points: 0)
    for index in 0..<13 {
        drive.change(to: index, value: HeroDrive.threshold(index) * 1.1)
        drive.run(1.2) { stage in
            builder.build(stage: stage, paint: HeroPaints.paint(dark: true), into: list)
            most = (max(most.items, list.items.count), max(most.points, list.points.count))
        }
    }
    #expect(list.overflow == 0)
    #expect(list.items.capacity == itemCapacity && list.points.capacity == pointCapacity, "no reallocation per frame")
    #expect(most.items < HeroDrawList.itemCapacity / 2 && most.points < HeroDrawList.pointCapacity / 2,
            "busiest frame: \(most.items) items, \(most.points) points")
}

@Test func upgradeFlashAddsLightOnlyInDark() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    for dark in [true, false] {
        var drive = HeroDrive(library: library)
        drive.prime(title: 1, value: 10)
        drive.change(to: 2, value: 13)
        drive.run(0.4)
        builder.build(stage: drive.stage, paint: HeroPaints.paint(dark: dark), into: list)
        let flash = try #require(zip(list.items, list.sections).first { $0.1 == .flash }?.0)
        #expect(flash.kind == .radial)
        #expect(flash.flags.contains(.additive) == dark)
    }
}

@Test func ghostsTrailTheUpgradingVehicles() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    var drive = HeroDrive(library: library)
    drive.prime(title: 4, value: 26)
    drive.change(to: 5, value: 34)
    drive.run(0.2)
    builder.build(stage: drive.stage, paint: HeroPaints.paint(dark: true), into: list)
    let ghosts = zip(list.items, list.sections).filter { $0.1 == .ghost }.map(\.0)
    #expect(!ghosts.isEmpty)
    #expect(ghosts.allSatisfy { $0.stroke.z == 0 }, "ghosts do not glow")
}

@Test func increaseContrastWidensStrokesAndHalvesGlow() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    func wheel(_ increase: Bool) throws -> HeroDrawItem {
        var drive = HeroDrive(library: library)
        drive.prime(title: 4, value: 30)
        drive.run(0.2)
        let list = HeroDrawList()
        builder.build(stage: drive.stage, paint: HeroPaints.paint(dark: true, increaseContrast: increase), into: list)
        return try #require(list.items.first { $0.kind == .circle && $0.shape.z > 7 })
    }
    let plain = try wheel(false), strong = try wheel(true)
    #expect(abs(strong.stroke.x / plain.stroke.x - 1.3) < 1e-4)
    #expect(abs(strong.stroke.z / plain.stroke.z - 0.5) < 1e-3)
}

@Test func reduceMotionShowsStaticSpeedMarksByBand() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    for (band, marks) in [(0.1, 1), (0.5, 2), (0.9, 3)] {
        var drive = HeroDrive(library: library)
        drive.reduceMotion = true
        let low = HeroDrive.threshold(4), high = HeroDrive.threshold(5)
        drive.prime(title: 4, value: low * pow(high / low, band))
        drive.run(0.5)
        builder.build(stage: drive.stage, paint: HeroPaints.paint(dark: false), into: list)
        #expect(list.sections.filter { $0 == .trails }.count == marks)
        #expect(!list.sections.contains(.speedLines) && !list.sections.contains(.particles))
        #expect(list.sweep.band.z == 0)
    }
}

@Test func parkedVehicleGetsTheLightBand() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    var drive = HeroDrive(library: library)
    drive.prime(title: nil, value: 0, parked: 3)
    var crossed: [Float] = []
    drive.run(6) { stage in
        builder.build(stage: stage, paint: HeroPaints.paint(dark: true), into: list)
        if list.sweep.band.z > 0 { crossed.append(list.sweep.band.x) }
        #expect(list.items.allSatisfy { $0.stroke.z == 0 }, "no glow while parked")
    }
    #expect(!crossed.isEmpty && crossed == crossed.sorted(), "the band travels left to right")
    #expect((crossed.first ?? 0) < 0 && (crossed.last ?? 0) > 100)
}

@Test func offKeepsAFixedGlow() throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    var glows: Set<Float> = []
    for value in [26.0, 30] {
        var drive = HeroDrive(library: library)
        drive.level = .off
        drive.prime(title: 4, value: value)
        drive.run(0.1)
        builder.build(stage: drive.stage, paint: HeroPaints.paint(dark: true), into: list)
        glows.insert(try #require(list.items.first { $0.kind == .circle && $0.shape.z > 7 }).stroke.z)
    }
    #expect(glows.count == 1)
}

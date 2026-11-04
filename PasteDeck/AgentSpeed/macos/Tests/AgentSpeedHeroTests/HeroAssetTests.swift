import Foundation
import Testing
@testable import AgentSpeedHero

enum HeroFixtures {
    static let specURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("spec/assets/vehicles.json")

    static var library: HeroLibrary {
        get throws { try #require(HeroLibrary.shared, "\(HeroLibrary.loadError ?? "")") }
    }

    /// The embedded JSON after `edit`, for validation failures.
    static func mutated(_ edit: (inout [String: Any]) -> Void) throws -> String {
        var root = try #require(JSONSerialization.jsonObject(with: Data(HeroAssetJSON.text.utf8)) as? [String: Any])
        edit(&root)
        return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }

    /// Edits part `part` of vehicle `vehicle` in a JSON tree.
    static func editPart(_ root: inout [String: Any], vehicle: Int, part: Int, _ edit: (inout [String: Any]) -> Void) {
        var vehicles = root["vehicles"] as? [[String: Any]] ?? []
        var parts = vehicles[vehicle]["parts"] as? [[String: Any]] ?? []
        edit(&parts[part])
        vehicles[vehicle]["parts"] = parts
        root["vehicles"] = vehicles
    }

    static func editVehicle(_ root: inout [String: Any], _ vehicle: Int, _ edit: (inout [String: Any]) -> Void) {
        var vehicles = root["vehicles"] as? [[String: Any]] ?? []
        edit(&vehicles[vehicle])
        root["vehicles"] = vehicles
    }

    static func problems(_ json: String) -> [String] {
        do {
            _ = try HeroLibrary(json: json)
            return []
        } catch let error as HeroLibraryError {
            return error.problems
        } catch {
            return ["\(error)"]
        }
    }
}

@Test func embeddedArtMatchesTheSpec() throws {
    let spec = try String(contentsOf: HeroFixtures.specURL, encoding: .utf8)
    let expected = spec.hasSuffix("\n") ? String(spec.dropLast()) : spec
    #expect(HeroAssetJSON.text == expected, "HeroAssetJSON.swift is stale: run macos/scripts/sync-vehicles.py")
}

@Test func embeddedArtLoadsAndValidates() throws {
    #expect(HeroLibrary.loadError == nil)
    let library = try HeroFixtures.library
    #expect(library.vehicles.map(\.key) == HeroVehicleKind.allCases.map(\.rawValue))
    #expect(library.vehicles[library.fallback].kind == .walk)
    #expect(library.strokeWidth == 2)
    #expect(library.mask.solid == 42 && library.mask.clear == 49)
    for vehicle in library.vehicles {
        #expect(vehicle.speed.lo < vehicle.speed.hi, "\(vehicle.key)")
    }
}

@Test func everySpeedRangeStartsAtThePreviousTop() throws {
    let library = try HeroFixtures.library
    for (lower, upper) in zip(library.vehicles, library.vehicles.dropFirst()) {
        #expect(upper.speed.lo >= lower.speed.hi, "\(upper.key) would slow the world down after \(lower.key)")
    }
}

@Test func preparedVehiclesCarryTheirRigsAndPivots() throws {
    let library = try HeroFixtures.library
    let walk = library.vehicles[0]
    guard case .walk(let rig)? = walk.rig else { Issue.record("walker has no walk rig"); return }
    #expect(rig.cycle == 38.4)
    guard case .pedal? = library.vehicles[1].rig else { Issue.record("bicycle has no pedal rig"); return }
    let car = library.vehicles[try #require(library.index(of: "car"))]
    #expect(car.rollsOnTires)
    #expect(car.pitchPivot == SIMD2(27.65, 61.61))
    let rocket = library.vehicles[12]
    let heading = try #require(rocket.heading)
    #expect(abs(heading - (-48 * .pi / 180)) < 1e-12)
    #expect(!rocket.rollsOnTires)
}

@Test func pathGrammarIsStrict() throws {
    #expect(try HeroPath.parse("M 1 2 L 3.25 -4 Z") == [.move(1, 2), .line(3.25, -4), .close])
    #expect(try HeroPath.parse("M 0 0 Q 1 1 2 0 C 1 2 3 4 5 6").count == 3)
    for bad in ["L 1 2", "M 1 2  L 3 4", " M 1 2", "M 1 2 A 1 1", "M 1.234 2", "M 1 2 L 3", "M 1. 2", "M 1 2 L x 4"] {
        #expect(throws: HeroPath.SyntaxError.self, "\(bad)") { try HeroPath.parse(bad) }
    }
}

@Test func flatteningClosesSubpathsAndFollowsCurves() throws {
    let vertices = HeroPath.flatten(try HeroPath.parse("M 0 0 C 0 10 10 10 10 0 Z M 20 0 L 30 0"))
    let first = try #require(vertices.first)
    #expect(first.move)
    let closing = try #require(vertices.firstIndex { $0.move && $0.x == 20 })
    #expect(vertices[closing - 1] == HeroVertex(x: 0, y: 0, move: false))
    let peak = vertices[0..<closing].map(\.y).max() ?? 0
    #expect(abs(peak - 7.5) < 0.05)
    let curve = vertices[0..<(closing - 1)]
    for (a, b) in zip(curve, curve.dropFirst()) {
        #expect(hypot(b.x - a.x, b.y - a.y) < 1.5)
    }
}

@Test func validationAcceptsTheArtRoundTripped() throws {
    #expect(HeroFixtures.problems(try HeroFixtures.mutated { _ in }).isEmpty)
}

@Test func validationRejectsBrokenArt() throws {
    let cases: [(String, (inout [String: Any]) -> Void)] = [
        ("title ladder", { HeroFixtures.editVehicle(&$0, 1) { $0["key"] = "unicycle" } }),
        ("version", { $0["version"] = 2 }),
        ("outside the safe circle", { HeroFixtures.editPart(&$0, vehicle: 1, part: 0) { $0["circle"] = [16.63, 60.23, 11.97] } }),
        ("unknown role", { HeroFixtures.editPart(&$0, vehicle: 1, part: 0) { $0["role"] = "tyre" } }),
        ("bad argument", { HeroFixtures.editPart(&$0, vehicle: 1, part: 9) { $0["d"] = "M 67.67 45.98 C 68.812 51 71.2 56.02 73.37 60.23" } }),
        ("unsupported token", { HeroFixtures.editPart(&$0, vehicle: 1, part: 9) { $0["d"] = "M 67.67 45.98 A 1 1 0 0 1 73.37 60.23" } }),
        ("previous title's top", { HeroFixtures.editVehicle(&$0, 1) { $0["motion"] = ["speed": [30, 87], "rest": 72.07, "bob": 0] } }),
        ("unknown keys", { HeroFixtures.editPart(&$0, vehicle: 1, part: 0) { $0["wobble"] = true } }),
        ("tire must touch the road", { HeroFixtures.editVehicle(&$0, 4) { $0["groundY"] = 63 } }),
        ("leg overextended", { HeroFixtures.editVehicle(&$0, 1) { vehicle in
            var rig = vehicle["rig"] as? [String: Any] ?? [:]
            rig["shin"] = 9
            vehicle["rig"] = rig
        } }),
    ]
    for (expected, edit) in cases {
        let problems = HeroFixtures.problems(try HeroFixtures.mutated(edit))
        #expect(problems.contains { $0.contains(expected) }, "\(expected): \(problems)")
    }
}

@Test func colorsMixInOKLab() {
    let teal = HeroColor.rgb(0x2DD4BF)
    #expect(HeroColor.mix(teal, HeroColor.whiteHot, 0) == teal)
    #expect(HeroColor.mix(teal, HeroColor.whiteHot, 1) == HeroColor.whiteHot)
    let half = HeroColor.mix(HeroColor.rgb(0x000000), HeroColor.rgb(0xFFFFFF), 0.5)
    #expect(abs(half.x - 0.389) < 0.01, "OKLab L 0.5 is sRGB 0.389")
}

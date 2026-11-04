import Foundation

/// The checks of `spec/tools/vehicles.py`, run on the embedded copy before anything is drawn from it.
enum HeroValidation {
    static let ladder = HeroVehicleKind.allCases.map(\.rawValue)
    static let emitterTypes: Set<String> = ["dust", "arc", "exhaust", "trail", "sparks", "contrail", "afterburner", "plume"]
    static let sceneryKinds: Set<String> = ["road", "rail", "guideway", "sky", "stratosphere", "space"]
    static let grounded: Set<String> = ["road", "rail", "guideway"]
    static let partKeys: Set<String> = ["id", "role", "d", "circle", "spin", "sprung", "bleed", "nozzle"]
    static let vehicleKeys: Set<String> = ["key", "scenery", "groundY", "heading", "motion", "rig", "parts", "emitters"]
    static let motionKeys: Set<String> = ["speed", "rest", "bob", "float", "hover"]

    static func validate(_ asset: HeroAsset, json: String) -> [String] {
        var problems: [String] = []
        func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition, !problems.contains(message()) { problems.append(message()) }
        }

        check(asset.version == 1, "version must be 1")
        check(asset.canvas.width == 100 && asset.canvas.height == 100, "canvas must be 100 × 100")
        check(asset.canvas.orbFraction > 0 && asset.canvas.orbFraction < 0.775, "canvas.orbFraction must keep the canvas inside the gauge")
        check(asset.mask.solid < asset.mask.clear && asset.mask.clear <= 50, "mask radii must satisfy solid < clear ≤ 50")
        check(asset.safeCircle.r <= asset.mask.solid, "the safe circle must sit inside the mask's opaque zone")
        check(asset.mask.clear / 100 * asset.canvas.orbFraction <= 0.3585, "mask clear radius reaches into the agent dots / gauge")
        check(asset.stroke.cap == "round" && asset.stroke.join == "round", "round caps and joins")
        check(Set(asset.roles.keys) == Set(HeroRole.allCases.map(\.name)), "roles must be exactly the known roles")
        for (name, role) in asset.roles {
            check(role.fill == nil || name == "flame" || name == "flameCore", "role \(name) may not fill")
        }
        for cloud in asset.scenery.sky.clouds {
            check((try? HeroPath.parse(cloud)) != nil, "scenery.sky.cloud: bad path")
        }
        check(asset.vehicles.map(\.key) == ladder, "vehicles must follow the title ladder: \(ladder)")
        check(asset.idle.vehicle == "last" && ladder.contains(asset.idle.fallback), "idle must name last + a fallback")
        checkKeys(json, check)

        let base = asset.stroke.width
        let center = SIMD2(asset.safeCircle.cx, asset.safeCircle.cy)
        let radius = asset.safeCircle.r
        func distance(_ x: Double, _ y: Double) -> Double { hypot(x - center.x, y - center.y) }
        var previousTop = 0.0
        for vehicle in asset.vehicles {
            let key = vehicle.key
            check(sceneryKinds.contains(vehicle.scenery), "\(key): unknown scenery")
            check((vehicle.groundY != nil) == grounded.contains(vehicle.scenery),
                  "\(key): groundY is required exactly for road, rail and guideway scenery")
            if let ground = vehicle.groundY { check(ground > 50 && ground < 88, "\(key): groundY out of range") }
            let speed = vehicle.motion.speed
            check(speed.count == 2 && speed[0] > 0 && speed[0] < speed[1], "\(key): motion.speed must be an increasing pair")
            if speed.count == 2 {
                check(speed[0] >= previousTop, "\(key): speed range must start at or above the previous title's top")
                previousTop = speed[1]
            }
            var ids: Set<String> = []
            for part in vehicle.parts {
                let at = "\(key).\(part.id)"
                check(!part.id.isEmpty && !ids.contains(part.id), "\(at): missing or duplicate id")
                ids.insert(part.id)
                guard let role = HeroRole(name: part.role), let style = asset.roles[part.role] else {
                    check(false, "\(at): unknown role")
                    continue
                }
                check((part.d != nil) != (part.circle != nil), "\(at): exactly one of d / circle")
                var points: [(x: Double, y: Double)] = []
                if let d = part.d {
                    do {
                        points = HeroPath.sample(try HeroPath.parse(d))
                    } catch {
                        check(false, "\(at): \(error)")
                        continue
                    }
                } else if let c = part.circle {
                    check(c.count == 3 && c[2] > 0, "\(at): circle is [cx, cy, r]")
                    guard c.count == 3 else { continue }
                    points = (0..<36).map { (c[0] + c[2] * cos(Double($0) * .pi / 18), c[1] + c[2] * sin(Double($0) * .pi / 18)) }
                }
                if role == .flame || role == .flameCore {
                    check(part.d?.hasSuffix("Z") == true, "\(at): filled flame shapes must be closed paths")
                    check(part.nozzle != nil, "\(at): flames need a nozzle (at, dir)")
                }
                if let nozzle = part.nozzle {
                    check(nozzle.at.count == 2 && nozzle.dir.count == 2, "\(at): nozzle needs at and dir")
                    if nozzle.dir.count == 2 { check(abs(hypot(nozzle.dir[0], nozzle.dir[1]) - 1) < 0.02, "\(at): nozzle.dir must be a unit vector") }
                }
                let half = base * style.weight / 2
                if let spin = part.spin {
                    check(spin.pivot.count == 2 && spin.radius > 0, "\(at): spin needs pivot and radius")
                    guard spin.pivot.count == 2 else { continue }
                    let reach = points.map { hypot($0.x - spin.pivot[0], $0.y - spin.pivot[1]) }.max() ?? 0
                    let far = distance(spin.pivot[0], spin.pivot[1]) + reach + half
                    check(far <= radius + 1e-6, "\(at): spinning part leaves the safe circle (\(far))")
                }
                if part.bleed == true {
                    check(points.allSatisfy { $0.x >= -0.01 && $0.x <= 100.01 && $0.y >= -0.01 && $0.y <= 100.01 },
                          "\(at): bleed part leaves the canvas")
                    if role == .body {
                        let front = points.filter { $0.x > 45 }.map { distance($0.x, $0.y) }
                        let worst = (front.max() ?? -half) + half
                        check(worst <= radius + 1e-6, "\(at): the leading half of a bleeding body leaves the safe circle (\(worst))")
                    }
                } else {
                    let worst = (points.map { distance($0.x, $0.y) }.max() ?? 0) + half
                    check(worst <= radius + 1e-6, "\(at): outside the safe circle (\(worst))")
                }
            }
            if let rig = vehicle.rig {
                checkRig(rig, vehicle: vehicle, base: base, distance: distance, radius: radius, check)
            }
            for emitter in vehicle.emitters {
                let at = "\(key).emitter.\(emitter.id)"
                check(emitterTypes.contains(emitter.type), "\(at): unknown emitter type")
                check(emitter.at.count == 2 && emitter.dir.count == 2, "\(at): emitter needs at and dir")
                guard emitter.at.count == 2, emitter.dir.count == 2 else { continue }
                check((0...100).contains(emitter.at[0]) && (0...100).contains(emitter.at[1]), "\(at): emitter outside canvas")
                let length = hypot(emitter.dir[0], emitter.dir[1])
                check(length == 0 || abs(length - 1) < 0.02, "\(at): dir must be a unit vector (or 0 for radial)")
            }
            if vehicle.scenery == "road", key != "walk", let ground = vehicle.groundY {
                for wheel in vehicle.parts where wheel.role == "wheel" {
                    if let c = wheel.circle, c.count == 3 {
                        check(abs(c[1] + c[2] - ground) < 0.05, "\(key).\(wheel.id): tire must touch the road")
                    }
                }
            }
        }
        return problems
    }

    private static func checkRig(_ rig: HeroAsset.Rig, vehicle: HeroAsset.Vehicle, base: Double,
                                 distance: (Double, Double) -> Double, radius: Double, _ check: (Bool, @autoclosure () -> String) -> Void) {
        let key = vehicle.key
        guard let prepared = HeroLibrary.prepareRig(rig) else {
            check(false, "\(key): unknown or incomplete rig")
            return
        }
        func inside(_ pose: HeroRigPose, _ what: String) {
            var limbs = [pose.far0, pose.far1]
            for index in 0..<pose.nearCount { limbs.append(pose.near(index)) }
            if let pedal = pose.nearPedal { limbs.append(pedal) }
            for limb in limbs {
                for index in 0..<limb.count {
                    let p = limb[index]
                    let worst = distance(p.x, p.y) + base / 2
                    check(worst <= radius + 1e-6, "\(key): \(what) leaves the safe circle (\(worst))")
                }
            }
            if let head = pose.head {
                let worst = distance(head.x, head.y) + head.z + base / 2
                check(worst <= radius + 1e-6, "\(key): \(what) head leaves the safe circle (\(worst))")
            }
        }
        let samples = 48
        switch prepared {
        case .walk(let walk):
            let ground = vehicle.groundY ?? 0
            inside(HeroRig.walk(walk, distance: 0, ground: ground, stand: 1).pose, "standing pose")
            for k in 0..<samples {
                let solved = HeroRig.walk(walk, distance: walk.cycle * Double(k) / Double(samples), ground: ground, stand: 0)
                check(!solved.stretched, "\(key): leg overextended")
                inside(solved.pose, "rig pose")
            }
        case .pedal(let pedal):
            for k in 0..<samples {
                let solved = HeroRig.pedal(pedal, distance: 2 * .pi * pedal.crankRadius * Double(k) / Double(samples), lift: 0)
                check(!solved.stretched, "\(key): leg overextended")
                inside(solved.pose, "rig pose")
            }
        }
    }

    /// Unknown keys would be silently ignored by the decoder; the spec forbids them.
    private static func checkKeys(_ json: String, _ check: (Bool, @autoclosure () -> String) -> Void) {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let vehicles = root["vehicles"] as? [[String: Any]] else {
            check(false, "vehicles.json must be an object with a vehicles array")
            return
        }
        for vehicle in vehicles {
            let key = vehicle["key"] as? String ?? "?"
            let extra = Set(vehicle.keys).subtracting(vehicleKeys)
            check(extra.isEmpty, "\(key): unknown keys \(extra.sorted())")
            if let motion = vehicle["motion"] as? [String: Any] {
                let extra = Set(motion.keys).subtracting(motionKeys)
                check(extra.isEmpty, "\(key): unknown motion keys \(extra.sorted())")
            }
            for part in vehicle["parts"] as? [[String: Any]] ?? [] {
                let extra = Set(part.keys).subtracting(partKeys)
                check(extra.isEmpty, "\(key).\(part["id"] as? String ?? "?"): unknown keys \(extra.sorted())")
            }
        }
    }
}

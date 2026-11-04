import Foundation

/// Part roles (DESIGN 4c, table `roles`).
public enum HeroRole: Int, CaseIterable, Sendable {
    case body, detail, window, wheel, rim, spoke, crank, rider, light, glow, shock, flame, flameCore

    public init?(name: String) {
        guard let role = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = role
    }

    public var name: String {
        switch self {
        case .body: "body"
        case .detail: "detail"
        case .window: "window"
        case .wheel: "wheel"
        case .rim: "rim"
        case .spoke: "spoke"
        case .crank: "crank"
        case .rider: "rider"
        case .light: "light"
        case .glow: "glow"
        case .shock: "shock"
        case .flame: "flame"
        case .flameCore: "flameCore"
        }
    }

    /// Roles whose opacity Increase Contrast raises to at least 0.9.
    public var isFaint: Bool { self == .detail || self == .window || self == .rim || self == .spoke }
}

public struct HeroRoleStyle: Sendable {
    public enum Fill: Sendable { case heat, hot }

    public let weight: Double
    public let opacity: Double
    public let glow: Double
    public let sprung: Bool
    /// Painted with the accent `H` instead of `C`.
    public let hot: Bool
    public let fill: Fill?
    public let fillOpacity: Double
}

/// Every vehicle of the title ladder, in ladder order.
public enum HeroVehicleKind: String, CaseIterable, Sendable {
    case walk, bicycle, ebike, motorcycle, car, sportsCar, bulletTrain, raceCar, maglev, jetliner, fighterJet, hypersonic, rocket
}

public enum HeroSceneryKind: String, Sendable {
    case road, rail, guideway, sky, stratosphere, space
}

public struct HeroPart: Sendable {
    public enum Shape: Sendable {
        case path([HeroVertex])
        case circle(cx: Double, cy: Double, r: Double)
    }

    public struct Spin: Sendable {
        public let pivot: SIMD2<Double>
        public let radius: Double
        public let symmetry: Double
    }

    public struct Nozzle: Sendable {
        public let at: SIMD2<Double>
        public let dir: SIMD2<Double>
    }

    public let id: String
    public let role: HeroRole
    public let shape: Shape
    public let spin: Spin?
    public let nozzle: Nozzle?
    public let sprung: Bool
    public let bleed: Bool
    /// First point of the path: the apex the shock cone scales about.
    public let apex: SIMD2<Double>
    /// Horizontal extent and height of a straight part (the maglev hover gap).
    public let span: (x0: Double, x1: Double, y: Double)
}

public enum HeroEmitterKind: String, Sendable {
    case dust, arc, exhaust, trail, sparks, contrail, afterburner, plume
}

public struct HeroEmitter: Sendable {
    public let kind: HeroEmitterKind
    public let at: SIMD2<Double>
    public let dir: SIMD2<Double>
    public let count: Int
    public let lanes: [Double]
    public let length: Double
    public let weak: Bool
}

public struct HeroWalkRig: Sendable {
    public let hip: SIMD2<Double>
    public let torso: SIMD2<Double>
    /// Offset from the shoulder and radius.
    public let head: SIMD3<Double>
    public let thigh, shin, foot, upperArm, forearm: Double
    public let cycle, stance, lift, bob, armSwing, elbow: Double
}

public struct HeroPedalRig: Sendable {
    public let hip: SIMD2<Double>
    public let crankPivot: SIMD2<Double>
    public let crankLength: Double
    public let crankRadius: Double
    public let thigh, shin, pedal, bob: Double
}

public enum HeroRigKind: Sendable {
    case walk(HeroWalkRig)
    case pedal(HeroPedalRig)
}

public struct HeroVehicle: Sendable {
    public let kind: HeroVehicleKind
    public let index: Int
    public let scenery: HeroSceneryKind
    public let groundY: Double?
    /// Travel direction (radians, screen space) for the rocket; nil travels right.
    public let heading: Double?
    public let speed: (lo: Double, hi: Double)
    public let rest: Double
    public let bob: Double
    public let float: Double
    public let hover: Double
    public let rig: HeroRigKind?
    public let parts: [HeroPart]
    public let emitters: [HeroEmitter]
    /// Body bounds (min x, min y, max x, max y) without flames, shock cone, glow and the bleeding tail.
    public let bounds: SIMD4<Double>
    /// Acceleration pitch pivot: the rear tire's ground contact, else the center of `bounds`.
    public let pitchPivot: SIMD2<Double>
    /// Road vehicles on tires (suspension pitch applies).
    public let rollsOnTires: Bool

    public var key: String { kind.rawValue }
    public var center: SIMD2<Double> { SIMD2((bounds.x + bounds.z) / 2, (bounds.y + bounds.w) / 2) }
    public var headingVector: SIMD2<Double> { heading.map { SIMD2(cos($0), sin($0)) } ?? SIMD2(1, 0) }

    public func emitter(_ kind: HeroEmitterKind) -> HeroEmitter? { emitters.first { $0.kind == kind } }
}

public struct HeroLibraryError: Error, CustomStringConvertible {
    public let problems: [String]
    public var description: String { "\(problems.count) problem(s):\n  " + problems.joined(separator: "\n  ") }
}

/// The parsed, validated and pre-flattened art. Built once; every frame only transforms its points.
public final class HeroLibrary: Sendable {
    public let strokeWidth: Double
    public let mask: HeroAsset.Mask
    public let orbFraction: Double
    public let roles: [HeroRoleStyle]
    public let vehicles: [HeroVehicle]
    public let scenery: HeroAsset.Scenery
    public let clouds: [[HeroVertex]]
    /// The vehicle shown parked when no title was ever reached.
    public let fallback: Int

    private static let loaded: Result<HeroLibrary, HeroLibraryError> = {
        do {
            return .success(try HeroLibrary(json: HeroAssetJSON.text))
        } catch let error as HeroLibraryError {
            return .failure(error)
        } catch {
            return .failure(HeroLibraryError(problems: ["\(error)"]))
        }
    }()

    /// The embedded `spec/assets/vehicles.json`; nil (with `loadError`) if it fails validation.
    public static var shared: HeroLibrary? { try? loaded.get() }
    public static var loadError: String? {
        if case .failure(let error) = loaded { return error.description }
        return nil
    }

    public convenience init(json: String) throws {
        let asset: HeroAsset
        do {
            asset = try HeroAsset.decode(json)
        } catch {
            throw HeroLibraryError(problems: ["vehicles.json does not decode: \(error)"])
        }
        let problems = HeroValidation.validate(asset, json: json)
        guard problems.isEmpty else { throw HeroLibraryError(problems: problems) }
        try self.init(validated: asset)
    }

    private init(validated asset: HeroAsset) throws {
        strokeWidth = asset.stroke.width
        mask = asset.mask
        orbFraction = asset.canvas.orbFraction
        scenery = asset.scenery
        roles = HeroRole.allCases.map { role in
            let spec = asset.roles[role.name]!
            return HeroRoleStyle(
                weight: spec.weight,
                opacity: spec.opacity,
                glow: spec.glow,
                sprung: spec.sprung,
                hot: spec.color == "hot",
                fill: spec.fill.map { $0 == "hot" ? .hot : .heat },
                fillOpacity: spec.fillOpacity ?? 0
            )
        }
        clouds = try asset.scenery.sky.clouds.map { HeroPath.flatten(try HeroPath.parse($0), step: 0.8) }
        vehicles = try asset.vehicles.enumerated().map { index, vehicle in
            try Self.prepare(vehicle, index: index, roles: asset.roles)
        }
        fallback = vehicles.firstIndex { $0.key == asset.idle.fallback } ?? 0
    }

    public func index(of key: String) -> Int? { vehicles.firstIndex { $0.key == key } }

    public func style(_ role: HeroRole) -> HeroRoleStyle { roles[role.rawValue] }

    // MARK: Preparation

    private static func point(_ values: [Double]) -> SIMD2<Double> { SIMD2(values[0], values[1]) }

    private static func prepare(_ vehicle: HeroAsset.Vehicle, index: Int, roles: [String: HeroAsset.Role]) throws -> HeroVehicle {
        guard let kind = HeroVehicleKind(rawValue: vehicle.key), let scenery = HeroSceneryKind(rawValue: vehicle.scenery) else {
            throw HeroLibraryError(problems: ["\(vehicle.key): unknown vehicle or scenery"])
        }
        let parts = try vehicle.parts.map { part -> HeroPart in
            let role = HeroRole(name: part.role)!
            let shape: HeroPart.Shape
            var apex = SIMD2<Double>(0, 0)
            var span = (x0: 0.0, x1: 0.0, y: 0.0)
            if let d = part.d {
                let commands = try HeroPath.parse(d)
                let vertices = HeroPath.flatten(commands)
                shape = .path(vertices)
                if let first = vertices.first { apex = SIMD2(first.x, first.y) }
                if let first = vertices.first, let last = vertices.last { span = (first.x, last.x, first.y) }
            } else {
                let c = part.circle!
                shape = .circle(cx: c[0], cy: c[1], r: c[2])
            }
            return HeroPart(
                id: part.id,
                role: role,
                shape: shape,
                spin: part.spin.map { HeroPart.Spin(pivot: point($0.pivot), radius: $0.radius, symmetry: $0.symmetry) },
                nozzle: part.nozzle.map { HeroPart.Nozzle(at: point($0.at), dir: point($0.dir)) },
                sprung: part.sprung ?? roles[part.role]!.sprung,
                bleed: part.bleed ?? false,
                apex: apex,
                span: span
            )
        }
        let emitters = vehicle.emitters.compactMap { emitter -> HeroEmitter? in
            guard let kind = HeroEmitterKind(rawValue: emitter.type) else { return nil }
            return HeroEmitter(
                kind: kind,
                at: point(emitter.at),
                dir: point(emitter.dir),
                count: emitter.count ?? 0,
                lanes: emitter.lanes ?? [],
                length: emitter.length ?? 0,
                weak: emitter.weak ?? false
            )
        }
        let rig = vehicle.rig.flatMap(prepareRig)
        let bounds = bodyBounds(vehicle, parts: parts, rig: rig)
        let rearSpokes = parts.first { $0.spin != nil && $0.role == .spoke }
        let pitchPivot: SIMD2<Double>
        if let rearSpokes, let spin = rearSpokes.spin, let ground = vehicle.groundY {
            pitchPivot = SIMD2(spin.pivot.x, ground)
        } else {
            pitchPivot = SIMD2((bounds.x + bounds.z) / 2, (bounds.y + bounds.w) / 2)
        }
        return HeroVehicle(
            kind: kind,
            index: index,
            scenery: scenery,
            groundY: vehicle.groundY,
            heading: vehicle.heading.map { $0 * .pi / 180 },
            speed: (vehicle.motion.speed[0], vehicle.motion.speed[1]),
            rest: vehicle.motion.rest ?? 0,
            bob: vehicle.motion.bob ?? 0,
            float: vehicle.motion.float ?? 0,
            hover: vehicle.motion.hover ?? 0,
            rig: rig,
            parts: parts,
            emitters: emitters,
            bounds: bounds,
            pitchPivot: pitchPivot,
            rollsOnTires: scenery == .road && parts.contains { $0.role == .wheel }
        )
    }

    static func prepareRig(_ rig: HeroAsset.Rig) -> HeroRigKind? {
        switch rig.type {
        case "walk":
            guard let torso = rig.torso, let head = rig.head, let foot = rig.foot, let upperArm = rig.upperArm,
                  let forearm = rig.forearm, let cycle = rig.cycle, let stance = rig.stance, let lift = rig.lift,
                  let armSwing = rig.armSwing, let elbow = rig.elbow else { return nil }
            return .walk(HeroWalkRig(
                hip: point(rig.hip), torso: point(torso), head: SIMD3(head[0], head[1], head[2]),
                thigh: rig.thigh, shin: rig.shin, foot: foot, upperArm: upperArm, forearm: forearm,
                cycle: cycle, stance: stance, lift: lift, bob: rig.bob, armSwing: armSwing, elbow: elbow
            ))
        case "pedal":
            guard let crank = rig.crank, let pedal = rig.pedal else { return nil }
            return .pedal(HeroPedalRig(
                hip: point(rig.hip), crankPivot: point(crank.pivot), crankLength: crank.length, crankRadius: crank.radius,
                thigh: rig.thigh, shin: rig.shin, pedal: pedal, bob: rig.bob
            ))
        default:
            return nil
        }
    }

    /// The drawing's body extent, as the prototype measures it for speed lines and the upgrade flash.
    private static func bodyBounds(_ vehicle: HeroAsset.Vehicle, parts: [HeroPart], rig: HeroRigKind?) -> SIMD4<Double> {
        var box = SIMD4<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        func add(_ x: Double, _ y: Double) {
            box = SIMD4(min(box.x, x), min(box.y, y), max(box.z, x), max(box.w, y))
        }
        for (part, source) in zip(parts, vehicle.parts) {
            let soft = part.role == .flame || part.role == .flameCore || part.role == .shock || part.role == .glow
            if part.bleed || soft {
                if part.bleed, part.role == .body, let d = source.d, let commands = try? HeroPath.parse(d) {
                    for p in HeroPath.endpoints(commands) where p.x > 30 { add(p.x, p.y) }
                }
                continue
            }
            switch part.shape {
            case .circle(let cx, let cy, let r):
                add(cx - r, cy - r)
                add(cx + r, cy + r)
            case .path:
                if let d = source.d, let commands = try? HeroPath.parse(d) {
                    for p in HeroPath.endpoints(commands) { add(p.x, p.y) }
                }
            }
        }
        switch rig {
        case .walk(let walk):
            let top = walk.hip.y + walk.torso.y + walk.head.y - walk.head.z
            add(walk.hip.x - 10, top)
            add(walk.hip.x + 12, vehicle.groundY ?? walk.hip.y)
        case .pedal(let pedal):
            add(pedal.hip.x - 10, pedal.hip.y - 20)
            add(pedal.hip.x + 12, vehicle.groundY ?? pedal.hip.y)
        case nil:
            break
        }
        return box
    }
}

extension HeroPath {
    /// Every coordinate pair written in the path (control points included), like the prototype's bounding box.
    static func endpoints(_ commands: [Command]) -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        for command in commands {
            switch command {
            case .move(let x, let y), .line(let x, let y):
                out.append((x, y))
            case .quad(let x1, let y1, let x2, let y2):
                out.append((x1, y1))
                out.append((x2, y2))
            case .cubic(let x1, let y1, let x2, let y2, let x3, let y3):
                out.append((x1, y1))
                out.append((x2, y2))
                out.append((x3, y3))
            case .close:
                break
            }
        }
        return out
    }
}

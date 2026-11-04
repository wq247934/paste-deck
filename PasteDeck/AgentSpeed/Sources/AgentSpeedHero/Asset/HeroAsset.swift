import Foundation

/// `spec/assets/vehicles.json` as decoded (DESIGN 4c, Art format). `HeroLibrary` prepares it for drawing.
public struct HeroAsset: Decodable, Sendable {
    public struct Canvas: Decodable, Sendable {
        public let width: Double
        public let height: Double
        public let orbFraction: Double
    }

    public struct Circle: Decodable, Sendable {
        public let cx: Double
        public let cy: Double
        public let r: Double
    }

    public struct Mask: Decodable, Sendable {
        public let cx: Double
        public let cy: Double
        public let solid: Double
        public let clear: Double
    }

    public struct Stroke: Decodable, Sendable {
        public let width: Double
        public let cap: String
        public let join: String
    }

    public struct Role: Decodable, Sendable {
        public let weight: Double
        public let opacity: Double
        public let glow: Double
        public let sprung: Bool
        public let color: String?
        public let fill: String?
        public let fillOpacity: Double?
    }

    public struct Scenery: Decodable, Sendable {
        public struct Road: Decodable, Sendable {
            public let dash: [Double]
            public let parallax: Double
        }

        public struct Rail: Decodable, Sendable {
            public let sleeperSpacing: Double
            public let sleeperDepth: Double
            public let parallax: Double
        }

        public struct Guideway: Decodable, Sendable {
            public let depth: Double
            public let pylonSpacing: Double
            public let pylonDepth: Double
            public let parallax: Double
        }

        public struct Sky: Decodable, Sendable {
            public struct Layer: Decodable, Sendable {
                public let y: Double
                public let scale: Double
                public let parallax: Double
                public let opacity: Double
            }

            public let clouds: [String]
            public let layers: [Layer]
        }

        public struct Stratosphere: Decodable, Sendable {
            public struct Horizon: Decodable, Sendable {
                public let cy: Double
                public let r: Double
            }

            public let horizon: Horizon
            public let parallax: Double
        }

        public struct Space: Decodable, Sendable {
            public let stars: Int
            public let parallax: Double
        }

        public let road: Road
        public let rail: Rail
        public let guideway: Guideway
        public let sky: Sky
        public let stratosphere: Stratosphere
        public let space: Space
    }

    public struct Motion: Decodable, Sendable {
        public let speed: [Double]
        public let rest: Double?
        public let bob: Double?
        public let float: Double?
        public let hover: Double?
    }

    public struct Rig: Decodable, Sendable {
        public struct Crank: Decodable, Sendable {
            public let pivot: [Double]
            public let length: Double
            public let radius: Double
        }

        public let type: String
        public let hip: [Double]
        public let torso: [Double]?
        public let head: [Double]?
        public let thigh: Double
        public let shin: Double
        public let foot: Double?
        public let upperArm: Double?
        public let forearm: Double?
        public let cycle: Double?
        public let stance: Double?
        public let lift: Double?
        public let bob: Double
        public let armSwing: Double?
        public let elbow: Double?
        public let crank: Crank?
        public let pedal: Double?
    }

    public struct Part: Decodable, Sendable {
        public struct Spin: Decodable, Sendable {
            public let pivot: [Double]
            public let radius: Double
            public let symmetry: Double
        }

        public struct Nozzle: Decodable, Sendable {
            public let at: [Double]
            public let dir: [Double]
        }

        public let id: String
        public let role: String
        public let d: String?
        public let circle: [Double]?
        public let spin: Spin?
        public let nozzle: Nozzle?
        public let sprung: Bool?
        public let bleed: Bool?
    }

    public struct Emitter: Decodable, Sendable {
        public let id: String
        public let type: String
        public let at: [Double]
        public let dir: [Double]
        public let count: Int?
        public let lanes: [Double]?
        public let length: Double?
        public let weak: Bool?
    }

    public struct Vehicle: Decodable, Sendable {
        public let key: String
        public let scenery: String
        public let groundY: Double?
        public let heading: Double?
        public let motion: Motion
        public let rig: Rig?
        public let parts: [Part]
        public let emitters: [Emitter]
    }

    public struct Idle: Decodable, Sendable {
        public let vehicle: String
        public let fallback: String
    }

    public let version: Int
    public let canvas: Canvas
    public let safeCircle: Circle
    public let mask: Mask
    public let stroke: Stroke
    public let roles: [String: Role]
    public let scenery: Scenery
    public let vehicles: [Vehicle]
    public let idle: Idle

    public static func decode(_ text: String) throws -> HeroAsset {
        try JSONDecoder().decode(HeroAsset.self, from: Data(text.utf8))
    }
}

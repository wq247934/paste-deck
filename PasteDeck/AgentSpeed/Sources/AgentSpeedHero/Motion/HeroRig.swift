import Foundation

/// A limb as a short polyline (at most four points).
public struct HeroLimb: Sendable, Equatable {
    public var count = 0
    public var p0 = SIMD2<Double>.zero
    public var p1 = SIMD2<Double>.zero
    public var p2 = SIMD2<Double>.zero
    public var p3 = SIMD2<Double>.zero

    public init() {}

    public init(_ a: SIMD2<Double>, _ b: SIMD2<Double>) {
        count = 2
        p0 = a
        p1 = b
    }

    public init(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) {
        count = 3
        p0 = a
        p1 = b
        p2 = c
    }

    public init(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>) {
        count = 4
        p0 = a
        p1 = b
        p2 = c
        p3 = d
    }

    public subscript(index: Int) -> SIMD2<Double> {
        switch index {
        case 0: p0
        case 1: p1
        case 2: p2
        default: p3
        }
    }
}

/// The generated limbs of a rig in one frame (DESIGN 4c, Walker rig / Pedal rig). Far limbs draw before the parts,
/// near limbs and the head after them.
public struct HeroRigPose: Sendable, Equatable {
    public var far0 = HeroLimb()
    public var far1 = HeroLimb()
    public var near0 = HeroLimb()
    public var near1 = HeroLimb()
    public var near2 = HeroLimb()
    public var nearCount = 0
    public var nearPedal: HeroLimb?
    /// Walker head: center and radius.
    public var head: SIMD3<Double>?
    /// Pedal rig: how far the `rider` parts move with the hip.
    public var riderOffset = SIMD2<Double>.zero
    public var hip = SIMD2<Double>.zero

    public init() {}

    public func near(_ index: Int) -> HeroLimb {
        switch index {
        case 0: near0
        case 1: near1
        default: near2
        }
    }
}

public enum HeroRig {
    /// Two-bone IK; the knee (or elbow) lies on the +x side of the hip–foot line (`cross < 0`, y down).
    /// `stretched` reports a target beyond reach.
    public static func knee(hip: SIMD2<Double>, foot: SIMD2<Double>, upper: Double, lower: Double) -> (point: SIMD2<Double>, stretched: Bool) {
        let dx = foot.x - hip.x, dy = foot.y - hip.y
        let reach = upper + lower - 1e-3
        var d = (dx * dx + dy * dy).squareRoot()
        let stretched = d > reach
        d = min(max(d, abs(upper - lower) + 1e-3, 1e-3), reach)
        let base = atan2(dy, dx)
        let cosine = (upper * upper + d * d - lower * lower) / (2 * upper * d)
        let alpha = acos(max(-1, min(1, cosine)))
        var best = SIMD2(hip.x, hip.y + upper)
        var sign = 1.0
        for _ in 0..<2 {
            let angle = base + sign * alpha
            let k = SIMD2(hip.x + upper * cos(angle), hip.y + upper * sin(angle))
            if dx * (k.y - hip.y) - dy * (k.x - hip.x) < 0 { best = k }
            sign = -1
        }
        return (best, stretched)
    }

    /// The walker at ground distance `distance`; `stand` blends to the standing pose (1 = parked).
    public static func walk(_ rig: HeroWalkRig, distance: Double, ground: Double, stand: Double) -> (pose: HeroRigPose, stretched: Bool) {
        var cycle = (distance / rig.cycle).truncatingRemainder(dividingBy: 1)
        if cycle < 0 { cycle += 1 }
        let p = cycle
        let stance = rig.stance
        let a = rig.cycle * stance / 2
        let bob = -rig.bob * cos(4 * .pi * (p - stance / 2)) * (1 - stand)
        let standHip = ground - 0.6 - (rig.thigh + rig.shin) * 0.97
        let hip = SIMD2(rig.hip.x, HeroMath.lerp(rig.hip.y + bob, standHip, stand))
        let shoulder = hip + rig.torso
        let head = SIMD3(shoulder.x + rig.head.x, shoulder.y + rig.head.y, rig.head.z)
        var stretched = false

        func leg(_ phase: Double, spread: Double) -> HeroLimb {
            var foot: SIMD2<Double>
            if phase < stance {
                foot = SIMD2(hip.x + a - 2 * a * (phase / stance), ground - 0.6)
            } else {
                let s = (phase - stance) / (1 - stance)
                foot = SIMD2(hip.x - a + 2 * a * HeroMath.smooth(s), ground - 0.6 - rig.lift * sin(.pi * s))
            }
            let rest = SIMD2(hip.x + spread, ground - 0.6)
            foot = foot + (rest - foot) * stand
            let solved = knee(hip: hip, foot: foot, upper: rig.thigh, lower: rig.shin)
            stretched = stretched || solved.stretched
            return HeroLimb(hip, solved.point, foot, SIMD2(foot.x + rig.foot, foot.y))
        }

        func arm(_ phase: Double, rest: Double) -> HeroLimb {
            let swing = -rig.armSwing * cos(2 * .pi * phase)
            let theta = HeroMath.lerp(swing, rest, stand) * .pi / 180
            let elbow = SIMD2(shoulder.x + rig.upperArm * sin(theta), shoulder.y + rig.upperArm * cos(theta))
            let bend = theta + rig.elbow * HeroMath.lerp(1, 0.5, stand) * .pi / 180
            return HeroLimb(shoulder, elbow, SIMD2(elbow.x + rig.forearm * sin(bend), elbow.y + rig.forearm * cos(bend)))
        }

        let opposite = (p + 0.5).truncatingRemainder(dividingBy: 1)
        var pose = HeroRigPose()
        pose.far0 = leg(opposite, spread: -1.6)
        pose.far1 = arm(opposite, rest: -4)
        pose.near0 = HeroLimb(hip, shoulder)
        pose.near1 = leg(p, spread: 1.6)
        pose.near2 = arm(p, rest: 4)
        pose.nearCount = 3
        pose.head = head
        pose.hip = hip
        return (pose, stretched)
    }

    /// A rider pedalling at ground distance `distance`; `lift` raises the hip off the saddle (start-up).
    public static func pedal(_ rig: HeroPedalRig, distance: Double, lift: Double) -> (pose: HeroRigPose, stretched: Bool) {
        let phi = HeroMath.wrapAngle(distance / rig.crankRadius)
        let pivot = rig.crankPivot
        let length = rig.crankLength
        let nearPedal = SIMD2(pivot.x - length * sin(phi), pivot.y + length * cos(phi))
        let farPedal = SIMD2(pivot.x + length * sin(phi), pivot.y - length * cos(phi))
        let bob = rig.bob * cos(2 * phi) - lift
        let hip = SIMD2(rig.hip.x + lift * 0.6, rig.hip.y + bob)
        let half = rig.pedal / 2
        let near = knee(hip: hip, foot: nearPedal, upper: rig.thigh, lower: rig.shin)
        let far = knee(hip: hip, foot: farPedal, upper: rig.thigh, lower: rig.shin)
        var pose = HeroRigPose()
        pose.far0 = HeroLimb(hip, far.point, farPedal)
        pose.far1 = HeroLimb(SIMD2(farPedal.x - half, farPedal.y), SIMD2(farPedal.x + half, farPedal.y))
        pose.near0 = HeroLimb(hip, near.point, nearPedal)
        pose.nearCount = 1
        pose.nearPedal = HeroLimb(SIMD2(nearPedal.x - half, nearPedal.y), SIMD2(nearPedal.x + half, nearPedal.y))
        pose.riderOffset = SIMD2(lift * 0.6, bob)
        pose.hip = hip
        return (pose, near.stretched || far.stretched)
    }
}

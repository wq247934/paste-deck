import QuartzCore

/// The plate's animated values (DESIGN 2b, Name plate, Motion), sampled in closed form so a retarget keeps position
/// and velocity: presence (opacity), the approach toward the disc, the appear scale, the capsule's two edges (relative
/// to its anchor), the chip crossfade and the name crossfade.
struct NameplateMotion {
    struct Sample {
        var presence: CGFloat
        var approach: CGFloat
        var scale: CGFloat
        var left: CGFloat
        var right: CGFloat
        var expand: CGFloat
        var morph: CGFloat
    }

    /// The width spring (response 0.3 s, damping 0.86, about the plate's center).
    static let widthSpring = OrbWindowMotion.spring(response: 0.3, damping: 0.86)

    private var presence = OrbWindowChannel(0, tolerance: 0.002)
    private var approach = OrbWindowChannel(0, tolerance: 0.01)
    private var scale = OrbWindowChannel(1, tolerance: 0.0005)
    private var left = OrbWindowChannel(0, tolerance: 0.02)
    private var right = OrbWindowChannel(0, tolerance: 0.02)
    private var expand = OrbWindowChannel(0, tolerance: 0.002)
    private var morph = OrbWindowChannel(1, tolerance: 0.002)

    var isActive: Bool {
        presence.isActive || approach.isActive || scale.isActive || left.isActive || right.isActive || expand.isActive
            || morph.isActive
    }

    var presenceTarget: CGFloat { presence.target }
    var isPresenceMoving: Bool { presence.isActive }
    var edgeTargets: (left: CGFloat, right: CGFloat) { (left.target, right.target) }
    var expandTarget: CGFloat { expand.target }

    func sample(at time: CFTimeInterval) -> Sample {
        Sample(presence: presence.value(at: time), approach: approach.value(at: time), scale: scale.value(at: time),
               left: left.value(at: time), right: right.value(at: time), expand: expand.value(at: time),
               morph: morph.value(at: time))
    }

    /// Ends finished animations; returns whether any is still running.
    @discardableResult
    mutating func settle(at time: CFTimeInterval) -> Bool {
        presence.settle(at: time)
        approach.settle(at: time)
        scale.settle(at: time)
        left.settle(at: time)
        right.settle(at: time)
        expand.settle(at: time)
        morph.settle(at: time)
        return isActive
    }

    /// Appear: opacity 0 → 1, 4 pt from the disc side → 0, scale 0.96 → 1, ease-out over `duration` (Reduce Motion: a
    /// fade only).
    mutating func appear(duration: Double, reduceMotion: Bool, at time: CFTimeInterval) {
        presence.set(0)
        approach.set(reduceMotion ? 0 : 4)
        scale.set(reduceMotion ? 1 : 0.96)
        let motion = OrbWindowMotion.ease(duration: duration)
        presence.animate(to: 1, motion: motion, at: time)
        approach.animate(to: 0, motion: motion, at: time)
        scale.animate(to: 1, motion: motion, at: time)
    }

    /// Disappear: a fade while moving 2 pt toward the disc (Reduce Motion: a fade only).
    mutating func disappear(duration: Double, reduceMotion: Bool, at time: CFTimeInterval) {
        let motion = OrbWindowMotion.ease(duration: duration)
        presence.animate(to: 0, motion: motion, at: time)
        if !reduceMotion { approach.animate(to: 2, motion: motion, at: time) }
    }

    mutating func show() {
        presence.set(1)
        approach.set(0)
        scale.set(1)
    }

    mutating func hide() {
        presence.set(0)
        approach.set(0)
        scale.set(1)
    }

    /// Moves the capsule's edges; nil motion jumps.
    mutating func setEdges(left newLeft: CGFloat, right newRight: CGFloat, motion: OrbWindowMotion?, at time: CFTimeInterval) {
        guard let motion else {
            left.set(newLeft)
            right.set(newRight)
            return
        }
        left.animate(to: newLeft, motion: motion, at: time)
        right.animate(to: newRight, motion: motion, at: time)
    }

    mutating func setExpand(_ value: CGFloat, duration: Double?, at time: CFTimeInterval) {
        guard let duration else { expand.set(value); return }
        expand.animate(to: value, motion: .ease(duration: duration), at: time)
    }

    /// Restarts the name crossfade from the previous face (0) to the current one (1).
    mutating func startMorph(duration: Double?, at time: CFTimeInterval) {
        guard let duration else { morph.set(1); return }
        morph.set(0)
        morph.animate(to: 1, motion: .ease(duration: duration), at: time)
    }
}

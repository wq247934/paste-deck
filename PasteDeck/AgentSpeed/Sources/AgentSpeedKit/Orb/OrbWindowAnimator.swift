import AppKit
import QuartzCore

/// Timing curves for window motion.
enum OrbWindowMotion: Sendable {
    case spring(response: Double, damping: Double)
    case ease(duration: Double)

    /// Magnetic edge snap.
    static let snap = OrbWindowMotion.spring(response: 0.35, damping: 0.8)
    /// Size changes and programmatic moves (DESIGN section 6 layout spring).
    static let layout = OrbWindowMotion.spring(response: 0.45, damping: 0.82)
    /// Mirrors `Motion.hover` used by the renderer for the 1.03 hover scale.
    static let hover = OrbWindowMotion.spring(response: 0.32, damping: 0.72)
    /// Reduce Motion replacement for springs.
    static let reduced = OrbWindowMotion.ease(duration: 0.15)
    /// A created or split orb springs in (DESIGN 2b, Placement and Split motion).
    static let entrance = OrbWindowMotion.spring(response: 0.45, damping: 0.78)
    /// The disc following the pointer while dragging near other orbs: critically damped, settle 0.12 s.
    static let follow = OrbWindowMotion.spring(response: 0.12, damping: 1)
}

/// One animated scalar, sampled in closed form so retargeting keeps position and velocity continuous.
struct OrbWindowChannel {
    private(set) var target: Double
    private var origin: Double
    private var initialVelocity: Double = 0
    private var startTime: CFTimeInterval = 0
    private var motion: OrbWindowMotion?
    private let tolerance: Double

    init(_ value: Double, tolerance: Double) {
        target = value
        origin = value
        self.tolerance = tolerance
    }

    var isActive: Bool { motion != nil }

    func value(at time: CFTimeInterval) -> Double { sample(at: time).value }

    mutating func set(_ value: Double) {
        target = value
        origin = value
        initialVelocity = 0
        motion = nil
    }

    mutating func animate(to newTarget: Double, motion: OrbWindowMotion, velocity: Double? = nil, at time: CFTimeInterval) {
        let current = sample(at: time)
        guard newTarget != target || isActive || (velocity ?? 0) != 0 else { return }
        origin = current.value
        initialVelocity = velocity ?? current.velocity
        target = newTarget
        startTime = time
        self.motion = motion
        if abs(origin - target) < tolerance, abs(initialVelocity) < tolerance * 10 { set(target) }
    }

    /// Ends the animation once settled; returns whether it is still running.
    @discardableResult
    mutating func settle(at time: CFTimeInterval) -> Bool {
        guard let motion else { return false }
        let current = sample(at: time)
        let done: Bool = switch motion {
        case let .ease(duration): time - startTime >= duration
        case .spring: abs(current.value - target) < tolerance && abs(current.velocity) < tolerance * 10
        }
        if done { set(target) }
        return !done
    }

    private func sample(at time: CFTimeInterval) -> (value: Double, velocity: Double) {
        guard let motion else { return (target, 0) }
        let t = max(0, time - startTime)
        let offset = origin - target
        switch motion {
        case let .ease(duration):
            guard duration > 0, t < duration else { return (target, 0) }
            let p = t / duration
            let eased = 1 - pow(1 - p, 3)
            let slope = 3 * pow(1 - p, 2) / duration
            return (origin + (target - origin) * eased, (target - origin) * slope)
        case let .spring(response, damping):
            let omega = 2 * Double.pi / max(response, 0.01)
            if damping >= 1 {
                let c = initialVelocity + omega * offset
                let decay = exp(-omega * t)
                return (target + (offset + c * t) * decay, (c - omega * (offset + c * t)) * decay)
            }
            let zeta = max(damping, 0.01)
            let wd = omega * sqrt(1 - zeta * zeta)
            let b = (initialVelocity + zeta * omega * offset) / wd
            let decay = exp(-zeta * omega * t)
            let cosine = cos(wd * t)
            let sine = sin(wd * t)
            let value = target + decay * (offset * cosine + b * sine)
            let velocity = decay * ((-zeta * omega * offset + wd * b) * cosine + (-zeta * omega * b - wd * offset) * sine)
            return (value, velocity)
        }
    }
}

/// The disc center, diameter and hover scale of the floating orb, animated on a display link of the host view.
@MainActor
final class OrbWindowAnimator {
    struct State: Equatable {
        var center: CGPoint
        var diameter: CGFloat
        var hoverScale: CGFloat
        /// Entrance and exit scale (created, split and merged orbs), 1 at rest.
        var presence: CGFloat = 1

        /// The scale the disc is drawn at.
        var scale: CGFloat { hoverScale * presence }
    }

    /// Called whenever the state changes, at most once per display frame while animating.
    var onChange: ((State) -> Void)?
    /// Called once when a center animation comes to rest.
    var onCenterSettled: (() -> Void)?

    private var x: OrbWindowChannel
    private var y: OrbWindowChannel
    private var diameter: OrbWindowChannel
    private var hoverScale: OrbWindowChannel
    private var presence = OrbWindowChannel(1, tolerance: 0.0005)
    private weak var view: NSView?
    private var link: CADisplayLink?
    private lazy var proxy = OrbWindowDisplayLinkProxy(owner: self)

    init(center: CGPoint, diameter: CGFloat) {
        x = OrbWindowChannel(center.x, tolerance: 0.05)
        y = OrbWindowChannel(center.y, tolerance: 0.05)
        self.diameter = OrbWindowChannel(diameter, tolerance: 0.05)
        hoverScale = OrbWindowChannel(1, tolerance: 0.0003)
    }

    /// The view whose display drives the animation clock.
    func attach(to view: NSView) {
        self.view = view
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    var state: State { state(at: CACurrentMediaTime()) }

    /// Final values once every running animation has settled.
    var targetState: State {
        State(center: CGPoint(x: x.target, y: y.target), diameter: diameter.target, hoverScale: hoverScale.target,
              presence: presence.target)
    }

    var isMovingCenter: Bool { x.isActive || y.isActive }

    /// Jumps the center (drag); the diameter and hover animations keep running.
    func setCenter(_ center: CGPoint) {
        x.set(center.x)
        y.set(center.y)
        publish()
    }

    /// Stops a center animation where it currently is.
    func freezeCenter() {
        let now = state
        x.set(now.center.x)
        y.set(now.center.y)
    }

    func jump(center: CGPoint, diameter: CGFloat) {
        x.set(center.x)
        y.set(center.y)
        self.diameter.set(diameter)
        publish()
    }

    func animate(center: CGPoint, motion: OrbWindowMotion?, velocity: CGVector = .zero) {
        guard let motion else { setCenter(center); onCenterSettled?(); return }
        let time = CACurrentMediaTime()
        x.animate(to: center.x, motion: motion, velocity: center.x == x.value(at: time) ? nil : Double(velocity.dx), at: time)
        y.animate(to: center.y, motion: motion, velocity: center.y == y.value(at: time) ? nil : Double(velocity.dy), at: time)
        run()
        if !isMovingCenter { onCenterSettled?() }
    }

    func animate(diameter target: CGFloat, motion: OrbWindowMotion?) {
        guard let motion else { diameter.set(target); publish(); return }
        diameter.animate(to: target, motion: motion, at: CACurrentMediaTime())
        run()
    }

    /// Sets the entrance scale at once (before an entrance animation).
    func setPresence(_ value: CGFloat) {
        presence.set(value)
        publish()
    }

    func animate(presence target: CGFloat, motion: OrbWindowMotion?) {
        guard let motion else { presence.set(target); publish(); return }
        presence.animate(to: target, motion: motion, at: CACurrentMediaTime())
        run()
    }

    func animate(hoverScale target: CGFloat, motion: OrbWindowMotion?) {
        guard let motion else { hoverScale.set(target); publish(); return }
        hoverScale.animate(to: target, motion: motion, at: CACurrentMediaTime())
        run()
    }

    /// Ends every animation at its target.
    func finish() {
        stop()
        let wasMoving = isMovingCenter
        settleAll()
        publish()
        if wasMoving { onCenterSettled?() }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let time = link.targetTimestamp
        let wasMoving = isMovingCenter
        x.settle(at: time)
        y.settle(at: time)
        diameter.settle(at: time)
        hoverScale.settle(at: time)
        presence.settle(at: time)
        onChange?(state(at: time))
        if !isAnimating { stop() }
        if wasMoving, !isMovingCenter { onCenterSettled?() }
    }

    private func state(at time: CFTimeInterval) -> State {
        State(
            center: CGPoint(x: x.value(at: time), y: y.value(at: time)),
            diameter: diameter.value(at: time),
            hoverScale: hoverScale.value(at: time),
            presence: presence.value(at: time)
        )
    }

    private var isAnimating: Bool { x.isActive || y.isActive || diameter.isActive || hoverScale.isActive || presence.isActive }

    private func run() {
        guard isAnimating else { stop(); publish(); return }
        guard link == nil else { return }
        guard let view, view.window?.isVisible == true else {
            settleAll()
            publish()
            return
        }
        let link = view.displayLink(target: proxy, selector: #selector(OrbWindowDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func settleAll() {
        let target = targetState
        x.set(target.center.x)
        y.set(target.center.y)
        diameter.set(target.diameter)
        hoverScale.set(target.hoverScale)
        presence.set(target.presence)
    }

    private func publish() {
        onChange?(state)
    }
}

/// Breaks the retain cycle between `CADisplayLink` (which retains its target) and the animator.
@MainActor
private final class OrbWindowDisplayLinkProxy: NSObject {
    private weak var owner: OrbWindowAnimator?

    init(owner: OrbWindowAnimator) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.tick(link)
    }
}

import AgentSpeedOrbModel
import AppKit
import QuartzCore

/// What a surface asks of the frame clock.
struct OrbFrameRequest: Equatable {
    var frameClass: OrbFrameClass
    /// Previews: never faster than this many frames per second (`frameClass` is then only on/off).
    var cap: Double?
    /// Floating orbs take part in the crowd rule (DESIGN 2a: from four orbs at 60 fps all but one drop to 30).
    var countsForCrowd = true

    static let none = OrbFrameRequest(frameClass: .none)
}

/// A surface the shared frame clock drives.
@MainActor
protocol OrbFrameClient: AnyObject {
    var frameRequest: OrbFrameRequest { get }
    /// The screen the surface is on (nil while not in a window).
    var frameScreen: NSScreen? { get }
    func renderFrame(at time: TimeInterval)
}

/// One frame clock per display for every orb and preview (DESIGN 2a, Frame policy): a single `CADisplayLink` per
/// screen running at the refresh rate divided by the common divisor of what its surfaces need; each surface renders
/// only on its own k-th refresh tick, so equal classes render together. No link runs while nothing animates.
@MainActor
final class OrbFrameClock {
    static let shared = OrbFrameClock()

    private struct Entry {
        weak var client: OrbFrameClient?
        var divisor: Int?
        var displayID: CGDirectDisplayID?
    }

    @MainActor
    private final class ScreenLink: NSObject {
        let displayID: CGDirectDisplayID
        let refresh: Double
        var link: CADisplayLink?
        var linkDivisor = 0
        var lastIndex: Int64 = .min
        weak var clock: OrbFrameClock?

        init(displayID: CGDirectDisplayID, refresh: Double, clock: OrbFrameClock) {
            self.displayID = displayID
            self.refresh = refresh
            self.clock = clock
        }

        @objc func tick(_ link: CADisplayLink) {
            clock?.tick(self, link: link)
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var links: [CGDirectDisplayID: ScreenLink] = [:]
    private var order: [ObjectIdentifier] = []
    /// The hovered or most recently interacted orb keeps 60 fps in a crowd.
    var focused: ObjectIdentifier? {
        didSet { if focused != oldValue { update() } }
    }
    /// Frames rendered since launch (benchmarks).
    private(set) var framesRendered = 0

    private init() {}

    func register(_ client: OrbFrameClient) {
        let id = ObjectIdentifier(client)
        guard entries[id] == nil else { return }
        entries[id] = Entry(client: client)
        order.append(id)
        update()
    }

    func unregister(_ client: OrbFrameClient) {
        let id = ObjectIdentifier(client)
        entries[id] = nil
        order.removeAll { $0 == id }
        update()
    }

    /// Call when a client's request or screen changed.
    func update() {
        entries = entries.filter { $0.value.client != nil }
        order.removeAll { entries[$0] == nil }
        let requests = order.map { entries[$0]?.client?.frameRequest ?? .none }
        let crowd = order.enumerated().filter { requests[$0.offset].countsForCrowd }
        let focusIndex = crowd.firstIndex { $0.element == focused }
        let effective = OrbFramePolicy.effective(crowd.map { requests[$0.offset].frameClass }, focused: focusIndex)
        var classes = requests.map(\.frameClass)
        for (index, item) in crowd.enumerated() { classes[item.offset] = effective[index] }

        var needed: [CGDirectDisplayID: [Int]] = [:]
        for (index, id) in order.enumerated() {
            guard var entry = entries[id], let client = entry.client else { continue }
            let request = requests[index]
            guard classes[index] != .none, let screen = client.frameScreen, let displayID = screen.orbDisplayID else {
                entry.divisor = nil
                entry.displayID = nil
                entries[id] = entry
                continue
            }
            let refresh = Double(max(30, screen.maximumFramesPerSecond))
            let divisor = request.cap.map { OrbFramePolicy.divisor(refresh: refresh, atMost: $0) }
                ?? OrbFramePolicy.divisor(refresh: refresh, target: classes[index].nominalRate)
            entry.divisor = divisor
            entry.displayID = displayID
            entries[id] = entry
            needed[displayID, default: []].append(divisor)
            if links[displayID] == nil || links[displayID]?.refresh != refresh {
                links[displayID]?.link?.invalidate()
                links[displayID] = ScreenLink(displayID: displayID, refresh: refresh, clock: self)
            }
            if let screenLink = links[displayID], screenLink.link == nil {
                let link = screen.displayLink(target: screenLink, selector: #selector(ScreenLink.tick(_:)))
                link.add(to: .main, forMode: .common)
                screenLink.link = link
            }
        }
        for (displayID, screenLink) in links {
            guard let divisors = needed[displayID] else {
                screenLink.link?.invalidate()
                screenLink.link = nil
                screenLink.linkDivisor = 0
                continue
            }
            let divisor = max(1, OrbFramePolicy.linkDivisor(divisors))
            if divisor != screenLink.linkDivisor, let link = screenLink.link {
                screenLink.linkDivisor = divisor
                screenLink.lastIndex = .min
                let rate = Float(screenLink.refresh / Double(divisor))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            }
        }
    }

    private func tick(_ screenLink: ScreenLink, link: CADisplayLink) {
        let step = Int64(max(1, screenLink.linkDivisor))
        let linkIndex = Int64((link.targetTimestamp * screenLink.refresh / Double(step)).rounded())
        guard linkIndex != screenLink.lastIndex else { return }
        screenLink.lastIndex = linkIndex
        let index = linkIndex * step
        let time = Clock.now + (link.targetTimestamp - CACurrentMediaTime())
        for id in order {
            guard let entry = entries[id], entry.displayID == screenLink.displayID, let divisor = entry.divisor,
                  let client = entry.client, OrbFramePolicy.renders(onTick: index, divisor: divisor) else { continue }
            client.renderFrame(at: time)
            framesRendered += 1
        }
    }
}

extension NSScreen {
    var orbDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

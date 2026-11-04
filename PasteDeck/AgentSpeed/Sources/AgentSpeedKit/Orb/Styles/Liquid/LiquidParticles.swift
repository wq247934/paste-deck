import Foundation

/// The liquid's particles (DESIGN 2a.3, Particles). Positions are points from the disc center (y down); each pool is a
/// fixed-capacity array with swap removal, so stepping never allocates.
struct LiquidMote {
    var x: Double
    var y: Double
    var vy: Double
    var size: Double
    /// Wobble phase (radians).
    var phase: Double
    /// New-peak gold motes rise faster and always glow.
    var gold: Bool
}

struct LiquidPop {
    var x: Double
    var y: Double
    var age: Double
    var size: Double
}

struct LiquidSplash {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double
    var life: Double
    var size: Double
}

struct LiquidSteam {
    var x: Double
    /// Height above the mean surface (negative = up).
    var y: Double
    var vy: Double
    var age: Double
    var life: Double
    var size: Double
    var phase: Double
}

/// A pulse droplet falling toward the surface.
struct LiquidDrop {
    var x: Double
    var y: Double
    var vy: Double
    var heat: Double
    var strength: Double
}

/// An impact on the surface: center x (points from the disc center), start time and amplitude (in S).
struct LiquidRipple {
    var x: Double
    var start: Double
    var amplitude: Double
}

/// A fixed-capacity buffer with swap removal.
struct LiquidPool<Element> {
    private(set) var items: ContiguousArray<Element> = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        items.reserveCapacity(capacity)
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    @discardableResult
    mutating func append(_ element: Element) -> Bool {
        guard items.count < capacity else { return false }
        items.append(element)
        return true
    }

    mutating func removeAll() {
        items.removeAll(keepingCapacity: true)
    }

    /// Updates every element; `body` returns false to remove it.
    mutating func update(_ body: (inout Element) -> Bool) {
        var index = 0
        while index < items.count {
            if body(&items[index]) {
                index += 1
            } else {
                items.swapAt(index, items.count - 1)
                items.removeLast()
            }
        }
    }

    mutating func removeFirst() {
        guard !items.isEmpty else { return }
        items.remove(at: 0)
    }
}

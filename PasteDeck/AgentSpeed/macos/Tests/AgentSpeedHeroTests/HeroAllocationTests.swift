import Darwin
import Foundation
import Testing
@testable import AgentSpeedHero

/// Counts heap allocations made on one thread through the system's malloc logger hook.
enum AllocationProbe {
    typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    nonisolated(unsafe) static var count = 0
    nonisolated(unsafe) static var thread: pthread_t?
    nonisolated(unsafe) static let slot = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?.assumingMemoryBound(to: Logger?.self)

    /// Allocations `body` makes on the calling thread, or nil when the hook is unavailable.
    static func allocations(_ body: () -> Void) -> Int? {
        guard let slot else { return nil }
        count = 0
        thread = pthread_self()
        slot.pointee = { type, _, _, _, _, _ in
            if type & 2 != 0, let thread = AllocationProbe.thread, pthread_equal(pthread_self(), thread) != 0 {
                AllocationProbe.count += 1
            }
        }
        body()
        slot.pointee = nil
        thread = nil
        return count
    }
}

#if DEBUG
/// Unoptimized code allocates for generic SIMD arithmetic, so the check runs in optimized builds only
/// (`swift test -c release`).
private let optimized = false
#else
private let optimized = true
#endif

@Test(.serialized, .enabled(if: optimized, "allocation check needs an optimized build: swift test -c release"),
      arguments: [HeroLevel.standard, .max])
func warmFramesDoNotAllocate(level: HeroLevel) throws {
    let library = try HeroFixtures.library
    let builder = HeroFrameBuilder(library: library)
    let list = HeroDrawList()
    let paint = HeroPaints.paint(dark: true)
    let sanity = AllocationProbe.allocations { _ = [Int](repeating: 1, count: Int.random(in: 100...200)) }
    guard let sanity, sanity > 0 else {
        Issue.record("malloc logger unavailable")
        return
    }
    var drive = HeroDrive(library: library)
    drive.level = level
    drive.prime(title: nil, value: 0)
    // Warm every vehicle, transition and start-up once, then count a second pass.
    var counts: [Int] = []
    for pass in 0..<2 {
        for index in 0..<13 {
            drive.change(to: index, value: HeroDrive.threshold(index) * 1.15)
            for _ in 0..<70 {
                let allocations = AllocationProbe.allocations {
                    drive.run(1.0 / 60)
                    builder.build(stage: drive.stage, paint: paint, into: list)
                } ?? 0
                if pass == 1 { counts.append(allocations) }
            }
        }
        drive.change(to: nil, value: 0)
        drive.run(1)
    }
    let total = counts.reduce(0, +)
    #expect(total == 0, "\(total) allocations over \(counts.count) warm frames")
}

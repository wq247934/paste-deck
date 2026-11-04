import Foundation
import Testing
@testable import AgentSpeedOrbModel

@Suite("LED noise")
struct LedNoiseTests {
    @Test func simplexMatchesTheShaderFunction() {
        // Values of the prototype's GLSL snoise (evaluated by a direct JavaScript port).
        #expect(abs(LedNoise.simplex(0.3, 0.2, 0.1) - -0.04521685759011959) < 1e-9)
        #expect(abs(LedNoise.simplex(1.7, -2.3, 4.1) - 0.42476389353915833) < 1e-9)
    }

    @Test func simplexIsBoundedAndSmooth() {
        var largest = 0.0
        // From k = 1: exact lattice ties (k = 0 is (0, 4, 0)) pick a degenerate simplex, in the shader too.
        for k in 1..<2000 {
            let t = Double(k) * 0.0137
            let n = LedNoise.simplex(sin(t * 3.1) * 4, cos(t * 1.7) * 4, t)
            largest = max(largest, abs(n))
            let step = LedNoise.simplex(sin(t * 3.1) * 4 + 0.001, cos(t * 1.7) * 4, t)
            #expect(abs(step - n) < 0.03)
        }
        #expect(largest <= 1.0)
        #expect(largest > 0.5)
    }

    @Test func coronaBodySamplesTheRimInZeroToOne() {
        var buffer = ContiguousArray<Float>()
        LedNoise.coronaBody(phase: 12.5, into: &buffer)
        #expect(buffer.count == LedNoise.coronaSamples)
        #expect(buffer.allSatisfy { $0 >= 0 && $0 <= 1 })
        // Sample k is the prototype's body at the angle 360° k / 128 (dir y up).
        let a = 2 * Double.pi * 32 / 128
        let expected = 0.5 + 0.5 * LedNoise.simplex(2.2 * cos(a), -2.2 * sin(a), 12.5 * 0.35)
        #expect(abs(Double(buffer[32]) - expected) < 1e-6)
        // A warm buffer is filled in place.
        let storage = buffer.withUnsafeBufferPointer { $0.baseAddress }
        LedNoise.coronaBody(phase: 13, into: &buffer)
        #expect(buffer.withUnsafeBufferPointer { $0.baseAddress } == storage)
    }
}

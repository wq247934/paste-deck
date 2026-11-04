import Foundation

/// 3D simplex noise (Ashima Arts / Stefan Gustavson, MIT), the same function as the `led` shaders' `snoise`, for the
/// values that depend only on the angle around the orb and are evaluated once per frame on the CPU.
public enum LedNoise {
    /// Samples of the corona's slow `body` noise around the rim (DESIGN 2.1, Corona).
    public static let coronaSamples = 128

    /// The corona body `0.5 + 0.5 snoise(2.2 dir, 0.35 φcorona)` at `count` angles clockwise from 3 o'clock on screen
    /// (sample k at 360° k / count), written into `buffer` (count ≥ `count`). `dir` is y up, as in the prototype.
    public static func coronaBody(phase: Double, count: Int = coronaSamples, into buffer: inout ContiguousArray<Float>) {
        if buffer.count < count { buffer.append(contentsOf: repeatElement(0, count: count - buffer.count)) }
        let z = phase * 0.35
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            buffer[k] = Float(0.5 + 0.5 * simplex(2.2 * cos(a), -2.2 * sin(a), z))
        }
    }

    public static func simplex(_ vx: Double, _ vy: Double, _ vz: Double) -> Double {
        let v = SIMD3(vx, vy, vz)
        let cx = 1.0 / 6.0, cy = 1.0 / 3.0
        var i = floor(v + SIMD3(repeating: (vx + vy + vz) * cy))
        let x0 = v - i + SIMD3(repeating: (i.x + i.y + i.z) * cx)
        let g = SIMD3(x0.y <= x0.x ? 1.0 : 0, x0.z <= x0.y ? 1.0 : 0, x0.x <= x0.z ? 1.0 : 0)
        let l = 1 - g
        let lzxy = SIMD3(l.z, l.x, l.y)
        let i1 = pointwiseMin(g, lzxy)
        let i2 = pointwiseMax(g, lzxy)
        let x1 = x0 - i1 + SIMD3(repeating: cx)
        let x2 = x0 - i2 + SIMD3(repeating: cy)
        let x3 = x0 - SIMD3(repeating: 0.5)
        i = mod289(i)
        let p = permute(permute(permute(SIMD4(repeating: i.z) + SIMD4(0, i1.z, i2.z, 1))
                + SIMD4(repeating: i.y) + SIMD4(0, i1.y, i2.y, 1))
            + SIMD4(repeating: i.x) + SIMD4(0, i1.x, i2.x, 1))
        // Divisions instead of the shader's products with 1/7: in single precision 0.142857142857 rounds up, so its
        // floors land on the integers; in double the products fall just short of them.
        let n = 1.0 / 7.0
        let ns = SIMD3(2 * n, 0.5 * n - 1, n)
        let j = p - 49 * floor(p / 49)
        let xa = floor(j / 7)
        let ya = floor(j - 7 * xa)
        let x = xa * ns.x + SIMD4(repeating: ns.y)
        let y = ya * ns.x + SIMD4(repeating: ns.y)
        let h = 1 - magnitude(x) - magnitude(y)
        let b0 = SIMD4(x.x, x.y, y.x, y.y)
        let b1 = SIMD4(x.z, x.w, y.z, y.w)
        let s0 = floor(b0) * 2 + 1
        let s1 = floor(b1) * 2 + 1
        let sh = SIMD4(h.x <= 0 ? -1.0 : 0, h.y <= 0 ? -1.0 : 0, h.z <= 0 ? -1.0 : 0, h.w <= 0 ? -1.0 : 0)
        let a0 = SIMD4(b0.x, b0.z, b0.y, b0.w) + SIMD4(s0.x, s0.z, s0.y, s0.w) * SIMD4(sh.x, sh.x, sh.y, sh.y)
        let a1 = SIMD4(b1.x, b1.z, b1.y, b1.w) + SIMD4(s1.x, s1.z, s1.y, s1.w) * SIMD4(sh.z, sh.z, sh.w, sh.w)
        var p0 = SIMD3(a0.x, a0.y, h.x)
        var p1 = SIMD3(a0.z, a0.w, h.y)
        var p2 = SIMD3(a1.x, a1.y, h.z)
        var p3 = SIMD3(a1.z, a1.w, h.w)
        let norm = 1.79284291400159 - 0.85373472095314 * SIMD4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3))
        p0 *= norm.x
        p1 *= norm.y
        p2 *= norm.z
        p3 *= norm.w
        var m = pointwiseMax(0.6 - SIMD4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), SIMD4(repeating: 0))
        m = m * m
        return 42 * dot(m * m, SIMD4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)))
    }

    private static func mod289(_ x: SIMD3<Double>) -> SIMD3<Double> { x - floor(x * (1 / 289)) * 289 }
    private static func mod289(_ x: SIMD4<Double>) -> SIMD4<Double> { x - floor(x * (1 / 289)) * 289 }
    private static func permute(_ x: SIMD4<Double>) -> SIMD4<Double> { mod289((x * 34 + 1) * x) }
    private static func floor<V: SIMD>(_ x: V) -> V where V.Scalar == Double { x.rounded(.down) }
    private static func magnitude(_ x: SIMD4<Double>) -> SIMD4<Double> { x.replacing(with: -x, where: x .< 0) }
    private static func dot<V: SIMD>(_ a: V, _ b: V) -> Double where V.Scalar == Double { (a * b).sum() }
}

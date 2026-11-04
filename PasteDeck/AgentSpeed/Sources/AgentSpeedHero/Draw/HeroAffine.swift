import Foundation

/// A 2D affine transform composed like a canvas context: each call applies before the ones made earlier.
struct HeroAffine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    static let identity = HeroAffine()

    @inline(__always) func apply(_ x: Double, _ y: Double) -> SIMD2<Double> {
        SIMD2(a * x + c * y + tx, b * x + d * y + ty)
    }

    @inline(__always) func apply(_ p: SIMD2<Double>) -> SIMD2<Double> { apply(p.x, p.y) }

    func translated(_ x: Double, _ y: Double) -> HeroAffine {
        var m = self
        m.tx += a * x + c * y
        m.ty += b * x + d * y
        return m
    }

    func rotated(_ angle: Double) -> HeroAffine {
        guard angle != 0 else { return self }
        let cs = cos(angle), sn = sin(angle)
        var m = self
        m.a = a * cs + c * sn
        m.b = b * cs + d * sn
        m.c = c * cs - a * sn
        m.d = d * cs - b * sn
        return m
    }

    func scaled(_ sx: Double, _ sy: Double) -> HeroAffine {
        var m = self
        m.a *= sx
        m.b *= sx
        m.c *= sy
        m.d *= sy
        return m
    }

    /// Rotation by `angle` about `pivot`.
    func rotated(_ angle: Double, about pivot: SIMD2<Double>) -> HeroAffine {
        guard angle != 0 else { return self }
        return translated(pivot.x, pivot.y).rotated(angle).translated(-pivot.x, -pivot.y)
    }
}

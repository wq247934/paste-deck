import Foundation

/// The hero's history of `live_A` per style (DESIGN 2c Content 1): glass a sparkline, timing one-second bars, neon a
/// 24-segment LED bar lit to the heat with today's peak marked. Ports of the prototypes' `drawSpark`, bar heights and
/// LED segments.
public enum BoardHistoryShape {
    /// Glass: the points of the sparkline in a `width` × `height` box (y down), oldest at x = 0. The scale tops out at
    /// 1.12 × the largest value (at least 10 tok/s); fewer than two values draw nothing.
    public static func sparkline(_ values: [Double], width: Double, height: Double) -> [SIMD2<Double>] {
        guard values.count >= 2 else { return [] }
        let top = max(10, values.max() ?? 0) * 1.12
        let last = Double(values.count - 1)
        return values.enumerated().map { index, value in
            SIMD2(Double(index) / last * width, height - 2 - max(0, value) / top * (height - 6))
        }
    }

    /// Glass's strip under the hero (DESIGN 2c Live metrics, *Hero*): the sparkline stretched over `width` × `height`
    /// with 1.5 pt free above and below, the same 1.12 × scale.
    public static func strip(_ values: [Double], width: Double, height: Double) -> [SIMD2<Double>] {
        guard values.count >= 2 else { return [] }
        let top = max(10, values.max() ?? 0) * 1.12
        let last = Double(values.count - 1)
        return values.enumerated().map { index, value in
            SIMD2(Double(index) / last * width, height - 1.5 - max(0, value) / top * (height - 3))
        }
    }

    /// Timing's strip: the heights of the 30 one-second bars, `max(1.5, value / max(10, maximum) × height)`.
    public static func stripBars(_ values: [Double], count: Int = 30, height: Double) -> [Double] {
        let recent = Array(values.suffix(count))
        let top = max(10, recent.max() ?? 0)
        let padding = Array(repeating: 0.0, count: count - recent.count)
        return (padding + recent).map { max(1.5, max(0, $0) / top * height) }
    }

    /// Timing: the heights of `count` bars for the latest values (missing ones at the start read 0), scaled to the
    /// largest of them (at least 10 tok/s), never below 2 pt.
    public static func bars(_ values: [Double], count: Int, height: Double) -> [Double] {
        let recent = Array(values.suffix(count))
        let top = max(10, recent.max() ?? 0)
        let padding = Array(repeating: 0.0, count: count - recent.count)
        return (padding + recent).map { max(2, max(0, $0) / top * height) }
    }

    /// Neon: segments lit by `heat`, and the segment marking today's peak (`peakHeat`) when it is beyond the lit ones.
    public static func led(heat: Double, peakHeat: Double, segments: Int = 24) -> (lit: Int, peak: Int?) {
        let lit = min(segments, max(0, Int((heat * Double(segments)).rounded())))
        let peak = min(segments - 1, Int((peakHeat * Double(segments)).rounded()) - 1)
        return (lit, peak >= lit && peak >= 0 ? peak : nil)
    }
}

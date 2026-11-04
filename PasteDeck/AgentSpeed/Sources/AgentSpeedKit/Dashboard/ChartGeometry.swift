import SwiftUI

/// Maps chart samples into the plot rectangle; shared by the plot and the crosshair so they always agree.
struct ChartGeometry {
    static let topInset: CGFloat = 8

    let size: CGSize
    let start: TimeInterval
    let end: TimeInterval
    let domain: Double

    var plotTop: CGFloat { Self.topInset }
    var baseline: CGFloat { size.height - 0.5 }
    var plotWidth: CGFloat { max(1, size.width - DashboardLayout.chartGutter) }

    func x(_ time: TimeInterval) -> CGFloat {
        CGFloat((time - start) / max(end - start, 1)) * plotWidth
    }

    func y(_ value: Double) -> CGFloat {
        let fraction = max(0, value) / max(domain, 1e-6)
        return baseline - CGFloat(fraction) * (baseline - plotTop)
    }

    func time(atX x: CGFloat) -> TimeInterval {
        start + TimeInterval(x / plotWidth) * (end - start)
    }

    func points(_ samples: [ChartSample], value: (ChartSample) -> Double) -> [CGPoint] {
        samples.map { CGPoint(x: x($0.time), y: y(value($0))) }
    }
}

/// Uniform Catmull-Rom splines through plotted points, kept above the baseline.
enum ChartPath {
    static func line(_ points: [CGPoint], over range: ClosedRange<Int>? = nil, floor: CGFloat) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        let range = range ?? 0...(points.count - 1)
        let lower = max(range.lowerBound, 0), upper = min(range.upperBound, points.count - 1)
        guard lower <= upper else { return path }
        path.move(to: points[lower])
        addCurves(to: &path, points, from: lower, to: upper, floor: floor)
        return path
    }

    static func area(_ points: [CGPoint], floor: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: floor))
        path.addLine(to: first)
        addCurves(to: &path, points, from: 0, to: points.count - 1, floor: floor)
        path.addLine(to: CGPoint(x: last.x, y: floor))
        path.closeSubpath()
        return path
    }

    /// The region between an upper and a lower curve sharing the same x positions.
    static func band(upper: [CGPoint], lower: [CGPoint], floor: CGFloat) -> Path {
        var path = Path()
        guard upper.count == lower.count, let first = upper.first, let lowerLast = lower.last else { return path }
        path.move(to: first)
        addCurves(to: &path, upper, from: 0, to: upper.count - 1, floor: floor)
        path.addLine(to: lowerLast)
        let reversed = Array(lower.reversed())
        addCurves(to: &path, reversed, from: 0, to: reversed.count - 1, floor: floor)
        path.closeSubpath()
        return path
    }

    private static func addCurves(to path: inout Path, _ points: [CGPoint], from lower: Int, to upper: Int, floor: CGFloat) {
        guard upper > lower else { return }
        let last = points.count - 1
        for index in lower..<upper {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, last)]
            var c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            var c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            let minX = min(p1.x, p2.x), maxX = max(p1.x, p2.x)
            c1.x = c1.x.clamped(to: minX...maxX)
            c2.x = c2.x.clamped(to: minX...maxX)
            c1.y = min(c1.y, floor)
            c2.y = min(c2.y, floor)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

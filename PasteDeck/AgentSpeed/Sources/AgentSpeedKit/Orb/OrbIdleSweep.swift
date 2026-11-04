import QuartzCore
import SwiftUI

/// The idle "sign of life" (DESIGN section 2): a slow light sweep along the unlit segments every 6 s, run entirely
/// by Core Animation so an idle orb renders no frames of its own.
struct OrbIdleSweep: NSViewRepresentable {
    let diameter: CGFloat
    let canvasSide: CGFloat
    let color: RGBColor
    let active: Bool
    let reduceMotion: Bool
    /// Start of the sweep cycle on the `Clock` time base.
    let epoch: TimeInterval

    func makeNSView(context: Context) -> OrbIdleSweepView {
        let view = OrbIdleSweepView()
        view.configure(self)
        return view
    }

    func updateNSView(_ view: OrbIdleSweepView, context: Context) {
        view.configure(self)
    }
}

final class OrbIdleSweepView: NSView {
    private struct Configuration: Equatable {
        var diameter: CGFloat
        var side: CGFloat
        var color: RGBColor
        var active: Bool
        var reduceMotion: Bool
        var epoch: TimeInterval
    }

    private let container = CALayer()
    private var segments: [CAShapeLayer] = []
    private var applied: Configuration?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        container.isGeometryFlipped = true
        container.actions = ["bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        container.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ sweep: OrbIdleSweep) {
        let configuration = Configuration(
            diameter: sweep.diameter, side: sweep.canvasSide, color: sweep.color,
            active: sweep.active, reduceMotion: sweep.reduceMotion, epoch: sweep.epoch
        )
        guard configuration != applied else { return }
        let geometryChanged = applied?.diameter != configuration.diameter || applied?.side != configuration.side
        applied = configuration
        if geometryChanged || segments.isEmpty { rebuild(configuration) }
        for segment in segments {
            segment.fillColor = configuration.color.cgColor
            segment.removeAllAnimations()
        }
        guard configuration.active else { return }
        animate(configuration)
    }

    private func rebuild(_ configuration: Configuration) {
        segments.forEach { $0.removeFromSuperlayer() }
        let geometry = OrbGeometry(diameter: configuration.diameter, canvasSide: configuration.side)
        segments = (0..<OrbGeometry.segmentCount).map { index in
            let angle = OrbGeometry.segmentAngle(index) * .pi / 180
            let center = geometry.point(angle: OrbGeometry.segmentAngle(index), radius: geometry.gaugeRadius)
            let rect = CGRect(x: -geometry.segmentLength / 2, y: -geometry.segmentWidth / 2,
                              width: geometry.segmentLength, height: geometry.segmentWidth)
            var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            let path = CGPath(roundedRect: rect, cornerWidth: geometry.segmentCorner, cornerHeight: geometry.segmentCorner, transform: &transform)
            let layer = CAShapeLayer()
            layer.path = path
            layer.opacity = 0
            layer.actions = ["opacity": NSNull(), "fillColor": NSNull()]
            container.addSublayer(layer)
            return layer
        }
    }

    private func animate(_ configuration: Configuration) {
        let period = OrbAnimator.sweepPeriod
        let duration = OrbAnimator.sweepDuration
        let caNow = CACurrentMediaTime()
        let begin = caNow - (Clock.now - configuration.epoch)
        let samples = 44
        for (index, segment) in segments.enumerated() {
            var times: [NSNumber] = []
            var values: [NSNumber] = []
            for step in 0...samples {
                let t = duration * Double(step) / Double(samples)
                let amount: Double
                if configuration.reduceMotion {
                    amount = 0.6 * sin(.pi * t / duration)
                } else {
                    let center = -5 + 46 * t / duration
                    let d = Double(index) - center
                    amount = exp(-(d * d) / (2 * 2.6 * 2.6))
                }
                times.append(NSNumber(value: t / period))
                values.append(NSNumber(value: amount))
            }
            times.append(1)
            values.append(0)
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.keyTimes = times
            animation.values = values
            animation.duration = period
            animation.repeatCount = .infinity
            animation.beginTime = begin
            animation.isRemovedOnCompletion = false
            segment.add(animation, forKey: "sweep")
        }
    }
}

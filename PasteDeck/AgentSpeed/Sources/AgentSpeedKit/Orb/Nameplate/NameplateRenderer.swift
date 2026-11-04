import AgentSpeedCore
import AgentSpeedOrbModel
import AppKit
import CoreText

/// Everything one frame of a plate draws, in y-up points: the capsule and positioned dots and text runs. The desktop
/// blur behind the capsule is not part of it (an `NSVisualEffectView` live, a blurred backdrop in previews).
struct NameplateScene: Equatable {
    struct Dot: Equatable {
        var dot: NameplateDot
        var x: CGFloat
        var scale: CGFloat = 1
        var alpha: CGFloat = 1
        /// The 1 pt ring in the plate color that separates overlapping dots.
        var ring: Bool
    }

    struct Run: Equatable {
        var text: String
        var x: CGFloat
        var role: NameplateFace.Role
        var tracking: CGFloat
        var ideographic: Bool
        var alpha: CGFloat = 1
    }

    var plate: CGRect
    var metrics: NameplateMetrics
    var tokens: NameplateTokens
    /// Appear / disappear opacity and scale (about the capsule's center).
    var opacity: CGFloat = 1
    var scale: CGFloat = 1
    var dots: [Dot] = []
    var runs: [Run] = []

    /// A face placed with its left edge at `originX`.
    mutating func add(_ face: NameplateFace, originX: CGFloat, alpha: CGFloat) {
        guard alpha > 0.001 else { return }
        let overlapping = face.dots.count > 1 && face.runs.count == 1
        dots += face.dots.map { Dot(dot: $0.dot, x: originX + $0.x, alpha: alpha, ring: overlapping) }
        runs += face.runs.map {
            Run(text: $0.text, x: originX + $0.x, role: $0.role, tracking: $0.tracking, ideographic: face.ideographic, alpha: alpha)
        }
    }
}

/// Draws a plate (DESIGN 2b, Name plate, Material and Content) with Core Graphics and Core Text. Shared by the live
/// plate, the undo chip and the previews, so they always match.
@MainActor
enum NameplateRenderer {
    /// Room around the capsule for the shadow.
    static let margin: CGFloat = 8

    static func draw(_ scene: NameplateScene, in context: CGContext) {
        guard scene.opacity > 0.001, scene.plate.width > 0 else { return }
        let plate = scene.plate
        let tokens = scene.tokens
        context.saveGState()
        context.setAlpha(scene.opacity)
        if scene.scale != 1 {
            context.translateBy(x: plate.midX, y: plate.midY)
            context.scaleBy(x: scene.scale, y: scene.scale)
            context.translateBy(x: -plate.midX, y: -plate.midY)
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawBody(plate, tokens: tokens, in: context)
        context.saveGState()
        context.addPath(capsule(plate))
        context.clip()
        for dot in scene.dots.reversed() {
            drawDot(dot, y: plate.midY, metrics: scene.metrics, tokens: tokens, in: context)
        }
        for run in scene.runs where run.alpha > 0.001 {
            drawRun(run, plate: plate, size: scene.metrics.fontSize, tokens: tokens, in: context)
        }
        context.restoreGState()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func capsule(_ rect: CGRect) -> CGPath {
        let radius = min(rect.height, rect.width) / 2
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // MARK: Body

    /// Shadow (outside the capsule only, so it never darkens the glass), vertical fill, inner rim and outer stroke.
    private static func drawBody(_ plate: CGRect, tokens: NameplateTokens, in context: CGContext) {
        let path = capsule(plate)
        context.saveGState()
        context.addRect(plate.insetBy(dx: -margin * 2, dy: -margin * 2))
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 6, color: tokens.shadow.cgColor)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        drawVertical(tokens.fillTop, tokens.fillBottom, in: plate, context: context)
        context.restoreGState()

        context.saveGState()
        context.addPath(capsule(plate.insetBy(dx: 0.5, dy: 0.5)))
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        drawVertical(tokens.rimTop, tokens.rimBottom, in: plate, context: context)
        context.restoreGState()

        let outer = tokens.outerWidth
        context.addPath(capsule(plate.insetBy(dx: -outer / 2, dy: -outer / 2)))
        context.setLineWidth(outer)
        context.setStrokeColor(tokens.outerStroke.cgColor)
        context.strokePath()
    }

    private static func drawVertical(_ top: RGBColor, _ bottom: RGBColor, in rect: CGRect, context: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top.cgColor, bottom.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // MARK: Dots

    private static func drawDot(_ item: NameplateScene.Dot, y: CGFloat, metrics: NameplateMetrics, tokens: NameplateTokens,
                                in context: CGContext) {
        guard item.alpha > 0.001, item.scale > 0.001 else { return }
        let radius = metrics.dot / 2 * item.scale
        let center = CGPoint(x: item.x, y: y)
        context.saveGState()
        context.setAlpha(item.alpha)
        if item.ring {
            context.setFillColor(tokens.separator.cgColor)
            context.fillEllipse(in: circle(center, radius + item.scale))
        }
        switch item.dot {
        case .source(let kind):
            context.setFillColor(tokens.dotColor(kind.tint).cgColor)
            context.fillEllipse(in: circle(center, radius))
        case .unavailable:
            let width = metrics.ringWidth * item.scale
            context.setStrokeColor(tokens.secondary.cgColor)
            context.setLineWidth(width)
            context.strokeEllipse(in: circle(center, radius - width / 2))
        case .spectrum:
            drawSpectrum(center: center, radius: radius, tokens: tokens, in: context)
        }
        context.restoreGState()
    }

    /// A conic gradient through every source color in source order, clockwise from 12 o'clock.
    private static func drawSpectrum(center: CGPoint, radius: CGFloat, tokens: NameplateTokens, in context: CGContext) {
        let colors = (SourceKind.allCases + [SourceKind.allCases[0]]).map { tokens.dotColor($0.tint).cgColor }
        let locations = colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                        locations: locations) else { return }
        context.saveGState()
        context.addEllipse(in: circle(center, radius))
        context.clip()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: -1)
        CGContextDrawConicGradient(context, gradient, .zero, -.pi / 2)
        context.restoreGState()
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }

    // MARK: Text

    private static func drawRun(_ run: NameplateScene.Run, plate: CGRect, size: CGFloat, tokens: NameplateTokens, in context: CGContext) {
        let typesetter = NameplateTypesetter.shared
        let color: RGBColor = switch run.role {
        case .text: tokens.text
        case .secondary: tokens.secondary
        case .accent: tokens.accent
        }
        let line = typesetter.line(run.text, size: size, tracking: run.tracking, color: color)
        let baseline = plate.midY - typesetter.baselineDrop(ideographic: run.ideographic, size: size)
        context.saveGState()
        context.setAlpha(run.alpha)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: run.x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

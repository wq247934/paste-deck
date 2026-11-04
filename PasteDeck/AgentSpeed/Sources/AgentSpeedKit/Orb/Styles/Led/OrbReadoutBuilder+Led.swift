import AgentSpeedOrbModel
import SwiftUI

/// The v1.4 `led` value (DESIGN 2.1, Readout): under each glyph a dark backing (dark, while moving), the redline
/// chromatic split (dark, Standard and Max), and from overdrive a second heat glow 2.4× wider. The heat glow itself
/// grows with overdrive in `addValue`.
struct LedValueExtras {
    var backing: Double
    var chroma: Double
    var chromaOffset: CGFloat
    var backingRadius: CGFloat
}

extension OrbReadoutBuilder {
    func ledValueExtras(_ scene: inout OrbScene, _ frame: OrbFrame, size: CGFloat, total: CGFloat, baseline: CGFloat,
                        glowStrength: Double, fade: Double) -> LedValueExtras? {
        let s = frame.s
        let wide = frame.tier >= .overdrive ? glowStrength : 0
        if wide > 0.01, fade > 0.01 {
            // A glyph glow 2.4× wider than the heat glow keeps almost nothing of the glyph shapes: a soft box around the
            // digits' ink, σ 2.4 × 0.0175 S.
            let sigma = 2.4 * 0.0175 * s * LedMath.glowScale(overdrive: frame.overdrive)
            let color = frame.tokens.heat(max(frame.heat, 0.2))
            let alpha = (frame.dark ? 0.45 : 0.2) * 0.42 * wide * fade
            scene.add(.roundedRect(center: CGPoint(x: frame.center.x, y: baseline - 0.36 * size),
                                   halfSize: CGSize(width: max(1, total / 2 - 0.08 * size), height: 0.3 * size),
                                   rotation: 0, corner: 0.28 * size, color: color.opacity(alpha),
                                   glow: OrbInstance.glow(sigma: sigma), glowAlpha: 1), blend: .over)
        }
        let backing = frame.dark ? frame.activity : 0
        let chroma = frame.dark && frame.effects.jitter && frame.tier == .redline ? frame.redlineAmount : 0
        guard backing > 0.01 || chroma > 0.01 else { return nil }
        return LedValueExtras(
            backing: backing,
            chroma: chroma,
            chromaOffset: LedMath.chromaOffset(overdrive: frame.overdrive, diameter: s),
            backingRadius: 2 * 0.0125 * s
        )
    }

    /// The value glyph with its dark backing (σ 0.0125 S at 70 %, plus the drop shadow's share) and the chromatic split,
    /// drawn under its glow in the same pass (CSS shadow order), and only its quad around the blurs.
    func ledGlyph(_ draw: OrbTextDraw, texture: OrbTextTexture, glowRadius: CGFloat, alpha: Double, extras: LedValueExtras?)
        -> OrbTextDraw {
        guard let extras else { return draw.inset(texture.padding - glowRadius - 1) }
        var draw = draw.ledUnderlays(backing: 0.78 * extras.backing * alpha, radius: extras.backingRadius,
                                     chroma: 0.55 * extras.chroma * alpha, offset: extras.chromaOffset)
        // A rolling digit's cell clip is widened so the backing's blur is not cut at the sides.
        if draw.instance.params.w == OrbTextClip.rect(.zero).mode {
            draw.instance.clip.x -= Float(extras.backingRadius)
            draw.instance.clip.z += Float(extras.backingRadius)
        }
        return draw.inset(texture.padding - max(glowRadius, extras.backingRadius) - 1)
    }
}

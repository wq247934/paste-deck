/// The `liquid` style's volume shader (DESIGN 2a.3): light spill, back wave, body, spherical shade, inner glow, readout
/// scrim, energy currents and the new-peak gold band in one pass (mode 0), and the meniscus (mode 1), all evaluated per
/// pixel from the surface `y(x)`. Its parameters mirror `OrbLiquidUniforms`.
enum OrbLiquidShaderSource {
    static let source = """
    struct LiquidParams {
        float4 frame;        // center x, center y, S, glass radius (points)
        float4 surface;      // mean level y_L (points, y down), wave amplitude (points), chop amplitude (points), back wave on
        float4 phases;       // φ1, φ2, φ3, φ4 (radians)
        float4 ripples[4];   // impact x (canvas), front 0.42 S τ, amplitude A_r S e^(−τ/0.75) (points), active
        float4 liquid;       // L (rgb), front alpha
        float4 deep;         // darkened L (rgb), alpha at the bottom
        float4 back;         // back wave color, alpha
        float4 spill;        // spill color, alpha at the surface (0: none)
        float4 glow;         // inner glow color, alpha at its center (0: none)
        float4 glowGeom;     // center x, center y, radius, additive
        float4 shade;        // spherical shade color, alpha at the glass
        float4 current;      // filament color, alpha (0: none)
        float4 currentGeom;  // unused, blur σ (points), drift phase, additive
        float4 meniscus;     // color, alpha
        float4 meniscusGlow; // color, alpha (0: none)
        float4 meniscusGeom; // width (points), glow σ (points), additive, unused
        float4 gold;         // band center y, alpha, half height (points), additive
        float4 flags;        // spill additive, scrim strength (0: none), body gradient top y, body gradient bottom y
    };

    static float orb_liquid_wave_y(float x, constant LiquidParams &liquid, bool back) {
        float s = liquid.frame.z;
        float xr = x - liquid.frame.x;
        float offset = back ? 1.7 : 0.0;
        float a = liquid.surface.y * (back ? 0.75 : 1.0);
        float y = liquid.surface.x - (back ? 0.008 * s : 0.0);
        if (a > 0.0) {
            y += a * (0.55 * sin(xr / (0.9 * s) * orb_tau + liquid.phases.x + offset)
                      + 0.30 * sin(xr / (0.47 * s) * orb_tau - liquid.phases.y + offset * 1.3)
                      + 0.15 * sin(xr / (0.23 * s) * orb_tau + liquid.phases.z + offset * 0.7));
        }
        if (liquid.surface.z > 0.0) {
            y += liquid.surface.z * sin(xr / (0.11 * s) * orb_tau + liquid.phases.w + offset)
                * (0.7 + 0.3 * sin(xr / (0.05 * s) + liquid.phases.w * 1.7));
        }
        for (int i = 0; i < 4; i++) {
            float4 ripple = liquid.ripples[i];
            if (ripple.w <= 0.0) {
                continue;
            }
            float u = abs(x - ripple.x) - ripple.y;
            float k = u / (0.075 * s);
            y -= ripple.z * exp(-k * k) * cos(orb_tau * u / (0.1 * s)) * (back ? 0.6 : 1.0);
        }
        return y;
    }

    // The liquid surface height (points, y down) at canvas x; used by the volume and to split the readout.
    static float orb_liquid_surface_y(float x, constant LiquidParams &liquid) {
        return orb_liquid_wave_y(x, liquid, false);
    }

    struct LiquidOut {
        float4 position [[position]];
        float2 canvas;
    };

    vertex LiquidOut orb_liquid_vertex(uint vid [[vertex_id]],
                                       constant Uniforms &uniforms [[buffer(1)]],
                                       constant LiquidParams &liquid [[buffer(2)]]) {
        float extent = liquid.frame.w + 2.0;
        float2 point = liquid.frame.xy + corners[vid] * extent;
        LiquidOut out;
        out.position = orb_clip_position(point, uniforms);
        out.canvas = point;
        return out;
    }

    static void orb_liquid_over(thread float3 &color, thread float &alpha, float3 rgb, float a) {
        a = clamp(a, 0.0, 1.0);
        color = rgb * a + color * (1.0 - a);
        alpha = a + alpha * (1.0 - a);
    }

    // Light adds up on dark glass (additive, like the shape pipeline: color adds, coverage accumulates) and blends
    // normally on porcelain.
    static void orb_liquid_light(thread float3 &color, thread float &alpha, float3 rgb, float a, bool additive) {
        if (additive) {
            a = clamp(a, 0.0, 1.0);
            color += rgb * a;
            alpha = a + alpha * (1.0 - a);
        } else {
            orb_liquid_over(color, alpha, rgb, a);
        }
    }

    fragment float4 orb_liquid_fragment(LiquidOut in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(1)]],
                                        constant LiquidParams &liquid [[buffer(2)]],
                                        constant int &mode [[buffer(3)]],
                                        texture2d<float> palette [[texture(0)]]) {
        float2 p = in.canvas;
        float2 c = liquid.frame.xy;
        float s = liquid.frame.z;
        float radius = liquid.frame.w;
        float aa = 1.0 / uniforms.viewport.z;
        float glass = clamp((radius - length(p - c)) / aa + 0.5, 0.0, 1.0);
        if (glass <= 0.0) {
            discard_fragment();
        }
        float3 color = float3(0.0);
        float alpha = 0.0;
        float y_surface = orb_liquid_wave_y(p.x, liquid, false);

        if (mode == 1) {
            // The meniscus: the surface stroked, with its glow.
            float slope = orb_liquid_wave_y(p.x + 0.5, liquid, false) - orb_liquid_wave_y(p.x - 0.5, liquid, false);
            float d = abs(p.y - y_surface) / sqrt(1.0 + slope * slope);
            float half_width = liquid.meniscusGeom.x * 0.5;
            if (liquid.meniscusGlow.a > 0.0) {
                float sigma = max(liquid.meniscusGeom.y, 0.001);
                float x = max(d - half_width, 0.0) / sigma;
                orb_liquid_light(color, alpha, liquid.meniscusGlow.rgb, liquid.meniscusGlow.a * exp(-0.5 * x * x),
                                 liquid.meniscusGeom.z > 0.5);
            }
            float core = clamp((half_width - d) / aa + 0.5, 0.0, 1.0);
            orb_liquid_over(color, alpha, liquid.meniscus.rgb, liquid.meniscus.a * core);
            color *= glass;
            alpha *= glass;
            if (alpha <= 0.0005 && max(color.r, max(color.g, color.b)) <= 0.0005) {
                discard_fragment();
            }
            return float4(color, alpha);
        }

        float y_level = liquid.surface.x;
        // Light spilling up into the glass from the surface.
        if (liquid.spill.a > 0.0) {
            float t = (p.y - (y_level - 0.22 * s)) / (0.22 * s);
            if (t >= 0.0 && t <= 1.0) {
                orb_liquid_light(color, alpha, liquid.spill.rgb, liquid.spill.a * t, liquid.flags.x > 0.5);
            }
        }
        // Back wave.
        if (liquid.surface.w > 0.5) {
            float y_back = orb_liquid_wave_y(p.x, liquid, true);
            float cover = clamp((p.y - y_back) / aa + 0.5, 0.0, 1.0);
            orb_liquid_over(color, alpha, liquid.back.rgb, liquid.back.a * cover);
        }
        // Liquid body, spherical shade and inner glow under the front surface.
        float cover = clamp((p.y - y_surface) / aa + 0.5, 0.0, 1.0);
        if (cover > 0.0) {
            float t = clamp((p.y - liquid.flags.z) / max(liquid.flags.w - liquid.flags.z, 1.0), 0.0, 1.0);
            orb_liquid_over(color, alpha, mix(liquid.liquid.rgb, liquid.deep.rgb, t), mix(liquid.liquid.a, liquid.deep.a, t) * cover);
            float2 shade_center = c + float2(-0.06, -0.08) * s;
            float inner = 0.35 * radius;
            float shade = clamp((length(p - shade_center) - inner) / max(radius - inner, 0.001), 0.0, 1.0);
            orb_liquid_over(color, alpha, liquid.shade.rgb, liquid.shade.a * shade * cover);
            if (liquid.glow.a > 0.0) {
                float d = length(p - liquid.glowGeom.xy) / max(liquid.glowGeom.z, 0.001);
                orb_liquid_light(color, alpha, liquid.glow.rgb, liquid.glow.a * max(0.0, 1.0 - d) * cover, liquid.glowGeom.w > 0.5);
            }
        }
        // Readout scrim (dark): an elliptical darkening behind the readout.
        if (liquid.flags.y > 0.0) {
            float k = length((p - (c + float2(0.0, 0.1 * s))) / float2(0.36 * s, 0.26 * s));
            if (k < 1.0) {
                float a = k < 0.55 ? mix(0.35, 0.30, k / 0.55) : mix(0.30, 0.0, (k - 0.55) / 0.45);
                orb_liquid_over(color, alpha, float3(0.0), a * liquid.flags.y);
            }
        }
        // Energy currents: three blurred filaments drifting inside the liquid.
        if (liquid.current.a > 0.0 && cover > 0.0) {
            float bottom = c.y + radius;
            float u = (p.x - (c.x - radius)) / (2.0 * radius);
            float sigma = max(liquid.currentGeom.y, 0.001);
            for (int k = 0; k < 3; k++) {
                float depth = 0.25 + 0.25 * float(k);
                float phase = liquid.currentGeom.z * (0.35 + 0.2 * float(k)) + 2.1 * float(k);
                float y = y_level + (bottom - y_level) * depth + 0.03 * s * sin(u * 7.0 + phase) + 0.015 * s * sin(u * 13.0 - phase * 1.7);
                float slope = (0.03 * s * 7.0 * cos(u * 7.0 + phase) + 0.015 * s * 13.0 * cos(u * 13.0 - phase * 1.7)) / (2.0 * radius);
                float d = abs(p.y - y) / sqrt(1.0 + slope * slope);
                float half_width = (0.018 - 0.004 * float(k)) * s * 0.5;
                float profile = 1.0 - smoothstep(max(half_width - 1.5 * sigma, 0.0), half_width + 1.5 * sigma, d);
                orb_liquid_light(color, alpha, liquid.current.rgb, liquid.current.a * (1.0 - 0.25 * float(k)) * profile * cover,
                                 liquid.currentGeom.w > 0.5);
            }
        }
        // New-peak gold band rising through the liquid.
        if (liquid.gold.y > 0.0) {
            float d = abs(p.y - liquid.gold.x) / max(liquid.gold.z, 0.001);
            if (d < 1.0) {
                orb_liquid_light(color, alpha, float3(250.0, 204.0, 21.0) / 255.0, liquid.gold.y * (1.0 - d), liquid.gold.w > 0.5);
            }
        }
        color *= glass;
        alpha *= glass;
        if (alpha <= 0.0005 && max(color.r, max(color.g, color.b)) <= 0.0005) {
            discard_fragment();
        }
        return float4(color, alpha);
    }

    """
}

/// Per-frame parameters of the liquid volume (layout matches `LiquidParams` in `OrbLiquidShaderSource`).
struct OrbLiquidUniforms {
    var frame: SIMD4<Float> = .zero
    var surface: SIMD4<Float> = .zero
    var phases: SIMD4<Float> = .zero
    var ripple0: SIMD4<Float> = .zero
    var ripple1: SIMD4<Float> = .zero
    var ripple2: SIMD4<Float> = .zero
    var ripple3: SIMD4<Float> = .zero
    var liquid: SIMD4<Float> = .zero
    var deep: SIMD4<Float> = .zero
    var back: SIMD4<Float> = .zero
    var spill: SIMD4<Float> = .zero
    var glow: SIMD4<Float> = .zero
    var glowGeom: SIMD4<Float> = .zero
    var shade: SIMD4<Float> = .zero
    var current: SIMD4<Float> = .zero
    var currentGeom: SIMD4<Float> = .zero
    var meniscus: SIMD4<Float> = .zero
    var meniscusGlow: SIMD4<Float> = .zero
    var meniscusGeom: SIMD4<Float> = .zero
    var gold: SIMD4<Float> = .zero
    var flags: SIMD4<Float> = .zero

    mutating func setRipple(_ index: Int, _ value: SIMD4<Float>) {
        switch index {
        case 0: ripple0 = value
        case 1: ripple1 = value
        case 2: ripple2 = value
        default: ripple3 = value
        }
    }
}

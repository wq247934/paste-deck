import AgentSpeedOrbModel
import Foundation

/// The `led` style's per-pixel fields (DESIGN 2.1), ported from the prototype's fragment shader: the silk core (mode
/// 0, one disc-sized quad, four noise evaluations per pixel) and the corona with the warp streaks (mode 1, one annulus
/// quad up to 0.74 S, at most three noise evaluations per pixel). Coordinates inside follow the prototype: orb units
/// with the rim at r = 0.5 and y up. Its parameters mirror `OrbLedFieldUniforms`.
enum OrbLedShaderSource {
    static var source: String { header + warpSeeds + noise + silk + corona }

    /// Vertices of a field's mesh (`orb_led_vertex`): a 48-triangle fan for the silk, a 48-quad strip for the corona.
    static func vertexCount(mode: Int32) -> Int { mode == 0 ? 3 * 48 : 6 * 48 }

    static let header = """
    struct LedFieldParams {
        float4 frame;    // center x, center y (points), S (points), alpha (style crossfade)
        float4 heat;     // h, o, act, lvl
        float4 phases;   // φsilk, φlight, clock (s), peak age (s; ≥ 1.4: none)
        float4 flags;    // dark, tier flash, ripple amount, silk brightness
        float4 corona;   // φcorona, φwarp, corona amount, warp amount
        float4 text;     // readout offset (S, y up), readout mask on, unused, unused
        float4 waves[4]; // age 0...1 (< 0: none), strength, unused, unused
    };

    struct LedFieldOut {
        float4 position [[position]];
        float2 canvas;
    };

    constant float3 led_hot = float3(1.0, 0.969, 0.839);

    static float3 led_heat(float h, texture2d<float> palette) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        return palette.sample(s, float2(clamp(h, 0.0, 1.0) * (255.0 / 256.0) + 0.5 / 256.0, 0.5)).rgb;
    }

    // Porcelain: deepen without muddying (gold stays gold, not khaki).
    static float3 led_ink(float3 c) { return pow(max(c, 0.0), float3(1.55)); }

    static float led_smoothstep(float e0, float e1, float x) {
        float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    static float led_ease_out(float t) {
        float u = 1.0 - clamp(t, 0.0, 1.0);
        return 1.0 - u * u * u;
    }

    struct LedAcc {
        float3 rgb;
        float a;
    };

    // Dark glass: light adds up; porcelain: colors are laid on like ink.
    static void led_glow(thread LedAcc &acc, float3 c, float a, bool dark) {
        a = clamp(a, 0.0, 1.0);
        if (dark) {
            acc.rgb += c * a;
            acc.a = max(acc.a, a * 0.35);
        } else {
            acc.rgb = c * a + acc.rgb * (1.0 - a);
            acc.a = a + acc.a * (1.0 - a);
        }
    }

    static void led_paint(thread LedAcc &acc, float3 c, float a) {
        a = clamp(a, 0.0, 1.0);
        acc.rgb = c * a + acc.rgb * (1.0 - a);
        acc.a = a + acc.a * (1.0 - a);
    }

    // Mode 0: a fan of 48 triangles around the silk disc (r ≤ 0.475 S); mode 1: a strip of 48 quads over the corona's
    // annulus (0.47...0.74 S), so neither shades the pixels it would only discard.
    constant float led_field_segments = 48.0;

    vertex LedFieldOut orb_led_vertex(uint vid [[vertex_id]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      constant LedFieldParams &led [[buffer(2)]],
                                      constant int &mode [[buffer(3)]]) {
        float s = led.frame.z;
        float pad = 2.0 / uniforms.viewport.z;
        float cover = 1.0 / cos(3.14159265 / led_field_segments);
        float step = 6.28318530718 / led_field_segments;
        float2 point = led.frame.xy;
        if (mode == 0) {
            uint segment = vid / 3;
            uint corner = vid % 3;
            if (corner > 0) {
                float a = float(segment + corner - 1) * step;
                point += float2(cos(a), sin(a)) * (0.475 * s * cover + pad);
            }
        } else {
            uint segment = vid / 6;
            uint corner = vid % 6;
            bool outer = corner == 1 || corner == 3 || corner == 4;
            bool next = corner == 2 || corner == 4 || corner == 5;
            float a = float(segment + (next ? 1 : 0)) * step;
            point += float2(cos(a), sin(a)) * (outer ? 0.74 * s * cover + pad : 0.47 * s - pad);
        }
        LedFieldOut out;
        out.position = orb_clip_position(point, uniforms);
        out.canvas = point;
        return out;
    }

    """

    /// The 96 warp-bin seeds (`hash11(bin + 3)` of the prototype), evaluated once in double precision.
    static var warpSeeds: String {
        let values = (0..<LedMath.warpBins).map { String(format: "%.6f", LedMath.warpSeed(bin: $0)) }
        return "constant float led_warp_seeds[\(LedMath.warpBins)] = { " + values.joined(separator: ", ") + " };\n\n"
    }

    static let noise = """
    // 3D simplex noise: Ashima Arts / Stefan Gustavson (MIT).
    static float3 led_mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    static float4 led_mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    static float4 led_permute(float4 x) { return led_mod289(((x * 34.0) + 1.0) * x); }
    static float4 led_taylor_inv_sqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

    static float led_snoise(float3 v, thread float3 *gradient) {
        const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
        const float4 D = float4(0.0, 0.5, 1.0, 2.0);
        float3 i = floor(v + dot(v, C.yyy));
        float3 x0 = v - i + dot(i, C.xxx);
        float3 g = step(x0.yzx, x0.xyz);
        float3 l = 1.0 - g;
        float3 i1 = min(g.xyz, l.zxy);
        float3 i2 = max(g.xyz, l.zxy);
        float3 x1 = x0 - i1 + C.xxx;
        float3 x2 = x0 - i2 + C.yyy;
        float3 x3 = x0 - D.yyy;
        i = led_mod289(i);
        float4 p = led_permute(led_permute(led_permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0))
                               + i.x + float4(0.0, i1.x, i2.x, 1.0));
        float n_ = 0.142857142857;
        float3 ns = n_ * D.wyz - D.xzx;
        float4 j = p - 49.0 * floor(p * ns.z * ns.z);
        float4 x_ = floor(j * ns.z);
        float4 y_ = floor(j - 7.0 * x_);
        float4 x = x_ * ns.x + ns.yyyy;
        float4 y = y_ * ns.x + ns.yyyy;
        float4 h = 1.0 - abs(x) - abs(y);
        float4 b0 = float4(x.xy, y.xy);
        float4 b1 = float4(x.zw, y.zw);
        float4 s0 = floor(b0) * 2.0 + 1.0;
        float4 s1 = floor(b1) * 2.0 + 1.0;
        float4 sh = -step(h, float4(0.0));
        float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
        float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
        float3 p0 = float3(a0.xy, h.x);
        float3 p1 = float3(a0.zw, h.y);
        float3 p2 = float3(a1.xy, h.z);
        float3 p3 = float3(a1.zw, h.w);
        float4 norm = led_taylor_inv_sqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
        p0 *= norm.x;
        p1 *= norm.y;
        p2 *= norm.z;
        p3 *= norm.w;
        float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
        float4 m2 = m * m;
        float4 pdotx = float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3));
        if (gradient) {
            // d/dx of m⁴ (p·x) with m = 0.6 − x·x: −8 m³ (p·x) x + m⁴ p.
            float4 temp = m2 * m * pdotx;
            float4 m4 = m2 * m2;
            *gradient = 42.0 * (-8.0 * (temp.x * x0 + temp.y * x1 + temp.z * x2 + temp.w * x3)
                                + m4.x * p0 + m4.y * p1 + m4.z * p2 + m4.w * p3);
        }
        return 42.0 * dot(m2 * m2, pdotx);
    }

    static float led_snoise(float3 v) { return led_snoise(v, nullptr); }

    """

    static let silk = """
    // Silk: a satin height field of long diagonal folds; a key light and a rim light in the speed palette glide over it.
    static float led_silk_box(float2 p, float2 b, float rad) {
        float2 d = abs(p) - b + rad;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
    }

    static float led_silk_fold(float ph) { return sin(ph + 0.25 * sin(ph)); }
    static float led_silk_bell(float x) { return exp(-x * x); }

    // The terms of `silk_height` that depend only on X = p·(0.8, 0.6): three of the four height samples share X (they
    // step along (−0.6, 0.8)), so these are evaluated twice per pixel instead of four times.
    struct LedSilkX {
        float y;   // added to Y
        float p1;  // phase of the broad wave
        float a2;  // amplitude and phase of the first fold band
        float p2;
        float a3;  // amplitude and phase of the second fold band
        float p3;
        float rip; // phase of the ripple packets
    };

    static LedSilkX led_silk_x(float X, float t, float rip) {
        LedSilkX x;
        x.y = 0.025 * sin(X * 5.0 + t * 0.3) + 0.03 * sin(X * 1.6 - t * 0.17);
        x.p1 = 0.25 * sin(X * 3.3 + t * 0.2);
        x.a2 = 0.6 * (0.7 + 0.3 * sin(X * 2.8 + 1.0 + t * 0.1));
        x.p2 = 0.35 * sin(X * 4.1 - t * 0.35);
        x.a3 = 0.22 * (0.5 + 0.5 * sin(X * 3.6 - t * 0.25 + 2.0));
        x.p3 = 0.4 * sin(X * 4.7 + t * 0.4);
        x.rip = rip > 0.0 ? 1.3 * sin(X * 2.7) : 0.0;
        return x;
    }

    // The prototype's silk_height with the X terms and the noise sample passed in.
    static float led_silk_height(float2 p, float X, thread const LedSilkX &x, float noise, float t, float rip, float wave,
                                 float clock) {
        float Y = dot(p, float2(-0.60, 0.80)) * (1.0 + 0.45 * X) + 0.03 * noise + x.y;
        float hgt = 0.5 * sin(Y * 6.0 + x.p1 + t * 0.15)
                  + x.a2 * led_silk_fold(Y * 16.5 + x.p2 + t * 0.6)
                  + x.a3 * led_silk_fold(Y * 27.0 + x.p3 - t * 0.8 + 2.0);
        if (rip > 0.0) {
            float packet = max(sin(Y * 4.0 - clock * 2.6 + x.rip), 0.0);
            hgt += rip * 0.05 * packet * packet * sin(Y * 44.0 + X * 6.0 - clock * 16.0);
        }
        if (wave > 0.0) {
            hgt += wave * 0.11 * sin(length(p) * 36.0 - clock * 8.0);
        }
        return hgt;
    }

    static void led_silk_core(thread LedAcc &acc, float2 p, float r, constant LedFieldParams &led, float wave_field,
                              texture2d<float> palette) {
        float fade = led_smoothstep(0.475, 0.385, r);
        if (fade <= 0.0) {
            return;
        }
        bool dark = led.flags.x > 0.5;
        float h = led.heat.x;
        float o = led.heat.y;
        float act = led.heat.z;
        float t = led.phases.x;
        float phase2 = led.phases.y;
        float clock = led.phases.z;
        float peak = led.phases.w;
        float rip = led.flags.z;
        float2 sp = p - p / max(r, 1e-3) * 0.03 * wave_field;
        float e = 0.008;
        float2 ac = float2(-0.6, 0.8);
        float2 al = float2(0.8, 0.6);
        // One noise evaluation with its gradient stands in for the four samples (the steps are 0.008 apart).
        float3 dn;
        float n0 = led_snoise(float3(sp * 1.1, t * 0.07), &dn);
        float2 dn2 = dn.xy * 1.1;
        float X0 = dot(sp, al);
        LedSilkX x0 = led_silk_x(X0, t, rip);
        LedSilkX xL = led_silk_x(X0 + e, t, rip);
        float h0 = led_silk_height(sp, X0, x0, n0, t, rip, wave_field, clock);
        float hA = led_silk_height(sp + ac * e, X0, x0, n0 + dot(dn2, ac * e), t, rip, wave_field, clock);
        float hB = led_silk_height(sp - ac * e, X0, x0, n0 - dot(dn2, ac * e), t, rip, wave_field, clock);
        float hL = led_silk_height(sp + al * e, X0 + e, xL, n0 + dot(dn2, al * e), t, rip, wave_field, clock);
        float2 g = ac * (hA - hB) / (2.0 * e) + al * (hL - h0) / e;
        float3 n = normalize(float3(-g * 0.05, 1.0));
        // Positive where the fold curves over a crest.
        float crest = led_smoothstep(-0.15, 0.75, -(hA - 2.0 * h0 + hB) / (e * e) * 0.006);

        float lift = led.text.x;
        float tx = min(led_silk_box(p - float2(0.0, 0.03 + lift), float2(0.27, 0.07), 0.07),
                       led_silk_box(p - float2(0.0, -0.17 + lift), float2(0.13, 0.06), 0.06));
        float text_mask = led.text.y > 0.5 ? mix(0.3, 1.0, led_smoothstep(-0.02, 0.1, tx)) : 1.0;

        float az = 2.2 + 0.3 * sin(phase2 * 0.35);
        float2 ld = float2(cos(az), sin(az));
        float sl = dot(n.xy, ld);
        float ao = 0.2 + 0.8 * led_smoothstep(-1.6, 1.1, h0);
        float body = pow(led_smoothstep(-0.12, 0.5, sl), 1.6) * ao;
        float sheen = led_silk_bell((sl - 0.3) / 0.11) * ao;
        float glint = led_silk_bell((sl - 0.33) / 0.045) * (0.35 + 0.65 * crest) * ao;
        float rim = led_silk_bell((sl + 0.42) / 0.1) * (0.4 + 0.6 * ao);

        float X = dot(p, float2(0.8, 0.6));
        float pk = peak < 1.4 ? 1.0 - led_smoothstep(0.7, 1.4, peak) : 0.0;
        float sweep = pk * led_silk_bell((X - mix(-0.55, 0.6, led_ease_out(peak / 1.2))) / 0.13);
        float amp = led.flags.w * (1.0 + 0.3 * led.flags.y + 0.5 * wave_field + 2.2 * sweep + 0.4 * pk);
        float k = fade * text_mask * amp;

        float glide = 0.05 * sin(X * 3.2 - phase2 * 0.8);
        float spread = mix(0.08, 1.0, act);
        float hot_k = clamp(led_smoothstep(0.0, 0.3, o) + sweep, 0.0, 1.0);
        float3 gold = float3(1.0, 0.84, 0.45);
        float3 c_body = led_heat(h + (-0.22 + 0.3 * led_smoothstep(-0.1, 0.5, sl) + glide) * spread, palette);
        float3 c_sheen0 = led_heat(h + (0.06 + glide) * spread, palette);
        float3 c_sheen = mix(c_sheen0, mix(gold, led_hot, 0.35), hot_k);
        float3 c_glint = mix(c_sheen, led_hot, 0.55 + 0.3 * hot_k);
        float3 c_rim = led_heat(h + (-0.32 - glide) * spread, palette);

        if (dark) {
            led_paint(acc, float3(0.008, 0.01, 0.016), 0.7 * fade);
            led_glow(acc, c_body, body * 0.32 * k, true);
            led_glow(acc, c_sheen, sheen * 0.75 * k, true);
            led_glow(acc, c_glint, glint * 0.7 * k, true);
            led_glow(acc, c_rim, rim * 0.35 * k, true);
            led_glow(acc, mix(gold, led_hot, 0.4), sweep * (0.12 + 0.6 * body + 0.8 * sheen) * fade * text_mask, true);
        } else {
            float tm = 0.4 + 0.6 * text_mask;
            led_paint(acc, float3(0.99, 0.985, 0.978), 0.55 * fade);
            led_paint(acc, float3(0.66, 0.67, 0.72), (pow(led_smoothstep(0.15, -0.45, sl), 1.3) * 0.38 + (1.0 - ao) * 0.12) * fade * tm);
            led_glow(acc, led_ink(c_rim), rim * 0.22 * k, false);
            led_glow(acc, mix(led_ink(c_sheen0), float3(0.96, 0.66, 0.16), hot_k), sheen * (0.3 + 0.15 * hot_k) * k, false);
            led_paint(acc, float3(1.0), (glint * 0.75 + sheen * 0.35) * fade * tm);
            led_glow(acc, led_ink(gold), sweep * (0.1 + 0.4 * body) * fade * tm, false);
        }
    }

    """

    static let corona = """
    // The corona's slow body noise depends only on the angle: sampled around the rim once per frame on the CPU.
    static float led_corona_body(float ang, constant float *body) {
        float u = ang / 360.0 * 128.0;
        float k = floor(u);
        int i0 = int(k) & 127;
        return mix(body[i0], body[(i0 + 1) & 127], u - k);
    }

    static void led_corona(thread LedAcc &acc, float2 p, float r, float ang, float px, constant LedFieldParams &led,
                           constant float *body_table, texture2d<float> palette) {
        bool dark = led.flags.x > 0.5;
        float h = led.heat.x;
        float o = led.heat.y;
        float3 hc = led_heat(h, palette);
        float outer = led_smoothstep(0.74, 0.64, r);
        // The body (drawn below this layer in the app) covers what reaches inside the rim.
        float disc = led_smoothstep(0.5 + px, 0.5 - px, r);
        float cover = 1.0 - disc * (dark ? 0.92 : 0.96);

        // Corona: flame tongues licking off the rim.
        float c_amt = led.corona.z;
        if (c_amt > 0.001) {
            float phase = led.corona.x;
            float2 dir = p / max(r, 1e-4);
            float body = led_corona_body(ang, body_table);
            float reach = 0.02 + (0.06 * h + 0.12 * o) * pow(body, 1.4) * 1.7;
            float d = (r - 0.499) / reach;
            float fall = exp(-d * 2.4) * led_smoothstep(0.49, 0.503, r) * outer;
            float base = exp(-max(r - 0.5, 0.0) / 0.012) * led_smoothstep(0.49, 0.503, r) * 0.35;
            float flame = 0.0;
            // The other three noises only where a flame can still show (its peak is fall × 1.25 × 1.15).
            if (fall * 1.44 * c_amt * cover > 0.002) {
                float rise = (r - 0.5) * 9.0 - phase;
                float warp_n = led_snoise(float3(dir * 3.0, rise * 0.5));
                float ridge = 1.0 - abs(led_snoise(float3(dir * 7.0 + warp_n * 0.35, rise)));
                ridge = pow(ridge, 5.0);
                float tongues = led_smoothstep(0.45, 0.8, 0.5 + 0.5 * led_snoise(float3(dir * 4.5, rise * 0.35)));
                flame = ridge * fall * mix(0.12, 1.25, tongues) * (0.45 + 0.7 * body);
            }
            float3 fc = mix(led_hot, hc, clamp(d * 0.9, 0.0, 1.0));
            led_glow(acc, dark ? fc : led_ink(hc), (flame + base) * c_amt * 0.95 * cover, dark);
        }

        // Warp streaks rushing into the orb.
        float w_amt = led.corona.w;
        if (w_amt > 0.001 && r > 0.5) {
            float bins = 96.0;
            int bin = clamp(int(floor(ang / 360.0 * bins)), 0, 95);
            float seed = led_warp_seeds[bin];
            if (seed < 0.18 + 0.42 * h) {
                float speed = 0.55 + seed * 0.9;
                float head = fract(seed * 7.3 + led.corona.y * speed);
                float rh = mix(0.74, 0.51, head);
                float len = (0.02 + 0.08 * h + 0.07 * o) * (0.55 + seed);
                float along = (r - rh) / len;
                float across_deg = abs(fract(ang / 360.0 * bins) - 0.5) * 360.0 / bins;
                float across = across_deg * 0.0174532925 * r;
                float line = led_smoothstep(0.0018 + 0.001 * h, 0.0, across) * pow(led_smoothstep(1.0, 0.0, along), 1.6) * step(0.0, along);
                float fade = led_smoothstep(0.0, 0.3, head) * led_smoothstep(1.0, 0.82, head);
                float3 wc = mix(hc, led_hot, 0.45);
                led_glow(acc, dark ? wc : led_ink(hc), line * fade * w_amt * (dark ? 0.8 : 0.75) * outer * cover, dark);
            }
        }
    }

    fragment float4 orb_led_fragment(LedFieldOut in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]],
                                     constant LedFieldParams &led [[buffer(2)]],
                                     constant int &mode [[buffer(3)]],
                                     constant float *body_table [[buffer(4)]],
                                     texture2d<float> palette [[texture(0)]]) {
        float s = led.frame.z;
        float2 p = (in.canvas - led.frame.xy) / s;
        p.y = -p.y;
        float r = length(p);
        LedAcc acc;
        acc.rgb = float3(0.0);
        acc.a = 0.0;
        if (mode == 0) {
            if (r >= 0.475) {
                discard_fragment();
            }
            float wave_field = 0.0;
            for (int i = 0; i < 4; i++) {
                float4 w = led.waves[i];
                if (w.x < 0.0 || w.x > 1.0) {
                    continue;
                }
                float rr = 0.1 + 0.4 * led_ease_out(w.x);
                float k = (r - rr) / 0.05;
                wave_field += w.y * (1.0 - w.x) * exp(-k * k);
            }
            led_silk_core(acc, p, r, led, wave_field, palette);
        } else {
            if (r < 0.47 || r > 0.74) {
                discard_fragment();
            }
            float ang = atan2(-p.y, p.x) * 57.2957795131;
            if (ang < 0.0) {
                ang += 360.0;
            }
            led_corona(acc, p, r, ang, 1.0 / (s * uniforms.viewport.z), led, body_table, palette);
        }
        float alpha = led.frame.w;
        acc.rgb *= alpha;
        acc.a *= alpha;
        if (acc.a <= 0.0005 && max(acc.rgb.r, max(acc.rgb.g, acc.rgb.b)) <= 0.0005) {
            discard_fragment();
        }
        return float4(acc.rgb, acc.a);
    }

    // The silk rendered beforehand at half the backing resolution (premultiplied), laid over the disc.
    fragment float4 orb_led_silk_fragment(LedFieldOut in [[stage_in]],
                                          constant LedFieldParams &led [[buffer(2)]],
                                          constant float4 &layer [[buffer(4)]],
                                          texture2d<float> silk [[texture(1)]]) {
        constexpr sampler s(address::clamp_to_zero, filter::linear);
        float2 uv = (in.canvas - led.frame.xy) / layer.x + 0.5;
        float4 color = silk.sample(s, uv);
        if (color.a <= 0.0005 && max(color.r, max(color.g, color.b)) <= 0.0005) {
            discard_fragment();
        }
        return color;
    }

    """
}

/// Per-frame parameters of the `led` fields (layout matches `LedFieldParams` in `OrbLedShaderSource`).
struct OrbLedFieldUniforms {
    var frame: SIMD4<Float> = .zero
    var heat: SIMD4<Float> = .zero
    var phases: SIMD4<Float> = .zero
    var flags: SIMD4<Float> = .zero
    var corona: SIMD4<Float> = .zero
    var text: SIMD4<Float> = .zero
    var wave0 = SIMD4<Float>(-1, 0, 0, 0)
    var wave1 = SIMD4<Float>(-1, 0, 0, 0)
    var wave2 = SIMD4<Float>(-1, 0, 0, 0)
    var wave3 = SIMD4<Float>(-1, 0, 0, 0)

    mutating func setWave(_ index: Int, _ value: SIMD4<Float>) {
        switch index {
        case 0: wave0 = value
        case 1: wave1 = value
        case 2: wave2 = value
        default: wave3 = value
        }
    }
}

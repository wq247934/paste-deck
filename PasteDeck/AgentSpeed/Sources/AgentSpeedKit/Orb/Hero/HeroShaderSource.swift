/// Metal shading language source for the hero vehicle layer, compiled once at runtime (no resource bundle needed).
///
/// Every `HeroDrawItem` is an instanced quad over its bounds whose fragment shader measures the distance to the
/// item's geometry in canvas units: strokes and fills are anti-aliased analytically and the glow is the exact Gaussian
/// blur of the shape (an erf profile), so no offscreen blur pass is needed. A quad reaches only as far as the item can
/// still draw 1/512 of alpha (at most 3.2 sigma), and polylines skip whole runs of segments whose bounds (`chunks`,
/// filled by `HeroLayerEncoder`) are out of reach.
enum HeroShaderSource {
    /// Segments per culling chunk: chunk `c` bounds the segments ending at points `c * chunk ..< (c + 1) * chunk`.
    static let chunk = 8

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // header: kind (0 polyline, 1 circle, 2 radial), first point, point count, flags
    // stroke: half width, opacity, glow opacity, glow sigma (canvas units)
    // color / fill: straight-alpha sRGB (radial: center and mid color)
    // shape: circle and radial center x, y, radius; polyline fade start and end (arc length)
    // bounds: geometry bounds before stroke and glow (min x, min y, max x, max y)
    struct HeroItem {
        float4 header;
        float4 stroke;
        float4 color;
        float4 fill;
        float4 shape;
        float4 bounds;
    };

    struct HeroUniforms {
        float4 viewport;   // width, height (points), pixels per point, pass (0 crisp, 1 glow)
        float4 layer;      // origin x, y (points), points per unit, one pixel in units
        float4 mask;       // center x, y, solid radius, clear radius (units)
        float4 sweepBand;  // center x, half width, strength, layer opacity
        float4 sweepColor; // straight alpha
    };

    struct HeroVertexOut {
        float4 position [[position]];
        float2 canvas;
        uint item [[flat]];
        float reach [[flat]];
    };

    constant uint HERO_STROKE = 1;
    constant uint HERO_FILL = 2;
    constant uint HERO_FADE = 4;
    constant uint HERO_SOFT = 8;
    constant uint HERO_ADDITIVE = 16;
    constant uint HERO_CHUNK = \(chunk);

    constant float2 hero_corners[6] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 0), float2(1, 1), float2(0, 1) };

    // Blur sigma with the pixel's box filter folded in, so tiny sigmas stay anti-aliased.
    static inline float hero_sigma(float sigma, float aa) {
        float s = max(sigma, 0.0);
        return sqrt(s * s + aa * aa * (1.0 / 12.0));
    }

    // Distance in units of sqrt(2) sigma beyond which a blur of peak alpha z stays under 1/512: erfc^-1(1 / (256 z))
    // from its asymptotic form, rounded up, never more than 3.2 sigma.
    static inline float hero_tail(float z) {
        float l = log(max(256.0 * z, 1.0));
        return min(1.03 * sqrt(max(l - 0.5 * log(3.14159265 * max(l, 0.1)), 0.0)) + 0.05, 2.2627417);
    }

    // How far from the geometry an item can still draw: stroke, anti-aliasing and blur.
    static inline float hero_reach(HeroItem item, bool glow, float aa) {
        float reach = max(item.stroke.x, 0.0) + 2.0 * aa;
        if (glow || (uint(item.header.w) & HERO_SOFT) != 0) {
            float peak = glow ? item.stroke.z : item.color.a * item.stroke.y;
            reach += 1.41421356 * hero_sigma(item.stroke.w, aa) * hero_tail(peak);
        }
        return reach;
    }

    // Winitzki's erf, maximum error about 1.2e-4.
    static inline float hero_erf(float x) {
        float x2 = x * x;
        float k = 0.147 * x2;
        return copysign(sqrt(1.0 - exp(-x2 * (1.27323954 + k) / (1.0 + k))), x);
    }

    // A band of half width w blurred by a Gaussian; inv = 1 / (sqrt(2) sigma).
    static inline float hero_band(float d, float w, float inv) {
        return max(0.5 * (hero_erf((d + w) * inv) - hero_erf((d - w) * inv)), 0.0);
    }

    vertex HeroVertexOut hero_vertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     const device HeroItem *items [[buffer(0)]],
                                     constant HeroUniforms &uniforms [[buffer(2)]]) {
        HeroItem item = items[iid];
        bool glow = uniforms.viewport.w > 0.5;
        bool radial = item.header.x > 1.5;
        float margin = radial ? 0.0 : hero_reach(item, glow, uniforms.layer.w);
        float2 lo = max(item.bounds.xy - margin, uniforms.mask.xy - uniforms.mask.w);
        float2 hi = min(item.bounds.zw + margin, uniforms.mask.xy + uniforms.mask.w);
        bool skip = any(lo >= hi) || (glow && (radial || item.stroke.z < 1.0 / 512.0));
        float2 canvas = skip ? lo : mix(lo, hi, hero_corners[vid]);
        float2 point = uniforms.layer.xy + canvas * uniforms.layer.z;
        HeroVertexOut out;
        out.position = float4(point.x / uniforms.viewport.x * 2.0 - 1.0, 1.0 - point.y / uniforms.viewport.y * 2.0, 0, 1);
        out.canvas = canvas;
        out.item = iid;
        out.reach = margin;
        return out;
    }

    fragment float4 hero_fragment(HeroVertexOut in [[stage_in]],
                                  const device HeroItem *items [[buffer(0)]],
                                  const device float4 *points [[buffer(1)]],
                                  constant HeroUniforms &uniforms [[buffer(2)]],
                                  const device float4 *chunks [[buffer(3)]]) {
        float2 p = in.canvas;
        float4 mask = uniforms.mask;
        float m = saturate((mask.w - distance(p, mask.xy)) / max(mask.w - mask.z, 1e-4));
        if (m <= 0.0) {
            discard_fragment();
        }
        HeroItem item = items[in.item];
        bool glow = uniforms.viewport.w > 0.5;
        uint flags = uint(item.header.w);
        float aa = uniforms.layer.w;
        float4 color;

        if (item.header.x > 1.5) {
            // Radial gradient: color at the center, fill at 45 % of the radius, transparent at the radius.
            float t = distance(p, item.shape.xy) / max(item.shape.z, 1e-4);
            float4 c = t < 0.45 ? mix(item.color, item.fill, t / 0.45)
                                : float4(item.fill.rgb, item.fill.a * saturate((1.0 - t) / 0.55));
            float a = c.a * item.stroke.y;
            color = float4(c.rgb * a, a);
        } else {
            bool polyline = item.header.x < 0.5;
            bool fill = polyline && (flags & HERO_FILL) != 0;
            bool stroke = (flags & HERO_STROKE) != 0;
            bool soft = (flags & HERO_SOFT) != 0;
            float w = max(item.stroke.x, 0.0);
            float d;
            float sd = 0.0;
            float arc = 0.0;
            if (polyline) {
                // Distances beyond the reach draw nothing, so the search starts there and skips distant chunks.
                uint first = uint(item.header.y);
                uint end = first + uint(item.header.z);
                float reach = in.reach;
                float best = reach * reach;
                bool inside = false;
                for (uint c = (first + 1) / HERO_CHUNK; c * HERO_CHUNK < end; c++) {
                    float4 box = chunks[c];
                    float2 e = max(max(box.xy - p, p - box.zw), 0.0);
                    bool crossing = fill && p.y >= box.y && p.y <= box.w && p.x <= box.z;
                    if (dot(e, e) >= best && !crossing) {
                        continue;
                    }
                    uint i = max(c * HERO_CHUNK, first + 1);
                    uint stop = min((c + 1) * HERO_CHUNK, end);
                    float4 a = points[i - 1];
                    for (; i < stop; i++) {
                        float4 b = points[i];
                        if (b.w < 0.5) {
                            float2 pa = p - a.xy;
                            float2 ba = b.xy - a.xy;
                            float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-12));
                            float2 q = pa - ba * h;
                            float dd = dot(q, q);
                            if (dd < best) {
                                best = dd;
                                arc = mix(a.z, b.z, h);
                            }
                            if (fill && (a.y > p.y) != (b.y > p.y) && p.x < a.x + (p.y - a.y) * ba.x / ba.y) {
                                inside = !inside;
                            }
                        }
                        a = b;
                    }
                }
                d = sqrt(best);
                sd = inside ? -d : d;
            } else {
                d = abs(distance(p, item.shape.xy) - item.shape.z);
            }
            float fade = 1.0;
            if (polyline && (flags & HERO_FADE) != 0) {
                fade = 1.0 - saturate((arc - item.shape.x) / max(item.shape.y - item.shape.x, 1e-4));
            }
            if (glow) {
                float inv = 0.70710678 / hero_sigma(item.stroke.w, aa);
                float profile = fill ? 0.5 * (1.0 - hero_erf((sd - (stroke ? w : 0.0)) * inv)) : hero_band(d, w, inv);
                float a = item.stroke.z * profile * fade;
                color = float4((stroke ? item.color.rgb : item.fill.rgb) * a, a);
            } else {
                color = float4(0.0);
                if (fill) {
                    float a = saturate(0.5 - sd / aa) * item.fill.a;
                    color = float4(item.fill.rgb * a, a);
                }
                if (stroke) {
                    float coverage;
                    if (soft) {
                        coverage = hero_band(d, w, 0.70710678 / hero_sigma(item.stroke.w, aa));
                    } else {
                        // Hairlines keep one pixel of width and dim instead of breaking up.
                        float half_width = max(w, 0.5 * aa);
                        coverage = saturate((half_width - d) / aa + 0.5) * (w / half_width);
                    }
                    float a = coverage * item.color.a * item.stroke.y;
                    color = float4(item.color.rgb * a, a) + color * (1.0 - a);
                }
                color *= fade;
            }
        }

        if (!glow && (flags & HERO_ADDITIVE) == 0 && uniforms.sweepBand.z > 0.0) {
            float4 band = uniforms.sweepBand;
            float k = band.z * max(0.0, 1.0 - abs(p.x - band.x) / max(band.y, 1e-4)) * uniforms.sweepColor.a;
            color.rgb = mix(color.rgb, uniforms.sweepColor.rgb * color.a, k);
        }
        color *= m * uniforms.sweepBand.w;
        if (color.a < 1.0 / 512.0) {
            discard_fragment();
        }
        return color;
    }
    """
}

// Where the waterfall meets the lake (tools/world.py): droplets thrown up and out in arcs,
// a churning white bulge of foam, mist rising and drifting. Under the surface `mask` (the
// lake's, r: water, g: water or open air) keeps it off the rock. Compiled with qsb (see README).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;      // seconds, wrapped every hour
    vec2 extent;     // the item, in units
    float level;     // the lake's surface, units above the item's bottom
    float impact;    // where the waterfall lands, units from the item's left
    float fallWidth; // the waterfall's width there
    vec4 maskRect;   // the mask's left, bottom, width, height, in units from the item's bottom-left
    vec4 shallow;
    vec4 light;
};

layout(binding = 1) uniform sampler2D mask;

float hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    return noise(p) * 0.5 + noise(p * 2.03 + 3.7) * 0.28 + noise(p * 4.1 + 7.1) * 0.14 + noise(p * 8.3 + 1.3) * 0.08;
}

// Distance from p to the segment a-b.
float segment(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * t);
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * extent.x, (1.0 - qt_TexCoord0.y) * extent.y);  // units, y up
    vec2 muv = vec2((p.x - maskRect.x) / maskRect.z, 1.0 - (p.y - maskRect.y) / maskRect.w);
    vec4 m = texture(mask, muv);
    float x = p.x - impact;
    float y = p.y - level;  // above the surface (+)

    // Droplets: each thrown from where the water lands, up and outwards, falling back; seeded,
    // so each one comes back on its own rhythm.
    float drops = 0.0;
    for (int i = 0; i < 64; i++) {
        float n = float(i);
        float life = 0.5 + 0.75 * hash(n + 0.1);
        float t = fract(time / life + hash(n + 0.2)) * life;
        float side = hash(n + 0.3) < 0.5 ? -1.0 : 1.0;
        vec2 v0 = vec2(side * (0.4 + 3.6 * hash(n + 0.4)), 2.8 + 5.5 * hash(n + 0.5));
        vec2 at = vec2((hash(n + 0.6) - 0.5) * fallWidth * 0.8, 0.05);
        float g = 22.0;
        vec2 pos = at + v0 * t - vec2(0.0, 0.5 * g * t * t);
        vec2 vel = v0 - vec2(0.0, g * t);
        if (pos.y < -0.05) {
            continue;  // back in the lake
        }
        float r = 0.028 + 0.045 * hash(n + 0.7);
        float d = segment(vec2(x, y), pos, pos - vel * 0.018);  // a short streak along its path
        drops += (1.0 - smoothstep(r * 0.35, r, d)) * (1.0 - t / life * 0.5);
    }

    // The bulge of foam where it lands: churning, boiling up and outwards.
    float spread = fallWidth * 0.75 + 0.5;
    float churn = fbm(vec2(x * 3.4 + sign(x) * time * 0.8, y * 4.5 - time * 3.2));
    float bubbles = fbm(vec2(x * 9.0 - time * 0.5, y * 9.0 - time * 4.0));
    float shape = exp(-pow(x / spread, 2.0)) * exp(-max(y, 0.0) / (0.55 + 0.45 * churn)) * smoothstep(-0.9, -0.15, y);
    float foam = clamp(smoothstep(0.28, 0.58, churn) * 1.2 + smoothstep(0.5, 0.68, bubbles) * 0.6, 0.0, 1.0) * shape;

    // Mist: a soft cloud rising and drifting from it.
    float cloud = fbm(vec2(x * 0.75 - time * 0.12, y * 0.9 - time * 0.55));
    float mist = smoothstep(0.3, 0.8, cloud) * exp(-pow(x / (1.3 + 0.35 * max(y, 0.0)), 2.0))
        * exp(-max(y, 0.0) / 1.6) * smoothstep(-0.1, 0.25, y) * 0.42;

    // Above the surface it all flies in front of the rocks around; under it, only in the water.
    float a = clamp(foam * 0.97 + drops + mist, 0.0, 1.0) * mix(m.g, 1.0, smoothstep(-0.05, 0.3, y));
    vec3 c = mix(shallow.rgb, light.rgb, clamp(0.55 + foam * 0.6 + drops, 0.0, 1.0));
    fragColor = vec4(c * a, a) * qt_Opacity;
}

// The lake's surface (tools/world.py LAKE): a bright, gently moving line along the top, a
// lit band under it, glints drifting in the water, rings spreading from where the waterfall
// lands, foam drifting away from it on the surface. Its still body is baked into the world's front
// layer; `mask` keeps all this off the rock (r: water, g: open air or water).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;    // seconds, wrapped every hour
    vec2 extent;   // the item, in units
    float level;   // the surface, units above the item's bottom
    float impact;  // where the waterfall lands, units from the item's left
    vec4 shallow;
    vec4 light;
};

layout(binding = 1) uniform sampler2D mask;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    return noise(p) * 0.55 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 7.1) * 0.15;
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * extent.x, (1.0 - qt_TexCoord0.y) * extent.y);  // units, y up
    vec4 m = texture(mask, qt_TexCoord0);
    float near = exp(-pow((p.x - impact) / 1.3, 2.0));  // close to where the waterfall lands
    float wave = 0.03 * sin(p.x * 2.7 + time * 1.3) + 0.02 * sin(p.x * 6.1 - time * 1.9)
        + near * 0.05 * sin(p.x * 11.0 - time * 7.0);
    float d = p.y - level - wave;  // above (+) or below (-) the moving surface

    float line = 1.0 - smoothstep(0.018, 0.055, abs(d));
    float band = d < 0.0 ? exp(d / 0.22) * 0.3 : 0.0;

    // Glints: short dashes drifting in rows under the surface, fading with depth.
    float row = floor(-d / 0.16);
    float across = abs(fract(-d / 0.16) - 0.5);
    float dir = mod(row, 2.0) * 2.0 - 1.0;
    float g = noise(vec2(p.x * 1.7 + dir * time * (0.12 + 0.12 * hash(vec2(row, 2.0))) + row * 7.3, row * 3.7));
    float glint = d < -0.08 ? smoothstep(0.76, 0.84, g) * (1.0 - smoothstep(0.06, 0.18, across)) * exp(d / 0.9) * 0.8 : 0.0;

    // Rings spreading on the surface from the impact.
    float ripple = 0.0;
    for (int k = 0; k < 4; k++) {
        float phase = fract(time * 0.3 + float(k) * 0.25);
        float r = 0.35 + phase * 3.6;
        float e = length(vec2(p.x - impact, d * 7.0));
        ripple += (1.0 - smoothstep(0.02, 0.1, abs(e - r))) * (1.0 - phase) * 0.9;
    }
    ripple *= smoothstep(-0.32, -0.12, d) * (1.0 - smoothstep(0.0, 0.04, d));

    // Foam drifting away on the surface from where it lands (the splash itself: splash.frag).
    float away = abs(p.x - impact);
    float f = fbm(vec2((p.x - sign(p.x - impact) * time * 0.35) * 2.2, d * 6.0));
    float foam = smoothstep(0.5, 0.75, f) * exp(-away / 2.2) * (1.0 - smoothstep(0.02, 0.12, abs(d + 0.03))) * 0.85;
    float mist = 0.0;

    float water = (line + band + glint + ripple) * m.r;
    float air = (foam + mist) * m.g;
    float a = clamp(water + air, 0.0, 1.0);
    vec3 c = mix(shallow.rgb, light.rgb, clamp((line + glint + ripple + foam + mist) / max(a, 1e-4), 0.0, 1.0));
    fragColor = vec4(c * a, a) * qt_Opacity;
}

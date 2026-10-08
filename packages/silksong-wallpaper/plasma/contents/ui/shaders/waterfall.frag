// The waterfall (tools/world.py WATERFALL): water pouring from the crack in the rock to the lake,
// spreading after the lip. Fast bright streaks over slower ones, turning frothy and white as it
// falls, droplets breaking off its edges. Compiled with qsb (see README).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;    // seconds, wrapped every hour
    vec2 extent;   // the item, in units
    vec4 edges;    // left and right at the top, left and right at the bottom (units from the item's left)
    vec4 shallow;  // the water's colour
    vec4 light;    // its highlights
};

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
    return noise(p) * 0.55 + noise(p * 2.03 + 3.7) * 0.3 + noise(p * 4.1 + 7.1) * 0.15;
}

// Droplets falling beside one edge: one per cell of a column scrolling down, at a random
// distance out from the water, some cells empty.
float droplets(vec2 p, float edge, float side, float speed, float seed) {
    float cell = 0.42;
    float y = p.y - time * speed;
    float row = floor(y / cell);
    float h = hash(vec2(row, seed));
    if (h < 0.45) {
        return 0.0;
    }
    float out_ = 0.04 + 0.22 * hash(vec2(row, seed + 1.0)) * (0.3 + 0.7 * clamp(p.y / extent.y, 0.0, 1.0));
    vec2 c = vec2(edge + side * out_, (row + 0.5) * cell + time * speed);
    vec2 d = p - c;
    d.y /= 2.8;  // drawn as short streaks: they fall fast
    return (1.0 - smoothstep(0.012, 0.035, length(d))) * (0.5 + 0.5 * h);
}

void main() {
    vec2 p = qt_TexCoord0 * extent;  // units, y down from the top
    float v = qt_TexCoord0.y;
    float spread = pow(v, 0.6);  // it spreads quickly after the lip, then falls straight
    float waver = 0.05 * sin(p.y * 1.7 - time * 7.0) + 0.03 * sin(p.y * 4.3 - time * 11.0 + 1.3);
    float left = mix(edges.x, edges.z, spread) + waver * spread;
    float right = mix(edges.y, edges.w, spread) - 0.8 * waver * spread;
    float w = right - left;
    float u = (p.x - left) / w;
    float dist = min(u, 1.0 - u) * w;  // to the nearer edge, units (negative outside)
    float fade = smoothstep(0.0, 0.5, p.y) * (1.0 - smoothstep(extent.y - 0.2, extent.y, p.y));

    // Droplets beside the edges, more of them lower down.
    float drops = droplets(p, left, -1.0, 9.0, 1.0) + droplets(p, right, 1.0, 9.5, 5.0)
        + droplets(p + vec2(0.0, 0.21), left, -1.0, 11.0, 9.0) + droplets(p + vec2(0.0, 0.17), right, 1.0, 10.5, 13.0);
    drops *= smoothstep(0.15, 0.4, v) * fade;
    if (dist <= 0.0) {
        float a = clamp(drops, 0.0, 1.0) * 0.85;
        fragColor = vec4(light.rgb * a, a) * qt_Opacity;
        return;
    }

    float slow = noise(vec2(u * 8.0, (p.y - time * 6.5) * 0.32));
    float fast = noise(vec2(u * 21.0 + 7.0, (p.y - time * 9.5) * 0.55));
    float streak = slow * 0.6 + fast * 0.4;
    // Thin bright lines racing down, and darker runnels between them.
    float hi = smoothstep(0.7, 0.9, noise(vec2(u * 34.0 + 3.0, (p.y - time * 12.0) * 0.22)));
    float dark = smoothstep(0.65, 0.85, noise(vec2(u * 15.0 + 11.0, (p.y - time * 8.0) * 0.3)));
    // Frothing white as it falls: the lower half churns.
    float froth = smoothstep(0.45, 0.8, fbm(vec2(u * 10.0, (p.y - time * 8.5) * 1.3))) * smoothstep(0.35, 1.0, v);
    float edge = 1.0 - smoothstep(0.0, 0.2, dist);

    float a = 0.34 + 0.4 * streak * streak + 0.3 * edge + 0.45 * hi + 0.45 * froth - 0.18 * dark;
    a = clamp(a, 0.0, 0.95) * smoothstep(0.0, 0.035, dist) * fade;
    float white = clamp(edge * 0.6 + streak * 0.45 + hi * 0.9 + froth * 0.9 - dark * 0.3 - 0.1, 0.0, 1.0);
    vec3 c = mix(shallow.rgb, light.rgb, white);
    // Droplets in front, where they cross the water's edge.
    a = max(a, clamp(drops, 0.0, 1.0) * 0.85);
    fragColor = vec4(c * a, a) * qt_Opacity;
}

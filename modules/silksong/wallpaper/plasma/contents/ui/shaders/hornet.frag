// Hornet in the colours of the zone she's in (tools/world.py hero_grade), the way the game
// draws her: Sprites/Default-ColorFlash with IS_HERO (40% of the room's ambient light, then
// _HeroDesaturation), then the camera's ColorCorrectionCurves and saturation. The creatures drawn
// from sheets come through here too, with their own tint and a neutral ambient (0.5: unlit).
// Between two zones she's coloured as both, mixed by `blend` (WorldScene, World.zoneWeights).
// Compiled with qsb (see README); the .qsb sits next to this file.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 cell;            // the frame in the sheet: x, y, width, height in 0..1
    vec4 ambient;         // the room's ambient light (rgb)
    float heroSaturation;
    float saturation;
    vec4 tint;            // the sprite's own colour (tk2dSprite colour), 1 for Hornet
    vec4 ambient2;        // the other zone's
    float heroSaturation2;
    float saturation2;
    float blend;          // how much of the other zone (0: none)
    // Set by Qt: where each table lies in its texture (small images share an atlas). Not for the
    // sheet, which Qt then gives a texture of its own: its place in the atlas changes from run to
    // run, and un-premultiplying her outlines would turn that into a few levels of colour.
    vec4 qt_SubRect_lut;
    vec4 qt_SubRect_lut2;
};

layout(binding = 1) uniform sampler2D source;  // her sheet, premultiplied
layout(binding = 2) uniform sampler2D lut;     // 256x1: the camera curves per channel
layout(binding = 3) uniform sampler2D lut2;    // the other zone's

const vec3 LUMA = vec3(0.22, 0.707, 0.071);  // Unity's Luminance() in gamma space

vec3 curves(sampler2D table, vec4 rect, vec3 c) {
    vec3 u = rect.x + (clamp(c, 0.0, 1.0) * (255.0 / 256.0) + 0.5 / 256.0) * rect.z;
    float v = rect.y + 0.5 * rect.w;
    return vec3(texture(table, vec2(u.r, v)).r, texture(table, vec2(u.g, v)).g, texture(table, vec2(u.b, v)).b);
}

vec3 graded(vec3 c, vec3 amb, float heroSat, sampler2D table, vec4 rect, float sat) {
    c = c + (c * amb * 2.0 - c) * 0.4;
    float l = clamp(dot(c, LUMA), 0.0, 1.0);
    c = clamp(l + (c - l) * heroSat, 0.0, 1.0);
    c = curves(table, rect, c);
    l = dot(c, LUMA);
    return clamp(l + (c - l) * sat, 0.0, 1.0);
}

void main() {
    vec4 p = texture(source, cell.xy + qt_TexCoord0 * cell.zw);
    if (p.a < 0.002) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 c = p.rgb / p.a * tint.rgb;
    vec3 a = graded(c, ambient.rgb, heroSaturation, lut, qt_SubRect_lut, saturation);
    if (blend > 0.001) {
        a = mix(a, graded(c, ambient2.rgb, heroSaturation2, lut2, qt_SubRect_lut2, saturation2), blend);
    }
    fragColor = vec4(a * p.a, p.a) * qt_Opacity;
}

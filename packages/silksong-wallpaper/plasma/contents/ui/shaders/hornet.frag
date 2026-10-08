// Hornet in the colours of the zone she's in (tools/world.py hero_grade), the way the game
// draws her: Sprites/Default-ColorFlash with IS_HERO (40% of the room's ambient light, then
// _HeroDesaturation), then the camera's ColorCorrectionCurves and saturation.
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
};

layout(binding = 1) uniform sampler2D source;  // her sheet, premultiplied
layout(binding = 2) uniform sampler2D lut;     // 256x1: the camera curves per channel

const vec3 LUMA = vec3(0.22, 0.707, 0.071);  // Unity's Luminance() in gamma space

vec3 curves(vec3 c) {
    vec3 u = clamp(c, 0.0, 1.0) * (255.0 / 256.0) + 0.5 / 256.0;
    return vec3(texture(lut, vec2(u.r, 0.5)).r, texture(lut, vec2(u.g, 0.5)).g, texture(lut, vec2(u.b, 0.5)).b);
}

void main() {
    vec4 p = texture(source, cell.xy + qt_TexCoord0 * cell.zw);
    if (p.a < 0.002) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 c = p.rgb / p.a;
    c = c + (c * ambient.rgb * 2.0 - c) * 0.4;
    float l = clamp(dot(c, LUMA), 0.0, 1.0);
    c = clamp(l + (c - l) * heroSaturation, 0.0, 1.0);
    c = curves(c);
    l = dot(c, LUMA);
    c = clamp(l + (c - l) * saturation, 0.0, 1.0);
    fragColor = vec4(c * p.a, p.a) * qt_Opacity;
}

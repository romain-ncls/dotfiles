// The world drawn in lines while the lock screen makes it (Drawing.qml; tools/world.py
// build_drawing): the tile's red is the line, its green when the pen reaches it (0..1 of the
// drawing's time). Pale ink on black, brighter just where the pen is. Compiled with qsb (see
// README).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress; // how far the drawing is, 0..1
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 s = texture(source, qt_TexCoord0);
    float behind = progress - s.g; // how long ago the pen passed here, in the drawing's time
    float seen = s.r * clamp(behind / 0.012 + 1.0, 0.0, 1.0);
    float tip = s.r * exp(-(behind * behind) / (0.014 * 0.014)) * step(-0.005, behind);
    vec3 ink = vec3(0.91, 0.878, 0.816) * seen + vec3(0.157) * tip;
    fragColor = vec4(min(ink, vec3(1.0)), 1.0) * qt_Opacity;
}

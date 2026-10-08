// The particles' pixels (particle.vert places them and sets their frames and fades); the
// cells between two slots' quads are dropped.
#version 440

layout(location = 0) in vec2 texCoord;
layout(location = 1) in float alpha;
layout(location = 2) in float column;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float slots;
    float pxPerUnit;
    vec4 area;
    vec4 centre;
    vec4 axes;
    vec4 lifeSize;
    vec4 velocity;
    vec4 spin;
    vec4 misc;
    vec4 sheet;
    vec4 keyT0;
    vec4 keyT1;
    vec4 keyA0;
    vec4 keyA1;
};

layout(binding = 1) uniform sampler2D source;  // the system's texture, premultiplied

void main() {
    if (fract(column * 0.5) >= 0.5)
        discard;
    vec4 c = texture(source, texCoord) * alpha;
    if (misc.z > 0.5)
        c.a = 0.0;  // additive
    fragColor = c * qt_Opacity;
}

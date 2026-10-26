// The particles' pixels (particle.vert places them and sets their frame, colour and fade).
#version 440

layout(location = 0) in vec2 texCoord;
layout(location = 1) in vec4 colour;
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
    vec4 shapeMore;
    vec4 lifeSize;
    vec4 sizeMore;
    vec4 sizeT;
    vec4 sizeV;
    vec4 speed;
    vec4 velocity;
    vec4 force;
    vec4 spin;
    vec4 misc;
    vec4 tint;
    vec4 colourT;
    vec4 colour0;
    vec4 colour1;
    vec4 colour2;
    vec4 colour3;
    vec4 sheet;
    vec4 keyT0;
    vec4 keyT1;
    vec4 keyA0;
    vec4 keyA1;
    vec4 qt_SubRect_source;
};

layout(binding = 1) uniform sampler2D source;  // the system's texture, premultiplied

void main() {
    vec4 t = texture(source, texCoord);
    vec4 c = vec4(t.rgb * colour.rgb, t.a) * colour.a;
    if (misc.z > 0.5)
        c.a = 0.0;  // additive
    fragColor = c * qt_Opacity;
}

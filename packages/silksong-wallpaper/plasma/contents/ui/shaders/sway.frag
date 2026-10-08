// The swaying piece's pixels, from the atlas (sway.vert moves it).
#version 440

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float amount;
    float speed;
    float phase;
    float fps;
    float rootY;
    float push;
    vec4 mags;
    vec4 times;
    vec4 uv;
};

layout(binding = 1) uniform sampler2D source;  // sway.png, premultiplied

void main() {
    fragColor = texture(source, texCoord) * qt_Opacity;
}

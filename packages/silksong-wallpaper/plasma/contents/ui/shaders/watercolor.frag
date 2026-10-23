// The world painted in watercolor while the lock screen makes it (Painting.qml; tools/world.py
// build_painting): `paint` its colours, `timing` when the brush reaches each pixel (red, 0..1 of
// the painting's time) and how much of the light shafts' it takes (green; smooth, and small). On
// dark paper with its grain, each wash spreading with a soft, ragged edge and a darker wet front,
// the shafts glazed over it as strong as the hour has them, under its veil as the world is. Then
// the world under it washes in the same way, light first: the painting goes clear wash by wash.
// All of it told by two clocks (Painting.qml): the brush's, from the first frame, at which it
// paints at `speed`, then from `calm` on ever slower towards the end while the world is made; and
// the end's, once the world is drawn under it, from which the brush goes on to the end at the pace
// it had then, neither faster nor slower, while the world washes in (`washFor` seconds).
// Compiled with qsb (see README).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float clock;   // seconds since the brush started
    float speed;   // of the painting's time per second, at first
    float calm;    // how far it gets at that pace, before slowing
    float end;     // how far the end is, 0..1 of endFor
    float endFor;  // the end's seconds
    float washFor; // of which the world's washing in, from the start
    vec4 veil;      // the hour's light: its colour, and how much of it (a); premultiplied, as
                    // ShaderEffect passes colours
    vec4 light;     // the shafts' colour, and how strong the hour has them (a); premultiplied
};

layout(binding = 1) uniform sampler2D paint;
layout(binding = 2) uniform sampler2D timing;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise of features about a pixel at p = pixels / size.
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A wet edge's raggedness about px, 0..1: three octaves of noise (16, 8 and 4 pixels), each turned
// off the others' grid, so that a front follows round, uneven shapes rather than squares.
float ragged(vec2 px) {
    const mat2 turn = mat2(0.8, 0.6, -0.6, 0.8);
    vec2 p = px / 16.0;
    float n = 0.5 * noise(p);
    p = turn * p * 2.0 + 3.1;
    n += 0.3 * noise(p);
    p = turn * p * 2.0 + 7.7;
    return n + 0.2 * noise(p);
}

// How far the painting is after c seconds, before the end: at speed, then slowing towards the end
// itself, never quite there (as fast at first: its pace has no jump).
float pace(float c) {
    float p = speed * c;
    return p <= calm ? p : 1.0 - (1.0 - calm) * exp(-(p - calm) / (1.0 - calm));
}
// And its pace then.
float paceOf(float c) {
    float p = speed * c;
    return p <= calm ? speed : speed * exp(-(p - calm) / (1.0 - calm));
}

void main() {
    // The end, t seconds in: the brush going on at the pace it had as it started (the clocks run
    // together: clock - t then), the world washing in.
    float t = end * endFor;
    float progress = min(1.0, pace(clock - t) + paceOf(clock - t) * t);
    float develop = clamp(t / washFor, 0.0, 1.0);
    vec4 times = texture(timing, qt_TexCoord0);
    float when = times.r;
    vec3 colour = texture(paint, qt_TexCoord0).rgb * (1.0 - times.g * light.a) + light.rgb * times.g;
    vec2 px = gl_FragCoord.xy;
    // How long ago the brush reached it, in the painting's time, its front a little ragged. The
    // brush is a tenth quicker than its time, so that the last wash is dry when it ends.
    float behind = 1.1 * progress - when - 0.05 * (ragged(px) - 0.5);
    float painted = smoothstep(0.0, 1.0, clamp(behind / 0.03 + 1.0, 0.0, 1.0));
    float wet = exp(-(behind * behind) / (0.035 * 0.035)) * step(-0.02, behind);
    float grain = 0.6 * noise(px / 2.0) + 0.4 * noise(px / 5.0);
    vec3 paper = vec3(0.063, 0.058, 0.053) * (1.0 - 0.05 * grain);
    vec3 c = mix(paper, colour * (1.0 - 0.35 * wet), painted) * (1.0 - veil.a) + veil.rgb;
    // The world washing in: clear where it has, along a soft, ragged front.
    const float soft = 0.08;
    float until = clamp(when + 0.07 * (ragged(px + 170.0) - 0.5), 0.0, 1.0);
    float clear = smoothstep(0.0, 1.0, clamp((develop - until * (1.0 - soft)) / soft, 0.0, 1.0));
    float a = 1.0 - clear;
    fragColor = vec4(c * a, a) * qt_Opacity;
}

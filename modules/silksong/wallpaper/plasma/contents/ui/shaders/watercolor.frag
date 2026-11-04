// The world painted in watercolor while the lock screen makes it (Painting.qml; tools/world.py
// build_painting): `paint` its colours, `timing` when the brush reaches each pixel (red, 0..1 of
// the painting's time) and how much of the light shafts' it takes (green; smooth, and small). On
// dark paper with its grain, each wash spreading with a soft, ragged edge and a darker wet front,
// the shafts glazed over it as strong as the hour has them, under its veil as the world is. Then
// the world under it washes in the same way, light first: the painting goes clear wash by wash.
// All of it told by two clocks (Painting.qml): the brush's, from the first frame, at which it
// paints at `speed`, then from `calm` on slower and slower, easing towards `slowest`, while the
// world is made; and the end's, once the world is drawn under it, from which the brush goes on at
// the pace it had then, neither faster nor slower, and the world washes in behind it at that same
// pace (`washFor` seconds: the whole painting's time at it), so that neither ever outruns the other.
// Bare, it paints with no paper, over what's under it (the screen as it was, on Hyprland's lock
// screen). Compiled with qsb (see README).
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
    float washFor; // of which the world's washing in, from the start: the painting's time at the pace
                   // the brush had as the end began
    vec4 veil;      // the hour's light: its colour, and how much of it (a); premultiplied, as
                    // ShaderEffect passes colours
    vec4 light;     // the shafts' colour, and how strong the hour has them (a); premultiplied
    float bare;     // 1: no paper: where the brush hasn't been, the ground shows (the screen as
                    // it was, on Hyprland's lock screen: Painting.qml bare)
    float ramp;     // seconds the brush takes to get up to speed (pace())
    float slowest;  // the pace the brush eases towards from calm on, in painting a second
    vec4 groundRect; // bare: the part of the ground (the whole screen) this piece covers
};

layout(binding = 1) uniform sampler2D paint;
layout(binding = 2) uniform sampler2D timing;
layout(binding = 3) uniform sampler2D ground;

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

// How far the brush's pace alone takes it after c seconds: getting up to speed over the first
// `ramp` seconds (none on the dark paper; over the screen as it was, from a standstill), then at
// speed.
float run(float c) {
    return c < ramp ? speed * c * c / (2.0 * ramp) : speed * (c - 0.5 * ramp);
}
float runOf(float c) {
    return c < ramp ? speed * c / ramp : speed;
}
// How far the painting is after c seconds, before the end: so, then from calm on easing towards
// the slowest pace (pace's share of the run's going from 1 to slowest / speed), on to the end and
// past it (its progress stops there): its pace has no jump.
float pace(float c) {
    float p = run(c);
    float f = slowest / speed;
    return p <= calm ? p
        : calm + f * (p - calm) + (1.0 - f) * (1.0 - calm) * (1.0 - exp(-(p - calm) / (1.0 - calm)));
}
// And its pace then.
float paceOf(float c) {
    float p = run(c);
    float f = slowest / speed;
    return p <= calm ? runOf(c) : runOf(c) * (f + (1.0 - f) * exp(-(p - calm) / (1.0 - calm)));
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
    vec3 brushed = colour * (1.0 - 0.35 * wet);
    // Where the brush hasn't been: the dark paper, veiled, or bare, the screen as it was (ground)
    // as it is, the world washing in only where the brush has been (it never outruns the brush).
    vec3 c = bare > 0.5
        ? mix(texture(ground, groundRect.xy + qt_TexCoord0 * groundRect.zw).rgb,
              brushed * (1.0 - veil.a) + veil.rgb, painted)
        : mix(paper, brushed, painted) * (1.0 - veil.a) + veil.rgb;
    // The world washing in: clear where it has, along a soft, ragged front.
    const float soft = 0.08;
    float until = clamp(when + 0.07 * (ragged(px + 170.0) - 0.5), 0.0, 1.0);
    float clear = smoothstep(0.0, 1.0, clamp((develop - until * (1.0 - soft)) / soft, 0.0, 1.0));
    float a = 1.0 - clear;
    fragColor = vec4(c * a, a) * qt_Opacity;
}

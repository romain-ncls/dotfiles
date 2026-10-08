// A room's own ambient particle system (Verdania's fireflies), run the way Unity runs it
// (tools/world.py emitter): particles born in the emitter's shape, drifting at a speed of their
// own, spinning, fading by the alpha keys of their colour over lifetime, their sheet played over
// each life. One item per emitter: a grid of 2 * slots - 1 cells, a slot's quad in every other
// one (the cells between are dropped by particle.frag). Each slot lives a whole number of times
// an hour, so the clock's hourly wrap is seamless, and draws each life's randomness from the
// slot and the life.
#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 texCoord;
layout(location = 1) out float alpha;
layout(location = 2) out float column;  // its column in the grid: a slot's cells have an even floor

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;       // seconds, wrapped every hour
    float slots;
    float pxPerUnit;
    vec4 area;        // the item: left, bottom, width, height (units)
    vec4 centre;      // the emitter: x, y; shape (0 circle, 1 box); the circle's thickness
    vec4 axes;        // the shape's half axes: x (xy), y (zw)
    vec4 lifeSize;    // lifetime min, max (s); size min, max (units)
    vec4 velocity;    // x min, max; y min, max (units/s)
    vec4 spin;        // rotation speed min, max (rad/s); start rotation min, max (rad)
    vec4 misc;        // start alpha, gravity (units/s/s), additive
    vec4 sheet;       // tiles across, down, cycles over a life
    vec4 keyT0;       // the alpha keys' times (8)
    vec4 keyT1;
    vec4 keyA0;       // and their alphas
    vec4 keyA1;
};

out gl_PerVertex { vec4 gl_Position; };

float hash(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float fade(float u) {
    float t[8] = float[8](keyT0.x, keyT0.y, keyT0.z, keyT0.w, keyT1.x, keyT1.y, keyT1.z, keyT1.w);
    float a[8] = float[8](keyA0.x, keyA0.y, keyA0.z, keyA0.w, keyA1.x, keyA1.y, keyA1.z, keyA1.w);
    if (u <= t[0])
        return a[0];
    for (int i = 1; i < 8; i++) {
        if (u <= t[i])
            return mix(a[i - 1], a[i], (u - t[i - 1]) / max(t[i] - t[i - 1], 1e-4));
    }
    return a[7];
}

void main() {
    column = floor(qt_MultiTexCoord0.x * (2.0 * slots - 1.0) + 0.5);
    float slot = floor(column * 0.5);
    vec2 side = vec2(column - 2.0 * slot, qt_MultiTexCoord0.y);  // which corner of its quad
    float fi = slot + 1.0;
    float lives = max(1.0, floor(3600.0 / mix(lifeSize.x, lifeSize.y, hash(fi * 17.31)) + 0.5));
    float life = 3600.0 / lives;
    float tt = time + hash(fi * 5.77) * life;
    float n = floor(tt / life);
    float age = tt - n * life;
    float seed = fi * 1013.0 + mod(n, lives) * 7.31;

    vec2 q;
    if (centre.z < 0.5) {
        float r = sqrt(mix((1.0 - centre.w) * (1.0 - centre.w), 1.0, hash(seed + 1.0)));
        float a = hash(seed + 2.0) * 6.2831853;
        q = r * vec2(cos(a), sin(a));
    } else {
        q = vec2(hash(seed + 1.0), hash(seed + 2.0)) * 2.0 - 1.0;
    }
    vec2 p = centre.xy + axes.xy * q.x + axes.zw * q.y;
    p += vec2(mix(velocity.x, velocity.y, hash(seed + 3.0)), mix(velocity.z, velocity.w, hash(seed + 4.0))) * age;
    p.y -= 0.5 * misc.y * age * age;
    float size = mix(lifeSize.z, lifeSize.w, hash(seed + 5.0));
    float rot = mix(spin.z, spin.w, hash(seed + 6.0)) + mix(spin.x, spin.y, hash(seed + 7.0)) * age;

    vec2 corner = (side - 0.5) * vec2(1.0, -1.0) * size;  // y up
    float c = cos(rot), s = sin(rot);
    vec2 world = p + vec2(c * corner.x - s * corner.y, s * corner.x + c * corner.y);
    gl_Position = qt_Matrix * vec4((world.x - area.x) * pxPerUnit, (area.y + area.w - world.y) * pxPerUnit, 0.0, 1.0);

    float u = age / life;
    float frames = sheet.x * sheet.y;
    float f = mod(min(floor(u * frames * sheet.z), frames * sheet.z - 1.0), frames);
    vec2 cell = vec2(mod(f, sheet.x), floor(f / sheet.x));  // left to right, top to bottom
    texCoord = (cell + side) / sheet.xy;
    alpha = misc.x * fade(u);
}

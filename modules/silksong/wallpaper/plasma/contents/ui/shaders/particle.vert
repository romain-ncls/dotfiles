// A particle system from the game (room.particle_template; tools/world.py place_particles), run
// the way Unity runs it: particles born in the emitter's shape (a circle, a box or an edge),
// leaving it at their start speed (out of a circle, up from an edge), drifting, pushed by a force
// and by gravity, spinning, growing and fading, coloured over their life, their sheet played over
// each life. One item per emitter: a grid of 4 * slots - 1 cells, four columns of corners per
// slot (its quad's bottom left, its left edge, its right edge, its bottom right), so that only
// the cell between its edges has an area: those joining it to its neighbours fold into lines,
// of which the GPU draws nothing. Each slot lives a whole number of times an hour, so the clock's
// hourly wrap is seamless, and draws each life's randomness from the slot and the life.
#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 texCoord;
layout(location = 1) out vec4 colour;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;        // seconds, wrapped every hour
    float slots;
    float pxPerUnit;
    vec4 area;         // the item: left, bottom, width, height (units)
    vec4 centre;       // the emitter: x, y; shape (0 circle, 1 box, 2 edge); the circle's thickness
    vec4 axes;         // the shape's half axes: x (xy), y (zw)
    vec4 shapeMore;    // a circle's arc (radians); the way an edge's particles leave it (zw unused: x, y)
    vec4 lifeSize;     // lifetime min, max (s); start size min, max (units)
    vec4 sizeMore;     // a random size factor: min, max
    vec4 sizeT;        // size over a life: the keys' times
    vec4 sizeV;        // and values
    vec4 speed;        // start speed min, max (units/s)
    vec4 velocity;     // drift x min, max; y min, max (units/s)
    vec4 force;        // x min, max; y min, max (units/s/s)
    vec4 spin;         // rotation speed min, max (rad/s); start rotation min, max (rad)
    vec4 misc;         // start alpha, gravity (units/s/s, down), additive
    vec4 tint;         // start colour (rgb)
    vec4 colourT;      // colour over a life: the keys' times
    vec4 colour0;      // and colours
    vec4 colour1;
    vec4 colour2;
    vec4 colour3;
    vec4 sheet;        // tiles across, down, cycles over a life
    vec4 keyT0;        // alpha over a life: the keys' times (8)
    vec4 keyT1;
    vec4 keyA0;        // and alphas
    vec4 keyA1;
    vec4 qt_SubRect_source;  // set by Qt: where the image lies in its texture (an atlas, if small)
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

float grow(float u) {
    float t[4] = float[4](sizeT.x, sizeT.y, sizeT.z, sizeT.w);
    float v[4] = float[4](sizeV.x, sizeV.y, sizeV.z, sizeV.w);
    if (u <= t[0])
        return v[0];
    for (int i = 1; i < 4; i++) {
        if (u <= t[i])
            return mix(v[i - 1], v[i], (u - t[i - 1]) / max(t[i] - t[i - 1], 1e-4));
    }
    return v[3];
}

vec3 hue(float u) {
    float t[4] = float[4](colourT.x, colourT.y, colourT.z, colourT.w);
    vec3 c[4] = vec3[4](colour0.rgb, colour1.rgb, colour2.rgb, colour3.rgb);
    if (u <= t[0])
        return c[0];
    for (int i = 1; i < 4; i++) {
        if (u <= t[i])
            return mix(c[i - 1], c[i], (u - t[i - 1]) / max(t[i] - t[i - 1], 1e-4));
    }
    return c[3];
}

void main() {
    float column = floor(qt_MultiTexCoord0.x * (4.0 * slots - 1.0) + 0.5);
    float slot = floor(column * 0.25);
    float sub = column - 4.0 * slot;  // its bottom left (0), left edge, right edge, bottom right (3)
    vec2 side = vec2(sub < 1.5 ? 0.0 : 1.0, sub < 0.5 || sub > 2.5 ? 1.0 : qt_MultiTexCoord0.y);  // which corner of its quad
    float fi = slot + 1.0;
    float lives = max(1.0, floor(3600.0 / mix(lifeSize.x, lifeSize.y, hash(fi * 17.31)) + 0.5));
    float life = 3600.0 / lives;
    float tt = time + hash(fi * 5.77) * life;
    float n = floor(tt / life);
    float age = tt - n * life;
    float seed = fi * 1013.0 + mod(n, lives) * 7.31;

    // Where it's born, and the way its start speed sends it.
    vec2 q;
    vec2 away = vec2(0.0);
    if (centre.z < 0.5) {
        float r = sqrt(mix((1.0 - centre.w) * (1.0 - centre.w), 1.0, hash(seed + 1.0)));
        float a = hash(seed + 2.0) * shapeMore.x;
        q = r * vec2(cos(a), sin(a));
        away = normalize(axes.xy * cos(a) + axes.zw * sin(a) + vec2(1e-6, 0.0));
    } else if (centre.z < 1.5) {
        q = vec2(hash(seed + 1.0), hash(seed + 2.0)) * 2.0 - 1.0;
    } else {
        q = vec2(hash(seed + 1.0) * 2.0 - 1.0, 0.0);
        away = shapeMore.yz;
    }
    vec2 p = centre.xy + axes.xy * q.x + axes.zw * q.y;
    vec2 v = away * mix(speed.x, speed.y, hash(seed + 8.0))
        + vec2(mix(velocity.x, velocity.y, hash(seed + 3.0)), mix(velocity.z, velocity.w, hash(seed + 4.0)));
    vec2 f = vec2(mix(force.x, force.y, hash(seed + 9.0)), mix(force.z, force.w, hash(seed + 10.0))) - vec2(0.0, misc.y);
    p += v * age + 0.5 * f * age * age;

    float u = age / life;
    float size = mix(lifeSize.z, lifeSize.w, hash(seed + 5.0)) * mix(sizeMore.x, sizeMore.y, hash(seed + 11.0)) * grow(u);
    float rot = mix(spin.z, spin.w, hash(seed + 6.0)) + mix(spin.x, spin.y, hash(seed + 7.0)) * age;
    vec2 corner = (side - 0.5) * vec2(1.0, -1.0) * size;  // y up
    float c = cos(rot), s = sin(rot);
    vec2 world = p + vec2(c * corner.x - s * corner.y, s * corner.x + c * corner.y);
    gl_Position = qt_Matrix * vec4((world.x - area.x) * pxPerUnit, (area.y + area.w - world.y) * pxPerUnit, 0.0, 1.0);

    float frames = sheet.x * sheet.y;
    float k = mod(min(floor(u * frames * sheet.z), frames * sheet.z - 1.0), frames);
    vec2 cell = vec2(mod(k, sheet.x), floor(k / sheet.x));  // left to right, top to bottom
    texCoord = qt_SubRect_source.xy + (cell + side) / sheet.xy * qt_SubRect_source.zw;
    colour = vec4(tint.rgb * hue(u), misc.x * fade(u));
}

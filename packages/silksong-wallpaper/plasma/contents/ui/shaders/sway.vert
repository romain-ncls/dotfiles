// A plant or hanging vine swaying the way the game's grass shaders move it (Hollow Knight/
// Grass-Diffuse and Grass-Default, read from their OpenGL programs; tools/room.py sway_info):
// each vertex goes sideways by sway(t) times its height above the sprite's origin, with
//   t = (time, snapped to the material's frame rate if it has one) * speed + phase
//   sway(t) = amount * (A sin(t TA) + B sin(t TB) + C sin(t TC)) + push.
// A shear, so the quad's four corners are all it takes.
#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 texCoord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;    // seconds, wrapped every hour
    float amount;  // negative when the piece is drawn flipped
    float speed;
    float phase;   // from where it stands
    float fps;     // 0: not snapped
    float rootY;   // its origin, in item pixels from the top
    float push;    // Hornet walking into it (GrassBehaviour), in her direction
    vec4 mags;     // A, B, C
    vec4 times;    // TA, TB, TC
    vec4 uv;       // its rectangle in the atlas: u0, v0, u1, v1
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    float t = fps > 0.0 ? floor(time * fps + 0.5) / fps : time;
    float a = t * speed + phase;
    float s = mags.x * sin(a * times.x) + mags.y * sin(a * times.y) + mags.z * sin(a * times.z);
    vec4 p = qt_Vertex;
    p.x += (amount * s + push) * (rootY - p.y);
    texCoord = mix(uv.xy, uv.zw, qt_MultiTexCoord0);
    gl_Position = qt_Matrix * p;
}

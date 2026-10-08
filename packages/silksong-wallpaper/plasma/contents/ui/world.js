/*
 * The world is one fixed scene laid across the physical monitors, measured
 * in millimetres from the bottom-left corner of the leftmost screen, y up.
 * Scenes (tools/bake.py) are measured in game units from the same corner.
 *
 * Each screen runs its own copy of the wallpaper (plasmashell has one per
 * screen, the lock screen greeter is another process), so nothing here keeps
 * state: everything is computed from the screen list and the wall clock, and
 * every copy agrees without talking to the others.
 */
.pragma library

const WALK_SPEED = 5; // game units per second, HeroController.WALK_SPEED

// Screens side by side in KDE's left-to-right order, bottom edges aligned,
// gapMm apart. Sizes come from the physical size each output reports.
function layout(screens, gapMm) {
    const sorted = Array.from(screens).sort((a, b) => a.virtualX - b.virtualX);
    const rects = {};
    let x = 0;
    let height = 0;
    for (const s of sorted) {
        const w = s.width / s.pixelDensity;
        const h = s.height / s.pixelDensity;
        rects[s.name] = { x: x, y: 0, w: w, h: h };
        x += w + gapMm;
        height = Math.max(height, h);
    }
    return { screens: rects, width: x - gapMm, height: height };
}

// Frame index into a clip t seconds after it started, following tk2d's wrap modes.
function frameAt(clip, t) {
    const n = clip.frames;
    const i = Math.max(0, Math.floor(t * clip.fps));
    switch (clip.wrapMode) {
    case 1: // loop section
        return i < clip.loopStart ? i : clip.loopStart + (i - clip.loopStart) % (n - clip.loopStart);
    case 2: // once
        return Math.min(i, n - 1);
    case 3: { // ping-pong
        if (n < 2) {
            return 0;
        }
        const p = i % (2 * n - 2);
        return p < n ? p : 2 * n - 2 - p;
    }
    case 6: // single
        return 0;
    default: // loop
        return i % n;
    }
}

function clipDuration(clip) {
    return clip.frames / clip.fps;
}

// Height of the ground (game units) at x, interpolated from the baked profile.
function groundAt(scene, x) {
    const g = scene.ground;
    const f = Math.max(0, Math.min(g.length - 1, x / scene.groundStep));
    const i = Math.floor(f);
    const a = g[i] ?? g[i + 1] ?? 0;
    const b = g[Math.min(i + 1, g.length - 1)] ?? a;
    return a + (b - a) * (f - i);
}

// Hornet paces the scene's walkable span. Sprites face left, so facingRight means
// drawn mirrored. Turn starts facing right and ends facing left.
function routine(clips, scene) {
    const left = scene.walk[0] + 1.5;
    const right = scene.walk[1] - 1.5;
    const walk = (right - left) / WALK_SPEED;
    const turn = clipDuration(clips["Turn"]);
    return [
        { clip: "Idle", duration: 4, x: left, facingRight: true },
        { clip: "Walk", duration: walk, x: left, vx: WALK_SPEED, facingRight: true },
        { clip: "Idle", duration: 3, x: right, facingRight: true },
        { clip: "Turn", duration: turn, x: right, facingRight: false },
        { clip: "Walk", duration: walk, x: right, vx: -WALK_SPEED, facingRight: false },
        { clip: "Idle", duration: 3, x: left, facingRight: false },
        { clip: "Turn", duration: turn, x: left, facingRight: true },
    ];
}

function clipsUsed(clips, scene) {
    return [...new Set(routine(clips, scene).map(s => s.clip))];
}

// Where Hornet is at time t (seconds since the epoch): clip, frame, and her
// pivot in scene units.
function hornetAt(clips, scene, t) {
    const steps = routine(clips, scene);
    const period = steps.reduce((sum, s) => sum + s.duration, 0);
    let local = t % period;
    for (const s of steps) {
        if (local < s.duration) {
            const x = s.x + (s.vx || 0) * local;
            return {
                clip: s.clip,
                frame: frameAt(clips[s.clip], local),
                x: x,
                y: groundAt(scene, x) + scene.heroFeet,
                facingRight: s.facingRight,
            };
        }
        local -= s.duration;
    }
    return null;
}

// ---------------------------------------------------------------- the aquarium (tools/world.py)

// The zone drawn on top at a point of the world (later zones cover earlier ones), or the
// nearest one when the point is in a bezel or the rock between zones.
function zoneAt(world, x, y) {
    let found = null;
    let nearest = null;
    let best = Infinity;
    for (const z of world.zones) {
        const dx = Math.max(z.left - x, 0, x - (z.left + z.width));
        const dy = Math.max(z.bottom - y, 0, y - (z.bottom + z.height));
        if (dx === 0 && dy === 0) {
            found = z;
        } else if (dx * dx + dy * dy < best) {
            best = dx * dx + dy * dy;
            nearest = z;
        }
    }
    return found ?? nearest;
}

// Until navigation lands: Hornet paces Mosshome's floor.
function worldRoutine(clips, world) {
    const home = world.zones.find(z => z.id === "mosshome") ?? world.zones[0];
    return {
        floor: home.floor,
        steps: routine(clips, { walk: [home.left + 3, home.left + home.width - 3] }),
    };
}

function clipsUsedInWorld(clips, world) {
    return [...new Set(worldRoutine(clips, world).steps.map(s => s.clip))];
}

function hornetInWorld(clips, world, t) {
    const r = worldRoutine(clips, world);
    const period = r.steps.reduce((sum, s) => sum + s.duration, 0);
    let local = t % period;
    for (const s of r.steps) {
        if (local < s.duration) {
            return {
                clip: s.clip,
                frame: frameAt(clips[s.clip], local),
                x: s.x + (s.vx || 0) * local,
                y: r.floor + world.heroFeet,
                facingRight: s.facingRight,
            };
        }
        local -= s.duration;
    }
    return null;
}

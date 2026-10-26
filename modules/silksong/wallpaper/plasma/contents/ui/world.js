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

// Where one of a layer's tiles (tools/world.py) goes on a screen (me, its place in the layout,
// and its size in pixels) and which of its texels it shows there, or null if none. WorldScene's
// layers draw the tiles so, and tools/derive.qml cuts each screen's own view of them from the very
// same texels (so after a change here, run tools/derive.py again: the views keep the places they
// were made with). Each screen only loads the tiles it shows, and of each only the part it shows.
function tilePlace(world, tile, rows, me, width, height) {
    const pxPerMm = width / me.w;
    const pxPerUnit = pxPerMm * world.unitMm;
    const toX = xMm => (xMm - me.x) * pxPerMm;
    const toY = yMm => height - (yMm - me.y) * pxPerMm;
    const unitsX = tile.x / world.pixelsPerUnit;
    const unitsW = tile.width / world.pixelsPerUnit;
    if ((unitsX + unitsW) * world.unitMm <= me.x || unitsX * world.unitMm >= me.x + me.w) {
        return null;
    }
    // Where the whole tile goes. Neighbouring tiles share their edge exactly: an overlap would
    // draw a translucent column twice (a line through the lake), a gap would show the black behind.
    const fx = Math.round(toX(unitsX * world.unitMm));
    const fw = Math.round(toX((unitsX + unitsW) * world.unitMm)) - fx;
    const fy = Math.floor(toY(world.height * world.unitMm));
    const fh = Math.ceil(world.height * pxPerUnit);
    // The texels Qt scales it to (fw wide, never wider than it is), the height rounded as Qt
    // rounds it.
    const srcH = Math.round(world.height * world.pixelsPerUnit);
    const texW = Math.min(fw, tile.width);
    const texH = fw < tile.width ? Math.round(srcH * (fw / tile.width)) : srcH;
    const sx = fw / texW;
    const sy = fh / texH;
    // Of those, only the ones on the screen (one less tall than the world shows only part of it)
    // and in the rows that have anything in them (rows, in the tile's pixels, where known), and
    // one more on each side, which the smoothing reads. Qt cuts them out of the scaled image
    // (clip): they're the very texels the whole tile would show there.
    const top = rows ? rows[0] : 0;
    const bottom = rows ? rows[1] : srcH;
    const tx0 = Math.max(0, Math.floor(-fx / sx) - 1);
    const tx1 = Math.min(texW, Math.ceil((width - fx) / sx) + 1);
    const ty0 = Math.max(0, Math.floor(-fy / sy) - 1, Math.floor(top * texH / srcH) - 1);
    const ty1 = Math.min(texH, Math.ceil((height - fy) / sy) + 1, Math.ceil(bottom * texH / srcH) + 1);
    if (tx1 <= tx0 || ty1 <= ty0) {
        return null;
    }
    return { fx: fx, fy: fy, fw: fw, sx: sx, sy: sy, clip: [tx0, ty0, tx1 - tx0, ty1 - ty0],
             x: fx + tx0 * sx, y: fy + ty0 * sy, width: (tx1 - tx0) * sx, height: (ty1 - ty0) * sy };
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

// How much each zone holds a point, for what blends between zones (Hornet's colours and her
// light): each zone's own share rises over `feather` units on each side of its edge, and later
// zones cover earlier ones (as they're drawn), so crossing from one zone to the next is a
// gradual change, as the game's SceneColorManager lerps its colours inside a scene. Sorted, the
// largest first; the shares add up to 1. The same array again for the same point, so that what's
// bound to it isn't worked out again: the last answer is kept on the world it was asked for (each
// screen has its own copy), not in a WeakMap, which crashed the QML engine's garbage collector
// (Qt 6.11).
function zoneWeights(world, x, y, feather) {
    const m = world.lastZoneWeights;
    if (m && m.zones === world.zones && m.x === x && m.y === y && m.feather === feather) {
        return m.out;
    }
    const out = zoneWeightsOf(world, x, y, feather);
    world.lastZoneWeights = { zones: world.zones, x: x, y: y, feather: feather, out: out };
    return out;
}

function zoneWeightsOf(world, x, y, feather) {
    const smooth = t => {
        const u = Math.min(1, Math.max(0, t));
        return u * u * (3 - 2 * u);
    };
    const out = [];
    let left = 1;
    for (let i = world.zones.length - 1; i >= 0; i--) {
        const z = world.zones[i];
        const inside = Math.min(x - z.left, z.left + z.width - x, y - z.bottom, z.bottom + z.height - y);
        const cover = smooth((inside + feather) / (2 * feather));
        out.push({ zone: z, weight: cover * left });
        left *= 1 - cover;
    }
    const total = out.reduce((a, o) => a + o.weight, 0) || 1;
    return out.filter(o => o.weight > 0.002).map(o => ({ zone: o.zone, weight: o.weight / total }))
        .sort((a, b) => b.weight - a.weight);
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

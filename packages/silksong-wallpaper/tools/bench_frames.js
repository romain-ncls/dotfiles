/*
 * tools/bench.qml --trace-frames: what a screen shows at each tick of its clock, then over the
 * run, for each thing on it that changes by frames (the 15 fps grass, the Bell Beast, the floor
 * bells, Hornet, the small life), how often it changed, against how often it should have, and
 * whether any of its frames was skipped, held for longer than it lasts or drawn late. What it
 * should have shown is worked out from the scene's own time, every millisecond between ticks, and
 * where it changed, to the microsecond. The particles move on every tick: their rate is the
 * clock's while the screen shows them.
 */
.pragma library

// A 15 fps plant's frame as the GPU snaps it (shaders/sway.vert, in single precision), from the
// time a tick gives the shaders; and the one the exact time falls in.
function grassShown(ambientTime) {
    return Math.floor(Math.fround(Math.fround(Math.fround(ambientTime) * 15) + 0.5));
}
function grassAt(t) {
    return Math.floor((t % 3600) * 15 + 0.5);
}

function cellName(clips, clip, frame) {
    const c = clips[clip];
    return c ? clip + " " + c.sequence[Math.min(frame, c.frames - 1)] : "";
}

function bellFrame(bell, t) {
    return t < bell.endsAt ? 1 + Math.floor((Math.max(t, bell.startedAt) - bell.startedAt) * bell.fps) % bell.frames : 0;
}

// A bell between two ticks: its shake as the first saw it, until the second starts another. One
// that ends with the bell still stirred starts again on the tick it ends on (or with what's drawn
// within 12 ms of it): it goes on jingling, rather than coming to rest for that long.
function bellAt(before, after, t) {
    const again = after.startedAt !== before.startedAt && after.startedAt - before.endsAt < 0.013;
    return bellFrame(t >= after.startedAt || (again && t >= before.endsAt) ? after : before, t);
}

// What the scene shows now: called once a tick has gone through, everything bound to its time up
// to date. Hornet only where she's drawn into the screen; the bells' shakes with their timing.
function sample(scene, bells) {
    const seen = scene.hornetSeen ?? scene.hornetHere;
    const h = scene.shownHornet;
    const b = scene.beastPose;
    return {
        t: scene.time,
        grass: grassShown(scene.ambientTime),
        beast: b ? cellName(scene.clips, b.clip, b.frame) : null,
        hornet: seen && h ? cellName(scene.clips, h.clip, h.frame) : null,
        critters: scene.critterPoses.map(p => p ? cellName(scene.clips, p.clip, p.frame) : null),
        bells: bells.map(bell => ({ frame: bell.frame, startedAt: bell.startedAt, endsAt: bell.endsAt, fps: bell.a.fps,
                                    frames: bell.a.frames })),
        particles: scene.showsParticles,
    };
}

function spread(values) {
    if (!values.length) {
        return null;
    }
    const v = values.slice().sort((a, b) => a - b);
    const at = q => Math.round(v[Math.min(v.length - 1, Math.floor(v.length * q))] * 100) / 100;
    return { median: at(0.5), p95: at(0.95), max: Math.round(v[v.length - 1] * 100) / 100 };
}

// One thing's frames over the run: shown(sample) is what a tick showed (null where it isn't
// drawn), truth(t, before, after) what it should show at t between two ticks. Its rate is
// counted over the time it was drawn, or busy (a bell, while it jingles).
function follow(samples, shown, truth, busy) {
    const out = { seconds: 0, changes: 0, due: 0, skipped: 0, doubled: 0, stale: 0, late: [] };
    let last = null; // the last change shown: when, and when it was due
    for (let i = 1; i < samples.length; i++) {
        const p = samples[i - 1];
        const c = samples[i];
        const a = shown(p);
        const z = shown(c);
        if (a === null || z === null || c.t - p.t <= 0 || c.t - p.t > 1) {
            last = null;
            continue;
        }
        if (!busy || busy(a, z)) {
            out.seconds += c.t - p.t;
        }
        if (truth(c.t, p, c) !== z) {
            out.stale++; // drawn as it was before, or ahead of itself
        }
        // Every millisecond in between: how many times it should have changed, and the last.
        let value = truth(p.t, p, c);
        let runs = 0;
        let from = p.t;
        let until = p.t;
        for (let k = 1; ; k++) {
            const u = Math.min(p.t + k * 0.001, c.t);
            const v = truth(u, p, c);
            if (v !== value) {
                runs++;
                value = v;
                from = Math.min(c.t, p.t + (k - 1) * 0.001);
                until = u;
            }
            if (u >= c.t) {
                break;
            }
        }
        out.due += runs;
        out.skipped += Math.max(0, runs - 1);
        if (runs === 0) {
            continue;
        }
        if (z === a) {
            last = null; // and back again, between two ticks
            continue;
        }
        out.changes++;
        // Where it changed, to the microsecond.
        const before = truth(from, p, c);
        while (until - from > 1e-6) {
            const mid = (from + until) / 2;
            if (truth(mid, p, c) === before) {
                from = mid;
            } else {
                until = mid;
            }
        }
        out.late.push((c.t - until) * 1000);
        // Held longer than it lasts: shown for half a frame or more past its time.
        if (last !== null && runs === 1 && (c.t - last.shown) - (until - last.due) > (until - last.due) / 2) {
            out.doubled++;
        }
        last = runs === 1 ? { shown: c.t, due: until } : null;
    }
    return out;
}

function sum(results) {
    const out = { seconds: 0, changes: 0, due: 0, skipped: 0, doubled: 0, stale: 0, late: [] };
    for (const r of results) {
        for (const k of ["seconds", "changes", "due", "skipped", "doubled", "stale"]) {
            out[k] += r[k];
        }
        out.late = out.late.concat(r.late);
    }
    return out;
}

// Its changes a second (each, for the bells and the small life), shown and due.
function report(r) {
    if (r.seconds <= 0) {
        return null;
    }
    const s = r.seconds;
    return { per_s: Math.round(r.changes / s * 10) / 10, due_per_s: Math.round(r.due / s * 10) / 10, skipped: r.skipped,
             doubled: r.doubled, stale: r.stale, late_ms: spread(r.late) };
}

// The run's table, from the samples of one screen (scene: its WorldScene, Life: life.js).
function analyse(samples, scene, Life) {
    const world = scene.world;
    const clips = scene.clips;
    const which = scene.crittersHere;
    let critterT = NaN;
    let critters = [];
    const crittersAt = t => {
        if (t !== critterT) {
            critterT = t;
            critters = Life.critterPosesAt(world, clips, t, which);
        }
        return critters;
    };
    const hornetAt = t => {
        const segs = Life.daySegments(world, clips, t);
        const p = Life.pose(world, clips, segs[Life.segmentIndex(segs, t)], t);
        return cellName(clips, p.clip, p.frame);
    };
    const beastAt = t => {
        const b = Life.beastAt(world, clips, t);
        return b ? cellName(clips, b.clip, b.frame) : null;
    };
    // Its clock's ticks a second, over the run's time on it (the clock may have been set back).
    let seconds = 0;
    let ticks = 0;
    for (let i = 1; i < samples.length; i++) {
        if (samples[i].t > samples[i - 1].t && samples[i].t - samples[i - 1].t < 1) {
            seconds += samples[i].t - samples[i - 1].t;
            ticks++;
        }
    }
    const out = { ticks_per_s: seconds > 0 ? Math.round(ticks / seconds * 10) / 10 : 0 };
    if (scene.swayHere.some(it => it.fps === 15 && it.amount !== 0)) {
        out.grass = report(follow(samples, s => s.grass, t => grassAt(t)));
    }
    if (scene.showsBeast) {
        out.beast = report(follow(samples, s => s.beast, t => beastAt(t)));
    }
    const bells = (samples[0]?.bells ?? []).map((_, i) => follow(samples,
        s => s.bells[i].frame, (t, p, c) => bellAt(p.bells[i], c.bells[i], t), (a, z) => a > 0 || z > 0));
    if (bells.length) {
        out.bells = report(sum(bells));
    }
    out.hornet = report(follow(samples, s => s.hornet, t => hornetAt(t)));
    const flies = which.map((_, i) => follow(samples, s => s.critters[i], t => {
        const p = crittersAt(t)[i];
        return p ? cellName(clips, p.clip, p.frame) : null;
    }));
    if (flies.length) {
        out.critters = report(sum(flies));
    }
    let shown = 0;
    let moved = 0;
    for (let i = 1; i < samples.length; i++) {
        if (samples[i].particles && samples[i].t > samples[i - 1].t && samples[i].t - samples[i - 1].t < 1) {
            shown += samples[i].t - samples[i - 1].t;
            moved++;
        }
    }
    if (shown > 0) {
        out.particles = { per_s: Math.round(moved / shown * 10) / 10 };
    }
    return out;
}

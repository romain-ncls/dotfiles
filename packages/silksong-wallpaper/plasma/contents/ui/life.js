/*
 * Hornet's day in the aquarium.
 *
 * Every copy of the wallpaper (one per screen, plus the lock screen) builds the
 * same timeline for the day from the date: a seeded simulation that starts at
 * 04:00 with Hornet asleep and picks what she does next from her needs and the
 * hour. Each copy then shows the moment it's at, so they agree without talking.
 *
 * world.nav (tools/nav.py) has the surfaces she stands on, the links between
 * them (walk, drop, jump, jump2, climb, harpoon, bounce) and the places she
 * spends time.
 */
.pragma library

const WALK_SPEED = 5;     // HeroController.WALK_SPEED
const RUN_SPEED = 8.25;   // HeroController.RUN_SPEED
const RUN_FROM = 14;      // run when the walk is longer than this
const GRAVITY = 60;       // Physics2D gravity
const MAX_FALL = 30;
const JUMP_SPEED = 18.6;  // held for JUMP_HOLD, then she falls back under gravity
const JUMP_HOLD = 0.16;
const DOUBLE_JUMP_SPEED = 15;
const DOUBLE_JUMP_HOLD = 0.12;
const POD_SPEED = 26;     // what a struck pod throws her up at
const NEEDLE_SPEED = 70;  // her needle flying to a ring
const HARPOON_SPEED = 32; // and her, pulled after it
const HANG = 1.1;         // her pivot below the ring she hangs from
const TURN = "Turn";      // starts facing right, ends facing left (sprites face left)

// ------------------------------------------------------------------ random

function rng(seed) {
    let a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function between(r, lo, hi) {
    return lo + (hi - lo) * r();
}

// ------------------------------------------------------------------ clips

function clipLength(clips, name) {
    const c = clips[name];
    return c ? c.frames / c.fps : 0;
}

function frameAt(clip, t) {
    const n = clip.frames;
    const i = Math.max(0, Math.floor(t * clip.fps));
    switch (clip.wrapMode) {
    case 1:
        return i < clip.loopStart ? i : clip.loopStart + (i - clip.loopStart) % (n - clip.loopStart);
    case 2:
        return Math.min(i, n - 1);
    case 3: {
        if (n < 2) {
            return 0;
        }
        const p = i % (2 * n - 2);
        return p < n ? p : 2 * n - 2 - p;
    }
    case 6:
        return 0;
    default:
        return i % n;
    }
}

// ------------------------------------------------------------------ jumping

function fallDistance(t) {
    const tc = MAX_FALL / GRAVITY;
    return t < tc ? 0.5 * GRAVITY * t * t : 0.5 * GRAVITY * tc * tc + MAX_FALL * (t - tc);
}

function fallTime(h) {
    const tc = MAX_FALL / GRAVITY;
    const hc = 0.5 * GRAVITY * tc * tc;
    return h <= 0 ? 0 : h <= hc ? Math.sqrt(2 * h / GRAVITY) : tc + (h - hc) / MAX_FALL;
}

// A jump the way the game makes one: rising at speed v while the button is held (up to
// `hold`), then slowing under gravity; a double jump starts again at the top of the first;
// then the fall, down to y1. The jump is held only as long as it needs to clear y1.
function jumpPlan(y0, y1, double, v, maxHold) {
    v = v || JUMP_SPEED;
    maxHold = maxHold === undefined ? JUMP_HOLD : maxHold;
    const free = v * v / (2 * GRAVITY);
    const hold1 = double ? maxHold : Math.min(maxHold, Math.max(0, (y1 + 0.8 - y0 - free) / v));
    const apex1 = y0 + v * hold1 + free;
    const tA = hold1 + v / GRAVITY;
    const p = { v: v, hold1: hold1, apex1: apex1, tA: tA, v2: 0, hold2: 0, apex: apex1, tB: tA };
    if (double) {
        const need = Math.max(0.6, y1 + 0.8 - apex1);
        let v2 = DOUBLE_JUMP_SPEED;
        const free2 = v2 * v2 / (2 * GRAVITY);
        if (need < free2) {
            v2 = Math.sqrt(2 * GRAVITY * need);
        } else {
            p.hold2 = Math.min(DOUBLE_JUMP_HOLD, (need - free2) / v2);
        }
        p.v2 = v2;
        p.apex = apex1 + v2 * p.hold2 + v2 * v2 / (2 * GRAVITY);
        p.tB = tA + p.hold2 + v2 / GRAVITY;
    }
    p.T = p.tB + fallTime(p.apex - y1);
    return p;
}

function jumpY(p, y0, t) {
    if (t < p.hold1) {
        return y0 + p.v * t;
    }
    if (t < p.tA) {
        const u = t - p.hold1;
        return y0 + p.v * p.hold1 + p.v * u - 0.5 * GRAVITY * u * u;
    }
    if (t < p.tB) {
        const u = t - p.tA;
        if (u < p.hold2) {
            return p.apex1 + p.v2 * u;
        }
        const w = u - p.hold2;
        return p.apex1 + p.v2 * p.hold2 + p.v2 * w - 0.5 * GRAVITY * w * w;
    }
    return p.apex - fallDistance(t - p.tB);
}

// ------------------------------------------------------------------ the map

function height(s, x, step) {
    const f = Math.min(Math.max((x - s.x0) / step, 0), s.y.length - 1);
    const i = Math.floor(f);
    const j = Math.min(i + 1, s.y.length - 1);
    return s.y[i] + (s.y[j] - s.y[i]) * (f - i);
}

// Cheapest route from (surface a, x) to (surface b, x): a list of link objects, in order.
function route(nav, a, xa, b, xb) {
    if (a === b) {
        return [];
    }
    // Nodes: the start, the goal, and every link end. Walking along a surface joins them.
    const nodes = [{ s: a, x: xa }, { s: b, x: xb }];
    const fromNode = [];
    const toNode = [];
    for (const l of nav.links) {
        fromNode.push(nodes.length);
        nodes.push({ s: l.from, x: l.x0 });
        toNode.push(nodes.length);
        nodes.push({ s: l.to, x: l.x1 });
    }
    const dist = nodes.map(() => Infinity);
    const prev = nodes.map(() => null); // [node, link index or -1 for a walk]
    const done = nodes.map(() => false);
    dist[0] = 0;
    for (;;) {
        let u = -1;
        for (let i = 0; i < nodes.length; i++) {
            if (!done[i] && dist[i] < Infinity && (u < 0 || dist[i] < dist[u])) {
                u = i;
            }
        }
        if (u < 0 || u === 1) {
            break;
        }
        done[u] = true;
        for (let v = 0; v < nodes.length; v++) {
            if (!done[v] && nodes[v].s === nodes[u].s) {
                const d = dist[u] + Math.abs(nodes[v].x - nodes[u].x) / RUN_SPEED;
                if (d < dist[v]) {
                    dist[v] = d;
                    prev[v] = [u, -1];
                }
            }
        }
        for (let k = 0; k < nav.links.length; k++) {
            if (fromNode[k] === u) {
                const v = toNode[k];
                const d = dist[u] + nav.links[k].time + 0.3;
                if (d < dist[v]) {
                    dist[v] = d;
                    prev[v] = [u, k];
                }
            }
        }
    }
    if (dist[1] === Infinity) {
        return null;
    }
    const used = [];
    for (let v = 1; prev[v]; v = prev[v][0]) {
        if (prev[v][1] >= 0) {
            used.unshift(nav.links[prev[v][1]]);
        }
    }
    return used;
}

// ------------------------------------------------------------------ building the day

// Segments: { t0, t1, kind, clip, ... }. Poses are computed from them when sampling.
function Planner(world, clips, seed) {
    this.world = world;
    this.nav = world.nav;
    this.clips = clips;
    this.r = rng(seed);
    this.segments = [];
    this.log = []; // what she did where: { id, t0, t1 }
    this.routes = {};
    this.t = 0;
    this.surface = 0;
    this.x = 0;
    this.facingRight = true;
}

Planner.prototype.route = function (surface, x) {
    const key = this.surface + ":" + this.x.toFixed(2) + ">" + surface + ":" + x.toFixed(2);
    if (!(key in this.routes)) {
        this.routes[key] = route(this.nav, this.surface, this.x, surface, x);
    }
    return this.routes[key];
};

Planner.prototype.push = function (seg, duration) {
    seg.t0 = this.t;
    seg.t1 = this.t + duration;
    this.segments.push(seg);
    this.t = seg.t1;
    return seg;
};

Planner.prototype.y = function (surface, x) {
    return height(this.nav.surfaces[surface], x, this.nav.step) + this.world.heroFeet;
};

Planner.prototype.face = function (right) {
    if (right === this.facingRight) {
        return;
    }
    // Turn is drawn going from right-facing to left-facing; mirrored, the other way.
    this.push({ kind: "clip", clip: TURN, x: this.x, y: this.y(this.surface, this.x), facingRight: right },
        clipLength(this.clips, TURN));
    this.facingRight = right;
};

Planner.prototype.hold = function (clip, duration, extra) {
    const seg = { kind: "clip", clip: clip, x: this.x, y: this.y(this.surface, this.x), facingRight: this.facingRight };
    if (extra) {
        for (const k in extra) {
            seg[k] = extra[k];
        }
    }
    return this.push(seg, duration === undefined ? clipLength(this.clips, clip) : duration);
};

Planner.prototype.walkTo = function (x) {
    const dx = x - this.x;
    if (Math.abs(dx) < 0.05) {
        return;
    }
    this.face(dx > 0);
    const run = Math.abs(dx) > RUN_FROM;
    const speed = run ? RUN_SPEED : WALK_SPEED;
    this.push({ kind: "walk", clip: run ? "Run" : "Walk", surface: this.surface, x0: this.x, x1: x, facingRight: dx > 0 },
        Math.abs(dx) / speed);
    this.x = x;
    if (run) {
        this.hold("Run To Idle");
    }
};

// A ballistic move from (x0, y0) to (x1, y1), y being her pivot; `clips` names what she
// plays rising, falling, and at the top of a double jump.
Planner.prototype.leap = function (x0, y0, x1, y1, opts) {
    opts = opts || {};
    let p = jumpPlan(y0, y1, !!opts.double, opts.speed, opts.hold);
    if (p.apex < y1 + 0.2 && !opts.double) {
        // Too high for one jump: her second, at the top of the first.
        opts = Object.assign({}, opts, { double: true });
        p = jumpPlan(y0, y1, true, opts.speed, opts.hold);
    }
    return this.push({ kind: "jump", plan: p, x0: x0, y0: y0, x1: x1, y1: y1, facingRight: this.facingRight,
                       clip: opts.rise || "Airborne", fall: opts.fall || "Fall", second: opts.double ? "Double Jump" : "",
                       antic: opts.antic || "" }, p.T);
};

// On the ground at the end of a link: where she is is updated before anything else is drawn
// there (a pose held at the old spot would show her back where she took off for a moment).
Planner.prototype.arrive = function (link, clip, duration) {
    this.surface = link.to;
    this.x = link.x1;
    this.hold(clip, duration);
};

// Turning in the air: no Turn animation (it stands on the ground), she just faces the other way.
Planner.prototype.faceInAir = function (right) {
    this.facingRight = right;
};

Planner.prototype.follow = function (link) {
    this.walkTo(link.x0);
    const right = link.x1 > link.x0 ? true : link.x1 < link.x0 ? false : this.facingRight;
    const feet = this.world.heroFeet;
    const y0 = link.y0 + feet;
    const y1 = link.y1 + feet;
    if (link.kind === "walk") {
        this.face(right);
        this.push({ kind: "line", clip: "Walk", x0: link.x0, y0: y0, x1: link.x1, y1: y1, facingRight: right },
            Math.max(0.15, Math.abs(link.x1 - link.x0) / WALK_SPEED));
    } else if (link.kind === "drop") {
        this.face(right);
        this.push({ kind: "fall", clip: "Fall", x0: link.x0, y0: y0, x1: link.x1, y1: y1, facingRight: right },
            Math.max(0.2, fallTime(y0 - y1)));
        this.arrive(link, "Land", 0.25);
    } else if (link.kind === "jump" || link.kind === "jump2") {
        this.face(right);
        this.leap(link.x0, y0, link.x1, y1, { double: link.kind === "jump2" });
        this.arrive(link, "Land", 0.25);
    } else if (link.kind === "climb") {
        this.climb(link, y0, y1);
    } else if (link.kind === "harpoon") {
        // The Clawline: her needle thrown to the ring on its silk, then she's pulled after it,
        // catches it and lets go above where she lands.
        const rx = link.ring[0];
        const ry = link.ring[1];
        this.face(rx > link.x0 ? true : rx < link.x0 ? false : right);
        const hand = [link.x0 + (this.facingRight ? 0.5 : -0.5), y0 + 0.4];
        this.hold("Harpoon Antic");
        const fly = Math.hypot(rx - hand[0], ry - hand[1]) / NEEDLE_SPEED;
        this.hold("Harpoon Throw", Math.max(clipLength(this.clips, "Harpoon Throw"), fly),
            { needle: { from: hand, to: [rx, ry] } });
        const hx = rx;
        const hy = ry - HANG;
        this.push({ kind: "line", clip: "Harpoon Dash", x0: link.x0, y0: y0, x1: hx, y1: hy, facingRight: this.facingRight,
                    thread: [rx, ry], tilt: true },
            Math.hypot(hx - link.x0, hy - y0) / HARPOON_SPEED);
        // The catch, at the ring: she has her needle back in hand (the sprite holds it).
        this.push({ kind: "clip", clip: "Harpoon Catch", x: hx, y: hy, facingRight: this.facingRight },
            clipLength(this.clips, "Harpoon Catch") + 0.1);
        // Then she jumps off the ring towards where she's going.
        this.faceInAir(link.x1 > hx ? true : link.x1 < hx ? false : this.facingRight);
        this.leap(hx, hy, link.x1, y1);
        this.arrive(link, "Land", 0.25);
    } else if (link.kind === "bounce") {
        // Up and down onto the pod with her needle pointing down; it throws her high.
        const px = link.pod[0];
        const py = link.pod[1] + feet - 0.4;
        this.face(px >= link.x0);
        this.leap(link.x0, y0, px, py, { antic: "DownSpike Antic", fall: "DownSpike" });
        this.faceInAir(link.x1 >= px);
        this.leap(px, py, link.x1, y1, { speed: POD_SPEED, hold: 0, rise: "DownSpikeBounce 1" });
        this.arrive(link, "Land", 0.25);
    }
    this.surface = link.to;
    this.x = link.x1;
};

// Up a wall the way she does it in the game: a jump against it, a catch, walljumps out and
// back in (each one higher), then the last stretch scrambling up and over the edge.
Planner.prototype.climb = function (link, y0, y1) {
    const dir = link.x1 >= link.x0 ? 1 : -1; // the wall's side
    // Facing the wall (the climbing sprites have it on their left; mirrored, on the right).
    this.face(dir > 0);
    const px = link.x0 - dir * 0.24; // her pivot against the wall: hands and feet on it
    const top = y1 - 0.5;            // where the scramble reaches the edge
    let y = Math.min(y0 + 4.3, top); // where she catches the wall from her jump
    this.leap(link.x0, y0, px, y);
    const cling = () => {
        this.push({ kind: "line", clip: "Wall Cling", x0: px, y0: y, x1: px, y1: y - 0.15, facingRight: this.facingRight },
            0.3);
        y -= 0.15;
    };
    cling();
    while (top - y > 1.6) {
        const gain = Math.min(2.6, top - y - 1.0);
        this.push({ kind: "wallhop", clip: "Walljump", second: "Airborne", x0: px, y0: y, x1: px, y1: y + gain,
                    out: -dir * 1.3, lift: 0.9, facingRight: this.facingRight }, 0.6);
        y += gain;
        cling();
    }
    this.push({ kind: "line", clip: "Wall Scramble", x0: px, y0: y, x1: px, y1: top, facingRight: this.facingRight },
        Math.max(0.3, clipLength(this.clips, "Wall Scramble") * (top - y) / 1.6));
    this.push({ kind: "line", clip: "Wall Scramble Mantle", x0: px, y0: top, x1: px + dir * 0.5, y1: y1 + 0.2,
                facingRight: this.facingRight }, 0.12);
    this.push({ kind: "line", clip: "Mantle Land", x0: px + dir * 0.5, y0: y1 + 0.2, x1: link.x1, y1: y1,
                facingRight: this.facingRight }, 0.14);
    this.arrive(link, "Land", 0.2);
};

Planner.prototype.goTo = function (surface, x) {
    const path = this.route(surface, x);
    if (path === null) {
        return false;
    }
    for (const link of path) {
        this.follow(link);
    }
    this.walkTo(x);
    return true;
};

// What Hornet does at each kind of place: a list of steps. Short, so she keeps moving.
Planner.prototype.activity = function (poi) {
    const r = this.r;
    if (poi.face !== undefined) {
        this.face(poi.face > 0);
    }
    switch (poi.activity) {
    case "lookup":
        this.hold("LookUp");
        this.hold("LookingUp", between(r, 4, 12));
        this.hold("LookUpEnd");
        break;
    case "map":
        this.hold("Map Open");
        this.hold("Map Idle", between(r, 8, 20));
        this.hold("Map Away");
        break;
    case "needolin":
        this.hold("Needolin Start");
        this.hold("Needolin Play", between(r, 15, 35));
        this.hold("Needolin End");
        break;
    case "needolin_sit":
        this.hold("NeedolinSit Start");
        this.hold("NeedolinSit Play", between(r, 20, 45));
        this.hold("NeedolinSit End");
        break;
    case "kneel":
        this.hold("Abyss Kneel");
        this.hold("Abyss Kneel Idle", between(r, 8, 20));
        this.hold("Abyss Kneel to Stand");
        break;
    case "desk": {
        const at = { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror };
        this.hold("Hornet Desk Sit", undefined, at);
        this.hold("Hornet Desk Sit", between(r, 20, 60), { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror, frame: -1 });
        this.hold("Hornet Desk Stand", undefined, at);
        break;
    }
    case "bench": {
        // Sat on the bench a while: looking around, now and then her map.
        const seat = { y: this.y(this.surface, this.x) + (poi.seat || 0) };
        this.hold("Sit", undefined, seat);
        const end = this.t + between(r, 20, 50);
        while (this.t < end) {
            this.hold("Sit Idle", between(r, 4, 10), seat);
            const pick = r();
            if (pick < 0.3) {
                this.hold("SitLook " + (1 + Math.floor(r() * 4)), undefined, seat);
            } else if (pick < 0.45) {
                this.hold("Sit Map Open", undefined, seat);
                this.hold("Sit Map Open", between(r, 6, 14), { y: seat.y, frame: -1 });
                this.hold("Sit Map Close", undefined, seat);
            }
        }
        this.hold("Sit", undefined, { y: seat.y, reverse: true });
        break;
    }
    case "visit":
    case "listen":
    default: {
        // Stand around, now and then looking up.
        const end = this.t + between(r, 10, 25);
        while (this.t < end) {
            this.hold("Idle", Math.min(between(r, 4, 10), end - this.t));
            if (this.t < end && r() < 0.4) {
                this.hold("LookUp");
                this.hold("LookingUp", between(r, 2, 5));
                this.hold("LookUpEnd");
            }
        }
    }
    }
};

// Bed: lie down, maybe read the map a while, sleep until `until`, sit up.
Planner.prototype.sleep = function (poi, until, readMap) {
    const at = { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror };
    const lying = { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror, frame: -1 };
    this.hold("Hornet Lay Down", undefined, at);
    if (readMap) {
        this.hold("Hornet Lay Map Open", undefined, at);
        this.hold("Hornet Lay Map Open", between(this.r, 120, 600), lying);
        this.hold("Hornet Lay Map Close", undefined, at);
    }
    this.hold("Hornet Lay Down", Math.max(1, until - this.t), lying);
    this.hold("Hornet Sit Up", undefined, at);
};

function localSeconds(day0, hours) {
    return day0 + hours * 3600;
}

// The whole day from 04:00 (local) to 04:00 the next day.
function planDay(world, clips, day0, dateKey) {
    const p = new Planner(world, clips, dateKey);
    const pois = world.nav.pois;
    const bed = pois.find(q => q.activity === "sleep");
    const r = p.r;
    const wake = localSeconds(day0, 3 + between(r, 0, 0.75));      // 07:00-07:45
    const bedtime = localSeconds(day0, 19 + between(r, 0, 0.75));  // 23:00-23:45
    const nextWake = localSeconds(day0, 24 + 3 + between(rng(dateKey + 1), 0, 0.75));

    p.t = day0;
    p.surface = bed.surface;
    p.x = bed.x;
    p.facingRight = !bed.mirror;
    p.sleep(bed, wake, false);

    // Spots she can wander to: along every surface she can reach, away from its ends.
    const spots = [];
    world.nav.surfaces.forEach((sf, i) => {
        for (let x = sf.x0 + 1; x <= sf.x1 - 1; x += 4) {
            spots.push({ surface: i, x: x });
        }
    });

    // Needs grow with time and are met by activities.
    const needs = { rest: 0.3, music: 0.5, curiosity: 0.8 };
    const meets = { desk: "rest", sleep: "rest", bench: "rest", listen: "music", needolin: "music", needolin_sit: "music",
                    lookup: "curiosity", map: "curiosity", visit: "curiosity", kneel: "rest" };
    const recent = [bed.id];
    let stuck = 0;
    // One thing she does: a wander, or an activity somewhere.
    const step = () => {
        const hour = ((p.t - day0) / 3600 + 4) % 24;
        if (r() < 0.35 && spots.length) {
            // Wandering: somewhere else for a moment, a look around, and on.
            const spot = spots[Math.floor(r() * spots.length)];
            if (p.goTo(spot.surface, spot.x)) {
                const look = r();
                if (look < 0.3) {
                    p.hold("LookUp");
                    p.hold("LookingUp", between(r, 2, 4));
                    p.hold("LookUpEnd");
                } else if (look < 0.55) {
                    p.face(!p.facingRight);
                    p.hold("Idle", between(r, 1, 3));
                } else {
                    p.hold("Idle", between(r, 2, 5));
                }
                return;
            }
        }
        const options = pois.filter(q => q.activity !== "sleep" && recent.indexOf(q.id) < 0);
        const weights = options.map(q => {
            let w = 0.2 + needs[meets[q.activity]];
            // Close places are a little more tempting, but she likes to roam.
            const path = p.route(q.surface, q.x);
            const trip = path === null ? 999 : path.reduce((sum, l) => sum + l.time, 0)
                + Math.abs((path.length ? path[path.length - 1].x1 : p.x) - q.x) / RUN_SPEED;
            w /= 1 + trip / 150;
            if (q.activity === "desk" && hour >= 9 && hour <= 17) {
                w += 0.1; // work hours at the desk
            }
            if ((q.activity === "needolin" || q.activity === "needolin_sit") && hour >= 18) {
                w += 0.3; // evening music
            }
            return w * between(r, 0.5, 1.5);
        });
        let pick = 0;
        for (let i = 1; i < options.length; i++) {
            if (weights[i] > weights[pick]) {
                pick = i;
            }
        }
        const poi = options[pick];
        const before = p.t;
        if (!p.goTo(poi.surface, poi.x)) {
            recent.push(poi.id);
            if (++stuck > options.length) {
                p.hold("Idle", 60); // nowhere to go from here: wait a minute
                stuck = 0;
            }
            return;
        }
        stuck = 0;
        const start = p.t;
        p.activity(poi);
        p.log.push({ id: poi.id, t0: start, t1: p.t });
        for (const k in needs) {
            needs[k] = Math.min(2, needs[k] + (p.t - before) / 3600 * { rest: 0.6, music: 0.9, curiosity: 1.5 }[k] * 4);
        }
        needs[meets[poi.activity]] = 0;
        recent.push(poi.id);
        while (recent.length > 3) {
            recent.shift(); // she doesn't go back to the last few places straight away
        }
        if (r() < 0.3) {
            p.hold("Idle", between(r, 1, 4));
        }
    };
    // The Bell Beast sings the hours from 9 to 21 (planBeast). Whatever would run across one is
    // undone: she waits about for it instead, and listens while it sings, turned towards it.
    const songs = [];
    for (let h = 9; h <= 21; h++) {
        songs.push(day0 + (h - 4) * 3600);
    }
    const towards = world.beast ? world.beast.x : null;
    const listen = at => {
        while (at - p.t > 8) {
            p.hold("Idle", Math.min(at - 4 - p.t, between(r, 3, 8)));
            if (r() < 0.4) {
                p.face(!p.facingRight);
            }
        }
        if (towards !== null) {
            p.face(towards > p.x);
        }
        if (at > p.t) {
            p.hold("Idle", at - p.t);
        }
        p.hold("LookUp");
        p.hold("LookingUp", between(r, 6, 9));
        p.hold("LookUpEnd");
    };
    while (p.t < bedtime - 600) {
        const mark = { segments: p.segments.length, log: p.log.length, t: p.t, x: p.x, surface: p.surface,
                       facingRight: p.facingRight, needs: Object.assign({}, needs), recent: recent.slice(), stuck: stuck };
        step();
        const song = songs.find(at => at > mark.t && at <= p.t + 2);
        if (song !== undefined) {
            p.segments.length = mark.segments;
            p.log.length = mark.log;
            p.t = mark.t;
            p.x = mark.x;
            p.surface = mark.surface;
            p.facingRight = mark.facingRight;
            Object.assign(needs, mark.needs);
            recent.length = 0;
            recent.push(...mark.recent);
            stuck = mark.stuck;
            listen(song);
        }
    }
    p.goTo(bed.surface, bed.x);
    p.face(!bed.mirror);
    p.sleep(bed, nextWake, r() < 0.6);
    return { segments: p.segments, log: p.log, wake: wake, bedtime: bedtime };
}

// The day's plans (Hornet's and the Bell Beast's), made once per day and per world build.
let cache = { key: "", segments: [], beast: [] };

// ------------------------------------------------------------------ the Bell Beast

// The Bell Beast's day in its station, from Hornet's: it wakes a little after her, sings the
// hours, looks about, turns to her and shakes happily when she visits, and lies down to sleep
// in the evening. Clips are its own ("Bell Beast ..."); it doesn't move from its spot.
function planBeast(world, clips, day0, dateKey, hornet) {
    const r = rng(dateKey * 7 + 3);
    const segs = [];
    let t = day0;
    let right = false; // which way it's looking
    const clip = name => "Bell Beast " + name;
    const push = (name, duration, extra) => {
        const seg = { kind: "clip", clip: clip(name), t0: t, t1: t + duration };
        for (const k in extra || {}) {
            seg[k] = extra[k];
        }
        segs.push(seg);
        t += duration;
    };
    const once = name => push(name, clipLength(clips, clip(name)));
    const idle = until => {
        if (until > t) {
            push(right ? "Idle Right" : "Idle Left", until - t);
        }
    };
    const turn = toRight => {
        if (toRight !== right) {
            once(toRight ? "Turn Right" : "Turn Left");
            right = toRight;
        }
    };

    const wake = hornet.wake + between(r, 600, 1500);
    const asleep = day0 + (17.5 + between(r, 0, 0.6)) * 3600; // 21:30-22:06
    push("Sleep", wake - t);
    once("Wake");
    // Things that happen at set times: the hourly songs, Hornet's visits.
    const events = [];
    for (let h = 9; h <= 21; h++) {
        const at = day0 + (h - 4) * 3600;
        if (at > t && at < asleep - 60) {
            events.push({ t: at, kind: "sing" });
        }
    }
    for (const v of hornet.log) {
        if (v.id === "bell_beast" && v.t0 > t && v.t1 < asleep) {
            events.push({ t: v.t0 + 1.0, kind: "visit", until: v.t1 });
        }
    }
    events.sort((a, b) => a.t - b.t);
    let next = 0;
    let greeted = -Infinity;
    while (t < asleep) {
        const e = events[next];
        // Until the next event, idle, now and then looking the other way or shaking.
        const wander = t + between(r, 25, 90);
        if (!e || wander < e.t - 3) {
            idle(Math.min(wander, asleep));
            if (t >= asleep) {
                break;
            }
            if (r() < 0.3 && !right) {
                once("Shake");
            } else {
                turn(!right);
            }
            continue;
        }
        idle(e.t);
        next++;
        if (e.kind === "sing") {
            // The hour: a song, some seconds long.
            push(right ? "Sing Right" : "Sing", between(r, 5, 9));
            once(right ? "Sing End Right" : "Sing End");
        } else {
            // Hornet came to see it: it looks at her, and shakes for joy (not every time).
            turn(false);
            if (t - greeted > 1800) {
                idle(t + 1.2);
                once("Shake");
                greeted = t;
            }
            idle(Math.max(t, Math.min(e.until, asleep)));
        }
    }
    // Lying down: waking played backwards, from looking left.
    turn(false);
    push("Wake", clipLength(clips, clip("Wake")), { reverse: true });
    push("Sleep", day0 + 24 * 3600 + 1 - t);
    return segs;
}

// The Bell Beast at time t: { clip, frame }.
function beastAt(world, clips, t) {
    if (!world || !world.nav || !clips || !clips["Bell Beast Sleep"]) {
        return null;
    }
    daySegments(world, clips, t);
    const segs = cache.beast;
    const seg = segs[segmentIndex(segs, t)];
    const c = clips[seg.clip];
    let frame = frameAt(c, t - seg.t0);
    if (seg.reverse) {
        frame = c.frames - 1 - frame;
    }
    return { clip: seg.clip, frame: frame };
}

// The Bell Beast's clips from t to t + horizon seconds.
function beastClipsAhead(world, clips, t, horizon) {
    if (!world || !world.nav || !clips || !clips["Bell Beast Sleep"]) {
        return [];
    }
    daySegments(world, clips, t);
    const segs = cache.beast;
    const names = {};
    for (let i = segmentIndex(segs, t); i < segs.length && segs[i].t0 < t + horizon; i++) {
        names[segs[i].clip] = true;
    }
    return Object.keys(names).sort();
}

// ------------------------------------------------------------------ sampling

function lerp(a, b, t) {
    return a + (b - a) * t;
}

// Pose at time t: { clip, frame, x, y, facingRight, scale, angle, needle, thread }.
// needle: { x, y, angle } of her thrown needle; thread: [x0, y0, x1, y1] of its silk.
function pose(world, clips, seg, t) {
    const local = t - seg.t0;
    const s = Math.min(1, Math.max(0, local / Math.max(1e-6, seg.t1 - seg.t0)));
    const out = { clip: seg.clip, frame: 0, x: 0, y: 0, facingRight: seg.facingRight, scale: 1, angle: 0,
                  needle: null, thread: null };
    let tc = local; // time into the clip shown
    switch (seg.kind) {
    case "walk":
        out.x = lerp(seg.x0, seg.x1, s);
        out.y = height(world.nav.surfaces[seg.surface], out.x, world.nav.step) + world.heroFeet;
        break;
    case "line":
        out.x = lerp(seg.x0, seg.x1, s);
        out.y = lerp(seg.y0, seg.y1, s);
        if (seg.tilt) {
            const a = Math.atan2(seg.y1 - seg.y0, Math.abs(seg.x1 - seg.x0)) * 180 / Math.PI;
            out.angle = Math.max(-60, Math.min(60, a));
        }
        break;
    case "fall":
        out.x = lerp(seg.x0, seg.x1, s);
        out.y = Math.max(seg.y1, seg.y0 - fallDistance(local));
        break;
    case "wallhop":
        // Kicked off the wall and back onto it, higher: out and in, up with an arc.
        out.x = seg.x0 + seg.out * Math.sin(Math.PI * s);
        out.y = lerp(seg.y0, seg.y1, s) + 4 * s * (1 - s) * seg.lift;
        if (s > 0.5) {
            out.clip = seg.second; // turning back towards the wall
            tc = local - 0.5 * (seg.t1 - seg.t0);
        }
        break;
    case "jump": {
        const p = seg.plan;
        out.x = lerp(seg.x0, seg.x1, s);
        out.y = jumpY(p, seg.y0, local);
        const top = seg.second ? p.tB : p.tA;
        if (seg.second && local >= p.tA && local < p.tA + clipLength(clips, seg.second)) {
            out.clip = seg.second; // the double jump: her wings at the top of the first
            tc = local - p.tA;
        } else if (local >= top) {
            out.clip = seg.fall;
            tc = local - top;
        } else if (seg.antic && local >= top - clipLength(clips, seg.antic)) {
            out.clip = seg.antic;
            tc = local - (top - clipLength(clips, seg.antic));
        }
        break;
    }
    default:
        out.x = seg.pivot ? seg.pivot[0] : seg.x;
        out.y = seg.pivot ? seg.pivot[1] : seg.y;
        if (seg.mirror) {
            out.facingRight = true; // the house is mirrored, so are its animations
        }
        out.scale = seg.scale || 1;
    }
    if (seg.needle) {
        // The needle flies from her hand to the ring, its silk behind it.
        const f = Math.min(1, local / Math.max(1e-6, Math.hypot(seg.needle.to[0] - seg.needle.from[0],
                                                                 seg.needle.to[1] - seg.needle.from[1]) / NEEDLE_SPEED));
        const nx = lerp(seg.needle.from[0], seg.needle.to[0], f);
        const ny = lerp(seg.needle.from[1], seg.needle.to[1], f);
        out.needle = { x: nx, y: ny, angle: Math.atan2(seg.needle.to[1] - seg.needle.from[1], seg.needle.to[0] - seg.needle.from[0]) * 180 / Math.PI };
        out.thread = [seg.needle.from[0], seg.needle.from[1], nx, ny];
    }
    if (seg.thread) {
        const hand = [out.x + (out.facingRight ? 0.3 : -0.3), out.y + 0.5];
        out.thread = [hand[0], hand[1], seg.thread[0], seg.thread[1]];
        out.needle = { x: seg.thread[0], y: seg.thread[1], angle: Math.atan2(seg.thread[1] - hand[1], seg.thread[0] - hand[0]) * 180 / Math.PI };
    }
    const clip = clips[out.clip];
    if (clip) {
        out.frame = seg.frame === -1 ? clip.frames - 1 : frameAt(clip, tc);
        if (seg.reverse) {
            out.frame = clip.frames - 1 - out.frame;
        }
    }
    return out;
}


function dayStart(date) {
    const d = new Date(date.getTime());
    if (d.getHours() < 4) {
        d.setDate(d.getDate() - 1);
    }
    d.setHours(4, 0, 0, 0);
    return d;
}

// The day's segments, planned once per day (and per world build).
function daySegments(world, clips, t) {
    const start = dayStart(new Date(t * 1000));
    const dateKey = start.getFullYear() * 10000 + (start.getMonth() + 1) * 100 + start.getDate();
    const key = dateKey + ":" + (world.build || 0) + ":" + world.nav.surfaces.length + ":" + world.nav.links.length;
    if (cache.key !== key) {
        const plan = planDay(world, clips, start.getTime() / 1000, dateKey);
        cache = { key: key, segments: plan.segments, beast: planBeast(world, clips, start.getTime() / 1000, dateKey, plan) };
    }
    return cache.segments;
}

function segmentIndex(segs, t) {
    let lo = 0;
    let hi = segs.length - 1;
    while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (segs[mid].t0 <= t) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo;
}

// Hornet at time t (seconds since the epoch).
function hornetAt(world, clips, t) {
    if (!world || !world.nav || !clips) {
        return null;
    }
    const segs = daySegments(world, clips, t);
    return pose(world, clips, segs[segmentIndex(segs, t)], t);
}

// The clips she plays from t to t + horizon seconds, sorted: their sheets should be loaded
// before she needs them (her needle's too).
function clipsAhead(world, clips, t, horizon) {
    if (!world || !world.nav || !clips) {
        return [];
    }
    const segs = daySegments(world, clips, t);
    const names = {};
    for (let i = segmentIndex(segs, t); i < segs.length && segs[i].t0 < t + horizon; i++) {
        const seg = segs[i];
        for (const n of [seg.clip, seg.second, seg.fall, seg.antic]) {
            if (n) {
                names[n] = true;
            }
        }
        if (seg.needle || seg.thread) {
            names["Harpoon Needle"] = true;
        }
    }
    return Object.keys(names).filter(n => clips[n] !== undefined).sort();
}

/*
 * Hornet's day in the aquarium.
 *
 * Every copy of the wallpaper (one per screen, plus the lock screen) builds the
 * same timeline for the day from the date: a seeded simulation that starts at
 * 04:00 with Hornet asleep and picks what she does next from her needs and the
 * hour. Each copy then shows the moment it's at, so they agree without talking.
 *
 * world.nav (tools/nav.py) has the surfaces she stands on (and the water she
 * swims on), the links between them (walk, drop, jump, jump2, mantle, mantle2,
 * float, climb, slide, wade, harpoon, bounce) and the places she spends time.
 * She moves as she does in the game, at its speeds and with its animations:
 * running (starting, stopping, turning, landing into it), walking, walking with
 * her map open, sprinting, swimming, each as she chooses for the trip; she takes
 * each link on the move, jumping from a run and running on from where she lands. Each trip picks its
 * way with her own preferences and a little chance, so the same trip goes
 * different ways (routeTree).
 *
 * The screens ask for her (and the Bell Beast, the small life) on every frame,
 * so what runs that often has no for-of loop or array destructuring: in the
 * QML engine each step allocates an iterator result, which was most of what
 * the creatures cost and kept its garbage collector busy. And nothing here
 * uses WeakMap, WeakSet or WeakRef, which crashed that garbage collector
 * (Qt 6.11): what's remembered between calls lives in plain properties of each
 * screen's world and clips or of the day's plan, or in this file's own caches.
 */
.pragma library

const WALK_SPEED = 5;     // HeroController.WALK_SPEED
const RUN_SPEED = 8.25;   // HeroController.RUN_SPEED
const SPRINT_SPEED = 17.5; // the Sprint FSM's Sprint Speed Regular
const MAP_WALK_SPEED = 4; // the Map Control FSM's Walk Speed
const SWIM_SPEED = 5;     // HeroWaterController.swimSpeed
const SWIM_DASH_SPEED = 10; // its sprintSwimSpeed
const FLOAT_SPEED = 3;    // how fast she sinks under the Drifter's Cloak (HeroController.FLOAT_SPEED)
const FLOAT_OPEN = 0.3;   // she falls this long while it opens (tools/nav.py FLOAT_OPEN)
const WALLSLIDE_ACCEL = 24; // down a wall (HeroController.WALLSLIDE_ACCEL), after sticking to it a moment
const WALLSLIDE_STICK = 0.15;
const BIG_FALL_TIME = 0.5; // falling at full speed longer than this, she lands hard
const FLOAT_MIN = 4;      // she opens her cloak only on a longer way down (tools/nav.py FLOAT_MIN)
const WATER_JUMP_LIFT = 1; // jumping out of the water, she's lifted this much first (tools/nav.py)
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

// The cell of its sheet a clip played by `seg` shows in its frame k (from the segment's start).
function cellOf(clip, seg, k) {
    let f = frameAt(clip, (k + 0.5) / clip.fps);
    if (seg.reverse) {
        f = clip.frames - 1 - f;
    }
    return clip.sequence[Math.min(f, clip.frames - 1)];
}

// The next time after t that the clip played by `seg` shows another cell of its sheet, or `end`
// if it doesn't before then: frames that repeat a cell (most of her sitting idles), a clip played
// to its end and a held frame change nothing on screen.
function nextCellChange(clips, seg, t, end) {
    const clip = clips[seg.clip];
    if (!clip || seg.frame === -1 || clip.wrapMode === 6) {
        return end;
    }
    const i = Math.floor((t - seg.t0) * clip.fps + 1e-6);
    const now = cellOf(clip, seg, i);
    // Within two rounds of the clip, unless it has stopped (or shows one cell throughout).
    for (let k = i + 1; k <= i + 2 * clip.frames + 2; k++) {
        const at = seg.t0 + k / clip.fps;
        if (at >= end) {
            return end;
        }
        if (cellOf(clip, seg, k) !== now) {
            return at;
        }
    }
    return end;
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
// then the fall, down to y1. The jump is held only as long as it needs to clear y1; a double
// jump's second, longer if she must stay up `minT` seconds (to go a long way at run speed).
function jumpPlan(y0, y1, double, v, maxHold, minT) {
    v = v || JUMP_SPEED;
    maxHold = maxHold === undefined ? JUMP_HOLD : maxHold;
    const free = v * v / (2 * GRAVITY);
    const hold1 = double ? maxHold : Math.min(maxHold, Math.max(0, (y1 + 0.8 - y0 - free) / v));
    const apex1 = y0 + v * hold1 + free;
    const tA = hold1 + v / GRAVITY;
    const p = { v: v, hold1: hold1, apex1: apex1, tA: tA, v2: 0, hold2: 0, apex: apex1, tB: tA };
    const second = need => {
        let v2 = DOUBLE_JUMP_SPEED;
        const free2 = v2 * v2 / (2 * GRAVITY);
        p.hold2 = 0;
        if (need < free2) {
            v2 = Math.sqrt(2 * GRAVITY * need);
        } else {
            p.hold2 = Math.min(DOUBLE_JUMP_HOLD, (need - free2) / v2);
        }
        p.v2 = v2;
        p.apex = apex1 + v2 * p.hold2 + v2 * v2 / (2 * GRAVITY);
        p.tB = tA + p.hold2 + v2 / GRAVITY;
    };
    p.T = p.tB + fallTime(p.apex - y1);
    if (!double && minT && p.T < minT && hold1 < maxHold) {
        // Held longer, until she's up long enough: the least that does.
        let lo = hold1;
        let hi = maxHold;
        const plan = h => {
            p.hold1 = h;
            p.apex1 = p.apex = y0 + v * h + free;
            p.tA = p.tB = h + v / GRAVITY;
            p.T = p.tB + fallTime(p.apex - y1);
        };
        for (let i = 0; i < 16; i++) {
            const mid = (lo + hi) / 2;
            plan(mid);
            if (p.T < minT) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        plan(hi);
    }
    if (double) {
        let lo = Math.max(0.6, y1 + 0.8 - apex1);
        let hi = DOUBLE_JUMP_SPEED * DOUBLE_JUMP_HOLD + DOUBLE_JUMP_SPEED * DOUBLE_JUMP_SPEED / (2 * GRAVITY);
        second(lo);
        p.T = p.tB + fallTime(p.apex - y1);
        if (minT && p.T < minT && lo < hi) {
            // Higher, until she's up long enough (the higher, the longer): the least that does.
            for (let i = 0; i < 16; i++) {
                const mid = (lo + hi) / 2;
                second(mid);
                if (p.tB + fallTime(p.apex - y1) < minT) {
                    lo = mid;
                } else {
                    hi = mid;
                }
            }
            second(hi);
            p.T = p.tB + fallTime(p.apex - y1);
        }
    }
    return p;
}

// When a jump (held as long as it can be) first rises to y1, or its top if it doesn't get there:
// where she catches a ledge.
function riseTime(p, y0, y1) {
    const top = p.v2 ? p.tB : p.tA;
    if (jumpY(p, y0, top) <= y1) {
        return top;
    }
    let lo = 0;
    let hi = top;
    for (let i = 0; i < 20; i++) {
        const mid = (lo + hi) / 2;
        if (jumpY(p, y0, mid) < y1) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return hi;
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

// Routes depend only on the map, so they're kept per world build, across days: the cheapest
// ways from each place she sets off from (a few dozen) to every link end, found once, which any
// goal is then a walk from.
let routes = { key: "", starts: new Map() };

function routesFor(world) {
    const nav = world.nav;
    const key = (world.build || 0) + ":" + nav.surfaces.length + ":" + nav.links.length;
    if (routes.key !== key) {
        // Nodes: 0 where she sets off, then each link's two ends (1 + 2k where it leaves, 2 + 2k
        // where it lands); walking along a surface joins those on it.
        const xs = [0];
        const ss = [-1];
        nav.links.forEach(l => {
            ss.push(l.from, l.to);
            xs.push(l.x0, l.x1);
        });
        const onSurface = nav.surfaces.map(() => []);
        for (let i = 1; i < ss.length; i++) {
            onSurface[ss[i]].push(i);
        }
        // Each surface's nodes in order along it, and where each node is in that order: walking
        // to a node further along passes the ones between, so only neighbours need joining.
        const along = onSurface.map(list => list.slice().sort((i, j) => xs[i] - xs[j] || i - j));
        const place = new Array(xs.length).fill(-1);
        along.forEach(list => list.forEach((v, k) => {
            place[v] = k;
        }));
        routes = { key: key, starts: new Map(), nav: nav, xs: xs, ss: ss, onSurface: onSurface, along: along, place: place };
    }
    return routes;
}

// The cheapest ways from (surface a, x) to every link end (routeTree at each link's own time),
// kept for the world build, with the ways to each goal asked for: { tree, paths }.
function routesFrom(R, a, xa) {
    const byX = R.starts.get(a) || new Map();
    R.starts.set(a, byX);
    let from = byX.get(xa);
    if (!from) {
        if (!R.ones) {
            R.ones = new Float64Array(R.nav.links.length).fill(1);
        }
        from = { tree: routeTree(R, a, xa, R.ones), paths: R.nav.surfaces.map(() => new Map()) };
        byX.set(xa, from);
    }
    return from;
}

// Cheapest route from (surface a, x) to (surface b, x): a list of link objects, in order (null
// when there's none), with `trip`, the time it takes (links, then the way along to x), alongside.
function routeTrip(R, a, xa, b, xb) {
    const from = routesFrom(R, a, xa);
    let found = from.paths[b].get(xb);
    if (found) {
        return found;
    }
    const path = treePath(R, from.tree, a, xa, b, xb);
    const speed = R.nav.surfaces[b].water ? SWIM_SPEED : RUN_SPEED;
    const trip = path === null ? 999 : path.reduce((sum, l) => sum + l.time, 0)
        + Math.abs((path.length ? path[path.length - 1].x1 : xa) - xb) / speed;
    found = { path: path, trip: trip };
    from.paths[b].set(xb, found);
    return found;
}

// Her ways from (surface a, x) to everywhere with her own preferences: each link costs its time
// times factors[link index] (what she feels like doing today, and some chance), so that the same
// trip doesn't always go the same way. { dist, prev, prevLink } per node (routesFor). A day has
// a few sets of factors (Planner.variants), each trip draws one, and each set's ways from a place
// are found once (Planner.routeFor).
function routeTree(R, a, xa, factors) {
    const n = R.xs.length;
    const xs = R.xs;
    const ss = R.ss;
    const links = R.nav.links;
    const surfaces = R.nav.surfaces;
    const dist = new Float64Array(n).fill(Infinity);
    const prev = new Int32Array(n).fill(-1);
    const prevLink = new Int32Array(n).fill(-1);
    if (!R.heap) {
        R.heap = { d: new Float64Array(4 * n + 8), v: new Int32Array(4 * n + 8) };
    }
    const heapD = R.heap.d;
    const heapV = R.heap.v;
    let size = 0;
    const pushHeap = (d, v) => {
        let i = size++;
        while (i > 0) {
            const up = (i - 1) >> 1;
            if (heapD[up] <= d) {
                break;
            }
            heapD[i] = heapD[up];
            heapV[i] = heapV[up];
            i = up;
        }
        heapD[i] = d;
        heapV[i] = v;
    };
    const popHeap = () => { // the cheapest node; its distance is left in heapD[size]
        const v = heapV[0];
        const d0 = heapD[0];
        size--;
        const d = heapD[size];
        const last = heapV[size];
        let i = 0;
        for (;;) {
            const l = 2 * i + 1;
            if (l >= size) {
                break;
            }
            const r = l + 1 < size && heapD[l + 1] < heapD[l] ? l + 1 : l;
            if (heapD[r] >= d) {
                break;
            }
            heapD[i] = heapD[r];
            heapV[i] = heapV[r];
            i = r;
        }
        heapD[i] = d;
        heapV[i] = last;
        heapD[size] = d0;
        return v;
    };
    dist[0] = 0;
    pushHeap(0, 0);
    while (size > 0) {
        const u = popHeap();
        const du = heapD[size];
        if (du > dist[u]) {
            continue;
        }
        const su = u === 0 ? a : ss[u];
        const xu = u === 0 ? xa : xs[u];
        const speed = surfaces[su].water ? SWIM_SPEED : RUN_SPEED;
        // Walking along: from the start to every node of its surface, from a node to its
        // neighbours along it (walking further passes them).
        const along = R.along[su];
        const k = R.place[u];
        const from = u === 0 ? 0 : Math.max(0, k - 1);
        const to = u === 0 ? along.length - 1 : Math.min(along.length - 1, k + 1);
        for (let j = from; j <= to; j++) {
            const v = along[j];
            if (v === u) {
                continue;
            }
            const d = du + Math.abs(xs[v] - xu) / speed;
            if (d < dist[v]) {
                dist[v] = d;
                prev[v] = u;
                prevLink[v] = -1;
                pushHeap(d, v);
            }
        }
        if (u % 2 === 1) { // where link l leaves from
            const l = (u - 1) / 2;
            const d = du + links[l].time * factors[l] + 0.3;
            if (d < dist[u + 1]) {
                dist[u + 1] = d;
                prev[u + 1] = u;
                prevLink[u + 1] = l;
                pushHeap(d, u + 1);
            }
        }
    }
    return { dist: dist, prev: prev, prevLink: prevLink };
}

// The way to (surface b, x) by a route tree from (surface a, x): a list of links (null when there's
// none). On her own surface she just goes along it.
function treePath(R, tree, a, xa, b, xb) {
    if (a === b) {
        return [];
    }
    const surfaces = R.nav.surfaces;
    const speed = surfaces[b].water ? SWIM_SPEED : RUN_SPEED;
    const on = R.onSurface[b];
    let best = Infinity;
    let last = -1;
    for (let j = 0; j < on.length; j++) {
        const u = on[j];
        const d = tree.dist[u] + Math.abs(xb - R.xs[u]) / speed;
        if (d < best) {
            best = d;
            last = u;
        }
    }
    if (last < 0 || best === Infinity) {
        return null;
    }
    const path = [];
    for (let v = last; v > 0; v = tree.prev[v]) {
        if (tree.prevLink[v] >= 0) {
            path.unshift(R.nav.links[tree.prevLink[v]]);
        }
    }
    return path;
}

// ------------------------------------------------------------------ building the day

// How she moves along the ground and the water, at the game's speeds: what she plays doing it,
// setting off, stopping (from standing still), turning on the move, landing into it.
const GAITS = {
    walk: { speed: WALK_SPEED, clip: "Walk", stop: "Walk To Idle", turn: "TurnWalk", land: "Land To Walk" },
    run: { speed: RUN_SPEED, clip: "Run", start: "Idle To Run", startShort: "Idle To Run Short", stop: "Run To Idle",
           turn: "Turn", land: "Land To Run" },
    sprint: { speed: SPRINT_SPEED, clip: "Sprint", start: "Idle To Run Short", stop: "Sprint Skid To Run",
              turn: "Sprint Turn", land: "Land to Sprint" },
    map: { speed: MAP_WALK_SPEED, clip: "Map Walk", open: "Map Open", stop: "Map Away", turn: "Map Turn" },
    swim: { speed: SWIM_SPEED, clip: "Surface IdleToSwim", turn: "Surface TurnToSwim" },
    dash: { speed: SWIM_DASH_SPEED, clip: "Swim Dash", turn: "Swim Dash Turn" },
};

// What she plays landing, going on running (or walking) from there, or standing.
const LANDING = { walk: "Land To Walk", run: "Land To Run", sprint: "Land to Sprint", stand: "Land" };
const MANTLED = { walk: "Mantle Land To Run", run: "Mantle Land To Run", sprint: "Mantle Land To Run", stand: "Mantle Land To Idle" };
const HARD = { walk: "HardLand", run: "HardLand", sprint: "HardLand", stand: "HardLand" };

// Segments: { t0, t1, kind, clip, ... }. Poses are computed from them when sampling.
function Planner(world, clips, seed) {
    this.world = world;
    this.nav = world.nav;
    this.clips = clips;
    this.r = rng(seed);
    this.segments = [];
    this.log = []; // what she did where: { id, t0, t1 }
    this.routes = routesFor(world);
    this.t = 0;
    this.surface = 0;
    this.x = 0;
    this.facingRight = true;
    this.moving = null;  // her gait while she's on the move (facing her way), else null
    this.landing = null; // just landed: what she plays going on from there (LANDING), else null
    this.prefs = null;   // what she feels like doing today: a factor on each kind of link's cost
    this.style = { float: 0, double: 0, slide: 0 }; // how often she floats down a drop, double jumps for the
    // joy of it, slides down a wall rather than drops beside it
    this.slides = {}; // the slides down a wall, by the surfaces they join: "from:to" -> link
    world.nav.links.forEach(l => {
        if (l.kind === "slide") {
            this.slides[l.from + ":" + l.to] = l;
        }
    });
    this.variants = [];  // a few sets of factors on each link's cost, drawn from those (routeTree)
    this.trees = new Map(); // their route trees from where she set off: "variant:surface:x" -> tree
}

Planner.prototype.inWater = function () {
    return !!this.nav.surfaces[this.surface].water;
};

// Her way there for this trip: by one of the day's sets of preferences (routeTree), drawn.
Planner.prototype.routeFor = function (surface, x) {
    if (!this.variants.length) {
        return this.route(surface, x);
    }
    const v = Math.floor(this.r() * this.variants.length);
    const key = v + ":" + this.surface + ":" + this.x;
    let tree = this.trees.get(key);
    if (!tree) {
        tree = routeTree(this.routes, this.surface, this.x, this.variants[v]);
        this.trees.set(key, tree);
    }
    return treePath(this.routes, tree, this.surface, this.x, surface, x);
};

// What she feels like doing today (a factor on each kind of link), and from it VARIANTS sets of
// factors on each link, each with some chance of its own.
const VARIANTS = 3;
Planner.prototype.prefer = function (prefs) {
    this.prefs = prefs;
    const links = this.nav.links;
    this.variants = [];
    for (let v = 0; v < VARIANTS; v++) {
        const f = new Float64Array(links.length);
        for (let l = 0; l < links.length; l++) {
            f[l] = (prefs[links[l].kind] || 1) * between(this.r, 0.7, 1.3);
        }
        this.variants.push(f);
    }
    this.trees = new Map();
};

Planner.prototype.route = function (surface, x) {
    return routeTrip(this.routes, this.surface, this.x, surface, x).path;
};

// How long getting there takes, links and walks (999 s when there's no way).
Planner.prototype.trip = function (surface, x) {
    return routeTrip(this.routes, this.surface, this.x, surface, x).trip;
};

// The clips she plays with an older tools/extract.py (without the moves it extracts now): the
// nearest it has, so that she's never missing.
const STAND_IN = {
    "Idle To Run Short": "Idle To Run", "Run To Walk": "Walk", "Land To Run": "Run", "Land To Walk": "Walk",
    "Land to Sprint": "Run", "Sprint": "Run", "Sprint To Run": "Run", "Sprint Skid To Run": "Run To Idle", "Sprint Turn": "Turn",
    "Map Walk": "Walk", "Map Turn": "TurnWalk", "HardLand": "Land", "Wall Slide": "Wall Cling",
    "Mantle Land To Run": "Run", "Mantle Land To Idle": "Land", "Mantle Cling": "Wall Scramble Mantle",
    "Umbrella Float": "Fall", "Umbrella Inflate Antic": "Fall", "Umbrella Inflate": "Fall", "Umbrella Deflate": "Fall",
    "Surface In": "Land", "Surface InToIdle": "Idle", "Surface Idle": "Idle", "Surface IdleToSwim": "Walk",
    "Surface TurnToSwim": "TurnWalk", "Swim Dash": "Walk", "Swim Dash Turn": "TurnWalk",
};

function clipOr(clips, name) {
    let n = name;
    for (let i = 0; i < 3 && n && !clips[n] && STAND_IN[n]; i++) {
        n = STAND_IN[n];
    }
    return n;
}

Planner.prototype.push = function (seg, duration) {
    for (const k of ["clip", "second", "fall", "antic"]) {
        if (seg[k]) {
            seg[k] = clipOr(this.clips, seg[k]);
        }
    }
    if (seg.also) {
        seg.also = seg.also.map(n => clipOr(this.clips, n));
    }
    seg.t0 = this.t;
    seg.t1 = this.t + duration;
    this.segments.push(seg);
    this.t = seg.t1;
    return seg;
};

Planner.prototype.y = function (surface, x) {
    return height(this.nav.surfaces[surface], x, this.nav.step) + this.world.heroFeet;
};

// Standing (stopping first if she's moving), turning to face that way.
Planner.prototype.face = function (right) {
    this.stop();
    if (right === this.facingRight) {
        return;
    }
    if (this.inWater()) {
        this.facingRight = right; // treading water she just turns about
        return;
    }
    // Turn is drawn going from right-facing to left-facing; mirrored, the other way.
    this.push({ kind: "clip", clip: TURN, x: this.x, y: this.y(this.surface, this.x), facingRight: right },
        clipLength(this.clips, TURN));
    this.facingRight = right;
};

// In the water, standing is treading water, and there's no looking up.
const IN_WATER = { "Idle": "Surface Idle", "LookUp": "Surface Idle", "LookingUp": "Surface Idle", "LookUpEnd": "Surface Idle" };

Planner.prototype.hold = function (clip, duration, extra) {
    this.stop();
    if (this.inWater() && IN_WATER[clip]) {
        clip = IN_WATER[clip];
    }
    const seg = { kind: "clip", clip: clip, x: this.x, y: this.y(this.surface, this.x), facingRight: this.facingRight };
    if (extra) {
        for (const k in extra) {
            seg[k] = extra[k];
        }
    }
    return this.push(seg, duration === undefined ? clipLength(this.clips, clip) : duration);
};

// Coming to a standstill: her gait's stop (or the landing she was going on from).
Planner.prototype.stop = function () {
    if (this.landing) {
        const clip = this.landing.stand;
        this.landing = null;
        this.push({ kind: "clip", clip: clip, x: this.x, y: this.y(this.surface, this.x), facingRight: this.facingRight },
            clipLength(this.clips, clip));
    }
    const gait = this.moving;
    this.moving = null;
    if (!gait || !GAITS[gait].stop) {
        return;
    }
    const at = { kind: "clip", x: this.x, y: this.y(this.surface, this.x), facingRight: this.facingRight };
    if (gait === "sprint") {
        this.push(Object.assign({ clip: "Sprint Skid To Run" }, at), clipLength(this.clips, "Sprint Skid To Run"));
        this.push(Object.assign({ clip: "Run To Idle" }, at), clipLength(this.clips, "Run To Idle"));
    } else if (gait === "map") {
        this.push(Object.assign({ clip: "Map Idle" }, at), between(this.r, 1, 3));
        this.push(Object.assign({ clip: "Map Away" }, at), clipLength(this.clips, "Map Away"));
    } else {
        this.push(Object.assign({ clip: GAITS[gait].stop }, at), clipLength(this.clips, GAITS[gait].stop));
    }
};

// Along her surface to x at a gait (swimming on the water), without stopping there; runUp: walking,
// she breaks into a run for the last of the way, up to a jump.
Planner.prototype.travel = function (x, gait, runUp) {
    if (Math.abs(x - this.x) < 0.05) {
        return;
    }
    if (runUp && gait === "walk" && Math.abs(x - this.x) > 3) {
        this.stretch(x - (x > this.x ? 2.5 : -2.5), "walk");
        gait = "run";
    }
    this.stretch(x, gait);
};

// One stretch of a travel, at one gait: setting off from standing still (or from where she
// landed), changing gait or turning on the move.
Planner.prototype.stretch = function (x, gait) {
    const dx = x - this.x;
    if (Math.abs(dx) < 0.05) {
        return;
    }
    const right = dx > 0;
    if (this.inWater()) {
        gait = gait === "dash" ? "dash" : "swim";
    } else if (gait === "swim" || gait === "dash") {
        gait = "run";
    }
    if (this.moving === "map" && gait !== "map") {
        this.stop(); // her map put away first
    }
    const g = GAITS[gait];
    let left = Math.abs(dx);
    const go = (clip, d, speed) => {
        d = Math.min(d, left);
        if (d <= 0.001) {
            return;
        }
        const x1 = this.x + (right ? d : -d);
        this.push({ kind: "walk", clip: clip, surface: this.surface, x0: this.x, x1: x1, facingRight: right }, d / (speed || g.speed));
        this.x = x1;
        left -= d;
    };
    const over = (clip, speed) => clipLength(this.clips, clip) * (speed || g.speed); // how far a clip takes her
    if (this.landing) {
        const landing = this.landing;
        this.landing = null;
        if (this.facingRight === right && landing[gait]) {
            // (at most her run's speed, but into a sprint)
            const v = landing[gait] === "Land to Sprint" ? g.speed : Math.min(g.speed, RUN_SPEED);
            this.moving = gait;
            go(landing[gait], over(landing[gait], v), v);
        } else {
            this.landing = landing;
            this.face(right);
        }
    }
    if (this.moving && this.facingRight !== right) {
        this.facingRight = right; // turning on the move
        go(g.turn, over(g.turn));
    } else if (!this.moving) {
        if (this.facingRight !== right) {
            if (g.turn && this.inWater()) {
                this.facingRight = right; // a turn into a stroke
                go(g.turn, over(g.turn));
            } else {
                this.face(right);
            }
        }
        if (g.open) {
            this.push({ kind: "clip", clip: g.open, x: this.x, y: this.y(this.surface, this.x), facingRight: right },
                clipLength(this.clips, g.open));
        } else if (g.start) {
            // (into a sprint from a run's start, at run speed)
            const v = gait === "sprint" ? RUN_SPEED : g.speed;
            go(left < over(g.start, v) && g.startShort ? g.startShort : g.start, over(g.start, v), v);
        }
    } else if (this.moving !== gait) {
        if (this.moving === "run" && gait === "walk") {
            go("Run To Walk", over("Run To Walk"));
        } else if (this.moving === "sprint") {
            go("Sprint To Run", over("Sprint To Run"));
        }
    }
    this.moving = gait;
    go(g.clip, left);
};

// After a link she lands on her new surface: into the water, or with what she plays going on
// from there (or standing, if she doesn't): the next travel or stop decides.
Planner.prototype.land = function (link, landing) {
    this.surface = link.to;
    this.x = link.x1;
    this.moving = null;
    if (this.inWater()) {
        this.landing = null;
        this.hold("Surface In");
        this.hold("Surface InToIdle");
        return;
    }
    this.landing = landing || LANDING;
};

// Setting off into the air at x0 towards `right`: on the move if she's going that way (from a
// landing, straight on), else from standing, turned that way.
Planner.prototype.takeOff = function (right) {
    if (this.landing && this.facingRight === right) {
        this.landing = null; // jumping again as she lands
    }
    if (!(this.moving && this.facingRight === right)) {
        this.face(right);
    }
    this.moving = null;
    this.facingRight = right;
};

// A ballistic move from (x0, y0) to (x1, y1), y being her pivot; `clips` names what she
// plays rising, falling, and at the top of a double jump.
Planner.prototype.leap = function (x0, y0, x1, y1, opts) {
    opts = opts || {};
    let p = jumpPlan(y0, y1, !!opts.double, opts.speed, opts.hold, opts.minT);
    if (p.apex < y1 + 0.2 && !opts.double) {
        // Too high for one jump: her second, at the top of the first.
        opts = Object.assign({}, opts, { double: true });
        p = jumpPlan(y0, y1, true, opts.speed, opts.hold, opts.minT);
    }
    // The game plays Airborne all the way, from her take-off to its falling frames; after a
    // double jump, from those.
    const fall = opts.fall !== undefined ? opts.fall : opts.double ? "Airborne" : "";
    return this.push({ kind: "jump", plan: p, x0: x0, y0: y0, x1: x1, y1: y1, facingRight: this.facingRight,
                       clip: opts.rise || "Airborne", fall: fall, fallFrom: opts.fallFrom !== undefined ? opts.fallFrom : fall === "Airborne" ? 7 : 0,
                       second: opts.double ? "Double Jump" : "", antic: opts.antic || "" }, p.T);
};

// Under the Drifter's Cloak from (x0, y0) to (x1, y1): a moment's fall while it opens, then a slow
// sink, drifting across.
Planner.prototype.glide = function (x0, y0, x1, y1) {
    const h0 = 0.5 * GRAVITY * FLOAT_OPEN * FLOAT_OPEN;
    const T = FLOAT_OPEN + Math.max(0, y0 - y1 - h0) / FLOAT_SPEED;
    this.push({ kind: "glide", clip: "Umbrella Float", x0: x0, y0: y0, x1: x1, y1: y1, facingRight: this.facingRight,
                also: ["Umbrella Inflate Antic", "Umbrella Inflate", "Umbrella Deflate"] }, T);
};

// Turning in the air: no Turn animation (it stands on the ground), she just faces the other way.
Planner.prototype.faceInAir = function (right) {
    this.facingRight = right;
};

// A link, on the move: she runs up to it at her gait and takes it without stopping where she
// can, and lands into her run (Planner.land; the next travel or stop plays it).
Planner.prototype.follow = function (link, gait) {
    const right = link.x1 > link.x0 ? true : link.x1 < link.x0 ? false : this.facingRight;
    const feet = this.world.heroFeet;
    let y0 = link.y0 + feet;
    const y1 = link.y1 + feet;
    const toWater = !!this.nav.surfaces[link.to].water;
    const leap = link.kind === "jump" || link.kind === "jump2" || link.kind === "mantle" || link.kind === "mantle2";
    if (link.kind !== "harpoon" && link.kind !== "bounce" && link.kind !== "climb" && link.kind !== "slide") {
        this.travel(link.x0, gait, leap);
    }
    if (leap && this.inWater()) {
        // Out of the water: the game lifts her first, then she jumps.
        this.takeOff(right);
        this.push({ kind: "line", clip: "Airborne", x0: link.x0, y0: y0, x1: link.x0, y1: y0 + WATER_JUMP_LIFT, facingRight: right },
            0.08);
        y0 += WATER_JUMP_LIFT;
    }
    switch (link.kind) {
    case "walk": {
        // Over a small bump without breaking her stride.
        this.landing = null;
        this.moving = this.moving || (gait === "map" ? "walk" : gait);
        const g = GAITS[this.moving] || GAITS.run;
        this.facingRight = right;
        this.push({ kind: "line", clip: g.clip, x0: link.x0, y0: y0, x1: link.x1, y1: y1, facingRight: right },
            Math.max(0.1, Math.abs(link.x1 - link.x0) / g.speed));
        this.surface = link.to;
        this.x = link.x1;
        return;
    }
    case "wade": {
        if (toWater) {
            // Walking (running) out into the water until it's deep enough to swim.
            const g = GAITS[this.moving] || GAITS.walk;
            this.facingRight = right;
            this.push({ kind: "line", clip: this.moving ? g.clip : "Walk", x0: link.x0, y0: y0, x1: link.x1, y1: y1,
                        facingRight: right }, Math.max(0.3, Math.abs(link.x1 - link.x0) / (this.moving ? g.speed : WALK_SPEED)));
            this.surface = link.to;
            this.x = link.x1;
            this.moving = null;
            this.landing = null;
        } else {
            // Out of the water: walking up the shore.
            this.facingRight = right;
            this.moving = null;
            this.push({ kind: "line", clip: "Walk", x0: link.x0, y0: y0, x1: link.x1, y1: y1, facingRight: right },
                Math.max(0.3, Math.abs(link.x1 - link.x0) / WALK_SPEED));
            this.surface = link.to;
            this.x = link.x1;
            this.moving = "walk";
        }
        return;
    }
    case "drop": {
        // Off the edge: falling, as the game shows it (Airborne's falling frames), on as fast as
        // she was going; a long way at full speed, she lands hard. A long way down, now and then
        // she opens her cloak instead, or slides down the wall beside her.
        const slide = this.slides[link.from + ":" + link.to];
        if (slide && Math.abs(slide.x0 - link.x0) < 1.5 && this.r() < this.style.slide) {
            this.follow(slide, gait);
            return;
        }
        this.takeOff(right);
        if (y0 - y1 >= FLOAT_MIN && this.r() < this.style.float) {
            this.glide(link.x0, y0, link.x1, y1);
            this.land(link);
            return;
        }
        const T = Math.max(0.2, fallTime(y0 - y1));
        this.push({ kind: "fall", clip: "Airborne", from: 7, x0: link.x0, y0: y0, x1: link.x1, y1: y1, facingRight: right }, T);
        this.land(link, T - MAX_FALL / GRAVITY > BIG_FALL_TIME ? HARD : LANDING);
        return;
    }
    case "jump":
    case "jump2": {
        // (as long as she needs to go the whole way at run speed: tools/nav.py jump_reach, jump2_time)
        this.takeOff(right);
        const dx = Math.abs(link.x1 - link.x0);
        if (link.kind === "jump" && y0 - y1 >= FLOAT_MIN + 1 && this.r() < this.style.float) {
            // Down across a gap, her cloak opened at the top of the jump.
            const p = jumpPlan(y0, y0, false);
            const top = y0 + JUMP_SPEED * p.hold1 + JUMP_SPEED * JUMP_SPEED / (2 * GRAVITY);
            const glide = FLOAT_OPEN + Math.max(0, top - y1 - 0.5 * GRAVITY * FLOAT_OPEN * FLOAT_OPEN) / FLOAT_SPEED;
            const xa = link.x0 + (link.x1 - link.x0) * p.tA / (p.tA + glide);
            this.push({ kind: "jump", plan: p, x0: link.x0, y0: y0, x1: xa, y1: top, facingRight: right, clip: "Airborne",
                        fall: "", fallFrom: 0, second: "", antic: "" }, p.tA);
            this.glide(xa, top, link.x1, y1);
        } else {
            // Now and then a double jump where one would do, for the joy of it.
            const double = link.kind === "jump2" || y1 > y0 + 0.3 && y1 - y0 < 4 && dx < 5 && this.r() < this.style.double;
            this.leap(link.x0, y0, link.x1, y1, { double: double, minT: dx / RUN_SPEED });
        }
        this.land(link);
        return;
    }
    case "mantle":
    case "mantle2": {
        // Up at the ledge: her hands catch its edge at the top of her jump (or double jump), she
        // pulls herself up and over.
        this.takeOff(right);
        const dir = right ? 1 : -1;
        const hx = link.x1 - dir * 0.45;
        const hy = y1 - 1.45;
        const p = jumpPlan(y0, hy + 2, link.kind === "mantle2");
        const T = riseTime(p, y0, hy);
        this.push({ kind: "jump", plan: p, x0: link.x0, y0: y0, x1: hx, y1: hy, facingRight: right, clip: "Airborne",
                    fall: "Airborne", fallFrom: 7, second: link.kind === "mantle2" ? "Double Jump" : "", antic: "" }, T);
        this.push({ kind: "line", clip: "Mantle Cling", x0: hx, y0: hy, x1: hx + dir * 0.2, y1: y1 + 0.15, facingRight: right },
            clipLength(this.clips, "Mantle Cling"));
        this.push({ kind: "line", clip: "Mantle Land", x0: hx + dir * 0.2, y0: y1 + 0.15, x1: link.x1, y1: y1, facingRight: right },
            clipLength(this.clips, "Mantle Land"));
        this.land(link, MANTLED);
        return;
    }
    case "float":
        // The Drifter's Cloak: off the edge, drifting out to where she lands.
        this.takeOff(right);
        this.glide(link.x0, y0, link.x1, y1);
        this.land(link);
        return;
    case "climb":
        this.climb(link, y0, y1, gait);
        return;
    case "slide": {
        // Off the top's edge, onto the wall's face below it, and down it.
        this.travel(link.x0, gait);
        const wall = link.x0 > link.x1 ? 1 : -1; // which side of her the wall is, sliding
        const px = link.x1 - wall * 0.24;
        this.takeOff(wall < 0);
        this.push({ kind: "fall", clip: "Airborne", from: 7, x0: link.x0, y0: y0, x1: px, y1: y0 - 0.5, facingRight: wall < 0 },
            fallTime(0.5));
        this.faceInAir(wall > 0);
        const drop = Math.max(0, y0 - 0.5 - y1);
        this.push({ kind: "wallslide", clip: "Wall Slide", x0: px, y0: y0 - 0.5, x1: px, y1: y1, facingRight: wall > 0 },
            WALLSLIDE_STICK + Math.sqrt(2 * drop / WALLSLIDE_ACCEL));
        this.land(link);
        this.x = px; // (where she slid down, beside the wall)
        return;
    }
    case "harpoon": {
        // The Clawline: her needle thrown to the ring on its silk, then she's pulled after it,
        // catches it and lets go above where she lands.
        const rx = link.ring[0];
        const ry = link.ring[1];
        this.travel(link.x0, gait);
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
        this.land(link);
        return;
    }
    case "bounce": {
        // Up and down onto the pod with her needle pointing down; it throws her high.
        const px = link.pod[0];
        const py = link.pod[1] + feet - 0.4;
        this.travel(link.x0, gait);
        this.takeOff(px >= link.x0);
        this.leap(link.x0, y0, px, py, { antic: "DownSpike Antic", fall: "DownSpike" });
        this.faceInAir(link.x1 >= px);
        this.leap(px, py, link.x1, y1, { speed: POD_SPEED, hold: 0, rise: "DownSpikeBounce 1", fall: "Airborne", fallFrom: 7 });
        this.land(link);
        return;
    }
    }
};

// Up a wall the way she does it in the game: a jump against it (on the move if she's coming
// that way), a catch, walljumps out and back in (each one higher), then the last stretch
// scrambling up and over the edge.
Planner.prototype.climb = function (link, y0, y1, gait) {
    const dir = link.x1 >= link.x0 ? 1 : -1; // the wall's side
    this.travel(link.x0, gait);
    // Facing the wall (the climbing sprites have it on their left; mirrored, on the right).
    this.takeOff(dir > 0);
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
    this.land(link, MANTLED);
};

// Her gait for a stretch from x0 to x1 on her surface, ending at `link` (or where she's going):
// the trip's (`base`), but sprinting only where there's room for it; on the water, swimming (a
// sprint now and then on a long way).
Planner.prototype.gaitFor = function (x0, x1, link, base) {
    const d = Math.abs(x1 - x0);
    if (this.inWater()) {
        return base === "sprint" && d > 10 ? "dash" : "swim";
    }
    const leap = link && (link.kind === "jump" || link.kind === "jump2" || link.kind === "mantle" || link.kind === "mantle2");
    if (base === "map") {
        return link ? (leap ? "run" : "walk") : "map";
    }
    if (base === "walk") {
        return "walk"; // (breaking into a run up to a jump: travel)
    }
    if (base === "sprint") {
        return d > 12 ? "sprint" : "run";
    }
    return "run";
};

// There, by her way for this trip, at a gait she chooses for it (a stroll with her map open, a
// walk, a run, a sprint: by how far, the hour's energy and chance), stopping there unless
// `keepMoving`.
Planner.prototype.goTo = function (surface, x, opts) {
    opts = opts || {};
    const path = this.routeFor(surface, x);
    if (path === null) {
        return false;
    }
    let base = opts.gait;
    if (!base) {
        const far = this.trip(surface, x) * RUN_SPEED; // about how far
        const pick = this.r();
        const energy = this.energy === undefined ? 1 : this.energy;
        const sprint = far > 25 ? 0.3 * energy : 0;
        const walk = (far < 10 ? 0.45 : far < 30 ? 0.2 : 0.08) / energy;
        base = pick < sprint ? "sprint" : pick < sprint + walk ? "walk" : "run";
    }
    for (let i = 0; i < path.length; i++) {
        this.follow(path[i], this.gaitFor(this.x, path[i].x0, path[i], base));
    }
    this.travel(x, this.gaitFor(this.x, x, null, base));
    if (!opts.keepMoving) {
        this.stop();
    }
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
    case "swim": {
        // Out on the water a while: treading it, looking about, swimming a little way and back.
        const end = this.t + between(r, 15, 35);
        const sf = this.nav.surfaces[this.surface];
        while (this.t < end) {
            this.hold("Surface Idle", between(r, 3, 8));
            if (r() < 0.6) {
                this.travel(Math.min(sf.x1 - 0.5, Math.max(sf.x0 + 0.5, this.x + between(r, -6, 6))), r() < 0.25 ? "dash" : "swim");
                this.stop();
            }
        }
        break;
    }
    case "visit":
        if (r() < 0.3) {
            // At the Bell Beast's: now and then her needolin, which it sings along to (and its
            // children, if they're there).
            this.hold("Needolin Start");
            this.hold("Needolin Play", between(r, 10, 25));
            this.hold("Needolin End");
            break;
        }
    // falls through: else standing about
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

// Bed: lie down (unless she's lying there already), maybe read the map a while, sleep until
// `until`, sit up.
Planner.prototype.sleep = function (poi, until, readMap, lying0) {
    const at = { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror };
    const lying = { pivot: poi.pivot, scale: poi.scale || 1, mirror: !!poi.mirror, frame: -1 };
    if (!lying0) {
        this.hold("Hornet Lay Down", undefined, at);
    }
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

// The game's idle look (HeroAnimationController): standing still, she plays "Idle Rest" once
// after 4-10 s, then again every 10-15 s; turning doesn't count, looking up starts it over.
function withIdleRests(segs, clips, r) {
    if (!clips["Idle Rest"]) {
        return segs;
    }
    const rest = clipLength(clips, "Idle Rest");
    const out = [];
    let left = null; // standing time before the next rest; null while she isn't standing
    for (let i = 0; i < segs.length; i++) {
        const seg = segs[i];
        const standing = seg.kind === "clip" && (seg.clip === "Idle" || seg.clip === TURN);
        if (!standing) {
            left = seg.kind === "clip" && (seg.clip.startsWith("LookUp") || seg.clip.startsWith("LookingUp"))
                ? between(r, 10, 15) : null;
            out.push(seg);
            continue;
        }
        if (left === null) {
            left = between(r, 4, 10);
        }
        if (seg.clip !== "Idle") {
            out.push(seg);
            continue;
        }
        let t = seg.t0;
        while (seg.t1 - t > left + rest) {
            out.push(Object.assign({}, seg, { t0: t, t1: t + left }));
            out.push(Object.assign({}, seg, { clip: "Idle Rest", t0: t + left, t1: t + left + rest }));
            t += left + rest;
            left = between(r, 10, 15);
        }
        // A rest due too late in this stretch to be played out is due as soon as she stands
        // again, not earlier: that would start it before her next stretch does, out of order.
        left = Math.max(0, left - (seg.t1 - t));
        out.push(Object.assign({}, seg, { t0: t }));
    }
    return out;
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
    // What she feels like doing today: some days she floats down rather than drops, swims rather
    // than goes round, catches ledges rather than double jumps...
    // (the slow ways, the cloak and the slide down a wall, cost her less than their time: she likes them)
    const like = () => between(r, 0.6, 1.5);
    p.prefer({ walk: 1, drop: like(), jump: like(), jump2: like(), mantle: like(), mantle2: like(), float: between(r, 0.6, 1.2),
               climb: like(), slide: between(r, 0.2, 0.7), wade: like(), harpoon: like(), bounce: like() });
    p.style = { float: between(r, 0.04, 0.15), double: between(r, 0.05, 0.25), slide: between(r, 0.2, 0.6) };
    p.sleep(bed, wake, false, true); // asleep since last night: the day starts with her lying there

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
                    lookup: "curiosity", map: "curiosity", visit: "curiosity", kneel: "rest", swim: "curiosity" };
    const recent = [bed.id];
    let stuck = 0;
    // One thing she does: a wander, or an activity somewhere.
    const step = () => {
        const hour = ((p.t - day0) / 3600 + 4) % 24;
        // Lively in the morning, calmer by evening: how likely she is to sprint, or walk.
        p.energy = (hour < 12 ? 1.3 : hour < 18 ? 1.0 : 0.7) * between(r, 0.8, 1.2);
        if (r() < 0.35 && spots.length) {
            // Wandering: somewhere else for a moment (now and then strolling with her map open),
            // a look around, and on.
            const spot = spots[Math.floor(r() * spots.length)];
            if (p.goTo(spot.surface, spot.x, { gait: r() < 0.3 ? "map" : r() < 0.3 ? "walk" : undefined })) {
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
            w /= 1 + p.trip(q.surface, q.x) / 150;
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
    return { segments: withIdleRests(p.segments, clips, rng(dateKey * 13 + 5)), log: p.log, wake: wake, bedtime: bedtime };
}

// The day's plans (Hornet's and the Bell Beast's), made once per day, world build and clips.
let cache = { key: "", segments: [], beast: [], critters: { songs: [], flights: {} }, from: 0, until: 0 };

// The screens showing the world (WorldScene.qml), counted so that the plans and routes kept for
// them go with the last one: plasmashell lives for days, and lets go the scenes of a desktop
// that stays hidden, or of a wallpaper no longer chosen.
let scenes = 0;

function join() {
    scenes++;
}

function leave() {
    scenes--;
    if (scenes === 0) {
        routes = { key: "", starts: new Map() };
        cache = { key: "", segments: [], beast: [], critters: { songs: [], flights: {} }, from: 0, until: 0 };
    }
}

// ------------------------------------------------------------------ the Bell Beast

// How the Bell Beast is with Hornet, from the game (its tk2dLookAnimNPC and Interaction FSM):
// while she's within its look detector (BEAST_LOOK_X to either side, BEAST_LOOK_Y up or down) it
// faces her, turning a moment after she crosses its middle, and shakes every so often; back
// after a while away, she's greeted with a song; her needolin nearby, it sings along. Without her
// it faces its own way, left.
const BEAST_LOOK_X = 14;
const BEAST_LOOK_Y = 5;
const BEAST_REACT = [0.1, 0.3];      // its turn, this long after she crosses its middle
const BEAST_SHAKE = [5, 15];         // with her near, a shake now and then (its Idle's WaitRandom)
const BEAST_SING_REACT = [1.5, 3];   // her needolin: it sings along this long after she starts...
const BEAST_SING_STOP = [0.4, 0.6];  // ...and stops this long after she does (a second at least)
const BEAST_GREET_AFTER = 300;       // back after this long away, a song for her

// When Hornet is near the Bell Beast (in its look detector), on which side, and whether she's
// playing her needolin there: [{ t, near, left, perf, x }] at each change through her day (x:
// where she was then).
function hornetNear(world, segs, beast) {
    const out = [];
    let last = null;
    const x0 = beast.x - BEAST_LOOK_X;
    const x1 = beast.x + BEAST_LOOK_X;
    const y0 = beast.y - BEAST_LOOK_Y - 1;
    const y1 = beast.y + BEAST_LOOK_Y + 1;
    // Where she is to it: 0 out of its reach, 1 in it on its left, 2 on its right (and her x).
    const side = (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1 ? (x < beast.x ? 1 : 2) : 0;
    let x = 0;
    const sideOn = (seg, local, T) => {
        const at = placeOn(world, seg, local, local / Math.max(1e-6, T));
        x = at[0];
        return side(at[0], at[1]);
    };
    const note = (t, s, perf, at) => {
        if (!last || last.side !== s || s && last.perf !== perf) {
            last = { t: t, near: s > 0, left: s === 1, perf: perf, x: at, side: s };
            out.push(last);
        }
    };
    for (let i = 0; i < segs.length; i++) {
        const seg = segs[i];
        if (seg.kind === "clip") {
            const at = seg.pivot ? seg.pivot[0] : seg.x;
            const s = side(at, seg.pivot ? seg.pivot[1] : seg.y);
            note(seg.t0, s, s > 0 && (seg.clip.indexOf("Needolin Play") >= 0 || seg.clip.indexOf("NeedolinSit Play") >= 0), at);
            continue;
        }
        if (Math.max(seg.x0, seg.x1) < x0 - 1 || Math.min(seg.x0, seg.x1) > x1 + 1) {
            note(seg.t0, 0, false, seg.x0);
            continue;
        }
        // Where she is every half second, and to a twentieth of a second where that changes
        // (coming in, going out, passing it).
        const T = seg.t1 - seg.t0;
        let prev = sideOn(seg, 0, T);
        note(seg.t0, prev, false, x);
        const n = Math.max(1, Math.ceil(T / 0.5));
        for (let k = 1; k <= n; k++) {
            const local = k * T / n;
            const cur = sideOn(seg, local, T);
            const curX = x;
            if (cur !== prev) {
                let lo = (k - 1) * T / n;
                let hi = local;
                let then = cur;
                let thenX = curX;
                while (hi - lo > 0.05) {
                    const mid = (lo + hi) / 2;
                    const s = sideOn(seg, mid, T);
                    if (s === prev) {
                        lo = mid;
                    } else {
                        hi = mid;
                        then = s;
                        thenX = x;
                    }
                }
                if (hi < T) { // (else the next segment tells)
                    note(seg.t0 + hi, then, false, thenX);
                    if (then !== cur && local < T) {
                        note(seg.t0 + local, cur, false, curX);
                    }
                }
            }
            prev = cur;
        }
    }
    return out;
}

// The Bell Beast's day in its station, from Hornet's: it wakes a little after her, sings the
// hours, is with her as the game has it while she's near (above), and lies down to sleep in the
// evening. Clips are its own ("Bell Beast ..."); it doesn't move from its spot.
function planBeast(world, clips, day0, dateKey, hornet, nearby) {
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
    const sing = until => {
        push(right ? "Sing Right" : "Sing", Math.max(0.1, until - t));
        once(right ? "Sing End Right" : "Sing End");
    };

    const wake = hornet.wake + between(r, 600, 1500);
    const asleep = day0 + (17.5 + between(r, 0, 0.6)) * 3600; // 21:30-22:06
    push("Sleep", wake - t);
    once("Wake");
    // The hours it sings, 9 to 21.
    const songs = [];
    for (let h = 9; h <= 21; h++) {
        const at = day0 + (h - 4) * 3600;
        if (at > t && at < asleep - 60) {
            songs.push(at);
        }
    }
    let si = 0;
    // Hornet near it, through the day.
    const track = nearby || (world.beast && hornet.segments ? hornetNear(world, hornet.segments, world.beast) : []);
    let ti = 0;
    let near = false;
    let left = true;
    let perf = false;
    let away = -Infinity; // when she last went out of its range
    let turnDue = Infinity;
    let greetDue = Infinity;
    let singDue = Infinity;
    let shakeDue = Infinity;
    const catchUp = upTo => {
        while (ti < track.length && track[ti].t <= upTo) {
            const e = track[ti++];
            if (e.near && !near) {
                if (e.t - away > BEAST_GREET_AFTER) {
                    greetDue = e.t;
                }
                shakeDue = e.t + between(r, BEAST_SHAKE[0], BEAST_SHAKE[1]);
            } else if (!e.near && near) {
                away = e.t;
                greetDue = singDue = shakeDue = Infinity;
            }
            if (e.near && e.perf && !(near && perf)) {
                singDue = e.t + between(r, BEAST_SING_REACT[0], BEAST_SING_REACT[1]);
            } else if (!(e.near && e.perf)) {
                singDue = Infinity;
            }
            near = e.near;
            left = e.left;
            perf = e.perf;
        }
    };
    // When the needolin she's playing (from now) ends: the first change that ends it.
    const perfEnds = () => {
        for (let k = ti; k < track.length; k++) {
            if (!(track[k].near && track[k].perf)) {
                return track[k].t;
            }
        }
        return asleep;
    };
    while (t < asleep) {
        catchUp(t);
        const want = near && !left; // facing right only for her, on its right
        if (want === right) {
            turnDue = Infinity;
        } else if (turnDue === Infinity) {
            turnDue = t + between(r, BEAST_REACT[0], BEAST_REACT[1]);
        }
        const nextE = ti < track.length ? track[ti].t : Infinity;
        const song = si < songs.length ? songs[si] : Infinity;
        const next = Math.min(nextE, turnDue, greetDue, singDue, shakeDue, song, asleep);
        idle(next);
        t = Math.max(t, next);
        if (next >= asleep) {
            break;
        }
        if (next === song) {
            si++;
            sing(t + between(r, 5, 9));
        } else if (next === turnDue) {
            turnDue = Infinity;
            turn(near && !left);
        } else if (next === greetDue) {
            greetDue = Infinity;
            turn(near && !left); // (its look turned it as she came)
            sing(t + 1.0 + between(r, BEAST_SING_STOP[0], BEAST_SING_STOP[1]));
            shakeDue = t + between(r, BEAST_SHAKE[0], BEAST_SHAKE[1]);
        } else if (next === singDue) {
            singDue = Infinity;
            turn(near && !left);
            sing(Math.min(asleep - 30, Math.max(t + 1.0, perfEnds() + between(r, BEAST_SING_STOP[0], BEAST_SING_STOP[1]))));
            shakeDue = t + between(r, BEAST_SHAKE[0], BEAST_SHAKE[1]);
        } else if (next === shakeDue) {
            // (its shake is drawn looking left: it turns to its own way for it)
            turn(false);
            once("Shake");
            shakeDue = t + between(r, BEAST_SHAKE[0], BEAST_SHAKE[1]);
        }
    }
    // Lying down: waking played backwards, from looking left.
    turn(false);
    push("Wake", clipLength(clips, clip("Wake")), { reverse: true });
    push("Sleep", day0 + 24 * 3600 + 1 - t);
    return segs;
}

// ------------------------------------------------------------------ the beastlings

// The Bell Beast's children, the beastlings, who now and then come to their mother's station:
// two or three pop out of the station's floor (the game spawns 2-3, at its nodes) and play as
// the game has them (their Control FSM): idle a moment, then turn, leap about (towards their
// mother when they're far from her, away from each other when too close), stamp, or call; a
// beastling too far from her digs into the ground and pops out again by its node; they sing
// along to Hornet's needolin, sleep when their mother sleeps, wake with her, and dig away when
// they leave. Some days they don't come; some nights they stay, asleep by her.
const LING_G = 120;               // their gravity (Rigidbody2D gravity scale 2)
const LING_LEAP = [7, 15, 18];    // a leap: across, and up between these (their Leap state)
const LING_HOP = [1, 5];          // waking: a little hop
const LING_ROLL = [30, 35];       // popping out of the ground: up between these
const LING_FEET = 1.25;           // their pivot above the floor (as their nodes stand)
const LING_TOO_FAR = 15;          // from their mother: they dig back to her
const LING_CLOSE = 2;             // to each other: one leaps away
const LING_LINGER = 60;           // after a visit: the longest they may still be finishing a song

// A beastling's segment at time t: { clip, frame, x, y, facingRight }, or null where it's not out.
function lingPose(clips, floorY, seg, t) {
    const local = Math.max(0, t - seg.t0);
    let clip = seg.clip;
    let tc = local;
    let x = seg.x0;
    let y = floorY(seg.x0);
    if (seg.kind === "hop") {
        const s = Math.min(1, local / Math.max(1e-6, seg.t1 - seg.t0));
        x = lerp(seg.x0, seg.x1, s);
        y = lerp(floorY(seg.x0), floorY(seg.x1), s) + seg.vy * local - 0.5 * LING_G * local * local;
    } else if (seg.kind === "pop") {
        // Out of the ground curled up, unrolling at the top, diving down onto the floor.
        y = Math.max(floorY(seg.x0), seg.y0 + seg.vy * local - 0.5 * LING_G * local * local);
        const top = seg.vy / LING_G;
        if (local >= top) {
            const unroll = clipLength(clips, "Beastling RollToDive");
            clip = local - top < unroll ? "Beastling RollToDive" : "Beastling Dive";
            tc = local - top < unroll ? local - top : local - top - unroll;
        } else {
            clip = "Beastling Insta Roll";
        }
    } else if (seg.kind === "dig") {
        const s = Math.min(1, local / Math.max(1e-6, seg.t1 - seg.t0));
        y = floorY(seg.x0) - 2.2 * s * s; // curling up and diving into the ground
    }
    const c = clips[clip];
    if (!c) {
        return null;
    }
    return { clip: clip, frame: seg.hold ? Math.max(0, Math.min(c.frames - 1, frameAt(c, tc))) : frameAt(c, tc), x: x, y: y,
             facingRight: seg.facingRight };
}

// The beastlings' visits for the day: [{ t0, t1, kids: [[segment]] }], from their mother's day
// (when she sleeps) and Hornet's (when she plays her needolin near them).
function planBeastlings(world, clips, day0, dateKey, beastSegs, track) {
    const nodes = world.beastlings && world.beastlings.nodes;
    const beast = world.beast;
    if (!nodes || !nodes.length || !beast || !clips["Beastling Idle"]) {
        return [];
    }
    const r = rng(dateKey * 31 + 17);
    const nav = world.nav;
    // The station's floor they play on, and how far along it they go.
    const floor = nav.surfaces.find(sf => sf.x0 <= beast.x && beast.x <= sf.x1 && height(sf, beast.x, nav.step) < beast.y);
    if (!floor) {
        return [];
    }
    const lo = Math.max(floor.x0 + 1, beast.x - LING_TOO_FAR + 1);
    const hi = Math.min(floor.x1 - 1, beast.x + LING_TOO_FAR - 1);
    const floorY = x => height(floor, Math.min(Math.max(x, floor.x0), floor.x1), nav.step) + LING_FEET;
    // Their mother: when she's lying asleep (her first sleep, and from lying down at night).
    const woke = beastSegs.length > 1 ? beastSegs[0].t1 : day0;
    const lie = beastSegs.find(sg => sg.reverse);
    const liesDown = lie ? lie.t0 : day0 + 24 * 3600;
    const motherAsleep = t => t < woke || t >= liesDown;
    // Hornet playing her needolin near them: [t0, t1] stretches.
    const songs = []; // [t0, t1, where she plays]
    for (let k = 0; k < track.length; k++) {
        if (track[k].near && track[k].perf) {
            songs.push([track[k].t, k + 1 < track.length ? track[k + 1].t : day0 + 24 * 3600, track[k].x]);
        }
    }
    const songAt = t => {
        for (let k = 0; k < songs.length && songs[k][0] <= t + 1e-6; k++) {
            if (t < songs[k][1]) {
                return songs[k];
            }
        }
        return null;
    };
    const songFrom = t => {
        for (let k = 0; k < songs.length; k++) {
            if (songs[k][0] > t) {
                return songs[k];
            }
        }
        return null;
    };

    // When they come: some days not at all, else once or twice for a while; some nights they stay.
    const visits = [];
    const awakeFrom = woke + 600;
    const awakeTo = liesDown - 1800;
    const count = r() < 0.35 ? 0 : r() < 0.6 ? 1 : 2;
    for (let k = 0; k < count && awakeTo - awakeFrom > 3600; k++) {
        const t0 = between(r, awakeFrom, awakeTo - 1200);
        const t1 = Math.min(awakeTo, t0 + between(r, 1200, 5400));
        if (!visits.some(v => t0 < v.t1 + 600 && v.t0 < t1 + 600)) {
            visits.push({ t0: t0, t1: t1 });
        }
    }
    if (r() < 0.25 && lie) {
        // Over the night: they come in the evening and sleep by her, leaving before 04:00.
        const t0 = liesDown - between(r, 1800, 5400);
        if (!visits.some(v => t0 < v.t1 + 600)) {
            visits.push({ t0: t0, t1: day0 + 24 * 3600 - between(r, 1800, 3600) });
        }
    }
    visits.sort((a, b) => a.t0 - b.t0);
    visits.forEach((v, k) => {
        v.n = r() < 0.5 ? 2 : 3;
        v.seed = dateKey * 53 + 977 * (k + 1);
    });

    // What they do on a visit, worked out the first time it's needed (most visits are never on a
    // lock screen), from its own draw.
    const play = v => {
        const r = rng(v.seed);
        const n = v.n;
        // Their spots in a random order (shuffled the same in every JS engine, as a sort isn't).
        const order = nodes.map((nd, i) => i);
        for (let i = order.length - 1; i > 0; i--) {
            const j = Math.floor(r() * (i + 1));
            const swap = order[i];
            order[i] = order[j];
            order[j] = swap;
        }
        const kids = [];
        for (let i = 0; i < n; i++) {
            const node = nodes[order[i % nodes.length]];
            kids.push({ home: node[0], x: node[0], right: r() < 0.5, t: v.t0 + (i ? between(r, 1, 2) : 0), segs: [], asleep: false,
                        done: false });
        }
        const stay = (kid, clip, duration, hold) => {
            kid.segs.push({ kind: "stay", clip: "Beastling " + clip, t0: kid.t, t1: kid.t + duration, x0: kid.x,
                            facingRight: kid.right, hold: !!hold });
            kid.t += duration;
        };
        const once = (kid, clip) => stay(kid, clip, clipLength(clips, "Beastling " + clip));
        const hop = (kid, dx, vy, clip) => {
            const T = 2 * vy / LING_G;
            const x1 = Math.min(hi, Math.max(lo, kid.x + dx));
            kid.segs.push({ kind: "hop", clip: "Beastling " + clip, t0: kid.t, t1: kid.t + T, x0: kid.x, x1: x1, vy: vy,
                            facingRight: kid.right });
            kid.t += T;
            kid.x = x1;
        };
        const turn = (kid, right) => {
            if (right !== kid.right) {
                kid.right = right;
                once(kid, "Turn");
            }
        };
        // Out of the ground at its node: curled up, high, then down onto the floor.
        const popOut = kid => {
            kid.x = kid.home;
            const vy = between(r, LING_ROLL[0], LING_ROLL[1]);
            const y0 = floorY(kid.x) - 1;
            const T = (vy + Math.sqrt(vy * vy + 2 * LING_G * (y0 - floorY(kid.x)))) / LING_G;
            kid.segs.push({ kind: "pop", clip: "Beastling Insta Roll", t0: kid.t, t1: kid.t + T, x0: kid.x, y0: y0, vy: vy,
                            facingRight: kid.right });
            kid.t += T;
            once(kid, "Land");
        };
        const digAway = kid => {
            kid.segs.push({ kind: "dig", clip: "Beastling Dig Away", t0: kid.t, t1: kid.t + clipLength(clips, "Beastling Dig Away"),
                            x0: kid.x, facingRight: kid.right });
            kid.t += clipLength(clips, "Beastling Dig Away");
        };
        const othersNear = kid => {
            for (let k = 0; k < kids.length; k++) {
                const o = kids[k];
                if (o !== kid && !o.done && Math.abs(o.x - kid.x) < LING_CLOSE) {
                    return o;
                }
            }
            return null;
        };
        const leap = (kid, dir) => {
            if (kid.x + dir * 2.5 > hi || kid.x + dir * 2.5 < lo) {
                dir = -dir; // a wall that way
            }
            turn(kid, dir > 0);
            once(kid, "Leap Antic");
            const vy = between(r, LING_LEAP[1], LING_LEAP[2]);
            hop(kid, dir * LING_LEAP[0] * 2 * vy / LING_G, vy, "Leap");
            once(kid, "Land");
        };
        for (const kid of kids) {
            kid.right = r() < 0.5;
            popOut(kid);
        }
        v.kids = kids.map(k => k.segs);
        // Then on, one move at a time (the one due first), only as far as asked: a lock screen
        // shows a visit from wherever it is in it.
        v.upTo = until => {
            for (;;) {
                let kid = null;
                for (let k = 0; k < kids.length; k++) {
                    if (!kids[k].done && (!kid || kids[k].t < kid.t)) {
                        kid = kids[k];
                    }
                }
                if (!kid || kid.t > until) {
                    break;
                }
                const t = kid.t;
                if (t >= v.t1) {
                    // Leaving: digging away (waking first, if asleep).
                    if (kid.asleep) {
                        once(kid, "Antic");
                    }
                    digAway(kid);
                    kid.done = true;
                    continue;
                }
                if (motherAsleep(t)) {
                    // Asleep by her until she wakes (or they go).
                    const until = Math.min(v.t1, t < woke ? woke : day0 + 24 * 3600);
                    if (!kid.asleep) {
                        kid.asleep = true;
                        stay(kid, r() < 0.5 ? "Sleep 1" : "Sleep 2", Math.max(0.3, until - t), true);
                    } else {
                        stay(kid, kid.segs[kid.segs.length - 1].clip.replace("Beastling ", ""), Math.max(0.3, until - t), true);
                    }
                    continue;
                }
                if (kid.asleep) {
                    // Waking with their mother: a start, and a little hop.
                    kid.asleep = false;
                    stay(kid, "Idle", between(r, 0.2, 0.5));
                    once(kid, "Antic");
                    hop(kid, (kid.right ? 1 : -1) * LING_HOP[0] * 2 * LING_HOP[1] / LING_G, LING_HOP[1], "Leap");
                    once(kid, "Land");
                    continue;
                }
                const song = songAt(t);
                if (song) {
                    // Singing along to her needolin, turned to her.
                    stay(kid, "Idle", between(r, 0.75, 1.0));
                    const second = r() < 0.5 ? " 2" : "";
                    if ((song[2] > kid.x) !== kid.right) {
                        kid.right = song[2] > kid.x;
                        once(kid, "TurnToSing" + second);
                    }
                    stay(kid, "Sing" + second, Math.max(0.5, song[1] + between(r, 0.5, 1.0) - kid.t));
                    once(kid, "Sing End");
                    continue;
                }
                // A moment idle (cut short if she starts playing), then something.
                const next = songFrom(t);
                stay(kid, "Idle", Math.max(0.2, Math.min(between(r, 0.5, 2.0), next ? next[0] + 0.75 - t : Infinity, v.t1 - t)));
                if (kid.t >= v.t1 || songAt(kid.t)) {
                    continue;
                }
                const close = othersNear(kid);
                if (close) {
                    leap(kid, kid.x >= close.x ? 1 : -1); // away from it
                } else if (Math.abs(kid.x - beast.x) > LING_TOO_FAR || r() < 0.05) {
                    digAway(kid); // back to her, by its node
                    kid.t += 0.4 + between(r, 0.5, 1.0);
                    popOut(kid);
                } else {
                    const pick = r() * 2.5; // turn 0.5, leap 1, stamp 0.5, call 0.5
                    if (pick < 0.5) {
                        turn(kid, !kid.right);
                    } else if (pick < 1.5) {
                        // Towards their mother when they're away from her, else either way; once or a
                        // few times.
                        let leaps = 1 + (r() < 0.5 ? 1 : 0) + (r() < 0.25 ? 1 : 0);
                        while (leaps-- > 0 && kid.t < v.t1) {
                            const dir = Math.abs(kid.x - beast.x) > 7 ? (beast.x > kid.x ? 1 : -1) : r() < 0.5 ? 1 : -1;
                            leap(kid, dir);
                        }
                    } else if (pick < 2.0) {
                        stay(kid, "Stamp", between(r, 1.0, 1.5));
                        once(kid, "Recover");
                    } else {
                        stay(kid, "Sing", 0.5); // a call
                        stay(kid, "Sing", 0.5, true);
                        once(kid, "Sing End");
                    }
                }
            }
        };
    };
    return { visits: visits, floorY: floorY, floor: floor, play: play };
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

// When what beastAt() shows next changes after t (seconds since the epoch). Its day is back to
// back, the last of it running on to the next 04:00, where the next day's takes over.
function beastNext(world, clips, t) {
    if (!world || !world.nav || !clips || !clips["Bell Beast Sleep"]) {
        return Infinity;
    }
    daySegments(world, clips, t);
    const segs = cache.beast;
    const i = segmentIndex(segs, t);
    const until = cache.until / 1000;
    return nextCellChange(clips, segs[i], t, i + 1 < segs.length ? Math.min(segs[i].t1, until) : until);
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

// A visit's beastlings, worked out up to time until if they aren't yet: [segments] for each.
function kidsOn(plan, v, until) {
    if (!v.kids) {
        plan.play(v);
    }
    v.upTo(until);
    return v.kids;
}

// The beastlings out at time t: [{ clip, frame, x, y, facingRight }] (none on most of the day).
function beastlingsAt(world, clips, t) {
    if (!world || !world.nav || !clips) {
        return [];
    }
    daySegments(world, clips, t);
    const plan = cache.beastlings;
    const out = [];
    if (!plan || !plan.visits) {
        return out;
    }
    for (let i = 0; i < plan.visits.length; i++) {
        const v = plan.visits[i];
        if (t < v.t0 || t > v.t1 + LING_LINGER) {
            continue;
        }
        const kids = kidsOn(plan, v, t + 1);
        for (let k = 0; k < kids.length; k++) {
            const segs = kids[k];
            if (!segs.length || t < segs[0].t0 || t >= segs[segs.length - 1].t1) {
                continue;
            }
            const seg = segs[segmentIndex(segs, t)];
            const pose = t < seg.t1 ? lingPose(clips, plan.floorY, seg, t) : null; // (between digging in and out: underground)
            if (pose) {
                pose.id = k; // the same beastling from one moment to the next
                out.push(pose);
            }
        }
    }
    return out;
}

// When what beastlingsAt() shows next changes after t: t while one moves through the air or the
// ground, else its clip's next cell, or the next visit.
function beastlingsNext(world, clips, t) {
    if (!world || !world.nav || !clips) {
        return Infinity;
    }
    daySegments(world, clips, t);
    const plan = cache.beastlings;
    if (!plan || !plan.visits) {
        return Infinity;
    }
    let next = Infinity;
    for (let i = 0; i < plan.visits.length; i++) {
        const v = plan.visits[i];
        if (t < v.t0) {
            next = Math.min(next, v.t0);
            continue;
        }
        if (t > v.t1 + LING_LINGER) {
            continue;
        }
        const kids = kidsOn(plan, v, t + 1);
        for (let k = 0; k < kids.length; k++) {
            const segs = kids[k];
            if (!segs.length || t >= segs[segs.length - 1].t1) {
                continue;
            }
            if (t < segs[0].t0) {
                next = Math.min(next, segs[0].t0);
                continue;
            }
            const at = segmentIndex(segs, t);
            const seg = segs[at];
            if (t >= seg.t1 && at + 1 < segs.length) {
                next = Math.min(next, segs[at + 1].t0); // underground until it pops out again
                continue;
            }
            if (seg.kind !== "stay") {
                return t;
            }
            next = Math.min(next, seg.hold ? Math.min(seg.t1, nextCellChange(clips, seg, t, seg.t1)) : nextCellChange(clips, seg, t, seg.t1));
        }
    }
    return next;
}

// The beastlings' clips from t to t + horizon seconds.
function beastlingClipsAhead(world, clips, t, horizon) {
    if (!world || !world.nav || !clips) {
        return [];
    }
    daySegments(world, clips, t);
    const plan = cache.beastlings;
    const names = {};
    if (plan && plan.visits) {
        for (const v of plan.visits) {
            if (v.t1 + LING_LINGER < t || v.t0 > t + horizon) {
                continue;
            }
            for (const segs of kidsOn(plan, v, t + horizon)) {
                for (let i = segs.length && t > segs[0].t0 ? segmentIndex(segs, t) : 0; i < segs.length && segs[i].t0 < t + horizon; i++) {
                    names[segs[i].clip] = true;
                    if (segs[i].kind === "pop") {
                        names["Beastling RollToDive"] = names["Beastling Dive"] = true;
                    }
                }
            }
        }
    }
    return Object.keys(names).filter(n => clips[n] !== undefined).sort();
}

// ------------------------------------------------------------------ small life

// The grotto's moss flies and dragonflies, Verdania's lilypad flies (tools/world.py CRITTERS),
// as functions of time, so every screen sees them alike. Hornet's day sets what they react to:
// the songs she plays on her needolin (dragonflies hold still, lilypad flies sing along) and the
// moments she comes close to a lilypad fly (it flies to its next perch).
const SONG_REACH = 20;   // units: how far her needolin is heard (across the lake)
const STARTLE = 2.0;     // units: how close she comes before a lilypad fly takes off
const FLIGHT_SPEED = 4.5;

function hashOf(a, b, c) {
    const x = Math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453;
    return x - Math.floor(x);
}

function idNumber(id) {
    let n = 0;
    for (let i = 0; i < id.length; i++) {
        n = (n * 31 + id.charCodeAt(i)) % 100003;
    }
    return n;
}

// Whether she's within reach of a lilypad fly's perch at t, on a segment she moves along: where
// pose() puts her (the same arithmetic, without the rest of the pose).
function startles(world, seg, t, perch) {
    const local = t - seg.t0;
    const at = placeOn(world, seg, local, Math.min(1, Math.max(0, local / Math.max(1e-6, seg.t1 - seg.t0))));
    return at !== null && Math.abs(at[0] - perch[0]) < STARTLE && Math.abs(at[1] - world.heroFeet - perch[1]) < 1.6;
}

// The first entry of a perch's list (move indices, in order) at or after move `pos` that ends at
// or after `free`: both rise along the list.
function firstFrom(list, moves, pos, free, k) {
    let hi = list.length;
    while (k < hi) {
        const mid = (k + hi) >> 1;
        if (list[mid] >= pos && moves[list[mid]].t1 >= free) {
            hi = mid;
        } else {
            k = mid + 1;
        }
    }
    return k;
}

// From Hornet's day: her songs ([t0, t1, x, y]) and, for each lilypad fly, its flights
// ({ t0, t1, from, to } perch indices) as she comes close to the perch it's on.
function planCritters(world, clips, segs) {
    const songs = [];
    // Where she moves (walks, lines, falls, jumps), in order, and for each perch of each lilypad
    // fly, those of her moves that pass near enough to it to matter (by their ends' x).
    const flies = (world.critters || []).filter(c => c.species === "lilypad_fly" && c.perches.length >= 2);
    const near = flies.map(c => c.perches.map(() => []));
    const moves = [];
    segs.forEach(seg => {
        if (seg.kind === "clip") {
            if (seg.clip.indexOf("Needolin Play") >= 0 || seg.clip.indexOf("NeedolinSit Play") >= 0) {
                songs.push([seg.t0, seg.t1, seg.x, seg.y]);
            }
            return;
        }
        if (!(seg.kind === "walk" || seg.kind === "line" || seg.kind === "fall" || seg.kind === "jump" || seg.kind === "glide"
              || seg.kind === "wallslide" || seg.kind === "wallhop")) {
            return;
        }
        const i = moves.length;
        moves.push(seg);
        for (let f = 0; f < flies.length; f++) {
            const perches = flies[f].perches;
            for (let p = 0; p < perches.length; p++) {
                if (!(seg.x0 !== undefined && Math.min(seg.x0, seg.x1) - STARTLE > perches[p][0]
                    || seg.x0 !== undefined && Math.max(seg.x0, seg.x1) + STARTLE < perches[p][0])) {
                    near[f][p].push(i);
                }
            }
        }
    });
    const flights = {};
    flies.forEach((c, f) => {
        const out = [];
        let at = 0;
        let free = -Infinity;
        let pos = 0; // the next of her moves to look at
        const next = c.perches.map(() => 0); // where each perch's list was left
        for (;;) {
            // Her next move near the perch it's on, once it minds her again.
            const list = near[f][at];
            const k = firstFrom(list, moves, pos, free, next[at]);
            if (k >= list.length) {
                break;
            }
            next[at] = k + 1;
            const seg = moves[list[k]];
            pos = list[k] + 1;
            const perch = c.perches[at];
            // Where she is along the segment, every 0.2 s, until she comes close.
            for (let t = Math.max(seg.t0, free); t < seg.t1; t += 0.2) {
                if (startles(world, seg, t, perch)) {
                    const to = (at + 1) % c.perches.length;
                    const d = Math.hypot(c.perches[to][0] - perch[0], c.perches[to][1] - perch[1]);
                    const dur = 0.4 + d / FLIGHT_SPEED;
                    out.push({ t0: t, t1: t + dur, from: at, to: to });
                    at = to;
                    free = t + dur + 90; // it settles a while before it minds her again
                    break;
                }
            }
        }
        flights[c.id] = out;
    });
    return { songs: songs, flights: flights };
}

// The song she's playing at t within reach of (x, y), or null.
function songAt(plan, t, x, y) {
    // The songs are in order and never overlap (she plays one at a time): only the last one
    // started by t can be playing.
    const i = lastStarted(plan.songs, t) - 1;
    const s = plan.songs[i];
    if (s && s[0] <= t && t < s[1] && Math.abs(s[2] - x) < SONG_REACH && Math.abs(s[3] - y) < SONG_REACH) {
        return s;
    }
    return null;
}

// How many of these songs ([t0, ...], in order) started before t (strictly, or at t too).
function lastStarted(songs, t, strict) {
    let lo = 0;
    let hi = songs.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (strict ? songs[mid][0] < t : songs[mid][0] <= t) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

// The time a dragonfly has spent flying by t: its clock stops while she plays near it.
function dragonflyTime(plan, t, c) {
    // The songs it hears, and how long all those before each one lasted, added up in their order
    // (so each sum is the running total's, to the last bit): found once per day and creature.
    plan.heard = plan.heard || {};
    let heard = plan.heard[c.id];
    if (!heard) {
        const songs = plan.songs.filter(s => Math.abs(s[2] - c.home[0]) < SONG_REACH && Math.abs(s[3] - c.home[1]) < SONG_REACH);
        const before = [0];
        songs.forEach(s => before.push(before[before.length - 1] + (s[1] - s[0])));
        heard = plan.heard[c.id] = { songs: songs, before: before };
    }
    // The songs before t: all over but the last, which may still be playing.
    const n = lastStarted(heard.songs, t, true);
    if (n === 0) {
        return t;
    }
    const s = heard.songs[n - 1];
    return t - (heard.before[n - 1] + (Math.min(t, s[1]) - s[0]));
}

function catmull(p0, p1, p2, p3, u) {
    const u2 = u * u, u3 = u2 * u;
    return 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3);
}

function critterPose(world, clips, plan, c, t) {
    // What doesn't change with time (its number, period, phase), and the points it flies through
    // until the next one, kept per day and creature: found again only when they change.
    plan.memo = plan.memo || {};
    let m = plan.memo[c.id];
    if (!m) {
        m = plan.memo[c.id] = { n: idNumber(c.id), k: NaN };
    }
    const n = m.n;
    const tw = t % 3600; // for frames: an hourly wrap in a clip is never seen (positions use t itself)
    const out = { id: c.id, layer: c.layer, zone: c.zone, scale: c.scale, tint: c.tint || null, clip: "", frame: 0,
                  x: 0, y: 0, facingRight: false };
    if (c.species === "moss_fly") {
        // The game's TinyMossFly: a new point within its range every 0.75-1 s, flown to and
        // through smoothly, facing the way it goes.
        if (m.period === undefined) {
            m.period = 0.75 + 0.25 * hashOf(n, 1, 0);
            m.phase = hashOf(n, 4, 4);
        }
        const period = m.period;
        const k = Math.floor(t / period);
        const u = t / period - k;
        if (m.k !== k) {
            const point = (j, axis) => {
                const a = hashOf(n, j, 2) * 2 * Math.PI, r = Math.sqrt(hashOf(n, j, 3));
                return c.home[axis] + c.range[axis] * r * (axis ? Math.sin(a) : Math.cos(a));
            };
            m.k = k;
            m.xs = [k - 1, k, k + 1, k + 2].map(j => point(j, 0));
            m.ys = [point(k - 1, 1), point(k, 1), point(k + 1, 1), point(k + 2, 1)];
        }
        const xs = m.xs, ys = m.ys;
        out.x = catmull(xs[0], xs[1], xs[2], xs[3], u);
        out.y = catmull(ys[0], ys[1], ys[2], ys[3], u);
        out.facingRight = xs[2] > xs[1];
        out.clip = "Moss Fly Fly";
        out.frame = frameAt(clips[out.clip], tw + m.phase);
    } else if (c.species === "dragonfly") {
        // Hovering, then a dart up, down, left or right (its FSM's Up, Down, L and R), turning
        // the way it darts; all of it holding still while she plays near.
        const tau = dragonflyTime(plan, t, c);
        if (m.period === undefined) {
            m.period = 1.3 + 0.7 * hashOf(n, 5, 0);
            m.phase = hashOf(n, 9, 9);
        }
        const period = m.period;
        const k = Math.floor(tau / period);
        const u = tau - k * period;
        if (m.k !== k) {
            const X = j => c.home[0] + c.range[0] * (2 * hashOf(n, j, 6) - 1);
            const Y = j => c.home[1] + c.range[1] * (2 * hashOf(n, j, 7) - 1);
            const at = j => [X(Math.floor((j + 1) / 2)), Y(Math.floor(j / 2))];
            m.k = k;
            m.start = period * (0.45 + 0.25 * hashOf(n, k, 8)); // the dart ends within the hop
            m.a = at(k);
            m.b = at(k + 1);
            // Which way it faces, before its dart and after (only even hops turn it).
            const before = Math.floor((k + 1) / 2);
            m.faceBefore = X(before) > X(before - 1);
            const after = Math.floor((k + 2) / 2);
            m.faceAfter = X(after) > X(after - 1);
        }
        const s = Math.min(1, Math.max(0, (u - m.start) / 0.3));
        const e = s * s * (3 - 2 * s);
        const a = m.a, b = m.b;
        out.x = lerp(a[0], b[0], e);
        out.y = lerp(a[1], b[1], e);
        out.facingRight = k % 2 === 0 && s > 0 ? m.faceAfter : m.faceBefore;
        out.clip = "Dragonfly Idle";
        out.frame = frameAt(clips[out.clip], tw + m.phase);
    } else if (c.species === "lilypad_fly") {
        const fl = (plan.flights[c.id] || []);
        let perch = 0;
        let flying = null;
        // Its flights are in order, apart (it settles 90 s after each): the last one begun by t
        // is the one it's in, or the one that brought it to its perch.
        let lo = 0;
        let hi = fl.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (fl[mid].t0 > t) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        if (lo > 0) {
            const f = fl[lo - 1];
            if (t < f.t1) {
                flying = f;
            } else {
                perch = f.to;
            }
        }
        if (flying) {
            // To the next perch in a low arc.
            const a = c.perches[flying.from], b = c.perches[flying.to];
            const s = (t - flying.t0) / (flying.t1 - flying.t0);
            const e = s * s * (3 - 2 * s);
            out.x = lerp(a[0], b[0], e);
            out.y = lerp(a[1], b[1], e) + c.feet * c.scale + Math.sin(Math.PI * s) * (1.2 + 0.15 * Math.abs(b[0] - a[0]));
            out.facingRight = b[0] > a[0];
            out.clip = "Lilypad Fly Fly";
            out.frame = frameAt(clips[out.clip], t - flying.t0);
        } else {
            const p = c.perches[perch];
            out.x = p[0];
            out.y = p[1] + c.feet * c.scale;
            out.facingRight = p[2];
            const song = songAt(plan, t, p[0], p[1]);
            if (song) {
                out.clip = "Lilypad Fly Sing";
                out.facingRight = song[2] > p[0];
                out.frame = frameAt(clips[out.clip], t - song[0]);
            } else {
                // One of its three idles, a few seconds each.
                const slot = Math.floor(tw / 7.5);
                out.clip = "Lilypad Fly Idle 0" + (1 + Math.floor(hashOf(n, slot, 10) * 3));
                out.frame = frameAt(clips[out.clip], tw - slot * 7.5);
            }
        }
    }
    return clips[out.clip] ? out : null;
}

// The creatures (default: all of them) at time t, in the world's order.
function crittersAt(world, clips, t, which) {
    return critterPosesAt(world, clips, t, which || (world && world.critters)).filter(p => p !== null);
}

// The same, one entry per creature of `which`, in its order (null for one that can't be drawn).
function critterPosesAt(world, clips, t, which) {
    if (!world || !world.nav || !world.critters || !clips) {
        return [];
    }
    daySegments(world, clips, t);
    const out = new Array(which.length);
    for (let i = 0; i < which.length; i++) {
        out[i] = critterPose(world, clips, cache.critters, which[i], t);
    }
    return out;
}

// The clips a set of creatures can play.
const CRITTER_CLIPS = {
    moss_fly: ["Moss Fly Fly"],
    dragonfly: ["Dragonfly Idle"],
    lilypad_fly: ["Lilypad Fly Idle 01", "Lilypad Fly Idle 02", "Lilypad Fly Idle 03", "Lilypad Fly Sing", "Lilypad Fly Fly"],
};

function critterClips(clips, which) {
    const names = {};
    for (const c of which) {
        for (const n of CRITTER_CLIPS[c.species] || []) {
            if (clips[n]) {
                names[n] = true;
            }
        }
    }
    return Object.keys(names).sort();
}

// ------------------------------------------------------------------ sampling

function lerp(a, b, t) {
    return a + (b - a) * t;
}

// Where a segment she moves along has her `local` seconds into it (s: the share of it gone by):
// [x, y], y her pivot; null for a pose held in one place.
function placeOn(world, seg, local, s) {
    switch (seg.kind) {
    case "walk": {
        const x = lerp(seg.x0, seg.x1, s);
        return [x, height(world.nav.surfaces[seg.surface], x, world.nav.step) + world.heroFeet];
    }
    case "line":
        return [lerp(seg.x0, seg.x1, s), lerp(seg.y0, seg.y1, s)];
    case "fall":
        return [lerp(seg.x0, seg.x1, s), Math.max(seg.y1, seg.y0 - fallDistance(local))];
    case "glide": {
        // A moment's fall while the cloak opens, then the slow sink under it.
        const dy = local < FLOAT_OPEN ? 0.5 * GRAVITY * local * local
            : 0.5 * GRAVITY * FLOAT_OPEN * FLOAT_OPEN + (local - FLOAT_OPEN) * FLOAT_SPEED;
        return [lerp(seg.x0, seg.x1, s), Math.max(seg.y1, seg.y0 - dy)];
    }
    case "wallslide": {
        const u = Math.max(0, local - WALLSLIDE_STICK);
        return [seg.x0, Math.max(seg.y1, seg.y0 - 0.5 * WALLSLIDE_ACCEL * u * u)];
    }
    case "wallhop":
        // Kicked off the wall and back onto it, higher: out and in, up with an arc.
        return [seg.x0 + seg.out * Math.sin(Math.PI * s), lerp(seg.y0, seg.y1, s) + 4 * s * (1 - s) * seg.lift];
    case "jump":
        return [lerp(seg.x0, seg.x1, s), jumpY(seg.plan, seg.y0, local)];
    }
    return null;
}

// Pose at time t: { clip, frame, x, y, facingRight, scale, angle, needle, thread }.
// needle: { x, y, angle } of her thrown needle; thread: [x0, y0, x1, y1] of its silk.
function pose(world, clips, seg, t) {
    const local = t - seg.t0;
    const s = Math.min(1, Math.max(0, local / Math.max(1e-6, seg.t1 - seg.t0)));
    const out = { clip: seg.clip, frame: 0, x: 0, y: 0, facingRight: seg.facingRight, scale: 1, angle: 0,
                  needle: null, thread: null };
    let tc = local; // time into the clip shown
    const fps = name => clips[name] ? clips[name].fps : 15;
    const at = placeOn(world, seg, local, s);
    if (at) {
        out.x = at[0];
        out.y = at[1];
    }
    switch (seg.kind) {
    case "walk":
    case "wallslide":
        break;
    case "line":
        if (seg.tilt) {
            const a = Math.atan2(seg.y1 - seg.y0, Math.abs(seg.x1 - seg.x0)) * 180 / Math.PI;
            out.angle = Math.max(-60, Math.min(60, a));
        }
        break;
    case "fall":
        tc = local + (seg.from || 0) / fps(seg.clip); // (Airborne from its falling frames)
        break;
    case "wallhop":
        if (s > 0.5) {
            out.clip = seg.second; // turning back towards the wall
            tc = local - 0.5 * (seg.t1 - seg.t0);
        }
        break;
    case "glide": {
        // The cloak opening, held open, folded away just before she lands.
        if (!clips["Umbrella Float"]) {
            break; // (an older extract.py: she just falls)
        }
        const antic = clipLength(clips, "Umbrella Inflate Antic");
        const inflate = clipLength(clips, "Umbrella Inflate");
        const deflate = clipLength(clips, "Umbrella Deflate");
        const T = seg.t1 - seg.t0;
        if (local < antic) {
            out.clip = "Umbrella Inflate Antic";
        } else if (local < antic + inflate) {
            out.clip = "Umbrella Inflate";
            tc = local - antic;
        } else if (local >= T - deflate) {
            out.clip = "Umbrella Deflate";
            tc = local - (T - deflate);
        } else {
            tc = local - antic - inflate;
        }
        break;
    }
    case "jump": {
        const p = seg.plan;
        const top = seg.second ? p.tB : p.tA;
        if (seg.second && local >= p.tA) {
            // The double jump: her wings at the top of the first, then falling.
            const len = clipLength(clips, seg.second);
            if (local < p.tA + len) {
                out.clip = seg.second;
                tc = local - p.tA;
            } else {
                out.clip = seg.fall || seg.clip;
                tc = local - p.tA - len + (seg.fallFrom || 0) / fps(out.clip);
            }
        } else if (seg.fall && local >= top) {
            out.clip = seg.fall;
            tc = local - top + (seg.fallFrom || 0) / fps(seg.fall);
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

// What the plans take from the clips, how many there are and how long they play: the day is
// planned again for new ones (tools/extract.py run again), not for each screen's copy of the
// same. Worked out once per copy and kept on it, where listing its clips doesn't find it.
function clipsSignature(clips) {
    if (clips.planSignature === undefined) {
        const names = Object.keys(clips);
        let length = 0;
        for (let i = 0; i < names.length; i++) {
            length += clipLength(clips, names[i]);
        }
        Object.defineProperty(clips, "planSignature", { value: names.length + ":" + length });
    }
    return clips.planSignature;
}

// The day's segments, planned once per day (and per world build and clips).
function daySegments(world, clips, t) {
    // Most calls are for the day planned last: t (in milliseconds, as new Date(t * 1000) holds
    // it) between its 04:00 and the next, the same world build and clips. Only otherwise is the
    // date worked out, which takes the QML engine longer than all the rest.
    const ms = Math.trunc(t * 1000);
    const signature = clipsSignature(clips);
    if (ms >= cache.from && ms < cache.until && cache.build === (world.build || 0)
        && cache.surfaces === world.nav.surfaces.length && cache.links === world.nav.links.length
        && cache.clips === signature) {
        return cache.segments;
    }
    const start = dayStart(new Date(t * 1000));
    const dateKey = start.getFullYear() * 10000 + (start.getMonth() + 1) * 100 + start.getDate();
    const key = dateKey + ":" + (world.build || 0) + ":" + world.nav.surfaces.length + ":" + world.nav.links.length
        + ":" + signature;
    if (cache.key !== key) {
        const plan = planDay(world, clips, start.getTime() / 1000, dateKey);
        const track = world.beast ? hornetNear(world, plan.segments, world.beast) : [];
        const beast = planBeast(world, clips, start.getTime() / 1000, dateKey, plan, track);
        cache = { key: key, segments: plan.segments, beast: beast,
                  beastlings: planBeastlings(world, clips, start.getTime() / 1000, dateKey, beast, track),
                  critters: planCritters(world, clips, plan.segments) };
    }
    cache.from = start.getTime();
    cache.until = dayStart(new Date(start.getTime() + 30 * 3600 * 1000)).getTime(); // the next 04:00
    cache.build = world.build || 0;
    cache.surfaces = world.nav.surfaces.length;
    cache.links = world.nav.links.length;
    cache.clips = signature;
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

// Whether two poses show her alike (with her needle out, a moment's flight, they never do).
function samePose(a, b) {
    return a.clip === b.clip && a.frame === b.frame && a.x === b.x && a.y === b.y && a.facingRight === b.facingRight
        && a.scale === b.scale && a.angle === b.angle && a.needle === null && b.needle === null
        && a.thread === null && b.thread === null;
}

// Hornet at time t (seconds since the epoch). While nothing in her pose changes (asleep, standing
// on one frame) it's the same object as last time, kept on the world it was asked for (each screen
// has its own copy), so that what's bound to it isn't worked out again for nothing.
function hornetAt(world, clips, t) {
    if (!world || !world.nav || !clips) {
        return null;
    }
    const segs = daySegments(world, clips, t);
    const p = pose(world, clips, segs[segmentIndex(segs, t)], t);
    const last = world.lastPose;
    if (last !== undefined && samePose(p, last)) {
        return last;
    }
    world.lastPose = p;
    return p;
}

// When what hornetAt() shows next changes after t (seconds since the epoch): t itself while she
// moves (or her needle flies), else when her clip next shows another cell of its sheet, or the
// end of her segment when it holds one (asleep, at the desk, a clip played to its end). A screen
// she's on only needs drawing again then (or at its own effects' rate), instead of every frame.
function hornetChangesAt(world, clips, t) {
    if (!world || !world.nav || !clips) {
        return Infinity;
    }
    const segs = daySegments(world, clips, t);
    const seg = segs[segmentIndex(segs, t)];
    // Her day is back to back, the last of it running past the next 04:00, where the next day's
    // plan takes over.
    const end = Math.min(seg.t1, cache.until / 1000);
    if (seg.kind !== "clip" || seg.needle) {
        return t;
    }
    return Math.max(t, nextCellChange(clips, seg, t, end));
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
        for (const n of [seg.clip, seg.second, seg.fall, seg.antic].concat(seg.also || [])) {
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

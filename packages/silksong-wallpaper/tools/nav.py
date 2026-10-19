"""Navigation map of the aquarium: where Hornet can stand and how she gets from one place to another.

The world's rock (the same polygons that are drawn) is rasterised; surfaces are runs of rock with
room for Hornet above, and the water's surface where it's deep enough to swim. Links between them
are the ways she has in the game, sized with her real movement (HeroController, its Sprint and
Umbrella Float FSMs, HeroWaterController and Physics2D settings): drops (running off an edge she
lands further out), jumps and double jumps, a ledge caught at the top of a jump and climbed onto
(mantle), the Drifter's Cloak opened on the way down (float), wall climbs and wall slides, wading
in and out of the water. Nothing is hidden: no ground or wall exists that isn't drawn, bezels
included.
"""
import numpy as np
from PIL import Image, ImageDraw

NAV_PPU = 8  # raster cells per unit
STEP = 0.25  # surface sampling in the output, units
HEADROOM = 2.6  # Hornet's height with a little margin
MAX_SLOPE = 0.15  # height change between neighbouring cells (1/8 unit apart) that still counts as walking: about 50°
STEP = 0.5  # a step this high between two surfaces is walked over, higher ones are jumped
MIN_SURFACE = 1.5  # shorter ledges are ignored

GRAVITY = 60.0  # Physics2D gravity, Rigidbody2D gravityScale 1
JUMP_SPEED = 18.6  # held for JUMP_STEPS physics steps, then ballistic
JUMP_HOLD = 8 / 50  # JUMP_STEPS at Unity's 50 Hz fixed step
JUMP_HEIGHT = JUMP_SPEED * JUMP_HOLD + JUMP_SPEED ** 2 / (2 * GRAVITY)  # about 5.9
JUMP_MAX = JUMP_HEIGHT - 0.6  # keep a margin for a believable landing
DOUBLE_JUMP_MAX = JUMP_MAX + 2.6  # the Faydown Cloak's second jump (DOUBLE_JUMP_RISE_STEPS)
DOUBLE_JUMP_SPEED = 15.0  # the second jump, as life.js plays it: this fast, held this long
DOUBLE_JUMP_HOLD = 0.12
DOUBLE_JUMP_RISE = DOUBLE_JUMP_SPEED * DOUBLE_JUMP_HOLD + DOUBLE_JUMP_SPEED ** 2 / (2 * GRAVITY)  # about 3.7
MAX_FALL = 30.0
RUN_SPEED = 8.25
WALK_SPEED = 5.0
CLIMB_MAX = 14.0  # a wall climb (cling and walljumps) up to this height
MANTLE_REACH = 1.0  # a ledge this far above the top of her jump is caught with her hands and climbed onto
MANTLE_MAX = JUMP_MAX + 0.6 + MANTLE_REACH  # (with the same margin as a landing)
MANTLE2_MAX = DOUBLE_JUMP_MAX + 0.6 + MANTLE_REACH  # the same, at the top of a double jump
FLOAT_SPEED = 3.0  # how fast she sinks under the Drifter's Cloak (HeroController.FLOAT_SPEED)
FLOAT_OPEN = 0.3  # she falls this long before it's open (Umbrella Inflate Antic and Inflate)
FLOAT_MIN = 4.0  # lower drops aren't worth opening it
FLOAT_MAX = 22.0  # she drifts at most this far across under it
WALLSLIDE_ACCEL = 24.0  # down a wall (HeroController.WALLSLIDE_ACCEL), after sticking to it a moment
WALLSLIDE_STICK = 0.15
SWIM_DEPTH = 1.2  # water this deep is swum, shallower she doesn't go into
# Swimming, the game holds her pivot 0.4 above its water region (SurfaceWaterRegion), whose drawn
# surface is 0.35 above it: her pivot just above the water's surface, her feet this far under it.
SWIM_SINK = 1.5
WATER_JUMP_LIFT = 1.0  # jumping out, she's lifted this much first (HeroWaterController.jumpTranslateHeight)
SWIM_SPEED = 5.0  # HeroWaterController.swimSpeed
WADE_GAP = 2.5  # from the end of a shore this far out to where the water is deep enough

def fall_time(h):
    """Time to fall h units from rest (capped at MAX_FALL)."""
    if h <= 0:
        return 0.0
    t_cap = MAX_FALL / GRAVITY
    h_cap = 0.5 * GRAVITY * t_cap ** 2
    return float(np.sqrt(2 * h / GRAVITY)) if h <= h_cap else t_cap + (h - h_cap) / MAX_FALL


def jump_time(rise):
    """Time from take-off to landing on a ledge `rise` units higher (rise may be negative)."""
    up = JUMP_HOLD + JUMP_SPEED / GRAVITY
    return up + fall_time(max(0.0, JUMP_HEIGHT - rise))


def jump2_time(rise):
    """Time from take-off to landing on a ledge `rise` units higher with the whole of her second
    jump, at the top of the first: as long as she can stay up, for the furthest reach."""
    up = JUMP_HOLD + JUMP_SPEED / GRAVITY + DOUBLE_JUMP_HOLD + DOUBLE_JUMP_SPEED / GRAVITY
    return up + fall_time(max(0.0, JUMP_HEIGHT + DOUBLE_JUMP_RISE - rise))


def jump_reach(rise):
    """How far across a jump at run speed carries her onto a ledge `rise` units higher (rise may
    be negative): her flight time at run speed."""
    return RUN_SPEED * jump_time(rise)


def float_time(drop):
    """Time to come down `drop` units under the cloak: a moment's fall while it opens, then a
    slow sink."""
    h0 = 0.5 * GRAVITY * FLOAT_OPEN ** 2
    return FLOAT_OPEN + max(0.0, drop - h0) / FLOAT_SPEED


def float_reach(drop):
    return min(FLOAT_MAX, RUN_SPEED * float_time(drop))


def slide_time(drop):
    """Time to slide `drop` units down a wall."""
    return WALLSLIDE_STICK + float(np.sqrt(2 * max(drop, 0.0) / WALLSLIDE_ACCEL))


def solid_map(world_size, polygons):
    """The rock as a grid of cells (row 0 at the top)."""
    W, H = int(np.ceil(world_size[0] * NAV_PPU)), int(np.ceil(world_size[1] * NAV_PPU))
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)
    for pts in polygons:
        d.polygon([(x * NAV_PPU, (world_size[1] - y) * NAV_PPU) for x, y in pts], fill=1)
    return np.array(img)


def surfaces(solid, world_h):
    """Runs of standable cells: solid with HEADROOM of air above. Returns lists of (x, y)."""
    H, W = solid.shape
    need = int(np.ceil(HEADROOM * NAV_PPU))
    columns = []
    for c in range(W):
        col = solid[:, c]
        tops = []
        for r in range(need, H):
            if col[r] and not col[r - 1] and not col[r - need:r].any():
                tops.append(world_h - r / NAV_PPU)
        columns.append(tops)
    runs, active = [], []
    for c, tops in enumerate(columns):
        x = (c + 0.5) / NAV_PPU
        next_active = []
        used = set()
        for y in tops:
            best = None
            for i, run in enumerate(active):
                if i not in used and abs(run[-1][1] - y) <= MAX_SLOPE:
                    best = i
                    break
            if best is None:
                run = [(x, y)]
                runs.append(run)
            else:
                used.add(best)
                run = active[best]
                run.append((x, y))
            next_active.append(run)
        active = next_active
    return [r for r in runs if r[-1][0] - r[0][0] >= MIN_SURFACE]


def resample(run):
    """Surface as x0 and heights every STEP units."""
    xs = np.array([p[0] for p in run])
    ys = np.array([p[1] for p in run])
    x0, x1 = xs[0], xs[-1]
    grid = np.arange(x0, x1 + 1e-6, STEP)
    y = np.interp(grid, xs, ys)
    # The raster measures heights in 1/8 unit steps: smoothed over a unit, slopes stay slopes
    # instead of little stairs she'd pop up.
    if len(y) >= 5:
        k = np.ones(5) / 5
        y = np.convolve(np.pad(y, 2, mode="edge"), k, mode="valid")
    return {"x0": round(float(x0), 3), "x1": round(float(x1), 3), "y": [round(float(v), 3) for v in y]}


def height(s, x):
    i = (x - s["x0"]) / STEP
    i = min(max(i, 0), len(s["y"]) - 1)
    a, f = int(i), i - int(i)
    b = min(a + 1, len(s["y"]) - 1)
    return s["y"][a] * (1 - f) + s["y"][b] * f


def clear(solid, world_h, x0, y0, x1, y1, lift):
    """Is the arc from (x0, y0) to (x1, y1), peaking `lift` above the higher end, free of rock?"""
    H, W = solid.shape
    top = max(y0, y1) + lift
    for t in np.linspace(0.08, 0.97, 30):  # right up to the landing: arcs that end through a roof don't count
        x = x0 + (x1 - x0) * t
        y = (1 - t) * y0 + t * y1 + 4 * t * (1 - t) * (top - (y0 + y1) / 2)
        for dy in (0.3, 1.2, 2.0):  # feet, middle, head
            c, r = int(x * NAV_PPU), int((world_h - (y + dy)) * NAV_PPU)
            if 0 <= c < W and 0 <= r < H and solid[r, c]:
                return False
    return True


def clear_float(solid, world_h, x0, y0, x1, y1):
    """Is the way down under the cloak from (x0, y0) to (x1, y1) free of rock: stepping off, a
    moment's fall, then drifting down in a straight line?"""
    H, W = solid.shape
    T = float_time(y0 - y1)
    for t in np.linspace(0.04, 0.97, 40):
        tt = t * T
        x = x0 + (x1 - x0) * t
        y = y0 - (0.5 * GRAVITY * tt * tt if tt < FLOAT_OPEN else 0.5 * GRAVITY * FLOAT_OPEN ** 2 + (tt - FLOAT_OPEN) * FLOAT_SPEED)
        for dy in (0.3, 1.2, 2.2):  # feet, middle, the open cloak above
            c, r = int(x * NAV_PPU), int((world_h - (y + dy)) * NAV_PPU)
            if 0 <= c < W and 0 <= r < H and solid[r, c]:
                return False
    return True


def wall_top(solid, world_h, x, y):
    """Top of the wall rising at x from height y, or None when there is no wall there."""
    H, W = solid.shape
    c = int(x * NAV_PPU)
    if not 0 <= c < W:
        return None
    rows = [int((world_h - (y + dy)) * NAV_PPU) for dy in (0.6, 1.6)]
    if not all(0 <= r < H and solid[r, c] for r in rows):
        return None
    r = rows[0]
    while r > 0 and solid[r, c]:
        r -= 1
    return world_h - (r + 1) / NAV_PPU


def shaft(solid, world_h, x, y0, y1):
    """Is there open air to climb in at x from y0 to y1?"""
    H, W = solid.shape
    c = int(x * NAV_PPU)
    if not 0 <= c < W:
        return False
    r0, r1 = int((world_h - y1 - 1.0) * NAV_PPU), int((world_h - y0 - 0.5) * NAV_PPU)
    return not solid[max(r0, 0):max(r1, 0), c].any()


def links(solid, world_h, surfs):
    """Ways from one surface to another: a step over a bump, a drop, a jump or a double jump, a
    ledge caught at the top of a jump and climbed onto (mantle), the cloak opened on a long way
    down (float), a wall climb and the slide back down it (only walls that are there: from a
    surface that stops at a wall's foot to the top)."""
    out = []

    def add(kind, a, xa, b, xb, t):
        out.append({"kind": kind, "from": a, "x0": round(xa, 3), "y0": round(height(surfs[a], xa), 3),
                    "to": b, "x1": round(xb, 3), "y1": round(height(surfs[b], xb), 3), "time": round(t, 3)})

    # The furthest she gets across: a double jump onto a ledge just too high for one jump (at run
    # speed, for as long as she's up), or the cloak on the way down.
    reach2 = RUN_SPEED * jump2_time(JUMP_MAX)
    far = max(jump_reach(-6.0), reach2, FLOAT_MAX)
    for a, sa in enumerate(surfs):
        lift = WATER_JUMP_LIFT if sa.get("water") else 0.0  # out of the water she jumps from higher
        for end, direction in ((sa["x0"], -1), (sa["x1"], 1)):
            ya = height(sa, end)
            for b, sb in enumerate(surfs):
                if a == b:
                    continue
                # Landing spots on b within reach beyond this end: the nearest, and whether that's
                # b's edge (a ledge to catch) rather than a spot along it.
                lo, hi = sorted((end + direction * 0.3, end + direction * far))
                lo, hi = max(lo, sb["x0"]), min(hi, sb["x1"])
                if lo > hi:
                    continue
                xb = lo if direction > 0 else hi
                edge = xb == (sb["x0"] if direction > 0 else sb["x1"])
                yb = height(sb, xb)
                dy = yb - ya
                dx = abs(xb - end)
                if dx <= 1.2 and abs(dy) <= STEP:
                    add("walk", a, end, b, xb, dx / WALK_SPEED)  # over a small bump
                elif dy < -0.3:
                    if dx <= 3.5:
                        # Off the edge: running, she lands where her speed carries her; else she
                        # steps off clear of the ledge, further out if its side slopes.
                        xr = min(max(end + direction * RUN_SPEED * fall_time(ya - yb), sb["x0"]), sb["x1"])
                        tries = [(end, xr, 0.0)] + [(end + direction * 0.4, min(max(end + direction * off, sb["x0"]), sb["x1"]), 0.3)
                                                    for off in (0.8, 1.6, 2.6)]
                        for x0, x1, lift in tries:
                            if clear(solid, world_h, x0, ya, x1, height(sb, x1), lift):
                                add("drop", a, end, b, x1, fall_time(ya - height(sb, x1)) + 0.1)
                                break
                    elif dx <= jump_reach(dy) and clear(solid, world_h, end, ya, xb, yb, 1.0):
                        add("jump", a, end, b, xb, jump_time(dy))  # across a gap, landing lower
                    if -dy >= FLOAT_MIN and not sb.get("water"):
                        # The cloak opened on the way down, drifting out at least a little way.
                        xf = min(max(end + direction * max(dx, 2.5), sb["x0"]), sb["x1"])
                        yf = height(sb, xf)
                        if abs(xf - end) <= float_reach(ya - yf) and clear_float(solid, world_h, end, ya, xf, yf):
                            add("float", a, end, b, xf, float_time(ya - yf) + 0.3)
                elif dy > 0.3:
                    ya += lift
                    dy -= lift
                    if dy <= JUMP_MAX:
                        if dx <= jump_reach(dy) and clear(solid, world_h, end, ya, xb, yb, 1.0):
                            add("jump", a, end, b, xb, jump_time(dy))
                    else:
                        if dy <= DOUBLE_JUMP_MAX and dx <= RUN_SPEED * jump2_time(dy) and clear(solid, world_h, end, ya, xb, yb, 1.0):
                            add("jump2", a, end, b, xb, jump2_time(dy) if dx > jump_reach(dy) else jump_time(JUMP_MAX) + 0.35)
                        # Her hands catch the ledge's edge at the top of a jump (or a double jump),
                        # and she climbs onto it.
                        hang = (xb - direction * 0.5, yb - 1.6)
                        if edge and dy <= MANTLE_MAX and dx <= jump_reach(JUMP_HEIGHT) + 0.5 \
                                and clear(solid, world_h, end, ya, *hang, 0.2):
                            add("mantle", a, end, b, xb, jump_time(JUMP_HEIGHT) + 0.45)
                        elif edge and DOUBLE_JUMP_MAX < dy <= MANTLE2_MAX and dx <= reach2 \
                                and clear(solid, world_h, end, ya, *hang, 0.2):
                            add("mantle2", a, end, b, xb, jump_time(JUMP_MAX) + 0.8)
                    ya -= lift
                elif abs(dy) <= 0.3 and dx > 0.6 and dx <= jump_reach(0) and clear(solid, world_h, end, ya, xb, yb, 1.5):
                    add("jump", a, end, b, xb, jump_time(0))
        # Up onto this surface's ends from a surface below: she takes off a little way out from
        # under the end, so she clears its edge (or catches it, just too high).
        for end, direction in ((sa["x0"], -1), (sa["x1"], 1)):
            yb = height(sa, end)
            xt = end + direction * 1.3
            xl = end - direction * 0.5
            hang = (end + direction * 0.5, yb - 1.6)
            for b, sb in enumerate(surfs):
                if b == a or not sb["x0"] <= xt <= sb["x1"]:
                    continue
                ya = height(sb, xt) + (WATER_JUMP_LIFT if sb.get("water") else 0.0)
                dy = yb - ya
                if 0.3 < dy <= JUMP_MAX and clear(solid, world_h, xt, ya, xl, yb, 1.0):
                    add("jump", b, xt, a, xl, jump_time(dy))
                elif JUMP_MAX < dy <= DOUBLE_JUMP_MAX and clear(solid, world_h, xt, ya, xl, yb, 1.0):
                    add("jump2", b, xt, a, xl, jump_time(JUMP_MAX) + 0.35)
                if JUMP_MAX < dy <= MANTLE_MAX and clear(solid, world_h, xt, ya, *hang, 0.2):
                    add("mantle", b, xt, a, end, jump_time(JUMP_HEIGHT) + 0.45)
                elif DOUBLE_JUMP_MAX < dy <= MANTLE2_MAX and clear(solid, world_h, xt, ya, *hang, 0.2):
                    add("mantle2", b, xt, a, end, jump_time(JUMP_MAX) + 0.8)
        # Wall climbs: this end stops at the foot of a wall; she clings to it and scrambles up
        # to the surface on top. And back down: off the top's edge, she slides down the wall.
        for end, direction in ((sa["x0"], -1), (sa["x1"], 1)):
            ya = height(sa, end)
            # The wall's face wobbles (bumps low on it aren't its top): its highest point within the
            # first unit past the end.
            tops = [t for t in (wall_top(solid, world_h, end + direction * d, ya) for d in np.arange(0.2, 1.05, 0.125))
                    if t is not None]
            top = max(tops) if tops else None
            if top is None or not JUMP_MAX < top - ya <= CLIMB_MAX:
                continue
            if not shaft(solid, world_h, end - direction * 0.2, ya, top):
                continue  # something overhangs her on the way up
            xt = end + direction * 0.9
            for b, sb in enumerate(surfs):
                if b != a and sb["x0"] - 0.3 <= xt <= sb["x1"] + 0.3 and abs(height(sb, min(max(xt, sb["x0"]), sb["x1"])) - top) < 0.6:
                    xb = min(max(xt, sb["x0"]), sb["x1"])
                    add("climb", a, end, b, xb, (top - ya) / 6.0 + 0.4)
                    edge = sb["x0"] if direction > 0 else sb["x1"]  # the top's edge over the wall's face
                    if abs(edge - (end + direction * 0.2)) < 1.5:
                        add("slide", b, edge, a, end, 0.3 + slide_time(top - ya) + 0.25)
                    break
    # Keep the cheapest link of each kind between two surfaces.
    best = {}
    for e in out:
        k = (e["from"], e["to"], e["kind"])
        if k not in best or e["time"] < best[k]["time"]:
            best[k] = e
    return list(best.values())


def water_surfaces(solid, world_h, water):
    """The water's surface where it's deep enough to swim and open above: runs at each body's
    level, cut where rock stands out of it (a stone in the pool). Each {x0, x1, y, water: True},
    y being where her feet are as she swims."""
    H, W = solid.shape
    need = int(np.ceil(HEADROOM * NAV_PPU))
    out = []
    for x0, x1, level in water:
        r_level = int((world_h - level) * NAV_PPU)
        runs, run = [], []
        for c in range(max(0, int(x0 * NAV_PPU)), min(W, int(np.ceil(x1 * NAV_PPU)))):
            col = solid[:, c]
            below = np.nonzero(col[r_level:])[0]
            depth = (below[0] if len(below) else H - r_level) / NAV_PPU
            if depth >= SWIM_DEPTH and not col[max(0, r_level - need):r_level + 1].any():
                run.append((c + 0.5) / NAV_PPU)
            else:
                runs.append(run)
                run = []
        runs.append(run)
        for xs in runs:
            if len(xs) > 1 and xs[-1] - xs[0] >= MIN_SURFACE:
                n = int(round((xs[-1] - xs[0]) / STEP)) + 1
                out.append({"x0": round(xs[0], 3), "x1": round(xs[0] + (n - 1) * STEP, 3),
                            "y": [round(level - SWIM_SINK, 3)] * n, "water": True, "level": level})
    return out


def wade_links(surfs):
    """In and out of the water where a shore runs down to it: from the shore's end at the water's
    edge, wading out to where it's deep enough to swim, and back."""
    out = []
    for w, sw in enumerate(surfs):
        if not sw.get("water"):
            continue
        for wx, direction in ((sw["x0"], -1), (sw["x1"], 1)):  # direction: towards the shore
            for s, ss in enumerate(surfs):
                if ss.get("water"):
                    continue
                sx = ss["x1"] if direction < 0 else ss["x0"]
                gap = (wx - sx) * -direction
                if not -0.3 <= gap <= WADE_GAP or not sw["level"] - 0.6 <= height(ss, sx) <= sw["level"] + 1.0:
                    continue
                t = abs(wx - sx) / WALK_SPEED + 0.5
                for a, xa, b, xb in ((s, sx, w, wx), (w, wx, s, sx)):
                    out.append({"kind": "wade", "from": a, "x0": round(xa, 3), "y0": round(height(surfs[a], xa), 3),
                                "to": b, "x1": round(xb, 3), "y1": round(height(surfs[b], xb), 3), "time": round(t, 3)})
    return out


def connected(n, edges):
    """The largest group of surfaces that can all reach each other (Kosaraju)."""
    fwd = {i: [] for i in range(n)}
    back = {i: [] for i in range(n)}
    for e in edges:
        fwd[e["from"]].append(e["to"])
        back[e["to"]].append(e["from"])
    order, seen = [], set()
    for start in range(n):
        if start in seen:
            continue
        stack = [(start, iter(fwd[start]))]
        seen.add(start)
        while stack:
            node, it = stack[-1]
            nxt = next((v for v in it if v not in seen), None)
            if nxt is None:
                order.append(node)
                stack.pop()
            else:
                seen.add(nxt)
                stack.append((nxt, iter(fwd[nxt])))
    groups, assigned = [], set()
    for start in reversed(order):
        if start in assigned:
            continue
        group, stack = set(), [start]
        assigned.add(start)
        while stack:
            u = stack.pop()
            group.add(u)
            for v in back[u]:
                if v not in assigned:
                    assigned.add(v)
                    stack.append(v)
        groups.append(group)
    return max(groups, key=len)


def surface_at(surfs, x, near):
    """The surface under x closest to height `near`, and its height there."""
    best = None
    for i, sf in enumerate(surfs):
        if sf["x0"] - 0.2 <= x <= sf["x1"] + 0.2:
            y = height(sf, min(max(x, sf["x0"]), sf["x1"]))
            if best is None or abs(y - near) < abs(best[1] - near):
                best = (i, y)
    return best


# How fast her moves go, for the authored links.
HARPOON_SPEED = 32.0  # Clawline dash, units per second
THROW_TIME = 0.35  # antic and throw before she flies


def build(world_size, polygons, water=(), moves=()):
    """water: (x0, x1, level) bodies of water; Hornet doesn't stand under their surface, she swims
    on it where it's deep enough.
    moves: authored links the rock can't imply: {"kind": "harpoon", "ring": (x, y)} (she throws
    her needle to a ring and flies to it) or {"kind": "bounce", "pod": (x, y)} (she strikes down
    on a pod and it throws her), each with "from" and "to" as (x, near height)."""
    solid = solid_map(world_size, polygons)
    runs = []
    for run in surfaces(solid, world_size[1]):
        piece = []
        for x, y in run:
            if any(x0 <= x <= x1 and y < level - 0.05 for x0, x1, level in water):
                if len(piece) > 1 and piece[-1][0] - piece[0][0] >= MIN_SURFACE:
                    runs.append(piece)
                piece = []
            else:
                piece.append((x, y))
        if len(piece) > 1 and piece[-1][0] - piece[0][0] >= MIN_SURFACE:
            runs.append(piece)
    surfs = [resample(r) for r in runs] + water_surfaces(solid, world_size[1], water)
    edges = links(solid, world_size[1], surfs) + wade_links(surfs)
    for m in moves:
        a, b = surface_at(surfs, *m["from"]), surface_at(surfs, *m["to"])
        if a is None or b is None or abs(a[1] - m["from"][1]) > 1.5 or abs(b[1] - m["to"][1]) > 1.5:
            raise SystemExit(f"no ground for the move {m}")
        (x0, _), (x1, _) = m["from"], m["to"]
        if m["kind"] == "harpoon":
            rx, ry = m["ring"]
            t = THROW_TIME + float(np.hypot(rx - x0, ry - a[1])) / HARPOON_SPEED + 0.15 + fall_time(max(0.0, ry - b[1])) + 0.2
            extra = {"ring": [rx, ry]}
        else:
            px, py = m["pod"]
            t = jump_time(py - a[1]) + 0.25 + jump_time(b[1] - py) + 0.4
            extra = {"pod": [px, py]}
        edges.append(dict({"kind": m["kind"], "from": a[0], "x0": round(x0, 3), "y0": round(a[1], 3), "to": b[0],
                           "x1": round(x1, 3), "y1": round(b[1], 3), "time": round(t, 3)}, **extra))
    # Ledges Hornet could get onto but not off (or never reach) are left out.
    keep = sorted(connected(len(surfs), edges))
    index = {old: new for new, old in enumerate(keep)}
    surfs = [surfs[i] for i in keep]
    edges = [dict(e, **{"from": index[e["from"]], "to": index[e["to"]]}) for e in edges
             if e["from"] in index and e["to"] in index]
    return {"step": STEP, "surfaces": surfs, "links": edges}, solid

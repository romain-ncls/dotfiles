"""Navigation map of the aquarium: where Hornet can stand and how she gets from one place to another.

The world's rock (the same polygons that are drawn) is rasterised; surfaces are runs of rock with
room for Hornet above, and links between them are drops, jumps and wall climbs sized with her
real movement (HeroController and Physics2D settings). Nothing is hidden: no ground or wall
exists that isn't drawn, bezels included.
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
MAX_FALL = 30.0
RUN_SPEED = 8.25
WALK_SPEED = 5.0
JUMP_REACH = 7.0  # horizontal distance covered in a jump at run speed
CLIMB_MAX = 14.0  # a wall climb (cling and walljumps) up to this height

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
    """Ways from one surface to another: a step over a bump, a drop, a jump or a wall climb
    (only up walls that are there: from a surface that stops at a wall's foot to the top)."""
    out = []

    def add(kind, a, xa, b, xb, t):
        out.append({"kind": kind, "from": a, "x0": round(xa, 3), "y0": round(height(surfs[a], xa), 3),
                    "to": b, "x1": round(xb, 3), "y1": round(height(surfs[b], xb), 3), "time": round(t, 3)})

    for a, sa in enumerate(surfs):
        for end, direction in ((sa["x0"], -1), (sa["x1"], 1)):
            ya = height(sa, end)
            for b, sb in enumerate(surfs):
                if a == b:
                    continue
                # Landing spots on b within reach beyond this end.
                lo, hi = sorted((end + direction * 0.3, end + direction * JUMP_REACH))
                lo, hi = max(lo, sb["x0"]), min(hi, sb["x1"])
                if lo > hi:
                    continue
                xb = lo if direction > 0 else hi
                yb = height(sb, xb)
                dy = yb - ya
                dx = abs(xb - end)
                if dx <= 1.2 and abs(dy) <= STEP:
                    add("walk", a, end, b, xb, dx / WALK_SPEED)  # over a small bump
                elif dy < -0.3 and dx > 3.5 and clear(solid, world_h, end, ya, xb, yb, 1.0):
                    add("jump", a, end, b, xb, jump_time(dy))  # across a gap, landing lower
                elif dy < -0.3 and dx <= 3.5:
                    # Step off clear of the ledge before falling, further out if its side slopes.
                    for off in (0.8, 1.6, 2.6):
                        xb = min(max(end + direction * off, sb["x0"]), sb["x1"])
                        yb = height(sb, xb)
                        if clear(solid, world_h, end + direction * 0.4, ya, xb, yb, 0.3):
                            add("drop", a, end, b, xb, fall_time(ya - yb) + 0.1)
                            break
                elif 0.3 < dy <= JUMP_MAX and clear(solid, world_h, end, ya, xb, yb, 1.0):
                    add("jump", a, end, b, xb, jump_time(dy))
                elif JUMP_MAX < dy <= DOUBLE_JUMP_MAX and clear(solid, world_h, end, ya, xb, yb, 1.0):
                    add("jump2", a, end, b, xb, jump_time(JUMP_MAX) + 0.35)
                elif abs(dy) <= 0.3 and dx > 0.6 and clear(solid, world_h, end, ya, xb, yb, 1.5):
                    add("jump", a, end, b, xb, jump_time(0))
        # Up onto this surface's ends from a surface below: she takes off a little way out from
        # under the end, so she clears its edge.
        for end, direction in ((sa["x0"], -1), (sa["x1"], 1)):
            yb = height(sa, end)
            xt = end + direction * 1.3
            xl = end - direction * 0.5
            for b, sb in enumerate(surfs):
                if b == a or not sb["x0"] <= xt <= sb["x1"]:
                    continue
                ya = height(sb, xt)
                dy = yb - ya
                if 0.3 < dy <= JUMP_MAX and clear(solid, world_h, xt, ya, xl, yb, 1.0):
                    add("jump", b, xt, a, xl, jump_time(dy))
                elif JUMP_MAX < dy <= DOUBLE_JUMP_MAX and clear(solid, world_h, xt, ya, xl, yb, 1.0):
                    add("jump2", b, xt, a, xl, jump_time(JUMP_MAX) + 0.35)
        # Wall climbs: this end stops at the foot of a wall; she clings to it and scrambles up
        # to the surface on top.
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
                    break
    # Keep the cheapest link of each kind between two surfaces.
    best = {}
    for e in out:
        k = (e["from"], e["to"], e["kind"])
        if k not in best or e["time"] < best[k]["time"]:
            best[k] = e
    return list(best.values())


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
    """water: (x0, x1, level) bodies of water; Hornet doesn't stand under their surface.
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
    surfs = [resample(r) for r in runs]
    edges = links(solid, world_size[1], surfs)
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

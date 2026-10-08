"""The aquarium's own terrain: authored shapes, dressed with pieces harvested from rooms.

Rock is drawn as polygons in world units (floors with holes, walls with doors, ledges) and
dressed the way Hollow Knight builds its rooms: black organic silhouettes roughen the outline,
masses of moss cover the inside, and pieces chosen by the surface's direction line every edge
(clumps on floors, rocks on walls, hanging moss under ceilings), with plants in front.
"""
import json
import math
import re
import zlib
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

KITS = Path.home() / ".cache/silksong-wallpaper/kits"


# ---------------------------------------------------------------------------- shapes

@dataclass
class Rock:
    points: list  # [(x, y)] world units, counter-clockwise
    biome: str = None  # dressed with this biome whatever zone it faces (None: the zone's)
    dress: bool = True
    tags: set = field(default_factory=set)  # "ledge": dressed as a stone block
    draw: bool = True  # False: ground a room draws itself (still walked on)
    under: str = None  # biome of the faces that don't look up (and of the inside), if not the zone's
    under_x: tuple = None  # ... only between these x (the arcade's ends are the zone's)
    solid: bool = True  # False: drawn only (a dark cave back), nothing stands on it


def wobble(rng, a, b, n_per_unit=2.0, amp=0.12):
    """Points from a to b with a gentle organic wobble across the segment."""
    a, b = np.array(a, float), np.array(b, float)
    length = float(np.linalg.norm(b - a))
    n = max(2, int(length * n_per_unit))
    normal = np.array([-(b - a)[1], (b - a)[0]]) / max(length, 1e-6)
    pts = []
    phase = rng.uniform(0, 6.3)
    for i in range(n):
        t = i / (n - 1)
        off = 0 if i in (0, n - 1) else amp * (math.sin(t * length * 1.7 + phase) * 0.6 + rng.uniform(-0.5, 0.5))
        pts.append(tuple(a + (b - a) * t + normal * off))
    return pts


def box(rng, x0, y0, x1, y1, biome=None, walk_top=True, level=False, **kw):
    """A rectangle of rock with organic edges; the top stays gentle enough to walk on, or dead
    level for a built floor (`level`)."""
    top_amp = 0.0 if level else 0.06 if walk_top else 0.15
    pts = (wobble(rng, (x0, y0), (x1, y0), amp=0.18)[:-1]  # bottom, left to right
           + wobble(rng, (x1, y0), (x1, y1), amp=0.18)[:-1]  # right side, up
           + wobble(rng, (x1, y1), (x0, y1), amp=top_amp)[:-1]  # top, right to left
           + wobble(rng, (x0, y1), (x0, y0), amp=0.18)[:-1])  # left side, down
    return Rock(pts, biome, **kw)


def slab(rng, x0, x1, bottom, top, holes=(), biome=None):
    """A floor between two levels, from x0 to x1, with holes [(hx0, hx1)]."""
    rocks, x = [], x0
    for hx0, hx1 in sorted(holes):
        if hx0 > x:
            rocks.append(box(rng, x, bottom, hx0, top, biome))
        x = hx1
    if x < x1:
        rocks.append(box(rng, x, bottom, x1, top, biome))
    return rocks


def wall(rng, x0, x1, bottom, top, doors=(), biome=None):
    """A wall from bottom to top with door openings [(y0, y1)]."""
    rocks, y = [], bottom
    for dy0, dy1 in sorted(doors):
        if dy0 > y:
            rocks.append(box(rng, x0, y, x1, dy0, biome, walk_top=True))
        y = dy1
    if y < top:
        rocks.append(box(rng, x0, y, x1, top, biome, walk_top=False))
    return rocks


def ledge(rng, x0, x1, top, thickness=1.0, biome=None):
    return box(rng, x0, top - thickness, x1, top, biome, tags={"ledge"})


def chaikin(points, iterations=2, closed=True):
    """Rounded corners by corner cutting."""
    pts = [np.array(p, float) for p in points]
    for _ in range(iterations):
        out = [] if closed else [pts[0]]
        pairs = zip(pts, pts[1:] + pts[:1]) if closed else zip(pts[:-1], pts[1:])
        for a, b in pairs:
            out += [a * 0.75 + b * 0.25, a * 0.25 + b * 0.75]
        if not closed:
            out.append(pts[-1])
        pts = out
    return [tuple(p) for p in pts]


def blob(rng, points, biome=None, amp=0.12, rounds=2, **kw):
    """Organic rock from a coarse outline: corners rounded, edges wobbling."""
    pts = chaikin(points, rounds)
    out = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        out += wobble(rng, a, b, n_per_unit=2.0, amp=amp)[:-1]
    return Rock(out, biome, **kw)


def ground(rng, profile, bottom=-1.0, biome=None, **kw):
    """Ground under a walkable height profile [(x, y)] (left to right), down to `bottom`."""
    top = chaikin(profile, 3, closed=False)
    pts = []
    for a, b in zip(top, top[1:]):
        pts += wobble(rng, a, b, n_per_unit=2.0, amp=0.04)[:-1]
    pts.append(top[-1])
    pts = pts[::-1] + [(top[0][0], bottom), (top[-1][0], bottom)]  # the top from right to left, then the bottom
    return Rock([(x, y) for x, y in pts], biome, **kw)


def island(rng, x0, x1, top, depth=1.8, biome=None, **kw):
    """A floating platform: a flat top to stand on, a rounded underside hanging below."""
    w = x1 - x0
    under = chaikin([(x0, top - 0.35), (x0 + 0.15 * w, top - depth * rng.uniform(0.55, 0.75)),
                     (x0 + w * rng.uniform(0.4, 0.6), top - depth), (x1 - 0.15 * w, top - depth * rng.uniform(0.55, 0.75)),
                     (x1, top - 0.35)], 2, closed=False)
    outline = [(x0, top)] + under + [(x1, top)]  # down the left side, under, up the right side
    pts = []
    for a, b in zip(outline, outline[1:]):
        pts += wobble(rng, a, b, n_per_unit=2.0, amp=0.1)[:-1]
    pts += wobble(rng, (x1, top), (x0, top), n_per_unit=2.0, amp=0.03)[:-1]  # the top, back to the left
    kw.setdefault("tags", set()).add("island")
    return Rock(pts, biome, **kw)


# ---------------------------------------------------------------------------- kits

class Kit:
    """Pieces harvested from a room (tools/kit.py), with sets picked by name and size."""

    def __init__(self, room):
        self.dir = KITS / room
        self.pieces = json.loads((self.dir / "pieces.json").read_text())
        self._images = {}
        for p in self.pieces:
            p["lum"] = None

    def image(self, p):
        if p["name"] not in self._images:
            self._images[p["name"]] = Image.open(self.dir / p["file"]).convert("RGBA")
        return self._images[p["name"]]

    def luminance(self, p):
        if p["lum"] is None:
            a = np.asarray(self.image(p)).astype(np.float32) / 255
            mask = a[..., 3] > 0.5
            p["lum"] = float(a[..., :3][mask].mean()) if mask.any() else 0.0
        return p["lum"]

    def pick(self, pattern, wmin=0.0, wmax=99.0, dark=None, hmin=0.0, hmax=99.0):
        """Pieces whose object name matches; dark=True only black silhouettes, False only coloured."""
        rx = re.compile(pattern, re.I)
        out = []
        for p in self.pieces:
            if not rx.search(p["object"]) or not (wmin <= p["width"] <= wmax and hmin <= p["height"] <= hmax):
                continue
            if dark is not None and (self.luminance(p) < 0.06) != dark:
                continue
            out.append(p)
        return out


@dataclass
class Biome:
    kit: Kit
    floor: list  # clumps that sit on a surface, now and then
    wall: list  # pieces turned to face sideways
    ceiling: list  # pieces hanging from an edge
    silhouettes: list  # black organic shapes roughening the outline
    fill: list  # masses covering the inside
    plants: list  # small things in front of Hornet
    ledges: list = field(default_factory=list)  # stone blocks for small platforms
    fill_tint: float = 0.55
    floor_k: tuple = (0.32, 0.55)  # piece scales, by kind
    wall_k: tuple = (0.3, 0.5)
    ceiling_k: tuple = (0.25, 0.45)
    fill_k: tuple = (0.45, 0.75)
    fill_step: tuple = (2.6, 2.0)  # spacing of the masses inside the rock
    fill_angle: float = 25.0
    ceiling_p: float = 0.45  # how often a ceiling gets something hanging
    upright_walls: bool = False  # wall pieces stand as they are (posts) instead of facing out
    front_bits: bool = True  # small floor pieces in front of Hornet's feet between the plants
    strips: list = field(default_factory=list)  # low pieces laid end to end along every floor
    strip_h: float = 0.85  # their height, units
    strip_lift: float = 0.1  # their centre above the surface, in their heights (the walking line is the surface)
    clump_p: float = 0.12  # how often a floor gets a clump on top of its strip


# Pieces that looked wrong in the renders: round rosette clusters (they read as odd clumps on
# platforms) and soft black faders (dark smudges).
MOSS_SKIP = {"Moss_clump_set_2", "moss__0000_bmoss_126", "moss__0000_bmoss_13", "moss_wall_front_simple_mid_type_83",
             "moss__0003_bmoss_43", "moss__0000_bmoss_79"}


def without(biome, skip):
    for name in ("floor", "wall", "ceiling", "silhouettes", "fill", "plants", "ledges", "strips"):
        setattr(biome, name, [p for p in getattr(biome, name) if p["name"] not in skip])
    return biome


def moss_biome():
    k = Kit("tut_02")
    return without(Biome(
        kit=k,
        floor=k.pick(r"^(Moss_clump_set2?|Moss_clump_depress.*)$", 2.0, 8.0, dark=False),
        strips=k.pick(r"^(Clump [123]|Moss_clump_depress_curvy0000)$", 3.0, 4.2),
        wall=k.pick(r"bmoss|moss_wall_front|bone_moss_mid_rock", 2.5, 9.0, dark=False),
        ceiling=k.pick(r"stalac", 1.0, 4.0, hmax=6.0),
        silhouettes=k.pick(r"^(Moss_clump_set|Moss_clump_depress.*|moss__\d+_bmoss|Clump BG)$", 3.0, 12.0, dark=True),
        fill=k.pick(r"^(Moss_clump_set2?|Clump ?\d|moss__\d+_bmoss)$", 3.0, 9.0, dark=False),
        plants=k.pick(r"simple_grass|grass_0\d|mtwirl|Vine \d", 0.8, 3.0, hmax=3.0),
        ledges=k.pick(r"^(Sprites?|bone_plat_0\d)$", 2.0, 7.0, dark=False),
    ), MOSS_SKIP)


def clover_biome():
    k = Kit("clover_02c")
    return Biome(
        kit=k,
        floor=k.pick(r"^(Aspid__0007_1|clover___0007_ground|Aspid_break_bushes.*)$", 2.0, 8.0, dark=False, hmax=3.5),
        strips=k.pick(r"^(Aspid__0007_1|clover___0007_ground)$", 2.0, 8.0, dark=False, hmax=3.5),
        strip_h=0.9, clump_p=0.1,
        wall=k.pick(r"^Aspid__000[01]_c_(mid|inner)", 3.0, 8.0, dark=False),
        ceiling=k.pick(r"^(clover___0007_ground|back|front)$", 0.8, 2.0, dark=True, hmin=2.0, hmax=7.5)
        + k.pick(r"grove_pod_branch|Moss_Thick_Vine", 1.0, 5.0, dark=False),
        silhouettes=k.pick(r"^(Aspid__0001_c_mid_la|Moss_clump_set|Aspid__0000_c_inner_)$", 3.0, 12.0, dark=True),
        fill=k.pick(r"^(Aspid__000[01]_c_(mid|inner).*|clover___0007_ground)$", 3.0, 9.0, dark=False, hmax=9.0),
        plants=k.pick(r"simple_grass|^clover___0007_ground$|grass_02|grove_pod_main", 0.8, 3.5, dark=False, hmax=3.5),
        ledges=k.pick(r"^(Plat Sprite|clover_gate_grey_000)$", 3.0, 8.0, dark=False),
    )


def citadel_biome():
    k = Kit("bellway_city")
    return Biome(
        kit=k,
        floor=k.pick(r"sc_floor|Bell Floor|^top$|pilgrim_relief_brick", 1.5, 8.0, dark=False),
        strips=k.pick(r"^(SC_0029_sc_floor|base_main)$", 5.0, 8.0),
        clump_p=0.0, ceiling_p=0.25,
        wall=k.pick(r"pilgrim_relief_brick|Coral_Stone|^chunk$|SC_0039", 1.5, 8.0, dark=False),
        ceiling=k.pick(r"^(Chain|chain long|chain short)$", 0.3, 6.0),
        silhouettes=[],
        fill=k.pick(r"pilgrim_relief_brick|Coral_Stone|^chunk$", 2.0, 9.0, dark=False),
        plants=k.pick(r"sc_junk_piles_small", 1.0, 4.0, dark=False),
        ledges=k.pick(r"sc_floor_pla|^top$|SC_0039_sc_floor", 2.0, 8.0, dark=False),
        fill_tint=0.45,
    )


def house_biome():
    """Inside Hornet's home the rock stays plain: her furniture covers it (world.FURNITURE)."""
    return Biome(kit=Kit("belltown_room_spare"), floor=[], wall=[], ceiling=[], silhouettes=[], fill=[], plants=[])


def bellhart_biome():
    """Bellhart's timber and copper, for Hornet's house: planks inside walls, posts on their
    faces, floor trims, balcony lips and arches underneath."""
    k = Kit("belltown")
    return Biome(
        kit=k,
        floor=[],
        strips=k.pick(r"^(Belltown_floor_main|Belltown_floors_0001_1)$", 2.5, 8.0, hmax=1.3),
        strip_h=1.0, clump_p=0.0, strip_lift=-0.2,  # boards: their top a little above her feet
        wall=k.pick(r"^belltown_front_brace_0002_1$", 1.4, 1.7),
        ceiling=k.pick(r"^(balcony_lip|belltown_arch_set__0000_2|belltown_arch_set__0001_1)$", 1.9, 10.0, dark=False),
        silhouettes=[],
        fill=k.pick(r"^belltown_standard_wall_000[0-2]", 1.9, 2.3, hmin=2.9),
        plants=k.pick(r"^sc_bell_piles_0002_6$", 1.0, 2.0),
        fill_tint=0.85, floor_k=(0.9, 1.0), wall_k=(0.85, 1.0), ceiling_k=(0.55, 0.75), fill_k=(1.0, 1.0),
        fill_step=(1.9, 2.8), fill_angle=0.0, ceiling_p=0.8, upright_walls=True, front_bits=False,
    )


def vault_biome():
    """The Citadel's arcade: dressed by hand (world.vault_pieces), nothing scattered on it."""
    return Biome(kit=Kit("bellway_city"), floor=[], wall=[], ceiling=[], silhouettes=[], fill=[], plants=[])


BIOMES = {"moss": moss_biome, "clover": clover_biome, "citadel": citadel_biome, "house": house_biome,
          "bellhart": bellhart_biome, "vault": vault_biome}


# ---------------------------------------------------------------------------- dressing

def outward_normal(a, b):
    """Outward normal of a counter-clockwise polygon's edge a -> b."""
    d = np.array(b, float) - np.array(a, float)
    n = np.array([d[1], -d[0]])
    return n / max(np.linalg.norm(n), 1e-6)


def signed_area(pts):
    a = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        a += x0 * y1 - x1 * y0
    return a / 2


class Canvas:
    """World-sized RGBA layer, drawn in world units (y up)."""

    def __init__(self, world_size, ppu, opaque=False):
        self.ppu = ppu
        self.h_units = world_size[1]
        self.img = Image.new("RGBA", (round(world_size[0] * ppu), round(world_size[1] * ppu)),
                             (0, 0, 0, 255 if opaque else 0))
        self.swaying = None  # a list: pieces that sway are collected there instead of drawn (paste)
        self._moving = None  # where they are

    def start_swaying(self):
        self.swaying, self._moving = [], np.zeros((self.img.height, self.img.width), bool)

    def stop_swaying(self):
        out, self.swaying, self._moving = self.swaying, None, None
        return out

    def px(self, x, y):
        return x * self.ppu, (self.h_units - y) * self.ppu

    def polygon(self, pts, fill):
        ImageDraw.Draw(self.img).polygon([self.px(x, y) for x, y in pts], fill=fill)

    def paste(self, piece, x, y, width, height, angle=0.0, flip=False, anchor=(0.5, 0.5), tint=1.0, keep=None,
              max_cut=None, sway=None):
        """Draw a piece scaled to width x height units, rotated (degrees, ccw) about its anchor,
        with the anchor (fractions from the bottom-left of the piece) at world (x, y).
        keep(x0, y0, w, h) -> bool array: the pixels of that canvas rectangle it may cover. With
        max_cut, a piece that would lose more than that share of itself isn't drawn at all (a
        cut piece shows a straight edge). Returns whether it was drawn.
        sway: the kit piece, when the game sways it (its "sway" and "pivot"); while the canvas
        collects `swaying` (start_swaying), the piece goes there as it would be drawn, with the
        height of its origin (what it bends from), instead of into the image; so does a still
        piece drawn over one of them ("sway" None), to stay in front of it."""
        w, h = max(1, round(width * self.ppu)), max(1, round(height * self.ppu))
        img = piece.resize((w, h), Image.LANCZOS)
        if flip:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
            anchor = (1 - anchor[0], anchor[1])
        if tint != 1.0:
            a = np.asarray(img).astype(np.float32)
            a[..., :3] *= tint
            img = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")
        ax, ay = anchor[0] * w, (1 - anchor[1]) * h  # anchor in image pixels (y down)
        if angle:
            # Rotate about the anchor: expand, then find where the anchor went.
            cx, cy = w / 2, h / 2
            rad = math.radians(angle)
            dx, dy = ax - cx, ay - cy
            rx = dx * math.cos(rad) + dy * math.sin(rad)
            ry = -dx * math.sin(rad) + dy * math.cos(rad)
            img = img.rotate(angle, resample=Image.BICUBIC, expand=True)
            ax, ay = img.width / 2 + rx, img.height / 2 + ry
        X, Y = self.px(x, y)
        x0, y0 = round(X - ax), round(Y - ay)
        W, H = self.img.size
        if x0 >= W or y0 >= H or x0 + img.width <= 0 or y0 + img.height <= 0:
            return False
        sx, sy = max(0, -x0), max(0, -y0)
        crop = img.crop((sx, sy, min(img.width, W - x0), min(img.height, H - y0)))
        if keep is not None:
            a = np.asarray(crop).copy()
            mask = keep(x0 + sx, y0 + sy, crop.width, crop.height)
            if max_cut is not None:
                solid = a[..., 3] > 40
                if solid.any() and (solid & ~mask).sum() > max_cut * solid.sum():
                    return False
            a[..., 3] = np.where(mask, a[..., 3], 0)
            crop = Image.fromarray(a, "RGBA")
        if self.swaying is not None:
            moves = sway is not None and "sway" in sway
            covered = np.asarray(crop)[..., 3] > 8
            under = self._moving[y0 + sy:y0 + sy + crop.height, x0 + sx:x0 + sx + crop.width]
            if moves or (covered & under).any():
                self.swaying.append({"image": crop, "px": (x0 + sx, y0 + sy), "x": x,
                                     "root": y + ((sway["pivot"][1] if moves else 0.0) - anchor[1]) * height,  # rotation aside
                                     "flip": flip, "sway": sway["sway"] if moves else None,
                                     "react": sway.get("react") if moves else None})
                under |= covered
                return True
        self.img.alpha_composite(crop, (x0 + sx, y0 + sy))
        return True


def edge_samples(pts, spacing, rng):
    """Points along a polygon's outline every ~spacing units, with outward normal and edge slope."""
    out = []
    ccw = signed_area(pts) > 0
    ring = pts if ccw else pts[::-1]
    for a, b in zip(ring, ring[1:] + ring[:1]):
        a, b = np.array(a, float), np.array(b, float)
        length = float(np.linalg.norm(b - a))
        if length < 1e-6:
            continue
        n = outward_normal(a, b)
        steps = max(1, int(length / spacing))
        for i in range(steps):
            t = (i + rng.uniform(0.2, 0.8)) / steps
            out.append((a + (b - a) * t, n))
    return out


def inside(pts, x, y):
    c = False
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0 + 1e-12) + x0:
            c = not c
    return c


def choose(rng, pieces, last=None):
    """A piece, never the one just used when there's another."""
    if last is not None and len(pieces) > 1:
        pieces = [p for p in pieces if p["name"] != last]
    return pieces[int(rng.integers(len(pieces)))]


def dress(rocks, biome_at, back, front, graded, seed, clear=(), underlay=None, no_plants=()):
    """Draw rocks onto the back layer (fill, silhouettes, inside, edges) and plants onto the front.

    biome_at(x, y, own) is the biome at a point of air next to the rock (each face of a floor is
    dressed for the level it faces), or the rock's own biome when it has one; graded(kit, piece, x, y) returns a piece in the
    colours of the zone at (x, y). `clear` are holes (x0, bottom, x1, top) through floors: no
    dressing covers the way through them. underlay() draws what goes on the bare rock, under
    its dressing. Each rock draws its dressing from its own randomness (from `seed` and its
    outline), so reshaping one rock leaves the others' dressing as it was.

    Rules from reviewing the renders: a piece that would be cut is left out, the same piece
    never follows itself, floors and ceilings are lined end to end rather than piled, and the
    sides of islands and thin rocks get nothing turned sideways."""
    for rock in rocks:
        if rock.draw and not rock.solid:
            back.polygon(rock.points, (4, 8, 6, 225))  # a cave's back: the backdrop barely shows
    rocks = [r for r in rocks if r.draw and r.solid]
    fill_black = (0, 0, 0, 255)
    for rock in rocks:
        back.polygon(rock.points, fill_black)
    if underlay:
        underlay()
    solid = Image.new("1", back.img.size, 0)
    for rock in rocks:
        ImageDraw.Draw(solid).polygon([back.px(x, y) for x, y in rock.points], fill=1)
    solid = np.array(solid)

    # The way through each hole, from under the floor to Hornet's height above it, with edges
    # that wander a little so cut pieces don't line up.
    passage = np.zeros_like(solid)
    rng = np.random.default_rng(seed)
    for x0, bottom, x1, top in clear:
        r0, r1 = (round(v) for v in (back.px(0, top + 2.8)[1], back.px(0, bottom - 0.6)[1]))
        phase = rng.uniform(0, 6.3)
        for r in range(max(r0, 0), min(r1, passage.shape[0])):
            y = back.h_units - r / back.ppu
            inset = 0.3 + 0.12 * math.sin(y * 2.7 + phase) + 0.06 * math.sin(y * 7.1 + 2 * phase)
            passage[r, max(0, round((x0 + inset) * back.ppu)):round((x1 - inset) * back.ppu)] = True

    def free(fn=None):
        def keep(x0, y0, w, h):
            m = ~passage[y0:y0 + h, x0:x0 + w]
            return m if fn is None else m & fn(x0, y0, w, h)
        return keep

    def in_rock(x0, y0, w, h):
        return solid[y0:y0 + h, x0:x0 + w]

    def this_side(p, n):
        """Pieces dressing a face stay on its side: outside the rock, a piece only shows where
        the face could see it through the air (a floor's moss never comes through the ceiling
        of the level below, a hole's sides never poke above the floor)."""
        ox, oy = back.px(*(np.asarray(p) + n * 0.15))
        H, W = solid.shape

        def keep(x0, y0, w, h):
            out = np.ones((h, w), bool)
            ys, xs = np.nonzero(~solid[y0:y0 + h, x0:x0 + w])
            if not len(ys):
                return out
            X, Y = xs + x0 + 0.5, ys + y0 + 0.5
            blocked = np.zeros(len(ys), bool)
            for t in np.linspace(0.04, 0.96, 16):
                cx = np.clip((ox + (X - ox) * t).astype(int), 0, W - 1)
                cy = np.clip((oy + (Y - oy) * t).astype(int), 0, H - 1)
                blocked |= solid[cy, cx]
            out[ys[blocked], xs[blocked]] = False
            return out

        return keep
    for rock in rocks:
        if not rock.dress:
            continue
        pts = rock.points
        rng = np.random.default_rng([seed, zlib.crc32(np.round(np.asarray(pts, float), 2).tobytes())])
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        # 1. Black organic shapes across the outline: no straight edges.
        def biome(q, n=None):
            own = rock.biome
            if rock.under and (n is None or n[1] < 0.6) and (rock.under_x is None or rock.under_x[0] <= q[0] <= rock.under_x[1]):
                own = rock.under
            return biome_at(q[0], q[1], own)

        for (p, n) in edge_samples(pts, 2.2, rng):
            bio = biome(p + n * 1.2, n)
            if bio is None or not bio.silhouettes:
                continue
            s = choose(rng, bio.silhouettes)
            k = rng.uniform(0.18, 0.3)
            w, h = s["width"] * k, s["height"] * k
            angle = math.degrees(math.atan2(n[1], n[0])) - 90
            back.paste(bio.kit.image(s), p[0] - n[0] * h * 0.35, p[1] - n[1] * h * 0.35, w, h, angle, rng.random() < 0.5,
                       keep=free(this_side(p, n)), max_cut=0.2)
        # 2. Masses covering the inside of thick rock (islands stay dark under their edges).
        inner = None if "island" in rock.tags else biome(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2))
        inner = inner or (biome((min(xs), max(ys))) if rock.under else None)
        step = inner.fill_step if inner is not None else (2.6, 2.0)
        jitter = 0.3 if inner is not None and not inner.fill_angle else 1.0
        for gx in np.arange(min(xs) + step[0] / 2 - 0.4, max(xs) + step[0] / 2, step[0]):
            for gy in np.arange(min(ys) + step[1] / 2 - 0.4, max(ys) + step[1] / 2, step[1]):
                x, y = gx + rng.uniform(-0.8, 0.8) * jitter, gy + rng.uniform(-0.6, 0.6) * jitter
                bio = biome((x, y))  # the arcade's ends are mossy inside, its arches aren't
                near = bio is not None and any(inside(pts, x + dx, y + dy) for dx, dy in ((0, 0), (0.6, 0), (-0.6, 0), (0, 0.6), (0, -0.6)))
                if bio is None or not bio.fill or not near:
                    continue
                f = choose(rng, bio.fill)
                k = rng.uniform(*bio.fill_k)
                img = graded(bio.kit, f, x, y)
                back.paste(img, x, y, f["width"] * k, f["height"] * k, rng.uniform(-1, 1) * bio.fill_angle,
                           rng.random() < 0.5, tint=bio.fill_tint, keep=free(in_rock))
        # 3. Edges, by the way the surface faces.
        bio = biome(((min(xs) + max(xs)) / 2, max(ys) + 1.0))
        if "ledge" in rock.tags and bio is not None and bio.ledges:
            l = choose(rng, bio.ledges)
            cx, top = (min(xs) + max(xs)) / 2, max(ys)
            width = max(xs) - min(xs) + 0.6
            img = graded(bio.kit, l, cx, top + 1)
            back.paste(img, cx, top + 0.25, width, width * l["height"] / l["width"], 0, rng.random() < 0.5, anchor=(0.5, 1.0),
                       keep=free())
        along, next_strip, next_ceiling, last = 0.0, 0.0, 0.0, None
        used = {"strip": None, "floor": None, "ceiling": None, "wall": None}
        thin = "island" in rock.tags or max(ys) - min(ys) < 4.0
        for (p, n) in edge_samples(pts, 1.3, rng):
            step = 0.0 if last is None else float(np.linalg.norm(p - last))
            along += step
            prev, last = last, p
            out = p + n * 1.2  # a point in the air next to this edge, for the zone's colours
            bio = biome(out, n)
            if bio is None:
                continue
            angle = math.degrees(math.atan2(n[1], n[0])) - 90
            if n[1] > 0.6 and (bio.strips or bio.floor):  # a floor: a strip along it, now and then a clump
                if bio.strips and along >= next_strip:
                    # Laid end to end, each where it's due rather than at the next sample past
                    # that (up to 1.3 later: a gap after a narrow one); a piece that would be cut
                    # is swapped for another, then a smaller one, rather than leaving the floor bare.
                    q = p if prev is None or step < 1e-6 else p + (prev - p) * min(1.0, (along - next_strip) / step)
                    tries = [(choose(rng, bio.strips, used["strip"]), 1.0, bio.strip_lift) for _ in range(3)]
                    tries += [(choose(rng, bio.strips), scale, bio.strip_lift) for scale in (0.75, 0.75, 0.55, 0.55)]
                    for c, scale, lift in tries:
                        k = bio.strip_h * scale * rng.uniform(0.9, 1.1) / c["height"]
                        w, h = c["width"] * k, c["height"] * k
                        cx = min(max(q[0], min(xs) + w * 0.4), max(xs) - w * 0.4) if max(xs) - min(xs) > w * 0.8 else q[0]
                        if back.paste(graded(bio.kit, c, *out), cx, q[1] + h * lift, w, h, angle * 0.6, rng.random() < 0.5,
                                      keep=free(this_side(q, n)), max_cut=0.12 if scale > 0.6 else 0.25):
                            used["strip"] = c["name"]
                            next_strip = along - float(np.linalg.norm(p - q)) + w * rng.uniform(0.55, 0.7)
                            break
                if bio.floor and (not bio.strips or rng.random() < bio.clump_p):
                    c = choose(rng, bio.floor, used["floor"])
                    k = rng.uniform(*bio.floor_k) * (0.75 if bio.strips else 1.0)
                    w, h = c["width"] * k, c["height"] * k
                    if back.paste(graded(bio.kit, c, *out), p[0], p[1] + h * 0.08, w, h, angle * 0.5, rng.random() < 0.5,
                                  keep=free(this_side(p, n)), max_cut=0.12):
                        used["floor"] = c["name"]
            elif n[1] < -0.6 and bio.ceiling:  # a ceiling: now and then some hanging moss
                if along < next_ceiling or rng.random() > bio.ceiling_p:
                    continue
                c = choose(rng, bio.ceiling, used["ceiling"])
                k = rng.uniform(*bio.ceiling_k)
                w, h = c["width"] * k, c["height"] * k
                if p[0] - w * 0.45 < min(xs) or p[0] + w * 0.45 > max(xs):
                    continue  # it would hang out past the rock, like a ledge that isn't there
                if back.paste(graded(bio.kit, c, *out), p[0], p[1] + 0.25, w, h, 0, rng.random() < 0.5, anchor=(0.5, 1.0),
                              keep=free(this_side(p, n)), max_cut=0.15, sway=c):
                    used["ceiling"] = c["name"]
                    next_ceiling = along + w * rng.uniform(0.8, 1.1)
            elif bio.wall and not thin:  # a wall: pieces turned to face out
                c = choose(rng, bio.wall, used["wall"])
                k = rng.uniform(*bio.wall_k)
                w, h = c["width"] * k, c["height"] * k
                if bio.upright_walls:
                    angle, inset = 0.0, w * 0.3
                else:
                    inset = 0.3
                if back.paste(graded(bio.kit, c, *out), p[0] - n[0] * inset, p[1] - n[1] * inset, w, h, angle,
                              rng.random() < 0.5, keep=free(this_side(p, n)), max_cut=0.12):
                    used["wall"] = c["name"]
        # 4. Plants in front of Hornet's feet, on floors.
        for (p, n) in edge_samples(pts, 2.4, rng):
            bio = biome(p + n * 1.2, n)
            if bio is None:
                continue
            if any(x0 <= p[0] <= x1 and y0 <= p[1] <= y1 for x0, y0, x1, y1 in no_plants):
                continue  # something stands there: a bench, a statue, the pod plant
            if n[1] > 0.7 and bio.plants and rng.random() < 0.3:
                c = choose(rng, bio.plants)
                k = rng.uniform(0.35, 0.6)
                w, h = c["width"] * k, c["height"] * k
                front.paste(graded(bio.kit, c, *(p + n * 1.2)), p[0] + rng.uniform(-0.4, 0.4), p[1] - 0.15, w, h,
                            rng.uniform(-6, 6), rng.random() < 0.5, anchor=(0.5, 0.0), keep=free(), max_cut=0.1, sway=c)
            elif n[1] > 0.7 and bio.floor and bio.front_bits and rng.random() < 0.15:
                c = choose(rng, bio.floor)
                k = rng.uniform(0.18, 0.28)
                w, h = c["width"] * k, c["height"] * k
                front.paste(graded(bio.kit, c, *(p + n * 1.2)), p[0], p[1] - h * 0.2, w, h, 0, rng.random() < 0.5,
                            keep=free(this_side(p, n)), max_cut=0.1)

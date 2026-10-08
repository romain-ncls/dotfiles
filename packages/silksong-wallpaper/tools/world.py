#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy", "lz4"]
# ///
"""Build the aquarium: one world laid across the desk.

The world's structure is authored (layout()): one ground under all three screens, a walkway
and branches crossing the bezels, islands, a cliff, Hornet's house and balcony. It is dressed
with pieces harvested from rooms (tools/kit.py, tools/terrain.py) so every edge is covered in
moss, clover, gilded stone or Bellhart timber. Behind each screen, a zone shows a room's
background in that room's own colours; Hornet's home is furnished with her Bellhart house's
pieces (FURNITURE); props from other rooms stand around (PROPS); a lake and its waterfall.
Hornet navigates the same rock that is drawn.

    tools/world.py                 render the zones that changed, then compose the world
    tools/world.py --only lake     re-render one zone
    tools/world.py --compose-only  compose from the cached zones

Zones are rendered one per process (a room takes about 4 GB) and cached in
~/.cache/silksong-wallpaper/zones; the kits must be harvested first (tools/kit.py harvest ROOM
for tut_02, clover_02c, bellway_city, belltown, mosstown_01, and belltown_room_spare with its
furnishing flags).
The world lands in ~/.local/share/silksong-wallpaper/world:

  back_NN, mid_NN, front_NN, lights_NN.png   tiles: the backdrops (behind Hornet's light), the
                                              rock and near pieces (behind her), in front of her,
                                              and the light sources that shine through the night veil
  zones/<zone>/hornet/*.png, light_<zone>.png  Hornet and her light in each zone's colours
  World.qml                                   sizes, tiles, zones, navigation

Run it under a memory cap:
  systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 tools/world.py
"""
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

import nav
import terrain

DATA = Path.home() / ".local/share/silksong-wallpaper"
CACHE = Path.home() / ".cache/silksong-wallpaper/zones"
OUT = DATA / "world"

UNIT_MM = 10.0
WORLD = (1326.4 / UNIT_MM, 267.9 / UNIT_MM)  # the desk: three screens bottom-aligned, 15 mm gaps
PPU = 56  # the laptop panel's density at this scale
TILE_PX = 1024
HERO_FEET = 1.552
BACKDROP_Z = 1.0  # backdrops keep what stands this far behind Hornet; nearer is the room's own terrain
RENDER_VERSION = 3  # bump when render_zone changes what it draws

# Light sources: drawn again above the night veil, so they keep glowing after dark. Haze, fog
# and light shafts stay behind the veil: at night they would turn into pale blotches.
LIGHT_NAMES = re.compile(r"glow|light|lamp|lantern|candle|fire|flame|window|ember|torch", re.I)
NOT_LIGHTS = re.compile(r"haze|fog|mist|beam|shaft|ray|dust", re.I)
HAZE = re.compile(r"haze|fog|mist|beam|shaft|ray|light|glow", re.I)
DARKENERS = re.compile(r"^black_(fader|solid)|soft_mask|Remasker|Main Mask|msk_generic", re.I)

# Screens in world units: left monitor 0-47.62, laptop 49.12-83.52 (21.5 tall), right monitor
# 85.02-132.64, all standing on the desk.
H = WORLD[1]
L0, L1 = 0.0, 47.62
C0, C1, C_TOP = 49.12, 83.52, 21.5
R0, R1 = 85.02, 132.64
GROUND = 1.5  # the ground under the Citadel; it rolls and climbs elsewhere
TREE = 11.5  # the walkway at the great tree's foot, from bridge to bridge across the laptop
TOP = 17.5  # the floor of Hornet's house
CEILING = 26.1  # underside of the rock along the top of the side monitors
BEZELS = ((L1 + C0) / 2, (C1 + R0) / 2)  # their middles
BAND = 7.0  # across a bezel, backdrops, colours and dressing change over this far on each side
CENTERS = ((L0 + L1) / 2, (C0 + C1) / 2, (R0 + R1) / 2)


@dataclass
class Zone:
    """The backdrop of one level: a stretch of a room, positioned by its floor and shown
    inside `region` (world x0, y0, x1, y1). A level's region reaches up through the floor above
    it (SEAM past its top), so it shows through that floor's holes; the rock hides the other edges.

    The room's floor near `floor` (refined from its terrain) lands at world height
    `world[1]`; the zone is `height` tall after the `cuts` (bands squeezed out of the room).
    mode "background" keeps only what stands behind Hornet (plus `props`); "full" keeps the
    room as it is, for rooms whose own floor is the world's floor there."""
    id: str
    room: str
    x: tuple  # left, right in room units
    floor: float  # roughly where the room's floor is
    world: tuple  # world x of the zone's left edge, world height of its floor
    height: float
    region: tuple
    biome: str = "moss"
    mode: str = "background"
    props: list = field(default_factory=list)  # regexes on GameObject names kept in a background
    below: float = 2.0
    refine: bool = True  # look for the room's exact floor near `floor` (False: `floor` is exact)
    flip: bool = False
    cuts: list = field(default_factory=list)
    remove: list = field(default_factory=list)  # regexes on GameObject names to leave out
    save: dict = field(default_factory=dict)  # save flags (PlayerData) the room is shown with
    haze: float = 0.22  # how far the backdrop recedes into its own average colour, behind the rock
    backdrop_z: float = BACKDROP_Z  # in a background, what stands nearer than this is left out
    near_ceiling: float = None  # in a full room, near pieces hanging above this (room height) are left out
    ground: tuple = None  # world box (x0, y0, x1, y1): the room's own solid shapes inside it are walked on
    margin: tuple = (0.0, 0.0)  # units rendered past the screen's left and right edges, to cross-fade
    fade: tuple = (0.0, 0.0)  # over these first and last units its backdrop fades in over its neighbours'

    def squeeze(self, y):
        """Room height after the cuts below it are taken out."""
        out = y
        for a, b in self.cuts:
            if y >= b:
                out -= b - a
            elif y > a:
                out -= y - a
        return out

    def unsqueeze(self, v):
        lo, hi = v - 1, v + sum(b - a for a, b in self.cuts) + 1
        for _ in range(60):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if self.squeeze(mid) < v else (lo, mid)
        return (lo + hi) / 2

    def frame(self, room_floor):
        """src (room rectangle, before cuts) and at (world bottom-left) for an exact room floor."""
        bottom = room_floor - self.below
        top = self.unsqueeze(self.squeeze(bottom) + self.height)
        return ((self.x[0] - self.margin[0], bottom, self.x[1] + self.margin[1], top),
                (self.world[0] - self.margin[0], self.world[1] - self.below))

    @property
    def size(self):
        return self.x[1] - self.x[0] + self.margin[0] + self.margin[1], self.height

    @property
    def back_region(self):
        """Where its backdrop shows: its screen and the margins it cross-fades over."""
        return (self.world[0] - self.margin[0], self.region[1],
                self.world[0] + self.x[1] - self.x[0] + self.margin[1], self.region[3])

    def key(self):
        """What the render depends on (the region and biome only matter when composing)."""
        spec = {k: v for k, v in asdict(self).items() if k not in ("region", "biome", "haze", "ground")}
        spec["render"] = RENDER_VERSION
        return hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]


ZONES = [
    # One backdrop per screen (the laptop has two, split inside the floor between them), so the
    # joins are hidden behind the bezels and the rock.
    Zone("grotto", "tut_02", x=(25.0, 72.62), floor=12.0, refine=False, below=0.0, world=(L0, 0.0), height=H + 0.2,
         region=(L0 - 0.8, 0.0, L1 + 0.8, H), margin=(0.0, BAND + 0.75), backdrop_z=2.5),
    # The Citadel's hall on the ground (2.5 units lower: the dark band under its bells is cut
    # out), the great tree above it.
    Zone("bell_beast", "bellway_city", x=(32.8, 67.2), floor=9.3, refine=False, world=(C0, GROUND), height=11.0,
         below=1.5, region=(C0 - 0.8, 0.0, C1 + 0.8, TREE - 1.0), biome="moss", mode="full", cuts=[(12.6, 15.1)],
         remove=[r"^Bone Beast NPC$"], haze=0.1, margin=(BAND + 0.75, BAND + 0.75), fade=(2 * BAND, 2 * BAND),
         near_ceiling=16.0, ground=(C0 - 1.0, -8.0, C1 + 1.0, 3.0)),
    Zone("great_tree", "mosstown_02", x=(69.3, 103.7), floor=33.0, world=(C0, TREE), height=11.3, below=1.0,
         region=(C0 - 0.8, TREE - 1.0, C1 + 0.8, C_TOP + 0.8), haze=0.12,
         ground=(C0 - 1.0, TREE - 1.0, C1 + 1.0, TREE + 3.0),  # the clock's plinth
         # Its own clock frame and the plinth it stands on; the walkway's moss is the world's.
         props=[r"^(Inert Sign|backing_(front|back)|writing|glow_text_sprite|string|Loom_Room_00(14|15|23|24)|Fallen Sign)"],
         margin=(BAND + 0.75, BAND + 0.75), fade=(2 * BAND, 2 * BAND)),
    Zone("verdania", "clover_02c", x=(155.0, 202.62), floor=41.4, refine=False, below=0.0, world=(R0, 0.0),
         height=H + 0.2, region=(R0 - 0.8, 0.0, R1 + 0.8, H), biome="clover", margin=(BAND + 0.75, 0.0)),
]

# Hornet's home: the top-left corner, built from her Bellhart house's own pieces.
HOME = {"region": (L0 + 0.9, TOP - 0.5, 20.5, CEILING), "door_x": 21.75, "biome": "house"}

# The lake at the foot of the right monitor's cliff, and the waterfall pouring into it from a
# crack in the rock above, down past the cliff's edge.
LAKE = {"x0": 99.0, "x1": 121.0, "level": 3.0}
WATERFALL = {"top": (119.7, 120.5, H + 0.1), "bottom": (119.0, 120.9), "zone": "verdania"}


def layout():
    """The world's rock, in world units. One ground runs under all three screens (moss reaches
    into the laptop and tapers onto the Citadel's own floor); the Citadel's arcade carries a
    walkway across the laptop and both bezels, ending a few units into each side screen; a few
    well-spaced islands, a climbable step, Hornet's balcony and a cliff with a niche behind the
    waterfall make the ways between. Nothing Hornet stands on is hidden."""
    rng = np.random.default_rng(11)
    T = terrain
    rocks = []
    # The ground: Mosshome's village flat and a mossy hill on the left, the Citadel's own floor
    # in the middle, a rise to the lake shore, the lake bed and the cliff's foot on the right.
    rocks.append(T.ground(rng, [(L0 - 1.5, 1.5), (6.0, 1.5), (13.0, 1.6), (16.5, 2.1), (20.0, 3.3), (24.0, 3.9),
                                (28.0, 3.8), (31.0, 3.1), (34.0, 2.1), (37.0, 1.6), (42.0, 1.5), (45.0, 1.6),
                                (47.0, 2.1), (48.0, 2.2), (49.4, 2.2), (50.6, 1.0), (51.6, 0.2)]))
    # (Under the laptop, the Citadel's own floor, level with the moss at both bezels: room_ground().)
    rocks.append(T.ground(rng, [(78.6, 0.2), (79.4, 1.2), (80.2, 2.2), (86.0, 2.2), (88.5, 1.9), (91.0, 2.3), (94.0, 3.4),
                                (98.4, 3.6), (100.2, 2.4), (103.0, 1.1), (108.0, 0.6), (114.0, 0.7), (118.0, 1.4),
                                (120.4, 3.0), (122.0, 3.9), (R1 + 1.5, 3.9)]))
    # Outer walls (the left one with a step to climb), the rock along the top of the side
    # monitors with a mass hanging from it, the hidden band above the laptop.
    # (Openings are left in both outer walls, behind the step and behind the shrine, for the
    # scenes beyond them one day.)
    rocks.append(T.box(rng, L0 - 1.5, 0.0, L0 + 0.9, 9.6))
    rocks.append(T.box(rng, L0 - 1.5, 13.4, L0 + 0.9, H + 1.0, walk_top=False))
    rocks.append(T.box(rng, L0 - 1.5, 0.5, 3.6, 9.6))
    rocks.append(T.box(rng, R1 - 0.9, 12.8, R1 + 1.5, H + 1.0, walk_top=False))
    rocks.append(T.box(rng, L0 - 1.5, CEILING, L1 + 0.8, H + 1.0, walk_top=False))
    rocks.append(T.blob(rng, [(31.0, CEILING + 0.3), (34.5, 24.2), (38.5, 23.4), (42.0, 24.0), (45.5, CEILING + 0.3)]))
    rocks.append(T.box(rng, R0 - 0.8, CEILING, R1 + 1.5, H + 1.0, walk_top=False))
    rocks.append(T.blob(rng, [(95.0, CEILING + 0.3), (98.0, 24.6), (102.5, 23.8), (106.0, 24.8), (109.0, CEILING + 0.3)]))
    rocks.append(T.box(rng, C0 - 0.8, C_TOP + 0.3, C1 + 0.8, H + 1.0, walk_top=False, dress=False))
    # Hornet's house: its floor runs out of her door onto a balcony, over a foundation in the
    # rock; the wall with her door.
    rocks.append(T.box(rng, L0 + 0.9, TOP - 0.6, 26.5, TOP, biome="bellhart"))
    rocks.append(T.blob(rng, [(L0 - 1.5, TOP - 0.4), (21.2, TOP - 0.4), (20.6, 16.0), (15.0, 15.6), (8.0, 15.5),
                              (2.0, 15.8), (L0 - 1.5, 15.4)], rounds=1))
    rocks += T.wall(rng, 20.5, 23.0, TOP, H + 1.0, doors=[(TOP, TOP + 3.1)], biome="bellhart")
    # Left monitor: from the hill up to an island, a higher one, and from there the balcony or
    # the walkway.
    rocks.append(T.island(rng, 23.0, 28.0, 8.8, depth=1.8))
    rocks.append(T.island(rng, 31.5, 36.5, 13.8, depth=1.8))
    # The walkway at the great tree's foot, on the Citadel's arcade.
    xs, _ = arcade_spans()
    rocks.append(T.Rock(arcade_points(), under="vault", under_x=(xs[0] + 0.1, xs[-1] - 0.1)))
    # Right monitor: the lake kept open. One island over it with the pod plant, a rock standing
    # in the water by the niche behind the waterfall, the low cliff with the shrine on top, a
    # ledge high on the wall; rings to throw her needle to instead of more islands.
    rocks.append(T.island(rng, 103.0, 112.0, 9.6, depth=2.4))
    rocks.append(T.blob(rng, [(115.6, 0.4), (115.9, 3.4), (116.6, 3.75), (117.8, 3.7), (118.4, 3.3), (118.6, 0.4)],
                        rounds=1))
    rocks.append(T.Rock(T.chaikin(CLIFF, 1)))
    rocks.append(T.Rock(T.chaikin(NICHE, 1), solid=False, dress=False))
    rocks.append(T.blob(rng, [(129.4, 18.8), (R1 + 1.5, 18.8), (R1 + 1.5, 16.6), (131.6, 17.0), (130.2, 17.8)],
                        rounds=1))
    return rocks


def room_ground():
    """The solid shapes of the rooms shown in full (the Citadel's floor and benches, the clock's
    plinth), where the world draws them: Hornet walks on exactly what's drawn there. From the
    rendered zones (zone.json); without them, a flat floor at GROUND stands in."""
    rocks = []
    for zone in ZONES:
        if zone.ground is None:
            continue
        meta_file = CACHE / zone.id / "zone.json"
        meta = json.loads(meta_file.read_text()) if meta_file.exists() else {}
        if "terrain" not in meta:
            if zone.id == "bell_beast":
                rocks.append(terrain.Rock([(C0 - 0.8, -1.0), (C1 + 0.8, -1.0), (C1 + 0.8, GROUND), (C0 - 0.8, GROUND)],
                                          draw=False))
            continue
        x0, y0, x1, y1 = zone.ground
        for sh in meta["terrain"]:
            pts = [tuple(p) for p in sh["points"]]
            loop = sh["closed"] or (len(pts) > 3 and np.allclose(pts[0], pts[-1]))
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            if loop and x0 <= min(xs) and max(xs) <= x1 and y0 <= min(ys) and max(ys) <= y1:
                rocks.append(terrain.Rock(pts, draw=False))
    return rocks


# The cliff on the right, low enough for the shrine on top, with a niche at the water's level
# behind the waterfall: a bench, out of the spray.
CLIFF = [(120.6, -1.0), (120.8, 3.0), (120.5, 3.9), (125.8, 3.9), (126.4, 4.8), (126.2, 7.0), (123.6, 7.6),
         (120.6, 7.6), (120.8, 8.3), (121.2, 9.0), (R1 + 1.2, 9.0), (R1 + 1.5, 9.0), (R1 + 1.5, -1.0)]
NICHE = [(120.3, 3.9), (125.9, 3.9), (126.5, 4.8), (126.3, 7.1), (123.6, 7.7), (120.3, 7.7)]  # its dark back

# Moves the rock alone doesn't give her: needle throws to rings (Clawline), and the pod plant
# on the island, which throws her across the lake when she strikes down on it.
MOVES = [
    {"kind": "harpoon", "ring": (93.2, 10.2), "from": (95.4, 3.5), "to": (90.4, TREE)},  # rings atop tall poles
    {"kind": "harpoon", "ring": (128.0, 15.9), "from": (126.8, 9.0), "to": (131.0, 18.8)},
    {"kind": "bounce", "pod": (110.2, 11.4), "from": (108.4, 9.6), "to": (122.8, 9.0)},
]

# Hand-placed pieces (anchors are fractions of each piece from its bottom-left): the pod plant on
# the island, Verdania's own (its bulb is what she strikes); the Clawline rings, the game's own.
DECOR = [
    {"kit": "clover_02c", "piece": "grove_pod_main0000@4.03", "x": 108.0, "y": 9.45, "w": 2.8, "anchor": (0.5, 0.25)},
    {"kit": "clover_02c", "piece": "grove_pod_branch_right", "x": 107.5, "y": 10.3, "w": 0.8, "anchor": (0.5, 0.0)},
    {"kit": "clover_02c", "piece": "Clover Bounce Pod Activator", "x": 108.0, "y": 9.4, "w": 1.9, "anchor": (0.5, 0.04)},
    {"kit": "clover_02c", "piece": "grove_pod_main0000@4.03", "x": 110.2, "y": 9.5, "w": 1.6, "anchor": (0.5, 0.25)},
    {"kit": "clover_02c", "piece": "Clover Bounce Pod Activator", "x": 110.2, "y": 10.15, "w": 1.15, "anchor": (0.5, 0.0)},
    *({"kit": "ring", "piece": "ring_backing_basic", "x": m["ring"][0], "y": m["ring"][1], "w": 1.25, "anchor": (0.5, 0.5)}
      for m in MOVES if m["kind"] == "harpoon"),
    {"kit": "ring", "piece": "Slab_tall_ring_pole_0001_1", "x": 128.0, "y": 8.85, "w": 0.5, "anchor": (0.5, 0.0)},
    {"kit": "ring", "piece": "Slab_tall_ring_pole_0001_1", "x": 93.2, "y": 2.75, "w": 0.55, "anchor": (0.5, 0.0)},
]


# The Citadel's ceiling: an arcade carrying the walkway at the tree's foot, arches between
# pillars, dressed with the Citadel's gilded trims.
ARCADE = {"from": 42.5, "to": 89.3, "arches": 6, "half_pillar": 0.65, "foot": 8.5, "crown": 9.9}


def arcade_spans():
    xs = np.linspace(ARCADE["from"], ARCADE["to"], ARCADE["arches"] + 1)
    pw = ARCADE["half_pillar"]
    return xs, [(a + pw, b - pw) for a, b in zip(xs, xs[1:])]


def arcade_points():
    """The arcade's outline: the walkway on top, round arches underneath."""
    xs, spans = arcade_spans()
    foot, crown = ARCADE["foot"], ARCADE["crown"]
    pw = ARCADE["half_pillar"]
    # Each end rounds off under the walkway like an island's, instead of a flat face.
    end = 1.6
    left = [(xs[0] - pw - end + end * (1 - math.cos(t)), TREE - (TREE - foot) * math.sin(t)) for t in np.linspace(0, math.pi / 2, 9)]
    right = [(xs[-1] + pw + end - end * (1 - math.cos(t)), TREE - (TREE - foot) * math.sin(t)) for t in np.linspace(math.pi / 2, 0, 9)]
    pts = [(xs[-1] + pw + end, TREE), (xs[0] - pw - end, TREE)] + left[1:]
    for l, r in spans:
        c, half = (l + r) / 2, (r - l) / 2
        pts.append((l, foot))
        pts += [(c + half * math.cos(t), foot + (crown - foot) * math.sin(t) ** 0.7) for t in np.linspace(math.pi, 0, 19)[1:-1]]
        pts.append((r, foot))
    pts += right[:-1]
    return pts


def vault_pieces():
    """Under each arch a gilded arch with filigree haunches; corbels under the pillars, lamps
    hanging from every other one. Anchors are fractions of each piece from its bottom-left."""
    xs, spans = arcade_spans()
    foot, crown = ARCADE["foot"], ARCADE["crown"]
    out = []
    for l, r in spans:
        half = (r - l) / 2
        # Haunches: the filigree's mass against the pillar, its curve rising to the crown.
        out.append({"kit": "bellway_city", "piece": "sc_small_wall@7.41", "x": l - 0.3, "y": TREE - 0.2, "w": half + 0.9, "anchor": (1.0, 1.0),
                    "flip": True})
        out.append({"kit": "bellway_city", "piece": "sc_small_wall@7.41", "x": r + 0.3, "y": TREE - 0.2, "w": half + 0.9, "anchor": (1.0, 1.0)})
    for l, r in spans:
        out.append({"kit": "bellway_city", "piece": "vending_machine_back_dock_floor_0000_1@9.57", "x": (l + r) / 2, "y": crown + 0.3,
                    "w": r - l + 0.5, "anchor": (0.5, 1.0)})
    for x in xs:
        out.append({"kit": "bellway_city", "piece": "SC_0057_sc_floor_04@1.87", "x": x, "y": foot + 0.3, "w": 1.7, "anchor": (0.5, 1.0)})
    return out


# Hornet's home, furnished with her Bellhart house's pieces, arranged as in her room (mirrored:
# her door is on the right here). A group is placed by its first piece's origin at world x (and
# its height above the floor as in the room, or `top`/`y`); the other pieces keep their offsets in
# the room. "spot" pieces aren't drawn: they mark where her animations play. Layers: back (behind
# Hornet and the rock), over (over the rock: her door), front (in front of her).
HOUSE = "belltown_room_spare"
HOUSE_FLOOR = 6.1  # the floor of her room, in room units
CAM_Z = 38.1  # the game camera's distance: farther pieces look smaller
FURNITURE = [
    # The back wall twice over, curtains between and at the sides.
    {"items": ["pinhome_0012_1@9.88"], "x": 5.5, "flip": True},
    {"items": ["pinhome_0012_1@9.88"], "x": 15.3},
    {"items": ["pinhome_0012_1@3.06"], "x": 10.5},
    {"items": ["pinhome_0012_1@3.52"], "x": 2.3},
    {"items": ["pinhome_0012_1@3.52"], "x": 19.0, "flip": True},
    # Drapes and fairy lights along the ceiling.
    *({"items": ["pinhome_0012_1@3.04"], "x": x, "top": CEILING + 0.5, "scale": 0.8, "flip": i % 2 == 1}
      for i, x in enumerate((1.4, 7.5, 13.5, 19.7))),
    *({"items": [{"piece": "pinhome_0012_1@6.67", "light": True}], "x": x, "top": CEILING + 0.3, "flip": i % 2 == 1}
      for i, x in enumerate((4.4, 10.5, 16.6))),
    # The gramophone (its horn high on the wall), the trophy shelf with her mementos, pots below.
    {"items": ["gramophone_base", "gramophone_horn"], "x": 2.6, "flip": True},
    {"items": ["trophy_shelf", "Grey Memento", "Hunter Heart", "Crowman Memento", "Hunter Memento", "Memento Garmond",
               "Memento Seth", "Memento Surface", "Sprintmaster Memento"], "x": 6.2, "flip": True},
    {"items": ["sc_junk_piles_small_0000_1"], "x": 5.6},
    # The bed under its arch, the desk with her lists, stool and lamp bug, the hanging tub.
    {"items": ["RestBench", "trophy_cabinet@1.88", "pinhome_0012_1@1.83", {"piece": "hornet@3.33", "spot": "bed"}],
     "x": 10.3, "flip": True},
    {"items": ["desk", "librarian_list", "materium_list", "momento_list", "relicseeker_list", "extra 2", "seat",
               "house_furnishing_0010_1@0.61", "house_furnishing_0010_1@0.65", {"piece": "shop_lamp_bug0000", "light": True},
               {"piece": "hornet@2.39", "spot": "desk", "scale": 0.93}], "x": 15.3, "flip": True},
    {"items": ["bucket sprite", "house_furnishing_0004_1@3.42", "house_furnishing_0005_1@0.66",
               "house_furnishing_0004_1@2.24", "house_furnishing_0005_1@2.03", "house_furnishing_0005_1@2.47"],
     "x": 18.0, "flip": True},
    # Her door in the wall, with its glow; the floorboards in front.
    {"items": ["pinhome_0012_1@2.94", {"piece": "hornet_door_glow", "light": True}], "x": 21.75, "flip": True,
     "layer": "over"},
    {"items": ["bone_relic_room_0007_1@11.66"], "x": 5.8, "layer": "front"},
    {"items": ["bone_relic_room_0007_1@11.66"], "x": 15.6, "layer": "front", "flip": True},
]


# Pieces from other rooms standing in the world: Mosshome's urns, lamp and fences in the
# village, Verdania's statue on the shrine island. Each stands on the ground under (x, near).
PROPS = [
    {"kit": "mosstown_01", "piece": "Bone_house_breakable_very_large", "x": 4.6, "near": 2.0, "sink": 0.25},
    {"kit": "mosstown_01", "piece": "Bone_house_pieces_post", "x": 7.6, "near": 2.0, "sink": 0.3, "light": True},
    {"kit": "mosstown_01", "piece": "Bone_house_pieces_squat", "x": 11.2, "near": 2.0, "sink": 0.2},
    {"kit": "mosstown_01", "piece": "Bone_house_breakable_point@1.55", "x": 13.0, "near": 2.0, "sink": 0.2},
    {"kit": "mosstown_01", "piece": "Bone_house_pieces_0007_3_thin@2.88", "x": 16.2, "near": 2.6, "sink": 0.5},
    {"kit": "clover_02c", "piece": "Sprite Whole", "x": 123.8, "near": 9.0, "sink": 0.3},
    {"kit": "bellway_city", "piece": "RestBench", "x": 123.3, "near": 3.9, "sink": 0.05},
]

# Places Hornet spends time, in world units, at about height `near`. Home spots are filled in
# from the furniture.
POIS = [
    {"id": "gramophone", "zone": "home", "x": 4.6, "near": TOP, "activity": "listen", "face": -1},
    {"id": "village", "zone": "grotto", "x": 9.5, "near": GROUND, "activity": "needolin"},
    {"id": "step", "zone": "grotto", "x": 2.2, "near": 9.6, "activity": "map"},
    {"id": "hill", "zone": "grotto", "x": 30.5, "near": 3.2, "activity": "lookup"},
    {"id": "balcony", "zone": "grotto", "x": 25.0, "near": TOP, "activity": "lookup"},
    {"id": "bell_beast", "zone": "bell_beast", "x": 62.5, "near": 0.7, "activity": "visit", "face": 1},
    {"id": "clock", "zone": "great_tree", "x": 64.0, "near": 12.4, "activity": "lookup"},
    {"id": "lake", "zone": "verdania", "x": 97.4, "near": 3.6, "activity": "needolin_sit", "face": 1},
    {"id": "island", "zone": "verdania", "x": 105.5, "near": 9.6, "activity": "lookup"},
    {"id": "shrine", "zone": "verdania", "x": 126.0, "near": 9.0, "activity": "kneel", "face": -1},
    {"id": "waterfall bench", "zone": "verdania", "x": 123.3, "near": 3.9, "activity": "bench", "face": -1, "seat": 0.3},
    {"id": "lookout", "zone": "verdania", "x": 131.4, "near": 18.8, "activity": "lookup"},
]


# ---------------------------------------------------------------------------- one zone

def floor_near(shapes, x0, x1, hint, ppu=16, reach=3.0, headroom=2.5):
    """Exact height of the walkable surface near `hint` across a room's x range (median)."""
    from PIL import ImageDraw
    lo, hi = hint - reach - 1, hint + reach + headroom + 1
    w, h = max(1, int((x1 - x0) * ppu)), int((hi - lo) * ppu)
    mask = Image.new("1", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    for pts, closed in shapes:
        xy = [((x - x0) * ppu, (hi - y) * ppu) for x, y in pts]
        if closed and len(xy) >= 3:
            draw.polygon(xy, fill=1)
        else:
            draw.line(xy, fill=1, width=2)
    solid = np.array(mask)
    found = []
    for c in range(0, w, 4):
        col = solid[:, c]
        for r in range(1, h):
            if col[r] and not col[r - 1]:
                above = col[:r][::-1]
                free = len(above) if not above.any() else int(np.argmax(above))
                y = hi - r / ppu
                if (free >= headroom * ppu or free == len(above)) and abs(y - hint) <= reach:
                    found.append(y)
                    break
    return float(np.median(found)) if found else hint


def render_zone(zone):
    """Render a zone's backdrop in its own room's colours into the cache."""
    import game
    import room

    out = CACHE / zone.id
    out.mkdir(parents=True, exist_ok=True)
    scene = room.Scene(zone.room)
    room.apply_save_state(scene, zone.save)
    removes = [re.compile(r) for r in zone.remove]
    props = [re.compile(r) for r in zone.props]
    items = [it for it in room.collect(scene)
             if not room.is_unwanted(scene, it.go) and not any(r.search(it.name) for r in removes)
             and not DARKENERS.search(it.name)]
    if zone.mode == "background":
        items = [it for it in items if (it.z >= zone.backdrop_z or any(r.search(it.name) for r in props)) and not silhouette(it)]
    blur_z = next((float(scene.world(scene.go_transform[o.read().m_GameObject.path_id])[2, 3]) for o in scene.objects
                   if o.type.name == "MonoBehaviour" and game.script_class(o) == "BlurPlane"), None)
    shapes = room.terrain(scene)
    room_floor = floor_near(shapes, zone.x[0], zone.x[1], zone.floor) if zone.refine else zone.floor
    src, at = zone.frame(room_floor)
    if zone.cuts:
        items = squeeze_items(zone, items)
    if zone.near_ceiling is not None:
        # They'd hang over the world's own structures (the arcade), cut off by the zone's top.
        items = [it for it in items if not (it.z < -1.0 and float(it.matrix[1, 3]) > zone.near_ceiling)]
    left, bottom, right = src[0], zone.squeeze(src[1]), src[2]
    top = bottom + zone.height
    cam = room.Camera(left, bottom, right - left, top - bottom, PPU)
    width_px = (right - left) * PPU
    screen = (zone.margin[0] * PPU, width_px - zone.margin[1] * PPU)

    def area(it):
        return (np.linalg.norm(it.matrix[:2, 0]) * abs(it.corners[1, 0] - it.corners[0, 0])
                * np.linalg.norm(it.matrix[:2, 1]) * abs(it.corners[2, 1] - it.corners[0, 1]))

    def cut_by_edge(it):
        """A prop the screen's edge would cut in half (terrain and big backgrounds stay): near
        pieces stop at the screen's edges, backdrops cross-fade past them to the render's."""
        w = it.matrix
        c = it.corners
        pts = [w @ np.array([x, y, 0, 1]) for x, y in (*c, c[1] + c[2] - c[0])]
        centre = w @ np.array([c[:, 0].mean(), c[:, 1].mean(), 0, 1])
        xs = [cam.project(q[0], q[1], float(centre[2]), centre[0], centre[1])[0] for q in pts]
        lo, hi = min(xs), max(xs)
        edges = screen if it.z < BACKDROP_Z else (0, width_px)
        return (it.layer not in room.TERRAIN_LAYERS and hi - lo < 8 * PPU and it.z < 15
                and any(lo < e < hi for e in edges))

    items = [it for it in items if not cut_by_edge(it)]
    # Haze and fog spread over the whole view, near or not: they belong with the backdrop, which
    # cross-fades into the next screen instead of stopping at the bezel.
    for it in items:
        if HAZE.search(it.name) and it.z < BACKDROP_Z and area(it) > 30:
            it.z = BACKDROP_Z
    back, mid, front, grade = room.render(scene, items, cam, blur_z=blur_z, mid_z=BACKDROP_Z)

    # Light sources are small: a huge lit window or a soft halo around a whole scene is background
    # (above the night tint it turns into a pale box), and other characters' lights aren't ours.
    lights = [it for it in items if LIGHT_NAMES.search(it.name) and not NOT_LIGHTS.search(it.name)
              and it.name != "HeroLight" and area(it) < 40]
    lit_back, lit_front, _ = room.render(scene, lights, cam, blur_z=None, blur_units=0)
    lit_back.alpha_composite(lit_front)
    lit_a = np.asarray(lit_back).astype(np.float32) / 255
    lum = lit_a[..., :3].max(-1, keepdims=True)
    lit = Image.fromarray((np.concatenate([np.where(lum > 0, lit_a[..., :3] / np.maximum(lum, 1e-6), 0), lum], -1) * 255)
                          .round().astype(np.uint8), "RGBA")

    def graded(img, bloom):
        a = np.asarray(img).astype(np.float32) / 255
        rgb = game.bloom(a[..., :3], PPU) if bloom else a[..., :3]
        a[..., :3] = grade.apply(rgb)
        rng = np.random.default_rng(0)
        a[..., :3] += (rng.random(rgb.shape, np.float32) - rng.random(rgb.shape, np.float32)) / 255
        return Image.fromarray((a.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")

    for img, name, bloom in ((back, "back", True), (mid, "mid", True), (front, "front", False), (lit, "lights", False)):
        img = graded(img, bloom)
        if zone.flip:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        img.save(out / f"{name}.png")
    def to_world(pts):
        out = []
        for x, y in pts:
            wx = at[0] + ((src[2] - x) if zone.flip else (x - src[0]))
            wy = at[1] + zone.squeeze(y) - zone.squeeze(src[1])
            out.append([round(float(wx), 3), round(float(wy), 3)])
        return out

    # The room's own solid ground, where the world shows it: Hornet walks on what's drawn.
    room_terrain = [{"points": to_world(pts), "closed": bool(closed)} for pts, closed in shapes
                    if src[0] - 2 <= max(p[0] for p in pts) and min(p[0] for p in pts) <= src[2] + 2
                    and src[1] - 2 <= max(p[1] for p in pts) and min(p[1] for p in pts) <= top + sum(b - a for a, b in zone.cuts) + 2]
    meta = {
        "key": zone.key(),
        "terrain": room_terrain,
        "roomFloor": round(room_floor, 3),
        "src": [round(v, 3) for v in src],
        "at": [round(v, 3) for v in at],
        "grade": grade_json(grade),
    }
    (out / "zone.json").write_text(json.dumps(meta))
    print(f"{zone.id}: floor {room_floor:.2f} in the room, {len(items)} sprites, {len(lights)} lights", file=sys.stderr)


def grade_json(grade):
    return {"lut": np.asarray(grade.lut).tolist(), "saturation": grade.saturation, "heroSaturation": grade.hero_saturation,
            "ambient": np.asarray(grade.ambient_rgb()).tolist(), "heroLight": grade.hero_light}


_darkness = {}


def silhouette(it):
    """A small sprite drawn in black: in a room it frames the view, in a backdrop it's a dark hole."""
    if id(it.image) not in _darkness:
        a = np.asarray(it.image).astype(np.float32) / 255
        w = a[..., 3]
        _darkness[id(it.image)] = float((a[..., :3].max(-1) * w).sum() / max(w.sum(), 1e-6))
    w = np.linalg.norm(it.matrix[:2, 0]) * abs(it.corners[1, 0] - it.corners[0, 0])
    h = np.linalg.norm(it.matrix[:2, 1]) * abs(it.corners[2, 1] - it.corners[0, 1])
    return _darkness[id(it.image)] * max(it.color[:3]) < 0.05 and w * h < 40


def squeeze_items(zone, items):
    """Slide everything above each cut down by its height; drop small pieces caught inside it."""
    kept = []
    for it in items:
        y = float(it.matrix[1, 3])
        inside = any(a < y < b for a, b in zone.cuts)
        tall = abs(it.corners[2, 1] - it.corners[0, 1]) * abs(it.matrix[1, 1]) > 2 * max(b - a for a, b in zone.cuts)
        if inside and not tall:
            continue
        it.matrix = it.matrix.copy()
        it.matrix[1, 3] = zone.squeeze(y)
        kept.append(it)
    return kept


# ---------------------------------------------------------------------------- the world

class _Grade:
    """game.Grade rebuilt from cached parameters."""

    def __init__(self, g):
        import game
        self.xs = np.linspace(0, 1, 256)
        self.lut = np.array(g["lut"])
        self.saturation = g["saturation"]
        self.hero_saturation = g["heroSaturation"]
        self._ambient = np.array(g["ambient"])
        self.hero_light = g["heroLight"]
        self.apply = lambda rgb: game.Grade.apply(self, rgb)
        self.hero_shader = lambda rgb: game.Grade.hero_shader(self, rgb)

    def ambient_rgb(self):
        return self._ambient


def blend_grades(grades, a, b, t):
    """A colour grade between two zones' (cached in `grades` under a tuple key)."""
    key = (a, b, t)
    if key not in grades:
        ga, gb = grades[a], grades[b]
        grades[key] = _Grade({
            "lut": (np.asarray(ga.lut) * (1 - t) + np.asarray(gb.lut) * t).tolist(),
            "saturation": ga.saturation * (1 - t) + gb.saturation * t,
            "heroSaturation": ga.hero_saturation * (1 - t) + gb.hero_saturation * t,
            "ambient": (np.asarray(ga.ambient_rgb()) * (1 - t) + np.asarray(gb.ambient_rgb()) * t).tolist(),
            "heroLight": ga.hero_light,
        })
    return key


def grade_image(img, grade):
    a = np.asarray(img).astype(np.float32) / 255
    a[..., :3] = grade.apply(a[..., :3])
    return Image.fromarray((a * 255).round().astype(np.uint8), "RGBA")


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def recede(img, zone, at_x, fogs):
    """Atmospheric depth: the backdrop drifts towards a haze colour and softens, so the rock
    Hornet walks on stands out in front of it. The haze colour runs from screen to screen
    (each screen's own in its middle), and thickens near the bezels: neighbouring backdrops
    meet in the same haze."""
    a = np.asarray(img).astype(np.float32) / 255
    x = at_x + (np.arange(a.shape[1]) + 0.5) / PPU
    laptop = fogs[zone.id] if zone.id in ("bell_beast", "great_tree") else (fogs["bell_beast"] + fogs["great_tree"]) / 2
    anchors = np.array([fogs["grotto"], laptop, fogs["verdania"]])
    fog = np.stack([np.interp(x, CENTERS, anchors[:, c]) for c in range(3)], -1)  # per column
    haze = zone.haze + 0.3 * sum(np.exp(-((x - b) / BAND) ** 2) for b in BEZELS)
    a[..., :3] = a[..., :3] * (1 - haze[None, :, None]) + fog[None] * haze[None, :, None]
    out = Image.fromarray((a.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")
    from PIL import ImageFilter
    return out.filter(ImageFilter.GaussianBlur(zone.haze * 4))


def zone_fog(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255
    return np.clip(a.reshape(-1, 3).mean(0) * 1.45, 0, 1)


def paste_region(layer, img, at, size, region, fade=0.0, hfade=(0.0, 0.0), top_fade=0.0):
    """Paste a zone's layer (world bottom-left `at`, `size` units) clipped to `region`; with
    `fade`, it fades in over that many units above the region's bottom (seen through holes in
    the floor, where it meets the level below); `hfade`, over that many units from its left
    and right ends (cross-fading with the next screen's); `top_fade`, over that many units
    below its top, outside the laptop (where the laptop's backdrops reach into the side screens
    lower than their own)."""
    Hpx = layer.height
    x0, y0 = round(at[0] * PPU), Hpx - round((at[1] + size[1]) * PPU)
    piece = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    piece.alpha_composite(img, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))
    rx0, ry0 = round(region[0] * PPU), Hpx - round(region[3] * PPU)
    rx1, ry1 = round(region[2] * PPU), Hpx - round(region[1] * PPU)
    mask = Image.new("L", layer.size, 0)
    mask.paste(255, (max(rx0, 0), max(ry0, 0), min(rx1, layer.width), min(ry1, Hpx)))
    if fade:
        n = round(fade * PPU)
        t = (np.arange(n, 0, -1) - 0.5) / n
        ramp = (255 * t * t * (3 - 2 * t)).round().astype(np.uint8)  # smoothstep, 0 at the region's bottom
        band = Image.fromarray(np.repeat(ramp[:, None], max(0, min(rx1, layer.width) - max(rx0, 0)), 1), "L")
        mask.paste(band, (max(rx0, 0), ry1 - n))
    m = np.asarray(mask).astype(np.float32)
    if any(hfade):
        cols = (np.arange(layer.width) + 0.5) / PPU
        ramp = np.ones(layer.width, np.float32)
        if hfade[0]:
            ramp *= smoothstep((cols - region[0]) / hfade[0])
        if hfade[1]:
            ramp *= smoothstep((region[2] - cols) / hfade[1])
        m *= ramp[None, :]
    if top_fade:
        rows = H - (np.arange(layer.height) + 0.5) / PPU
        vramp = smoothstep((region[3] - rows) / top_fade)
        cols = (np.arange(layer.width) + 0.5) / PPU
        outside = ((cols < C0) | (cols > C1)).astype(np.float32)
        m *= 1 - outside[None, :] * (1 - vramp[:, None])
    piece.putalpha(Image.fromarray(np.minimum(np.asarray(piece.getchannel("A")), m.round().astype(np.uint8))))
    layer.alpha_composite(piece)


def find_piece(kit, spec):
    """A kit piece by object name, "name@width" picking among same-named pieces by width."""
    name, _, width = spec.partition("@")
    cands = [p for p in kit.pieces if p["object"] == name]
    if width:
        cands.sort(key=lambda p: abs(p["width"] - float(width)))
    if not cands:
        raise SystemExit(f"no piece {spec!r} in the {kit.dir.name} kit")
    return cands[0]


def as_light(img):
    """A piece as the lights layer stores it: colour at full strength, brightness as alpha."""
    a = np.asarray(img).astype(np.float32) / 255
    lum = (a[..., :3] * a[..., 3:]).max(-1, keepdims=True)
    rgb = np.where(lum > 0, a[..., :3] * a[..., 3:] / np.maximum(lum, 1e-6), 0)
    return Image.fromarray((np.concatenate([rgb, lum], -1).clip(0, 1) * 255).round().astype(np.uint8), "RGBA")


def build_home(canvases, kit, grade):
    """Hornet's home from her house's pieces; returns where her bed and desk animations play."""
    spots = {}
    for group in FURNITURE:
        items = [i if isinstance(i, dict) else {"piece": i} for i in group["items"]]
        first = find_piece(kit, items[0]["piece"])
        s = CAM_Z / (CAM_Z + first["zMedian"]) * group.get("scale", 1.0)
        mirror = -1 if group.get("flip") else 1
        ox, oy = first["at"]
        base_y = TOP + (oy - HOUSE_FLOOR) * s
        if "y" in group:
            base_y = group["y"]
        elif "top" in group:
            base_y = group["top"] - (1 - first["pivot"][1]) * first["height"] * s
        for item in items:
            p = find_piece(kit, item["piece"])
            x = group["x"] + mirror * (p["at"][0] - ox) * s
            y = base_y + (p["at"][1] - oy) * s
            if item.get("spot"):
                spots[item["spot"]] = (round(x, 3), round(y, 3), item.get("scale", 1.0), bool(group.get("flip")))
                continue
            img = grade_image(kit.image(p), grade)
            args = (x, y, p["width"] * s, p["height"] * s, 0, bool(group.get("flip")))
            canvases[group.get("layer", "back")].paste(img, *args, anchor=tuple(p["pivot"]))
            if item.get("light"):
                canvases["lights"].paste(as_light(img), *args, anchor=tuple(p["pivot"]))
    return spots


def compose():
    OUT.mkdir(parents=True, exist_ok=True)
    W, Hpx = round(WORLD[0] * PPU), round(WORLD[1] * PPU)
    names = ("back", "mid", "front", "lights")
    layers = {n: Image.new("RGBA", (W, Hpx), (0, 0, 0, 255 if n == "back" else 0)) for n in names}
    zones_out, grades = [], {}
    # 1. Backdrops: behind Hornet's light (back), the rooms' own near pieces (mid), in front of her.
    # Each backdrop reaches past its screen; the laptop's fade in over the side screens' across
    # the bezels, all of them in the same haze there.
    metas = {z.id: json.loads((CACHE / z.id / "zone.json").read_text()) for z in ZONES}
    fogs = {z.id: zone_fog(Image.open(CACHE / z.id / "back.png")) for z in ZONES}
    for zone in sorted(ZONES, key=lambda z: any(z.fade)):
        cache = CACHE / zone.id
        meta = metas[zone.id]
        grades[zone.id] = _Grade(meta["grade"])
        for name in names:
            img = Image.open(cache / f"{name}.png").convert("RGBA")
            if name == "back":
                paste_region(layers[name], recede(img, zone, meta["at"][0], fogs), meta["at"], zone.size,
                             zone.back_region, hfade=zone.fade,
                             top_fade=4.0 if zone.region[3] < H - 0.5 else 0.0)
            else:
                paste_region(layers[name], img, meta["at"], zone.size, zone.region)
        zones_out.append({"id": zone.id, "room": zone.room, "left": zone.region[0], "bottom": zone.region[1],
                          "width": zone.region[2] - zone.region[0], "height": zone.region[3] - zone.region[1],
                          "floor": zone.world[1], "light": bake_light(zone.id, meta["grade"]),
                          "grade": hero_grade(zone.id, meta["grade"])})
    # 2. Hornet's home: no backdrop shows inside, only her furniture.
    hx0, hy0, hx1, hy1 = HOME["region"]
    box = (round(hx0 * PPU), 0, round(hx1 * PPU), Hpx - round(hy0 * PPU))  # up to the top: no backdrop over it
    for name, img in layers.items():
        img.paste((0, 0, 0, 255 if name == "back" else 0), box)

    def canvas(img):
        c = terrain.Canvas((1, 1), PPU)
        c.h_units, c.img = WORLD[1], img
        return c

    canvases = {name: canvas(img) for name, img in layers.items()}
    canvases["over"] = canvas(Image.new("RGBA", (W, Hpx), (0, 0, 0, 0)))
    house = terrain.Kit(HOUSE)
    house_g = json.loads((house.dir / "grade.json").read_text())
    grades["home"] = _Grade(house_g)
    spots = build_home(canvases, house, grades["home"])
    zones_out.append({"id": "home", "room": HOUSE, "left": hx0, "bottom": hy0, "width": hx1 - hx0,
                      "height": hy1 - hy0, "floor": TOP, "light": bake_light("home", house_g),
                      "grade": hero_grade("home", house_g)})
    bake_hornet()

    # 3. The rock, dressed for the zone each face looks into (or as its own biome says), in the
    # middle layer: in front of Hornet's light, behind her.
    def zone_at(x, y):
        if x <= hx1 + 0.5 and y >= hy0 + 0.2:  # the house, and the rock around it up there
            return "home"
        for z in reversed(ZONES):
            r = z.region
            if r[0] <= x <= r[2] and r[1] <= y <= r[3]:
                return z.id
        return None

    biome_of = {z.id: z.biome for z in ZONES}
    biome_of["home"] = HOME["biome"]
    biomes = {}
    pick = np.random.default_rng(8)

    def biome_at(x, y, own=None):
        """A face's biome. Moss gives way to clover gradually inside the right monitor, so a
        platform crossing the bezel looks the same on both sides."""
        if own:
            name = own
        else:
            zid = zone_at(x, y)
            if zid is None:
                return None
            name = biome_of[zid]
            if name in ("moss", "clover"):
                name = "clover" if pick.random() < smoothstep((x - 86.5) / 12.5) else "moss"
        if name not in biomes:
            biomes[name] = terrain.BIOMES[name]()
        return biomes[name]

    def grade_at(x, y):
        """The colours at a point: its zone's, blended with the next screen's across a bezel."""
        zid = zone_at(x, y) or "grotto"
        for b in BEZELS:
            if abs(x - b) < BAND and zid != "home":
                left, right = zone_at(b - BAND - 0.5, y), zone_at(b + BAND + 0.5, y)
                if left and right and left != right and left != "home":
                    t = round(float(smoothstep((x - b + BAND) / (2 * BAND))) * 4) / 4
                    return blend_grades(grades, left, right, t)
        return zid

    piece_cache = {}

    def graded(kit, piece, x, y):
        key = (piece["name"], kit.dir.name, grade_at(x, y))
        if key not in piece_cache:
            g = key[2]
            piece_cache[key] = grade_image(kit.image(piece), grades[g])
        return piece_cache[key]

    rocks = layout()
    kits = {}

    def place(items):
        """Hand-placed pieces: {kit, piece, x, y, w, anchor, flip, layer, light}."""
        for v in items:
            kit = kits.setdefault(v["kit"], terrain.Kit(v["kit"]))
            piece = find_piece(kit, v["piece"])
            img = graded(kit, piece, v["x"], v["y"] - 0.5)
            args = (v["x"], v["y"], v["w"], v["w"] * piece["height"] / piece["width"], v.get("angle", 0), v.get("flip", False))
            canvases[v.get("layer", "mid")].paste(img, *args, anchor=v["anchor"])
            if v.get("light"):
                canvases["lights"].paste(as_light(img), *args, anchor=v["anchor"])

    # The arcade's gilding goes on its bare rock, under the moss on its walkway.
    standing = [(q["x"] - 2.4, q["near"] - 1.0, q["x"] + 2.4, q["near"] + 1.0) for q in PROPS]
    standing += [(m["pod"][0] - 3.0, m["from"][1] - 1.0, m["pod"][0] + 1.5, m["from"][1] + 1.0) for m in MOVES if "pod" in m]
    terrain.dress(rocks, biome_at, canvases["mid"], canvases["front"], graded, np.random.default_rng(5),
                  underlay=lambda: place(vault_pieces()), no_plants=standing)
    place(DECOR)
    # Where a room's own floor is walked on, it's drawn over the world's moss running under it.
    for zone in ZONES:
        if zone.ground is not None and zone.mode == "full":
            r = zone.region
            paste_region(layers["mid"], Image.open(CACHE / zone.id / "mid.png").convert("RGBA"), metas[zone.id]["at"],
                         zone.size, (r[0], r[1], r[2], min(r[3], zone.ground[3] + 0.6)))
    # Moss from the walkway drapes over the arcade's edge, so it doesn't run as a straight line:
    # only the strands, cut from under each piece's black root mass (that works against rock,
    # not over the gilding).
    moss = biome_at(66.0, TREE + 1.0, "moss")

    def strands(piece):
        a = np.asarray(graded(moss.kit, piece, 66.0, TREE + 0.5)).astype(np.float32) / 255
        dark = (a[..., 3] > 0.6) & (a[..., :3].max(-1) < 0.06)
        rows = np.nonzero(dark.mean(1) < 0.2)[0]
        cut = int(rows[0]) if len(rows) else 0
        return Image.fromarray((a[cut:] * 255).round().astype(np.uint8), "RGBA"), 1 - cut / a.shape[0]

    drape = np.random.default_rng(12)
    last = None
    for x in np.arange(ARCADE["from"] - 1.0, ARCADE["to"] + 1.0, 1.9):
        c = terrain.choose(drape, moss.ceiling, last)
        last = c["name"]
        img, kept = strands(c)
        k = drape.uniform(0.3, 0.5)
        x += drape.uniform(-0.4, 0.4)
        canvases["mid"].paste(img, x, TREE - 0.15, c["width"] * k, c["height"] * k * kept, 0, drape.random() < 0.5,
                              anchor=(0.5, 1.0))
    # Her door, over the wall's rock, standing on the floor.
    door = canvases["over"].img
    door.paste((0, 0, 0, 0), (round(hx1 * PPU), Hpx - round((TOP - 0.15) * PPU), round((HOME["door_x"] + 2) * PPU), Hpx))
    layers["mid"].alpha_composite(door)

    # 4. Props from other rooms, standing on the ground; the lake and its waterfall.
    solid = nav.solid_map(WORLD, [r.points for r in rocks if r.solid])
    for prop in PROPS:
        kit = kits.setdefault(prop["kit"], terrain.Kit(prop["kit"]))
        piece = find_piece(kit, prop["piece"])
        x = prop["x"]
        y = ground_at(solid, x, prop["near"]) - prop.get("sink", 0.0)
        zid = zone_at(x, y + 1) or "grotto"
        img = grade_image(kit.image(piece), grades[zid])
        args = (x, y, piece["width"], piece["height"], 0, prop.get("flip", False))
        canvases[prop.get("layer", "mid")].paste(img, *args, anchor=(0.5, 0.0))
        if prop.get("light"):
            canvases["lights"].paste(as_light(img), *args, anchor=(0.5, 0.0))
    # The waterfall falls in front of Hornet: sitting in the niche, she's seen through it.
    draw_waterfall(layers["front"], grades[WATERFALL["zone"]])
    rock_px = Image.new("1", (W, Hpx), 0)
    from PIL import ImageDraw
    for r in rocks:
        ImageDraw.Draw(rock_px).polygon([(x * PPU, (WORLD[1] - y) * PPU) for x, y in r.points], fill=1)
    draw_water(layers, np.array(rock_px), grades[WATERFALL["zone"]])

    for old in OUT.glob("*_??.png"):
        old.unlink()
    # What earlier builds left: lights and curves of zones that are gone, per-zone Hornet sheets.
    current = {z["light"]["file"] for z in zones_out} | {z["grade"]["lut"] for z in zones_out}
    for old in [*OUT.glob("light_*.png"), *OUT.glob("lut_*.png")]:
        if old.name not in current:
            old.unlink()
    if (OUT / "zones").is_dir():
        shutil.rmtree(OUT / "zones")
    tiles = {name: save_tiles(img, name) for name, img in layers.items()}
    preview = layers["back"].copy()
    preview.alpha_composite(layers["mid"])
    preview.alpha_composite(layers["front"])
    preview.convert("RGB").save(OUT / "preview.jpg", quality=85)

    # 5. Navigation over the same rock; she keeps out of the lake.
    nav_map, _ = nav.build(WORLD, [r.points for r in rocks + room_ground() if r.solid], water=[(LAKE["x0"], LAKE["x1"], LAKE["level"])],
                         moves=MOVES)
    pois = list(POIS)
    for spot, activity in (("bed", "sleep"), ("desk", "desk")):
        x, y, scale, mirror = spots[spot]
        pois.append({"id": spot, "zone": "home", "x": x, "near": TOP, "activity": activity, "pivot": [x, y],
                     "scale": round(scale, 3), "mirror": mirror})
    nav_map["pois"] = place_pois(nav_map, zones_out, pois)
    draw_nav(preview, nav_map).convert("RGB").save(OUT / "nav.jpg", quality=85)
    data = {
        "build": int(time.time()),  # new URLs for the tiles: a running wallpaper reloads them
        "unitMm": UNIT_MM,
        "width": round(WORLD[0], 3),
        "height": round(WORLD[1], 3),
        "pixelsPerUnit": PPU,
        "layers": tiles,
        "zones": zones_out,
        "heroFeet": HERO_FEET,
        "nav": nav_map,
    }
    # Replaced in one step, so the running wallpapers' folder watch sees a new file and reloads.
    tmp = OUT / ".World.qml.tmp"
    tmp.write_text("// Generated by packages/silksong-wallpaper/tools/world.py\nimport QtQml\n\n"
                   f"QtObject {{\n    readonly property var world: ({json.dumps(data)})\n}}\n")
    os.replace(tmp, OUT / "World.qml")
    kinds = {}
    for link in nav_map["links"]:
        kinds[link["kind"]] = kinds.get(link["kind"], 0) + 1
    print(f"world: {W}x{Hpx} px, {', '.join(f'{len(t)} {n}' for n, t in tiles.items())} tiles, {len(zones_out)} zones, "
          f"{len(rocks)} rocks, {len(nav_map['surfaces'])} surfaces, links {kinds} -> {OUT}", file=sys.stderr)


def ground_at(solid, x, near):
    """Height of the ground under x, the surface closest below about `near`."""
    c = int(x * nav.NAV_PPU)
    H = solid.shape[0]
    r = max(0, int((WORLD[1] - near - 1.5) * nav.NAV_PPU))
    while r < H - 1 and not (solid[r + 1, c] and not solid[r, c]):
        r += 1
    return WORLD[1] - (r + 1) / nav.NAV_PPU


def draw_waterfall(layer, grade):
    """The waterfall: from the crack in the rock above down to the lake, widening; sheets of
    water with streaks, brighter at its edges."""
    rng = np.random.default_rng(4)
    shallow, light = (grade.apply(np.array(c)) for c in ((0.42, 0.78, 0.72), (0.86, 1.0, 0.96)))
    level = LAKE["level"]

    def row(y):
        return round((WORLD[1] - y) * PPU)

    (tl, tr, ytop), (bl, br) = WATERFALL["top"], WATERFALL["bottom"]
    ra, rb = row(ytop), row(level)
    cx0, cx1 = round(min(tl, bl) * PPU) - 4, round(max(tr, br) * PPU) + 4
    n = cx1 - cx0
    u = np.arange(n) / PPU
    streak = sum(rng.uniform(0.3, 1.0) * np.sin(u * f + rng.uniform(0, 6.3)) for f in rng.uniform(6, 40, 9))
    streak = (streak - streak.min()) / (streak.max() - streak.min())
    fall = np.zeros((rb - ra, n, 4), np.float32)
    xs = np.arange(n)
    for i in range(rb - ra):
        f = i / max(1, rb - ra - 1)
        fe = f ** 0.6  # it spreads quickly after the lip, then falls straight
        left, right = (tl + (bl - tl) * fe) * PPU - cx0, (tr + (br - tr) * fe) * PPU - cx0
        inside = (xs >= left) & (xs <= right)
        edge = np.clip(1 - np.minimum(xs - left, right - xs) / (0.22 * PPU), 0, 1)
        drift = streak[(xs + int(i * 0.03)) % n]  # streaks lean very slightly
        a = (0.22 + 0.45 * drift + 0.3 * edge) * inside
        mix = np.clip(edge * 0.7 + drift * 0.25, 0, 1)[:, None]
        fall[i, :, :3] = shallow * (1 - mix) + light * mix
        fall[i, :, 3] = a
    layer.alpha_composite(Image.fromarray((fall.clip(0, 1) * 255).round().astype(np.uint8), "RGBA"), (cx0, ra))


def draw_water(layers, rock, grade):
    """The lake, in front of Hornet, with foam and ripples where the waterfall lands: still
    placeholders in the game's manner, a tinted body with a bright edge."""
    Hpx, W = rock.shape
    rng = np.random.default_rng(3)
    deep, shallow, light = (grade.apply(np.array(c)) for c in ((0.16, 0.42, 0.40), (0.42, 0.78, 0.72), (0.86, 1.0, 0.96)))

    def row(y):
        return round((WORLD[1] - y) * PPU)

    # The lake: deeper, darker, more opaque; a bright line along the surface, glints under it.
    x0, x1, level = round(LAKE["x0"] * PPU), round(LAKE["x1"] * PPU), LAKE["level"]
    r0 = row(level)
    depth = (np.arange(r0, Hpx) - r0)[:, None] / PPU
    t = np.clip(depth / 2.2, 0, 1)
    body = np.zeros((Hpx - r0, x1 - x0, 4), np.float32)
    body[..., :3] = (shallow * (1 - t[..., None]) + deep * t[..., None]) * np.ones((1, x1 - x0, 1))
    body[..., 3] = (0.42 + 0.4 * t) * np.ones((1, x1 - x0))
    water = ~rock[r0:, x0:x1]
    body[..., 3] *= water
    body[:3, :, :3] = light
    body[:3, :, 3] = 0.9 * water[:3]
    for _ in range(70):  # glints
        gy = r0 + int(rng.uniform(0.15, 1.3) * PPU)
        gx = int(rng.uniform(0, x1 - x0 - 40))
        n = int(rng.uniform(12, 50))
        body[gy - r0, gx:gx + n, :3] = light
        body[gy - r0, gx:gx + n, 3] = np.maximum(body[gy - r0, gx:gx + n, 3], 0.35 * water[gy - r0, gx:gx + n])
    lake = Image.fromarray((body.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")
    layers["front"].alpha_composite(lake, (x0, r0))

    bl, br = WATERFALL["bottom"]
    # Ripples spreading on the lake from where it lands.
    from PIL import ImageDraw
    ripples = Image.new("RGBA", (round(8 * PPU), round(1.2 * PPU)), (0, 0, 0, 0))
    d = ImageDraw.Draw(ripples)
    rc = (ripples.width / 2, round(0.25 * PPU))
    col = tuple(int(c * 255) for c in light)
    for k, rx in enumerate((0.9, 1.6, 2.5, 3.5)):
        ry = rx * 0.12
        d.ellipse([rc[0] - rx * PPU, rc[1] - ry * PPU, rc[0] + rx * PPU, rc[1] + ry * PPU], outline=col + (int(150 / (k + 1)),),
                  width=2)
    rx0, ry0 = round((bl + br) / 2 * PPU - ripples.width / 2), r0 - rc[1] + 2
    on_water = ~rock[ry0:ry0 + ripples.height, rx0:rx0 + ripples.width]
    cols = rx0 + np.arange(ripples.width)
    on_water &= ((cols >= x0) & (cols < x1))[None, :]
    a = np.asarray(ripples).copy()
    a[..., 3] = np.where(on_water, a[..., 3], 0)
    layers["front"].alpha_composite(Image.fromarray(a, "RGBA"), (rx0, ry0))

    # Foam and mist where it meets the lake.
    cx, cy = (bl + br) / 2, level
    size = (round(6 * PPU), round(4 * PPU))
    yy, xx = np.mgrid[0:size[1], 0:size[0]]
    ux, uy = (xx - size[0] / 2) / PPU, (size[1] / 2 - yy) / PPU
    mist = 0.28 * np.exp(-(ux ** 2 / 4.0 + (uy - 0.6) ** 2 / 1.6))
    foam = np.zeros_like(mist)
    for _ in range(40):
        bx, by = rng.normal(0, 0.7), rng.uniform(-0.15, 0.35)
        foam = np.maximum(foam, 0.8 * np.exp(-(((ux - bx) / 0.35) ** 2 + ((uy - by) / 0.18) ** 2)))
    a = np.clip(np.maximum(mist, foam), 0, 1)
    sx0, sy0 = round(cx * PPU - size[0] / 2), round((WORLD[1] - cy) * PPU - size[1] / 2)
    a *= ~rock[sy0:sy0 + size[1], sx0:sx0 + size[0]]  # spray over water and air, never over the rock
    spray = np.zeros(size[::-1] + (4,), np.float32)
    spray[..., :3] = light
    spray[..., 3] = a
    layers["front"].alpha_composite(Image.fromarray((spray * 255).round().astype(np.uint8), "RGBA"), (sx0, sy0))


def place_pois(nav_map, zones_out, pois):
    """Snap each point of interest onto the surface under it closest to its height `near`."""
    placed = []
    for poi in pois:
        best = None
        for i, sf in enumerate(nav_map["surfaces"]):
            if sf["x0"] <= poi["x"] <= sf["x1"]:
                y = nav.height(sf, poi["x"])
                if best is None or abs(y - poi["near"]) < abs(best[1] - poi["near"]):
                    best = (i, y)
        if best is None or abs(best[1] - poi["near"]) > 2.0:
            print(f"warning: no ground under {poi['id']} at x={poi['x']} near {poi['near']}", file=sys.stderr)
            continue
        placed.append(dict({k: v for k, v in poi.items() if k != "near"}, surface=best[0], y=round(best[1], 3)))
    return placed


def draw_nav(img, nav_map):
    """Debug view: surfaces in magenta, links coloured by kind, on the world preview."""
    from PIL import ImageDraw
    img = img.convert("RGB").copy()
    d = ImageDraw.Draw(img)
    Hpx = img.height

    def p(x, y):
        return x * PPU, Hpx - y * PPU

    for s in nav_map["surfaces"]:
        pts = [p(s["x0"] + i * nav_map["step"], y) for i, y in enumerate(s["y"])]
        d.line(pts, fill=(255, 0, 255), width=4)
    colors = {"walk": (255, 255, 255), "drop": (80, 160, 255), "jump": (255, 200, 0), "jump2": (255, 120, 0),
              "climb": (0, 255, 120), "harpoon": (240, 240, 255), "bounce": (120, 255, 60)}
    for e in nav_map["links"]:
        a, b = p(e["x0"], e["y0"] + 0.4), p(e["x1"], e["y1"] + 0.4)
        d.line([a, b], fill=colors[e["kind"]], width=3)
        d.ellipse([b[0] - 6, b[1] - 6, b[0] + 6, b[1] + 6], fill=colors[e["kind"]])
    for poi in nav_map.get("pois", []):
        x, y = p(poi["x"], poi["y"] + 1.5)
        d.ellipse([x - 10, y - 10, x + 10, y + 10], outline=(255, 80, 80), width=4)
        d.text((x + 12, y - 8), poi["id"], fill=(255, 255, 255))
    return img


def save_tiles(img, prefix):
    tiles = []
    for i, x in enumerate(range(0, img.width, TILE_PX)):
        tile = img.crop((x, 0, min(img.width, x + TILE_PX), img.height))
        if prefix != "back" and tile.getchannel("A").getbbox() is None:
            continue
        name = f"{prefix}_{i:02d}.png"
        tile.save(OUT / name, optimize=True)
        tiles.append({"file": name, "x": x, "width": tile.width})
    return tiles


def bake_hornet():
    """Hornet's sheets, once, with her share of the camera bloom around her but in no room's
    colours: the wallpaper colours her for the zone she's in on the GPU (hornet.frag, with
    hero_grade's parameters). Skipped when her extracted sheets haven't changed."""
    import game
    src = sorted((DATA / "hornet").glob("*.png"))
    out = OUT / "hornet"
    out.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1("".join(f"{p.name}{p.stat().st_mtime}" for p in src).encode()).hexdigest()
    stamp = out / ".source"
    if stamp.exists() and stamp.read_text() == key:
        return
    sheet_ppu = 64
    for png in src:
        a = np.asarray(Image.open(png).convert("RGBA")).astype(np.float32) / 255
        alpha = a[..., 3:4]
        lit = a[..., :3]
        bright = np.maximum(lit - game.BLOOM_THRESHOLD, 0) * game.BLOOM_INTENSITY * alpha
        halo = game.blur(bright, game.BLOOM_SIGMA_X * sheet_ppu, game.BLOOM_SIGMA_Y * sheet_ppu)
        # Additive light over a dark room is close to blending its hue at its brightest channel.
        h_alpha = halo.max(-1, keepdims=True).clip(0, 1)
        h_rgb = np.where(h_alpha > 0, halo / np.maximum(h_alpha, 1e-6), 0)
        out_a = alpha + h_alpha * (1 - alpha)
        out_rgb = (lit * alpha + h_rgb * h_alpha * (1 - alpha)) / np.maximum(out_a, 1e-6)
        sheet = np.concatenate([out_rgb, out_a], -1)
        Image.fromarray((sheet.clip(0, 1) * 255).round().astype(np.uint8), "RGBA").save(out / png.name, optimize=True)
    stamp.write_text(key)
    print(f"Hornet: {len(src)} sheets -> {out}", file=sys.stderr)


def hero_grade(zone_id, g):
    """What hornet.frag needs to colour Hornet as a zone's room would: its ambient light and
    hero saturation (Sprites/Default-ColorFlash with IS_HERO), its camera curves (a 256x1
    lookup image) and saturation."""
    grade = _Grade(g)
    lut = (np.asarray(grade.lut).reshape(1, -1, 3).clip(0, 1) * 255).round().astype(np.uint8)
    name = f"lut_{zone_id}.png"
    Image.fromarray(lut, "RGB").save(OUT / name)
    return {"lut": name, "ambient": [round(float(v), 4) for v in grade.ambient_rgb()],
            "heroSaturation": round(float(grade.hero_saturation), 4), "saturation": round(float(grade.saturation), 4)}


def bake_light(zone_id, g):
    """Hornet's light for a zone (HeroLight, screen-blended: white at alpha = its brightness),
    stored at full strength with the zone's strength beside it; the wallpaper raises it at night."""
    import game
    grade = _Grade(g)
    light = game.hero_light()
    tex = np.asarray(light["image"]).astype(np.float32) / 255
    color = np.array(light["color"]) * np.array([grade.hero_light[c] for c in "rgba"])
    strength = (tex[..., :3] * color[:3]).max(-1) * tex[..., 3] * color[3]
    peak = float(strength.max())
    img = np.zeros(tex.shape, np.float32)
    img[..., :3] = grade.apply(np.ones(3))
    img[..., 3] = strength / max(peak, 1e-6)
    name = f"light_{zone_id}.png"
    Image.fromarray((img.clip(0, 1) * 255).round().astype(np.uint8), "RGBA").save(OUT / name, optimize=True)
    x0, y0, x1, y1 = light["box"]
    sx, sy = light["scale"]
    ox, oy = light["offset"]
    return {"file": name, "left": ox + x0 * sx, "bottom": oy + y0 * sy, "width": (x1 - x0) * sx, "height": (y1 - y0) * sy,
            "strength": round(peak, 3)}


# What the previous layout had there and this one doesn't, drawn faintly in the wireframe so the
# changes show.
PREVIOUS = []  # nothing removed since the approved layout


def wireframe_svg():
    """The level as a to-scale drawing (SVG markup, styled by the page around it): the screens
    and what's hidden, the rock, water, Hornet's places with her silhouette to scale, the ways
    between them, and the islands the previous layout had."""
    k = 10.0
    pad = 2.0
    width, height = (WORLD[0] + 2 * pad) * k, (WORLD[1] + 2 * pad + 4.5) * k

    def X(x):
        return f"{(x + pad) * k:.1f}"

    def Y(y):
        return f"{(WORLD[1] + pad - y) * k:.1f}"

    def poly(points, cls):
        return f'<polygon class="{cls}" points="{" ".join(f"{X(x)},{Y(y)}" for x, y in points)}"/>'

    out = [f'<svg viewBox="0 0 {width:.0f} {height:.0f}" role="img" aria-label="To-scale wireframe of the aquarium '
           'across the three screens: rock, water, Hornet\'s places and the ways between them.">',
           '<defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
           '<line x1="0" y1="0" x2="0" y2="6" class="hatch"/></pattern></defs>']
    # What the screens show, and what is never visible.
    out.append(f'<clipPath id="world"><rect x="{X(0)}" y="{Y(H)}" width="{WORLD[0] * k:.1f}" height="{H * k:.1f}"/></clipPath>')
    for x0, x1, h, name, size in ((L0, L1, H, "left monitor", "Moss Grotto backdrop"),
                                  (C0, C1, C_TOP, "laptop", "great tree over the Citadel station"),
                                  (R0, R1, H, "right monitor", "Verdania backdrop")):
        out.append(f'<rect class="screen" x="{X(x0)}" y="{Y(h)}" width="{(x1 - x0) * k:.1f}" height="{h * k:.1f}"/>')
        out.append(f'<text class="screen-name" x="{X(x0)}" y="{float(Y(h)) - 6:.1f}">{name} <tspan class="dim">{size}</tspan></text>')
    for x0, x1, y0, y1 in ((L1, C0, 0, H), (C1, R0, 0, H), (C0, C1, C_TOP, H)):
        out.append(f'<rect class="hidden-area" x="{X(x0)}" y="{Y(y1)}" width="{(x1 - x0) * k:.1f}" height="{(y1 - y0) * k:.1f}"/>')
    # Water first, the rock over it, all inside the world's edges.
    out.append('<g clip-path="url(#world)">')
    out.append(f'<rect class="water" x="{X(LAKE["x0"])}" y="{Y(LAKE["level"])}" width="{(LAKE["x1"] - LAKE["x0"]) * k:.1f}" '
               f'height="{LAKE["level"] * k:.1f}"/>')
    rocks = layout()
    for r in rocks:
        if r.points and min(y for _, y in r.points) > H:
            continue
        out.append(poly(r.points, "rock" if r.draw else "rock floor-of-room"))
    (tl, tr, ytop), (bl, br) = WATERFALL["top"], WATERFALL["bottom"]
    out.append(poly([(tl, min(ytop, H)), (tr, min(ytop, H)), (br, LAKE["level"]), (bl, LAKE["level"])], "falls"))
    out.append('</g>')
    for x, y, anchor in ((L0 + 0.3, 11.5, "start"), (R1 - 0.3, 10.9, "end")):
        out.append(f'<text class="label opening" x="{X(x)}" y="{Y(y)}" text-anchor="{anchor}">opening</text>')
    hx0, hy0, hx1, hy1 = HOME["region"]
    out.append(f'<rect class="house" x="{X(hx0)}" y="{Y(hy1)}" width="{(hx1 - hx0) * k:.1f}" height="{(hy1 - hy0) * k:.1f}"/>')
    out.append(f'<text class="label strong" x="{X(hx0 + 0.6)}" y="{Y(hy1 - 1.4)}">Hornet\'s house</text>')
    xs, _ = arcade_spans()
    out.append(f'<text class="label" x="{X((xs[0] + xs[-1]) / 2)}" y="{Y(ARCADE["foot"] - 0.9)}" text-anchor="middle">'
               'Citadel arcade, gilded arches on both sides of each bezel</text>')
    # The previous layout's islands that are gone.
    out.append('<g class="previous">')
    for x0, x1, top in PREVIOUS:
        out.append(f'<rect class="old" x="{X(x0)}" y="{Y(top)}" width="{(x1 - x0) * k:.1f}" height="{1.2 * k:.1f}" rx="4"/>')
    out.append('</g>')
    # Hornet's ways.
    nav_map, _ = nav.build(WORLD, [r.points for r in rocks + room_ground() if r.solid], water=[(LAKE["x0"], LAKE["x1"], LAKE["level"])],
                         moves=MOVES)
    out.append('<g class="ways">')
    for e in nav_map["links"]:
        x0, y0, x1, y1 = e["x0"], e["y0"] + 1.3, e["x1"], e["y1"] + 1.3
        via = e.get("ring") or e.get("pod")
        if via:
            vx, vy = via
            if e["kind"] == "harpoon":  # the throw to the ring, then she flies there and lets go
                out.append(f'<path class="way harpoon" d="M{X(x0)},{Y(y0)} L{X(vx)},{Y(vy)} Q{X(x1)},{Y(vy + 1.0)} {X(x1)},{Y(y1)}"/>')
            else:  # onto the pod from above, then thrown high
                out.append(f'<path class="way bounce" d="M{X(x0)},{Y(y0)} Q{X((x0 + vx) / 2)},{Y(vy + 2.5)} {X(vx)},{Y(vy + 0.8)} '
                           f'Q{X((vx + x1) / 2)},{Y(max(vy, y1) + 7.0)} {X(x1)},{Y(y1)}"/>')
            continue
        lift = max(y0, y1) + (1.2 if e["kind"] in ("jump", "jump2") else 0.0)
        cx, cy = (x0 + x1) / 2, lift if e["kind"] != "climb" else (y0 + y1) / 2
        if e["kind"] == "climb":
            cx = x0
        out.append(f'<path class="way {e["kind"]}" d="M{X(x0)},{Y(y0)} Q{X(cx)},{Y(cy)} {X(x1)},{Y(y1)}"/>')
    out.append('</g>')
    for sf in nav_map["surfaces"]:
        pts = " ".join(f"{X(sf['x0'] + i * nav_map['step'])},{Y(y)}" for i, y in enumerate(sf["y"]))
        out.append(f'<polyline class="surface" points="{pts}"/>')
    # The rings she throws her needle to, the pod plant on the island.
    for m in MOVES:
        if m["kind"] == "harpoon":
            rx, ry = m["ring"]
            out.append(f'<circle class="ring" cx="{X(rx)}" cy="{Y(ry)}" r="{0.65 * k:.1f}"/>')
            out.append(f'<text class="label" x="{X(rx + 0.9)}" y="{Y(ry + 0.6)}">ring</text>')
        else:
            px, py = m["pod"]
            base = m["from"][1]
            out.append(f'<path class="pod-stem" d="M{X(px)},{Y(base)} C{X(px - 1.2)},{Y(base + 1.0)} {X(px + 0.8)},{Y(py - 0.8)} {X(px)},{Y(py - 0.3)}"/>')
            out.append(f'<ellipse class="pod" cx="{X(px)}" cy="{Y(py)}" rx="{0.6 * k:.1f}" ry="{0.55 * k:.1f}"/>')
            out.append(f'<ellipse class="pod" cx="{X(px - 1.3)}" cy="{Y(base + 0.7)}" rx="{0.9 * k:.1f}" ry="{0.75 * k:.1f}"/>')
            out.append(f'<text class="label" x="{X(px + 0.9)}" y="{Y(py + 0.6)}">pod plant</text>')
    # Hornet at her places, to scale (1 unit wide, 2.6 tall), and her props.
    for prop in PROPS:
        if prop["piece"] in ("RestBench",):
            out.append(f'<rect class="prop" x="{X(prop["x"] - 1.6)}" y="{Y(prop["near"] + 1.0)}" width="{3.2 * k:.1f}" height="{1.0 * k:.1f}" rx="3"/>')
    places = place_pois(nav_map, [], [dict(q) for q in POIS]) + [
        {"id": "bed", "x": 9.9, "y": TOP}, {"id": "desk", "x": 15.4, "y": TOP}]
    for q in places:
        x, y = q["x"], q["y"]
        out.append(f'<path class="hornet" d="M{X(x - 0.45)},{Y(y)} L{X(x + 0.45)},{Y(y)} L{X(x + 0.3)},{Y(y + 1.5)} '
                   f'L{X(x - 0.3)},{Y(y + 1.5)} Z M{X(x - 0.28)},{Y(y + 1.5)} L{X(x + 0.28)},{Y(y + 1.5)} L{X(x + 0.2)},{Y(y + 2.1)} '
                   f'L{X(x - 0.2)},{Y(y + 2.1)} Z M{X(x - 0.2)},{Y(y + 2.0)} L{X(x - 0.3)},{Y(y + 2.6)} L{X(x - 0.05)},{Y(y + 2.05)} Z '
                   f'M{X(x + 0.2)},{Y(y + 2.0)} L{X(x + 0.3)},{Y(y + 2.6)} L{X(x + 0.05)},{Y(y + 2.05)} Z"/>')
        out.append(f'<text class="label place" x="{X(x)}" y="{Y(y + 3.1)}" text-anchor="middle">{q["id"]}</text>')
    # Scale along the bottom.
    for v in range(0, 131, 10):
        out.append(f'<line class="tick" x1="{X(v)}" y1="{Y(-0.6)}" x2="{X(v)}" y2="{Y(-1.1)}"/>')
        out.append(f'<text class="tick-label" x="{X(v)}" y="{Y(-2.3)}" text-anchor="middle">{v * 10} mm</text>')
    out.append(f'<text class="tick-label" x="{X(WORLD[0])}" y="{Y(-3.6)}" text-anchor="end">1 game unit = 10 mm on the glass · '
               'Hornet stands about 26 mm tall</text>')
    out.append('</svg>')
    return "\n".join(out)


def layout_preview(path):
    """The rock, the lake, the screens and Hornet's ways, quickly: for working on layout()."""
    from PIL import ImageDraw
    k = 20
    rocks = layout()
    img = Image.new("RGB", (round(WORLD[0] * k), round(WORLD[1] * k)), (24, 28, 34))
    d = ImageDraw.Draw(img)

    def p(x, y):
        return x * k, (WORLD[1] - y) * k

    for x0, x1, h in ((L0, L1, H), (C0, C1, C_TOP), (R0, R1, H)):
        d.rectangle([p(x0, h), p(x1, 0)], fill=(40, 48, 58))
    for r in rocks:
        d.polygon([p(x, y) for x, y in r.points], fill=(110, 120, 90) if r.draw else (90, 70, 110))
    d.rectangle([p(LAKE["x0"], LAKE["level"]), p(LAKE["x1"], 0)], outline=(80, 180, 220))
    (tl, tr, ytop), (bl, br) = WATERFALL["top"], WATERFALL["bottom"]
    d.polygon([p(tl, ytop), p(tr, ytop), p(br, LAKE["level"]), p(bl, LAKE["level"])], fill=(120, 200, 230))
    hx0, hy0, hx1, hy1 = HOME["region"]
    d.rectangle([p(hx0, hy1), p(hx1, hy0)], outline=(220, 120, 80), width=2)
    nav_map, _ = nav.build(WORLD, [r.points for r in rocks + room_ground() if r.solid], water=[(LAKE["x0"], LAKE["x1"], LAKE["level"])],
                         moves=MOVES)
    nav_map["pois"] = place_pois(nav_map, [], [dict(q) for q in POIS])
    colors = {"walk": (255, 255, 255), "drop": (80, 160, 255), "jump": (255, 200, 0), "jump2": (255, 120, 0),
              "climb": (0, 255, 120), "harpoon": (240, 240, 255), "bounce": (120, 255, 60)}
    for sf in nav_map["surfaces"]:
        d.line([p(sf["x0"] + i * nav_map["step"], y) for i, y in enumerate(sf["y"])], fill=(255, 0, 255), width=3)
    for e in nav_map["links"]:
        via = e.get("ring") or e.get("pod")
        pts = [p(e["x0"], e["y0"] + 0.3)] + ([p(*via)] if via else []) + [p(e["x1"], e["y1"] + 0.3)]
        d.line(pts, fill=colors[e["kind"]], width=2)
    for m in MOVES:
        x, y = p(*(m.get("ring") or m.get("pod")))
        d.ellipse([x - 8, y - 8, x + 8, y + 8], outline=colors[m["kind"]], width=3)
    for q in nav_map["pois"]:
        x, y = p(q["x"], q["y"] + 1.2)
        d.ellipse([x - 6, y - 6, x + 6, y + 6], outline=(255, 80, 80), width=3)
        d.text((x + 8, y - 6), q["id"], fill=(255, 255, 255))
    img.save(path, quality=90)
    kinds = {}
    for link in nav_map["links"]:
        kinds[link["kind"]] = kinds.get(link["kind"], 0) + 1
    print(f"{len(rocks)} rocks, {len(nav_map['surfaces'])} surfaces, links {kinds}, {len(nav_map['pois'])} places -> {path}",
          file=sys.stderr)


# ---------------------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--only", nargs="*", help="zones to re-render even if unchanged")
    p.add_argument("--zone", help=argparse.SUPPRESS)  # internal: render one zone in this process
    p.add_argument("--compose-only", action="store_true", help="skip rendering, compose cached zones")
    p.add_argument("--layout", metavar="IMAGE", help="only draw the rock and Hornet's ways into IMAGE")
    p.add_argument("--wireframe", metavar="SVG", help="write the to-scale wireframe (SVG markup) into SVG")
    args = p.parse_args()

    if args.layout:
        layout_preview(args.layout)
        return
    if args.wireframe:
        Path(args.wireframe).write_text(wireframe_svg())
        return
    if args.zone:
        render_zone(next(z for z in ZONES if z.id == args.zone))
        return
    if not args.compose_only:
        for zone in ZONES:
            meta = CACHE / zone.id / "zone.json"
            fresh = meta.exists() and json.loads(meta.read_text()).get("key") == zone.key()
            if fresh and not (args.only and zone.id in args.only):
                continue
            print(f"rendering {zone.id} from {zone.room}", file=sys.stderr)
            subprocess.run([sys.executable, __file__, "--zone", zone.id], check=True)
    compose()


if __name__ == "__main__":
    main()

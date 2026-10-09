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
import zlib
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

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
GROUND = 1.5  # the lowest flat ground; it rolls and climbs elsewhere
PIT = 7.0  # the floor of the Bellway station's pit, in its room (bellway_city)
CITADEL_FLOOR = 3.7  # the station's floor at both its ends, where the ground on either side meets it
CLIFF_TOP = 9.8  # the shrine's ground, over the bench's niche
LOOKOUT = 19.4  # the ledge high on the right wall
TREE = 11.5  # the walkway at the great tree's foot, from bridge to bridge across the laptop
TOP = 17.5  # the floor of Hornet's house
CEILING = 26.1  # underside of the rock along the top of the side monitors
BEZELS = ((L1 + C0) / 2, (C1 + R0) / 2)  # their middles
BAND = 7.0  # across a bezel, backdrops, colours and dressing change over this far on each side
# How far the backdrops cross-fade on each side of each bezel: the right one joins two unlike
# rooms (the great tree's haze, Verdania's clover), over more of both screens.
BANDS = (BAND, 10.0)
SOFTEN = 0.1  # at a bezel, the backdrops blur by this much (units) too: they meet as soft as each other
# (not a room drawn in full, whose back layer stands right behind its floor)
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
    anchors: dict = field(default_factory=dict)  # name -> regex on GameObject names: where it is, in the world
    particles: list = field(default_factory=list)  # regexes on GameObject names: its ambient particles, kept
    animated: dict = field(default_factory=dict)  # group -> regex on GameObject names: pieces animated apart
    margin: tuple = (0.0, 0.0)  # units rendered past the screen's left and right edges, to cross-fade
    # Per side, a depth: in that margin, pieces standing wholly in it are kept only from that depth
    # back (None: all of them). What's near in a margin belongs to the room beyond the screen, and
    # it would land in the bezel's gap with an edge of its own; the far background cross-fades.
    margin_far: tuple = (None, None)
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
        if not any(v is not None for v in self.margin_far):
            del spec["margin_far"]
        spec["render"] = RENDER_VERSION
        return hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]


ZONES = [
    # One backdrop per screen (the laptop has two, split inside the floor between them), so the
    # joins are hidden behind the bezels and the rock.
    Zone("grotto", "tut_02", x=(25.0, 72.62), floor=12.0, refine=False, below=0.0, world=(L0, 0.0), height=H + 0.2,
         region=(L0 - 0.8, 0.0, L1 + 0.8, H), margin=(0.0, BAND + 0.75), backdrop_z=2.5),
    # The Citadel's hall on the ground (2.5 units lower: the dark band under its bells is cut
    # out), the great tree above it. Its Bellway station is open: no toll machine, the floor's
    # gate slid away, the Bell Beast (drawn apart, it moves) in its pit of bells.
    Zone("bell_beast", "bellway_city", x=(32.8, 67.2), floor=PIT, refine=False, world=(C0, 0.7), height=11.0,
         below=0.7, region=(C0 - 0.8, 0.0, C1 + 0.8, TREE - 1.0), biome="moss", mode="full", cuts=[(12.6, 15.1)],
         remove=[r"^Bone Beast NPC$", r"^Bellway Toll Machine", r"^bellway_floor_gate$", r"^Bellbeast Children"],
         animated={"floor_bells": r"^Bell Boss Floor"},  # they jingle when something stirs among them
         anchors={"bell_beast": r"^Bone Beast NPC$"}, haze=0.1, margin=(BANDS[0] + 0.75, BANDS[1] + 0.75), fade=(2 * BANDS[0], 2 * BANDS[1]),
         near_ceiling=16.0, ground=(C0 - 1.0, -8.0, C1 + 1.0, 4.6)),
    Zone("great_tree", "mosstown_02", x=(69.3, 103.7), floor=33.0, world=(C0, TREE), height=11.3, below=1.0,
         region=(C0 - 0.8, TREE - 1.0, C1 + 0.8, C_TOP + 0.8), haze=0.12,
         ground=(C0 - 1.0, TREE - 1.0, C1 + 1.0, TREE + 3.0),  # the clock's plinth
         # Its own clock frame and the plinth it stands on; the walkway's moss is the world's.
         # (its glyphs are left out: the window is the clock's dial, centred where they were).
         props=[r"^(Inert Sign|backing_(front|back)|string|Loom_Room_00(14|15|23|24)|Fallen Sign)"],
         anchors={"clock": r"^writing$"},
         margin=(BANDS[0] + 0.75, BANDS[1] + 0.75), fade=(2 * BANDS[0], 2 * BANDS[1]),
         margin_far=(None, 6.0)),  # its moss pillar stands just past the laptop's right edge
    Zone("verdania", "clover_02c", x=(155.0, 202.62), floor=41.4, refine=False, below=0.0, world=(R0, 0.0),
         height=H + 0.2, region=(R0 - 0.8, 0.0, R1 + 0.8, H), biome="clover", margin=(BANDS[1] + 0.75, 0.0),
         particles=[r"^immediate_BG"]),  # its fireflies
]

# Hornet's home: the top-left corner, built from her Bellhart house's own pieces.
HOME = {"region": (L0 + 0.9, TOP - 0.5, 20.5, CEILING), "door_x": 21.75, "biome": "house"}

# The lake at the foot of the right monitor's cliff, and the waterfall pouring into it from a
# crack in the rock above, down past the cliff's edge into a deep pool between the stepping rock
# and the cliff.
LAKE = {"x0": 99.0, "x1": 121.0, "level": 3.0}
LAKE_BED_SOFT = 0.25  # how softly the water's body meets the bed and the shores (units)
WATERFALL = {"top": (119.3, 119.95, H + 0.1), "bottom": (118.85, 120.35), "zone": "verdania"}


def layout():
    """The world's rock, in world units. One ground runs under all three screens (moss reaches
    into the laptop and tapers onto the Citadel's own floor); the Citadel's arcade carries a
    walkway across the laptop and both bezels, ending a few units into each side screen; a few
    well-spaced islands, a climbable step, Hornet's balcony and a cliff with a niche behind the
    waterfall make the ways between. Nothing Hornet stands on is hidden."""
    def R(name):
        """Each rock's own randomness: reshaping one never reshapes the others."""
        return np.random.default_rng([11, zlib.crc32(name.encode())])

    T = terrain
    rocks = []
    # The ground: Mosshome's village flat and a mossy hill on the left, the Citadel's own floor
    # in the middle, a rise to the lake shore, the lake bed and the cliff's foot on the right.
    rocks.append(T.ground(R("ground left"), [(L0 - 1.5, 1.5), (6.0, 1.5), (13.0, 1.6), (16.5, 2.1), (20.0, 3.3), (24.0, 3.9),
                                (28.0, 3.8), (31.0, 3.1), (34.0, 2.1), (37.0, 1.6), (41.0, 1.5), (43.5, 1.8),
                                (45.5, 2.6), (47.0, 3.4), (48.0, CITADEL_FLOOR), (49.4, CITADEL_FLOOR), (50.6, 2.5), (51.6, 1.7)]))
    # (Under the laptop, the Citadel's own floor, level with the moss at both bezels: room_ground().)
    rocks.append(T.ground(R("ground right"), [(78.6, 1.7), (79.4, 2.7), (80.2, CITADEL_FLOOR), (86.0, CITADEL_FLOOR), (88.5, 3.2), (91.0, 2.9), (94.0, 3.4),
                                (98.4, 3.6), (100.2, 2.4), (103.0, 1.1), (108.0, 0.6), (114.0, 0.7), (118.2, 0.9),
                                (119.5, 0.3), (120.4, 0.8), (120.8, 3.0), (122.0, 3.9), (R1 + 1.5, 3.9)]))
    # Outer walls (the left one with a step to climb), the rock along the top of the side
    # monitors with a mass hanging from it, the hidden band above the laptop.
    # (Openings are left in both outer walls, behind the step and behind the shrine, for the
    # scenes beyond them one day.)
    rocks.append(T.box(R("wall left"), L0 - 1.5, 0.0, L0 + 0.9, 9.6))
    rocks.append(T.box(R("wall left high"), L0 - 1.5, 13.4, L0 + 0.9, H + 1.0, walk_top=False))
    rocks.append(T.box(R("step"), L0 - 1.5, 0.5, 3.6, 9.6))
    rocks.append(T.blob(R("wall right high"), [(131.3, H + 1.0), (R1 + 1.5, H + 1.0), (R1 + 1.5, LOOKOUT - 0.6),
                                                 (131.3, LOOKOUT - 0.4)], rounds=1, amp=0.08))
    rocks.append(T.box(R("ceiling left"), L0 - 1.5, CEILING, L1 + 0.8, H + 1.0, walk_top=False))
    rocks.append(T.blob(R("hanging mass left"), [(31.0, CEILING + 0.3), (34.5, 24.2), (38.5, 23.4), (42.0, 24.0), (45.5, CEILING + 0.3)]))
    rocks.append(T.box(R("ceiling right"), R0 - 0.8, CEILING, R1 + 1.5, H + 1.0, walk_top=False))
    rocks.append(T.blob(R("hanging mass right"), [(95.0, CEILING + 0.3), (98.0, 24.6), (102.5, 23.8), (106.0, 24.8), (109.0, CEILING + 0.3)]))
    rocks.append(T.box(R("above the laptop"), C0 - 0.8, C_TOP + 0.3, C1 + 0.8, H + 1.0, walk_top=False, dress=False))
    # Hornet's house: its floor runs out of her door onto a balcony, over a foundation in the
    # rock; the wall with her door.
    rocks.append(T.box(R("house floor"), L0 + 0.9, TOP - 0.6, 26.5, TOP, biome="bellhart", level=True))
    rocks.append(T.blob(R("house foundation"), [(L0 - 1.5, TOP - 0.4), (21.2, TOP - 0.4), (20.6, 16.0), (15.0, 15.6), (8.0, 15.5),
                              (2.0, 15.8), (L0 - 1.5, 15.4)], rounds=1))
    rocks += T.wall(R("house wall"), 20.5, 23.0, TOP, H + 1.0, doors=[(TOP, TOP + 3.1)], biome="bellhart")
    # Left monitor: from the hill up to an island, a higher one, and from there the balcony or
    # the walkway.
    rocks.append(T.island(R("island left low"), 23.0, 28.0, 8.8, depth=1.8))
    rocks.append(T.island(R("island left high"), 31.5, 36.5, 13.8, depth=1.8))
    # The walkway at the great tree's foot, on the Citadel's arcade.
    xs, _ = arcade_spans()
    rocks.append(T.Rock(arcade_points(), under="vault", under_x=(xs[0] + 0.1, xs[-1] - 0.1)))
    # Right monitor: the lake kept open. One island over it with the pod plant, a rock standing
    # in the water by the niche behind the waterfall, the low cliff with the shrine on top, a
    # ledge high on the wall; rings to throw her needle to instead of more islands.
    rocks.append(T.island(R("island right"), 103.0, 112.0, 9.6, depth=2.4))
    rocks.append(T.blob(R("boulder"), [(115.2, 0.3), (115.6, 2.5), (116.1, 3.5), (117.1, 3.85), (118.1, 3.6), (118.6, 2.7),
                              (118.4, 1.4), (117.8, 0.3)], rounds=2, tags={"in_water"}))  # a stone standing in the pool
    rocks.append(T.Rock(T.chaikin(CLIFF, 1)))
    rocks.append(T.Rock(T.chaikin(NICHE, 2), solid=False, dress=False, soft=0.35))
    rocks.append(T.Rock(T.chaikin(DOORWAY, 2), solid=False, dress=False, soft=0.25))
    # The lookout, and under it the entrance to what lies beyond: its underside curves down into
    # the wall like a lintel.
    rocks.append(T.blob(R("lookout"), [(128.8, LOOKOUT), (R1 + 1.5, LOOKOUT), (R1 + 1.5, 15.4), (132.0, 15.7),
                                        (130.8, 16.7), (129.7, 17.8), (129.0, 18.7)], rounds=1))
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
                rocks.append(terrain.Rock([(C0 - 0.8, -1.0), (C1 + 0.8, -1.0), (C1 + 0.8, CITADEL_FLOOR), (C0 - 0.8, CITADEL_FLOOR)],
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


# The cliff on the right, low enough for the shrine on top, with an arched niche at the water's
# level behind the waterfall: a bench, out of the spray. Its dark back fades out towards the open
# side; the doorway behind the shrine (an opening for scenes beyond the screen) has one too.
CLIFF = [(120.6, -1.0), (120.8, 3.0), (120.5, 3.9), (125.8, 3.9), (126.5, 4.9), (126.6, 7.0), (125.7, 8.1),
         (123.9, 8.6), (122.0, 8.5), (120.6, 8.4), (120.8, 9.2), (121.2, CLIFF_TOP), (R1 + 1.2, CLIFF_TOP),
         (R1 + 1.5, CLIFF_TOP), (R1 + 1.5, -1.0)]
NICHE = [(120.9, 3.8), (125.9, 3.8), (126.7, 4.9), (126.8, 7.1), (125.8, 8.3), (123.9, 8.8), (120.9, 8.6)]
DOORWAY = [(130.0, CLIFF_TOP - 0.2), (R1 + 1.5, CLIFF_TOP - 0.2), (R1 + 1.5, 16.2), (131.6, 16.5), (130.5, 15.8),
           (129.9, 14.2), (129.8, 11.4)]

# Moves the rock alone doesn't give her: needle throws to rings (Clawline), and the pod plant
# on the island, which throws her across the lake when she strikes down on it.
MOVES = [
    {"kind": "harpoon", "ring": (93.2, 10.2), "from": (95.4, 3.5), "to": (90.4, TREE)},  # rings atop tall poles
    {"kind": "harpoon", "ring": (127.0, 16.4), "from": (126.2, CLIFF_TOP), "to": (130.6, LOOKOUT)},
    {"kind": "bounce", "pod": (110.2, 11.4), "from": (108.4, 9.6), "to": (122.8, CLIFF_TOP)},
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
    {"kit": "ring", "piece": "Slab_tall_ring_pole_0001_1", "x": 127.0, "y": CLIFF_TOP - 0.15, "w": 0.5, "anchor": (0.5, 0.0)},
    # The shrine's statue stands in a bed of clover, as in its room: its plinth sunk in leaves.
    {"kit": "clover_02c", "piece": "Aspid__0007_1@6.8", "x": 123.9, "y": CLIFF_TOP - 0.45, "w": 5.4, "anchor": (0.5, 0.0), "layer": "front"},
    {"kit": "clover_02c", "piece": "Aspid_break_bushes_0003_1", "x": 121.9, "y": CLIFF_TOP - 0.3, "w": 2.0, "anchor": (0.5, 0.0), "layer": "front"},
    {"kit": "clover_02c", "piece": "clover___0007_ground@2.4", "x": 126.1, "y": CLIFF_TOP - 0.1, "w": 1.9, "anchor": (0.5, 0.0)},
    {"kit": "ring", "piece": "Slab_tall_ring_pole_0001_1", "x": 93.2, "y": 2.75, "w": 0.55, "anchor": (0.5, 0.0)},
]


# The air, from the game's own atmosphere pieces placed against our world (in the colours of the
# zone each stands in), moving in WorldScene: light shafts falling behind the rock, slanted as the
# game slants them, that follow the daylight and carry drifting dust; mist at the foot of each
# backdrop; haze floating in front of everything, as the rooms hang it; mist lying on the lake;
# soft glows. `gain` scales the piece's own alpha; shafts end above what they fall on.
BEAM_PIECE = ("tut_02", "white_palace_light_beam")
HAZE_PIECE = ("clover_02c", "haze2")
FOG_PIECE = ("tut_02", "temp fog")
AIR = [
    # Left: two shafts from behind the mass hanging from the ceiling (clear of Hornet's house).
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (35.0, CEILING), "length": 24.0, "width": 3.4, "gain": 1.7},
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (45.2, CEILING), "length": 23.0, "width": 2.2, "gain": 1.5},
    # The laptop: two on the great tree, ending on the walkway (the station below is roofed).
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (56.6, C_TOP + 0.2), "length": 10.2, "width": 2.4, "gain": 1.4},
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (80.2, C_TOP + 0.2), "length": 10.2, "width": 1.9, "gain": 1.3},
    # Right: one onto the lake, one onto the shrine.
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (106.5, CEILING), "length": 23.0, "width": 3.6, "gain": 1.6},
    {"kind": "shaft", "piece": BEAM_PIECE, "top": (129.0, CEILING), "length": 17.0, "width": 2.4, "gain": 1.5},
    # Mist at the foot of the backdrops, behind the rock.
    {"kind": "mist", "layer": "back", "piece": FOG_PIECE, "x": (3.0, 48.5), "y": 1.3, "height": 4.5, "gain": 1.0},
    {"kind": "mist", "layer": "back", "piece": FOG_PIECE, "x": (48.5, 85.0), "y": TREE - 0.4, "height": 3.0, "gain": 0.9},
    {"kind": "mist", "layer": "back", "piece": ("clover_02c", "temp fog"), "x": (85.0, R1 + 1.0), "y": 2.0, "height": 4.5, "gain": 1.2},
    # Mist lying on the lake, in front.
    {"kind": "mist", "layer": "front", "piece": HAZE_PIECE, "x": (99.3, 118.6), "y": LAKE["level"] - 0.5, "height": 1.7, "gain": 1.6},
    # Haze floating in front of everything, as Verdania's room hangs it.
    {"kind": "haze", "layer": "front", "piece": HAZE_PIECE, "at": (13.0, 7.5), "size": (13.0, 3.0), "gain": 1.0},
    {"kind": "haze", "layer": "front", "piece": HAZE_PIECE, "at": (37.5, 18.5), "size": (11.5, 2.7), "gain": 1.0},
    {"kind": "haze", "layer": "front", "piece": HAZE_PIECE, "at": (94.5, 14.5), "size": (14.0, 3.4), "gain": 1.0},
    {"kind": "haze", "layer": "front", "piece": HAZE_PIECE, "at": (114.0, 19.0), "size": (12.0, 3.0), "gain": 0.9},
    # Soft glows: where the waterfall lands, in the grotto's open air, over the tree's foot.
    {"kind": "haze", "layer": "back", "piece": ("clover_02c", "white_haze"), "at": (120.0, 5.5), "size": (7.0, 6.0), "gain": 0.6},
    {"kind": "haze", "layer": "back", "piece": ("clover_02c", "white_haze"), "at": (27.5, 5.0), "size": (10.0, 8.0), "gain": 0.45},
    {"kind": "haze", "layer": "back", "piece": ("clover_02c", "white_haze"), "at": (71.0, 14.5), "size": (9.0, 6.0), "gain": 0.4},
    # The shrine's glow, as its statue has in its room.
    {"kind": "haze", "layer": "back", "piece": ("clover_02c", "white_haze"), "at": (123.8, 13.0), "size": (7.5, 8.0), "gain": 0.5},
]
SHAFT_ANGLE = -10.1  # degrees: the game's light beams lean so, light falling from the upper right
# The beams' dust (Bellhart's) is emitted along their depth axis, which a flat world can't show:
# it drifts slowly about instead (units/s: x min, max; y min, max).
BEAM_DUST = ("belltown", "light_beam_particles 3")
DUST_DRIFT = [-0.12, 0.12, -0.14, 0.08]

# Particle systems from other rooms (tools/kit.py particles ROOM), placed in our world, each as
# its room's camera sees it at its own depth: in a box (x0, y0, x1, y1) or along an edge (x0, x1,
# y); `count` particles alive; behind the rock, or in front of everything ("layer": "front").
# Motes and dust are glitter: our side screens show the world at 40 px a unit where the game
# shows 65, so they're drawn larger ("grow") to read on screen as they do in the game.
MOTES = [
    # Left: the grotto's motes (the next room's, tut_03) far back, near, and big and blurred in
    # front; its amber fungus spores; drips from the moss under the house, the mass hanging from
    # the ceiling and the low island.
    {"kit": "tut_03", "system": "far BG", "box": (3.6, 2.0, 25.0, 15.0), "count": 64, "grow": 1.8},
    {"kit": "tut_03", "system": "far BG", "box": (25.0, 2.0, 47.5, 15.0), "count": 64, "grow": 1.8},
    {"kit": "tut_03", "system": "far BG", "box": (27.0, 15.5, 47.5, 23.0), "count": 40, "grow": 1.8},
    {"kit": "tut_03", "system": "immediate_BG", "box": (3.6, 2.0, 47.5, 14.0), "count": 48, "grow": 1.6},
    {"kit": "tut_03", "system": "fung_immediate_BG", "box": (22.0, 2.5, 46.0, 12.0), "count": 16, "grow": 1.4, "layer": "front"},
    {"kit": "tut_03", "system": "FG", "box": (0.0, 0.0, 47.6, H), "count": 12, "grow": 1.3, "layer": "front"},
    {"kit": "tut_03", "system": "Fungus_drips", "edge": (2.0, 20.0, 15.4), "count": 2},
    {"kit": "tut_03", "system": "Fungus_drips", "edge": (33.0, 44.0, 23.6), "count": 2},
    {"kit": "tut_03", "system": "Fungus_drips", "edge": (24.0, 27.0, 7.4), "count": 1},
    # The laptop: Mosshome's low smoke drifting along the walkway at the tree's foot; dust
    # falling through two cracks in the arcade into the station, now and then a pebble.
    {"kit": "mosstown_02", "system": "low_smoke_Particle", "edge": (50.0, 84.0, TREE + 0.3), "count": 10, "layer": "front"},
    {"kit": "bellway_city", "system": "debris_fall_no_collision", "edge": (57.6, 58.6, 8.4), "count": 10},
    {"kit": "bellway_city", "system": "debris_fall_no_collision", "edge": (74.2, 75.0, 8.4), "count": 8},
    {"kit": "bellway_city", "system": "Particle System", "edge": (57.6, 58.6, 8.4), "count": 1},
]


# The small life of our rooms (life.js crittersAt; their clips: extract.py). Moss flies roam the
# grotto's air behind the rock, as the grotto's do (dimmed by the game's own tint, at their
# depth); dragonflies hover over the meadow and the lake, darting up, down, left or right, and
# hold still while Hornet plays her needolin nearby; lilypad flies sit on the shores, the island
# and the cliff, sing along to her needolin, and fly to their next perch when she comes close.
# home (x, y), range (half width, half height); perches: (x, ground, facing right).
CRITTERS = [
    *({"id": f"moss{i}", "species": "moss_fly", "home": home, "range": (1.0, 1.0), "layer": "back", "scale": 0.7,
       "tint": (0.54, 0.63, 0.54)}
      for i, home in enumerate([(12.0, 7.0), (17.0, 11.0), (22.0, 13.0), (28.0, 5.5), (30.0, 10.5), (38.0, 7.5),
                                (42.0, 11.0), (45.0, 16.0)])),
    *({"id": f"dragonfly{i}", "species": "dragonfly", "home": home, "range": (1.8, 0.8), "layer": "mid", "scale": 1.0}
      for i, home in enumerate([(7.0, 4.2), (12.0, 5.0), (16.5, 4.0), (102.0, 4.4), (106.5, 5.2), (110.5, 4.0),
                                (114.5, 5.6)])),
    {"id": "lilypad0", "species": "lilypad_fly", "layer": "mid", "scale": 1.0, "perches": [(95.6, 3.52, True), (117.1, 3.64, False)]},
    {"id": "lilypad1", "species": "lilypad_fly", "layer": "mid", "scale": 1.0, "perches": [(104.2, 9.66, True), (111.0, 9.66, False)]},
    {"id": "lilypad2", "species": "lilypad_fly", "layer": "mid", "scale": 1.0, "perches": [(121.8, CLIFF_TOP - 0.09, False), (93.0, 3.27, True)]},
]
SPECIES_CLIP = {"moss_fly": "Moss Fly Fly", "dragonfly": "Dragonfly Idle", "lilypad_fly": "Lilypad Fly Idle 01"}


def export_critters(zones_out):
    """CRITTERS as WorldScene draws them: with the zone each lives in, and for the ones that
    stand, how far below their pivot their feet are (from their extracted sheet)."""
    manifest = json.loads((DATA / "Sprites.qml").read_text().split("(", 1)[1].rsplit(")", 1)[0])
    feet = {}
    for species, clip in SPECIES_CLIP.items():
        info = manifest.get(clip)
        if info is None:
            continue
        a = np.asarray(Image.open(DATA / info["file"]).convert("RGBA"))[:info["cellHeight"], :info["cellWidth"], 3]
        rows = np.nonzero(a.max(1) > 40)[0]
        feet[species] = round(float((rows.max() - info["anchorY"]) / info["pixelsPerUnit"]), 3) if len(rows) else 0.0
    out = []
    for c in CRITTERS:
        if c["species"] not in feet:
            continue
        x, y = c.get("home") or c["perches"][0][:2]
        zone = next((z["id"] for z in zones_out if z["left"] <= x <= z["left"] + z["width"] and z["bottom"] <= y <= z["bottom"] + z["height"]
                     and z["id"] != "home"), None)
        out.append({**{k: (list(v) if isinstance(v, tuple) else v) for k, v in c.items()},
                    "perches": [list(p) for p in c.get("perches", [])], "feet": feet[c["species"]], "zone": zone})
    return out


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
    {"kit": "clover_02c", "piece": "Sprite Whole", "x": 123.8, "near": CLIFF_TOP, "sink": 0.3},
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
    {"id": "bell_beast", "zone": "bell_beast", "x": 60.6, "near": 0.7, "activity": "visit", "face": 1},
    {"id": "clock", "zone": "great_tree", "x": 64.0, "near": 12.4, "activity": "lookup"},
    {"id": "lake", "zone": "verdania", "x": 97.4, "near": 3.6, "activity": "needolin_sit", "face": 1},
    {"id": "island", "zone": "verdania", "x": 105.5, "near": 9.6, "activity": "lookup"},
    {"id": "shrine", "zone": "verdania", "x": 125.6, "near": CLIFF_TOP, "activity": "kneel", "face": -1},
    {"id": "waterfall bench", "zone": "verdania", "x": 123.3, "near": 3.9, "activity": "bench", "face": -1, "seat": 0.3},
    {"id": "lookout", "zone": "verdania", "x": 130.8, "near": LOOKOUT, "activity": "lookup"},
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
    anchored = {}
    for name, rx in zone.anchors.items():
        go_id = next((g for g, go in scene.gameobjects.items() if re.search(rx, go.m_Name)), None)
        if go_id is not None:
            m = scene.world(scene.go_transform[go_id])
            anchored[name] = (float(m[0, 3]), float(m[1, 3]))
    # What's removed is switched off, with everything under it: its sprites and its colliders.
    removes = [re.compile(r) for r in zone.remove]
    for go_id, go in scene.gameobjects.items():
        if any(r.search(go.m_Name) for r in removes):
            scene.overrides[go_id] = False
    scene._active.clear()
    props = [re.compile(r) for r in zone.props]
    items = [it for it in room.collect(scene) if not room.is_unwanted(scene, it.go) and not DARKENERS.search(it.name)]
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

    def near_in_margin(it):
        """A near piece standing wholly in a margin whose depth rule leaves it out (margin_far)."""
        w = it.matrix
        c = it.corners
        pts = [w @ np.array([x, y, 0, 1]) for x, y in (*c, c[1] + c[2] - c[0])]
        centre = w @ np.array([c[:, 0].mean(), c[:, 1].mean(), 0, 1])
        xs = [cam.project(q[0], q[1], float(centre[2]), centre[0], centre[1])[0] for q in pts]
        tol = 0.25 * PPU
        left, right = zone.margin_far
        return ((left is not None and it.z < left and max(xs) < screen[0] + tol)
                or (right is not None and it.z < right and min(xs) > screen[1] - tol))

    items = [it for it in items if not near_in_margin(it)]
    # Haze and fog spread over the whole view, near or not: they belong with the backdrop, which
    # cross-fades into the next screen instead of stopping at the bezel.
    for it in items:
        if HAZE.search(it.name) and it.z < BACKDROP_Z and area(it) > 30:
            it.z = BACKDROP_Z
    animated = {name: re.compile(rx) for name, rx in zone.animated.items()}
    moving = [(name, it) for it in items for name, rx in animated.items() if rx.search(it.name)]
    items = [it for it in items if not any(it is m for _, m in moving)]
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
    pieces = animate(scene, zone, moving, cam, blur_z, at, graded, out)

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
        "anchors": {name: to_world([xy])[0] for name, xy in anchored.items() if xy is not None},
        "roomFloor": round(room_floor, 3),
        "src": [round(v, 3) for v in src],
        "at": [round(v, 3) for v in at],
        "grade": grade_json(grade),
        "animated": pieces,
        "particles": [e for i, (go_id, t) in enumerate(particle_systems(scene, zone.particles))
                      if (e := emitter(scene, go_id, t, zone, cam, at, grade, out, f"particle_{i}.png")) is not None],
    }
    (out / "zone.json").write_text(json.dumps(meta))
    print(f"{zone.id}: floor {room_floor:.2f} in the room, {len(items)} sprites, {len(lights)} lights", file=sys.stderr)


def animate(scene, zone, moving, cam, blur_z, at, graded, out):
    """The pieces the zone animates apart (zone.animated: sprites flipped through by a
    BasicSpriteAnimator, such as the station's floor bells), each frame rendered on its own as
    the room is, cut to where it stands; in one sheet (animated.png), a row per piece: its rest
    sprite, then its animation's frames."""
    import game
    import room

    rows = []
    for group, it in moving:
        go = scene.gameobjects[it.go]
        anim = next((c.read() for c in go.m_Components if c.read().object_reader.type.name == "MonoBehaviour"
                     and game.script_class(c.read().object_reader) == "BasicSpriteAnimator"), None)
        if anim is None or zone.flip:
            continue
        t = anim.object_reader.read_typetree()
        frames = [it]
        for ref in t["frames"]:
            sprite = game.resolve(anim.object_reader, ref)
            parts = room.sprite_reader_parts(sprite) if sprite is not None else None
            if parts is None:
                break
            img, x0, x1, y0, y1, _ = parts
            if it.corners[1, 0] < it.corners[0, 0]:  # drawn flipped
                x0, x1 = -x0, -x1
            frames.append(replace(it, image=img, corners=np.array([[x0, y0], [x1, y0], [x0, y1]])))
        else:
            drawn = []
            for f in frames:
                _, mid_, front_, _ = room.render(scene, [f], cam, blur_z=blur_z, mid_z=BACKDROP_Z)
                layer, img = ("front", front_) if front_.getchannel("A").getbbox() else ("mid", mid_)
                drawn.append((layer, graded(img, layer != "front")))
            boxes = [img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox() for _, img in drawn]
            if not all(boxes) or len({layer for layer, _ in drawn}) > 1:
                continue
            box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
            rows.append((group, drawn[0][0], box, [img.crop(box) for _, img in drawn], t.get("fps", 12.0)))
    if not rows:
        return []
    pad = 2
    W = max(len(cells) * (cells[0].width + pad) for _, _, _, cells, _ in rows)
    sheet = Image.new("RGBA", (W, sum(cells[0].height + pad for _, _, _, cells, _ in rows)), (0, 0, 0, 0))
    pieces, y = [], 0
    for group, layer, box, cells, fps in rows:
        cw, ch = cells[0].width, cells[0].height
        for k, cell in enumerate(cells):
            sheet.paste(cell, (k * (cw + pad), y))
        pieces.append({"group": group, "layer": layer, "fps": fps, "frames": len(cells) - 1,
                       "x": round(at[0] + box[0] / PPU, 3), "y": round(at[1] + zone.height - box[3] / PPU, 3),
                       "w": round(cw / PPU, 3), "h": round(ch / PPU, 3), "cell": [0, y, cw, ch], "step": cw + pad})
        y += ch + pad
    sheet.save(out / "animated.png")
    return pieces


def particle_systems(scene, patterns):
    """The room's particle systems named by `patterns` (regexes), active and looping."""
    rx = [re.compile(r) for r in patterns]
    for o in scene.objects if rx else ():
        if o.type.name != "ParticleSystem":
            continue
        t = o.read_typetree()
        go_id = t["m_GameObject"]["m_PathID"]
        go = scene.gameobjects.get(go_id)
        if go is not None and scene.active(go_id) and t.get("looping") and any(r.search(go.m_Name) for r in rx):
            yield go_id, t


def emitter(scene, go_id, t, zone, cam, at, grade, out, file):
    """One of the room's particle systems (room.particle_template) where the zone's camera shows
    it, smaller and slower with its depth, its texture in the zone's colours (out/file)."""
    import game
    import room

    made = room.particle_template(scene, go_id, t)
    if made is None or zone.flip or zone.cuts:
        return None
    tpl, image = made
    (ex, ey), ez = tpl["at"], tpl["z"]
    px, py = cam.project(ex, ey, ez, ex, ey)
    e = place_particles(tpl, at[0] + px / PPU, at[1] + zone.height - py / PPU, game.CAM_Z / (game.CAM_Z + ez))
    if e is None:
        return None
    particle_texture(image, tpl["lit"], grade).save(out / file)
    return {**e, "texture": file}


def place_particles(tpl, x, y, s, count=None, axes=None, shape=None):
    """A particle template placed at (x, y), as seen at a depth that scales it by s (lengths and
    speeds), with `count` particles alive (default: as many as the game keeps), and optionally
    another emitting shape (axes: its half axes x (xy), y (zw) in world units)."""
    e = dict(tpl)
    for k in ("at", "z", "rate", "count", "lit", "name"):
        e.pop(k, None)
    e["name"] = tpl["name"]
    e["x"], e["y"] = round(x, 3), round(y, 3)
    e["axes"] = axes if axes is not None else [round(v * s, 4) for v in tpl["axes"]]
    e["shape"] = shape or tpl["shape"]
    for k in ("size", "speed", "velocity", "force"):
        e[k] = [round(v * s, 4) for v in tpl[k]]
    e["gravity"] = round(tpl["gravity"] * s, 4)
    e["slots"] = int(count if count is not None else tpl["count"])
    if e["slots"] < 1:
        return None
    life = tpl["life"][1]
    grow = max(k[1] for k in tpl["sizeKeys"]) * tpl["sizeRange"][1]
    reach = ((max(abs(v) for v in e["velocity"]) + max(abs(v) for v in e["speed"])) * life
             + 0.5 * (max(abs(v) for v in e["force"]) + abs(e["gravity"])) * life ** 2 + e["size"][1] * grow)
    ax = np.array(e["axes"][:2]); ay = np.array(e["axes"][2:])
    ext = np.abs(ax) + np.abs(ay) + reach
    e["area"] = [round(float(v), 3) for v in (x - ext[0], y - ext[1], 2 * ext[0], 2 * ext[1])]
    return e


def particle_texture(image, lit, grade):
    """A particle's texture as it's drawn in a zone: lit by its ambient light if its material is
    (Sprites/Lit), in its colour grade (None: as it is)."""
    a = np.asarray(image.convert("RGBA")).astype(np.float32) / 255
    if grade is not None:
        if lit:
            a[..., :3] *= np.asarray(grade.ambient_rgb()) * 2
        a[..., :3] = grade.apply(a[..., :3].clip(0, 1))
    return Image.fromarray((a.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")


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
    (each screen's own in its middle); near the bezels it thickens and the backdrop blurs:
    neighbouring backdrops meet in the same haze, as soft as each other."""
    a = np.asarray(img).astype(np.float32) / 255
    x = at_x + (np.arange(a.shape[1]) + 0.5) / PPU
    laptop = fogs[zone.id] if zone.id in ("bell_beast", "great_tree") else (fogs["bell_beast"] + fogs["great_tree"]) / 2
    anchors = np.array([fogs["grotto"], laptop, fogs["verdania"]])
    fog = np.stack([np.interp(x, CENTERS, anchors[:, c]) for c in range(3)], -1)  # per column
    near = sum(np.exp(-((x - b) / band) ** 2) for b, band in zip(BEZELS, BANDS))
    haze = zone.haze + 0.3 * near
    a[..., :3] = a[..., :3] * (1 - haze[None, :, None]) + fog[None] * haze[None, :, None]
    out = Image.fromarray((a.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")
    from PIL import ImageFilter
    out = out.filter(ImageFilter.GaussianBlur(zone.haze * 4))
    if zone.mode == "full":
        return out
    sharp = np.asarray(out).astype(np.float32)
    soft = np.asarray(out.filter(ImageFilter.GaussianBlur(SOFTEN * PPU))).astype(np.float32)
    w = np.clip(near, 0.0, 1.0)[None, :, None]
    return Image.fromarray((sharp * (1 - w) + soft * w).round().astype(np.uint8), "RGBA")


def zone_fog(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255
    return np.clip(a.reshape(-1, 3).mean(0) * 1.45, 0, 1)


def paste_region(layer, img, at, size, region, fade=0.0, hfade=(0.0, 0.0), top_fade=0.0):
    """Paste a zone's layer (world bottom-left `at`, `size` units) clipped to `region`; with
    `fade`, it fades in over that many units above the region's bottom (seen through holes in
    the floor, where it meets the level below); `hfade`, over that many units from its left
    and right ends (cross-fading with the next screen's); `top_fade`, over that many units
    below its top, outside the laptop (where the laptop's backdrops reach into the side screens
    lower than their own): beside the laptop it fades over only its last bit, more the further
    from the laptop, so across a bezel the two sides match up to the laptop's top."""
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
        cols = (np.arange(layer.width) + 0.5) / PPU
        top = min(region[3], at[1] + size[1])
        away = np.maximum(C0 - cols, cols - C1)  # outside the laptop, from its edge
        length = np.maximum(0.6, top_fade * smoothstep(away / 6.0))
        vramp = smoothstep((top - rows[:, None]) / length[None, :])
        m *= np.where(away[None, :] > 0, vramp, 1.0)
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

    def pick(x, y):
        """A number in [0, 1) fixed by the point alone, not by what was dressed before it."""
        return math.sin(round(x, 2) * 12.9898 + round(y, 2) * 78.233) * 43758.5453 % 1.0

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
                name = "clover" if pick(x, y) < smoothstep((x - 86.5) / 12.5) else "moss"
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
            canvases[v.get("layer", "mid")].paste(img, *args, anchor=v["anchor"], sway=piece)
            if v.get("light"):
                canvases["lights"].paste(as_light(img), *args, anchor=v["anchor"])

    # The arcade's gilding goes on its bare rock, under the moss on its walkway.
    standing = [(q["x"] - 2.4, q["near"] - 1.0, q["x"] + 2.4, q["near"] + 1.0) for q in PROPS]
    # Nothing grows on the world's rock where it runs under the station's own floor, in front of
    # the station's own bells.
    standing.append((C0 + 0.6, -1.0, C1 - 0.6, CITADEL_FLOOR - 0.2))
    standing += [(m["pod"][0] - 3.0, m["from"][1] - 1.0, m["pod"][0] + 1.5, m["from"][1] + 1.0) for m in MOVES if "pod" in m]
    # Plants and hanging vines on the game's grass shaders sway in the wallpaper: they're
    # collected apart, with what's drawn over them, in order; under the lake they stay in the
    # layer, under its water, and keep still.
    canvases["mid"].start_swaying()
    canvases["front"].start_swaying()
    terrain.dress(rocks, biome_at, canvases["mid"], canvases["front"], graded, 5,
                  underlay=lambda: place(vault_pieces()), no_plants=standing)
    place(DECOR)
    swaying = {}
    for name in ("mid", "front"):
        swaying[name] = []
        for p in canvases[name].stop_swaying():
            if LAKE["x0"] < p["x"] < LAKE["x1"] and p["root"] < LAKE["level"]:
                canvases[name].img.alpha_composite(p["image"], p["px"])
            else:
                swaying[name].append(p)
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
    rock_px = Image.new("1", (W, Hpx), 0)
    from PIL import ImageDraw
    for r in rocks:
        if "in_water" not in r.tags:  # a stone standing in the lake: the water covers its foot
            ImageDraw.Draw(rock_px).polygon([(x * PPU, (WORLD[1] - y) * PPU) for x, y in r.points], fill=1)
    water = draw_water(layers, np.array(rock_px), grades[WATERFALL["zone"]])

    clock = bake_clock(layers, canvases, metas, grades)

    for old in OUT.glob("*_??.png"):
        old.unlink()
    # What earlier builds left: lights and curves of zones that are gone, per-zone Hornet sheets.
    current = {z["light"]["file"] for z in zones_out} | {z["grade"]["lut"] for z in zones_out}
    if clock:
        current |= {p["file"] for p in clock["hands"] + clock["gears"]}
    current |= {f"particle_{zid}_{p['texture']}" for zid, z in metas.items() for p in z.get("particles", [])}
    current |= {f"animated_{zid}.png" for zid, z in metas.items() if z.get("animated")}
    for old in [*OUT.glob("light_*.png"), *OUT.glob("lut_*.png"), *OUT.glob("clock_*.png"), *OUT.glob("particle_*.png"),
                *OUT.glob("animated_*.png")]:
        if old.name not in current:
            old.unlink()
    if (OUT / "zones").is_dir():
        shutil.rmtree(OUT / "zones")
    tiles = {name: save_tiles(img, name) for name, img in layers.items()}
    sway = export_sway(swaying)
    particles = export_particles(metas)
    air, shafts = build_air(graded, kits)
    particles += place_motes(MOTES + [{"kit": BEAM_DUST[0], "system": BEAM_DUST[1], "shaft": sh} for sh in shafts],
                             lambda x, y: grades[grade_at(x, y)])
    animated = []
    for zone in ZONES:
        if metas[zone.id].get("animated"):
            shutil.copyfile(CACHE / zone.id / "animated.png", OUT / f"animated_{zone.id}.png")
            animated += [{**a, "sheet": f"animated_{zone.id}.png", "zone": zone.id} for a in metas[zone.id]["animated"]]
    preview = layers["back"].copy()
    for name in ("mid", "front"):  # the swaying and animated pieces at rest
        for a in animated:
            if a["layer"] == name and name == "front":
                cell = Image.open(OUT / a["sheet"]).crop((a["cell"][0], a["cell"][1], a["cell"][0] + a["cell"][2], a["cell"][1] + a["cell"][3]))
                preview.alpha_composite(cell, (round(a["x"] * PPU), round((WORLD[1] - a["y"] - a["h"]) * PPU)))
        preview.alpha_composite(layers[name])
        for p in swaying[name]:
            preview.alpha_composite(p["image"], p["px"])
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
        "clock": clock,
        "water": water,
        "sway": sway,
        "particles": particles,
        "animated": animated,
        "air": air,
        "critters": export_critters(zones_out),
        # The Bell Beast, where it stands in its room (its animations: life.js planBeast).
        "beast": ({"x": metas["bell_beast"]["anchors"]["bell_beast"][0],
                   "y": metas["bell_beast"]["anchors"]["bell_beast"][1], "zone": "bell_beast"}
                  if "bell_beast" in metas["bell_beast"].get("anchors", {}) else None),
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


def draw_water(layers, rock, grade):
    """The lake's still body (front layer: in front of Hornet), and what the wallpaper needs to
    move the water (shaders/waterfall.frag and lake.frag): the waterfall's shape, the lake's
    surface and a mask of where its shimmer may go (r: water, g: water or open air), in the
    lake's colours."""
    Hpx, W = rock.shape
    deep, shallow, light = (grade.apply(np.array(c)) for c in ((0.16, 0.42, 0.40), (0.42, 0.78, 0.72), (0.86, 1.0, 0.96)))

    def row(y):
        return round((WORLD[1] - y) * PPU)

    # The body: clearer at the top, deeper and darker below.
    # Its edge on the bed and the shores is soft: the water reaches a little over the rock, the
    # bed seen through it rather than cut by it.
    lx0, lx1, level = round(LAKE["x0"] * PPU), round(LAKE["x1"] * PPU), LAKE["level"]
    pad = round(3 * LAKE_BED_SOFT * PPU)
    x0, x1 = lx0 - pad, lx1 + pad
    r0 = row(level)
    water = np.zeros((Hpx - r0 + pad, x1 - x0), bool)  # with the open air above the surface
    water[:, pad:pad + lx1 - lx0] = ~rock[r0 - pad:, lx0:lx1]
    water[:pad, pad:pad + lx1 - lx0] = True
    soft = np.asarray(Image.fromarray(water.astype(np.uint8) * 255, "L").filter(ImageFilter.GaussianBlur(LAKE_BED_SOFT * PPU)))
    soft = (np.maximum(soft[pad:].astype(np.float32) / 255 * 1.6 - 0.15, 0)).clip(0, 1)  # as before over open water
    depth = (np.arange(r0, Hpx) - r0)[:, None] / PPU
    t = np.clip(depth / 2.2, 0, 1)
    body = np.zeros((Hpx - r0, x1 - x0, 4), np.float32)
    body[..., :3] = (shallow * (1 - t[..., None]) + deep * t[..., None]) * np.ones((1, x1 - x0, 1))
    body[..., 3] = (0.42 + 0.4 * t) * soft
    layers["front"].alpha_composite(Image.fromarray((body.clip(0, 1) * 255).round().astype(np.uint8), "RGBA"), (x0, r0))

    (tl, tr, ytop), (bl, br) = WATERFALL["top"], WATERFALL["bottom"]
    impact = (bl + br) / 2
    # The lake's shimmer: from its left shore to past where the waterfall lands, from under its
    # deepest glints to where the mist fades.
    lx0, lx1, ly0, ly1 = LAKE["x0"] - 0.5, max(LAKE["x1"], br) + 3.5, level - 2.0, level + 4.0
    mres = 16  # mask pixels per unit, sampled smoothly
    cols = ((np.arange(round((lx1 - lx0) * mres)) + 0.5) / mres + lx0)
    rows = (ly1 - (np.arange(round((ly1 - ly0) * mres)) + 0.5) / mres)
    rc = np.clip((cols * PPU).astype(int), 0, W - 1)
    rr = np.clip(((WORLD[1] - rows) * PPU).astype(int), 0, Hpx - 1)
    solid = rock[rr[:, None], rc[None, :]]
    in_lake = (cols[None, :] >= LAKE["x0"]) & (cols[None, :] <= LAKE["x1"]) & (rows[:, None] <= level + 0.15)
    water = in_lake & ~solid
    mask = np.zeros(solid.shape + (3,), np.uint8)
    mask[..., 0] = water * 255
    mask[..., 1] = ~solid * 255
    Image.fromarray(mask, "RGB").save(OUT / "water_mask.png")

    fl, fr = min(tl, bl) - 0.6, max(tr, br) + 0.6
    sx0, sy0 = impact - 3.0, level - 0.8

    def rgb(c):
        return [round(float(v), 4) for v in c]
    return {
        "fall": {"left": round(fl, 3), "bottom": level, "width": round(fr - fl, 3), "height": round(ytop - level, 3),
                 "edges": [round(v - fl, 3) for v in (tl, tr, bl, br)]},
        "lake": {"left": lx0, "bottom": ly0, "width": round(lx1 - lx0, 3), "height": round(ly1 - ly0, 3),
                 "level": round(level - ly0, 3), "impact": round(impact - lx0, 3), "mask": "water_mask.png"},
        # Where it lands: droplets, foam, mist (the mask's rectangle relative to this one).
        "splash": {"left": round(sx0, 3), "bottom": round(sy0, 3), "width": 6.0, "height": 4.4,
                   "level": round(level - sy0, 3), "impact": 3.0, "fallWidth": round(br - bl, 3),
                   "maskRect": [round(lx0 - sx0, 3), round(ly0 - sy0, 3), round(lx1 - lx0, 3), round(ly1 - ly0, 3)]},
        "shallow": rgb(shallow), "light": rgb(light),
    }


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


def export_sway(swaying):
    """The pieces that sway (shaders/sway.vert), packed into one image (sway.png): where each
    stands, the height of the origin it bends from, and the game's sway settings, with the phase
    its position gives it and its depth's share: the game sways a sprite (1 + |z|) times more,
    z clamped to ClampZ, and what stands in front of Hornet is the foreground (z -1 and nearer).
    Grass that bends as she walks into it says how (GrassBehaviour: WorldScene pushes it)."""
    items = [(layer, p) for layer, ps in swaying.items() for p in ps]
    pad, W = 2, 2048
    spots, x, y, shelf = {}, 0, 0, 0
    for i in sorted(range(len(items)), key=lambda i: -items[i][1]["image"].height):
        im = items[i][1]["image"]
        if x + im.width + 2 * pad > W:
            x, y, shelf = 0, y + shelf, 0
        spots[i] = (x + pad, y + pad)
        x, shelf = x + im.width + 2 * pad, max(shelf, im.height + 2 * pad)
    Ha = max(1, y + shelf)
    atlas = Image.new("RGBA", (W, Ha), (0, 0, 0, 0))
    out = []
    for i, (layer, p) in enumerate(items):
        im, (ax, ay) = p["image"], spots[i]
        sw = p["sway"] or {"amount": 0.0, "speed": 0.0, "worldOffset": 0.0, "phaseY": 0, "clampZ": 0.0,
                           "mags": [0.0, 0.0, 0.0], "times": [0.0, 0.0, 0.0], "fps": 0.0}  # still, drawn over one that sways
        atlas.paste(im, (ax, ay))
        left, top = p["px"][0] / PPU, WORLD[1] - p["px"][1] / PPU
        w, h = im.width / PPU, im.height / PPU
        phase = (p["x"] + sw["phaseY"] * p["root"]) * sw["worldOffset"]
        if all(float(m).is_integer() for m in sw["times"]):
            phase %= 2 * math.pi  # the same sway, in a shader's single precision
        depth = 1 + min(1.0, sw["clampZ"]) if layer == "front" else 1.0
        react = p["react"] if layer == "front" else None
        out.append({"layer": layer, "x": round(left, 3), "y": round(top - h, 3), "w": round(w, 3), "h": round(h, 3),
                    "uv": [round(v, 6) for v in (ax / W, ay / Ha, (ax + im.width) / W, (ay + im.height) / Ha)],
                    "root": round((top - p["root"]) / h, 4),  # down from its top, in heights
                    "amount": round(sw["amount"] * depth * (-1 if p["flip"] else 1), 5), "speed": sw["speed"],
                    "phase": round(phase, 4), "mags": sw["mags"], "times": sw["times"], "fps": sw["fps"],
                    **({"react": {**react, "amount": round(react["amount"] * depth, 4)}} if react else {})})
    atlas.save(OUT / "sway.png", optimize=True)
    return {"atlas": "sway.png", "size": [W, Ha], "items": out}


def export_particles(metas):
    """The rooms' ambient particles the zones keep (render_zone's emitters): those that stand on
    the zone's own screen, kept to it, their textures copied next to the world."""
    out = []
    for zone in ZONES:
        for p in metas.get(zone.id, {}).get("particles", []):
            r = zone.region
            if not (r[0] <= p["x"] <= r[2] and r[1] <= p["y"] <= r[3]):
                continue  # the room beyond what the zone shows of it
            x0, y0 = max(p["area"][0], r[0]), max(p["area"][1], r[1])
            x1, y1 = min(p["area"][0] + p["area"][2], r[2]), min(p["area"][1] + p["area"][3], r[3])
            if x1 <= x0 or y1 <= y0:
                continue
            file = f"particle_{zone.id}_{p['texture']}"
            shutil.copyfile(CACHE / zone.id / p["texture"], OUT / file)
            out.append({**p, "texture": file, "zone": zone.id,
                        "area": [round(v, 3) for v in (x0, y0, x1 - x0, y1 - y0)]})
    return out


def place_motes(placements, grade_at):
    """MOTES (and the shafts' dust) as emitters: each kit template at its place, its texture in
    the colours of the zone it's in (motes_*.png)."""
    import game

    for old in OUT.glob("motes_*.png"):
        old.unlink()
    templates, out = {}, []
    for j, m in enumerate(placements):
        if m["kit"] not in templates:
            templates[m["kit"]] = {t["name"]: t for t in json.loads((terrain.KITS / m["kit"] / "particles.json").read_text())}
        tpl = templates[m["kit"]][m["system"]]
        s = game.CAM_Z / (game.CAM_Z + tpl["z"])
        if "shaft" in m:
            sh = m["shaft"]
            e = place_particles(tpl, sh["x"], sh["y"], s, sh["count"], sh["axes"], "box")
            m = {**m, "grow": 1.8}
            e["velocity"] = [round(v * s, 4) for v in DUST_DRIFT]
        elif "edge" in m:
            x0, x1, y = m["edge"]
            e = place_particles(tpl, (x0 + x1) / 2, y, s, m["count"], [(x1 - x0) / 2, 0.0, 0.0, 0.0], "edge")
        else:
            x0, y0, x1, y1 = m["box"]
            e = place_particles(tpl, (x0 + x1) / 2, (y0 + y1) / 2, s, m["count"], [(x1 - x0) / 2, 0.0, 0.0, (y1 - y0) / 2], "box")
        e["size"] = [round(v * m.get("grow", 1.0), 4) for v in e["size"]]
        file = f"motes_{j:02d}.png"
        particle_texture(Image.open(terrain.KITS / m["kit"] / tpl["texture"]), tpl["lit"], grade_at(e["x"], e["y"])).save(OUT / file)
        out.append({**e, "texture": file, "layer": m.get("layer", "back")})
    return out


def build_air(graded, kits):
    """AIR as images (air_*.png) and what WorldScene does with them: each item's rectangle, layer,
    and how it moves (a slow drift sideways, a breathing opacity, shafts also with the daylight);
    the periods divide an hour, as the scene's clock wraps every hour. Returns them, and where
    each shaft's dust drifts (centre and half axes)."""
    from PIL import ImageFilter

    rng = np.random.default_rng(21)
    periods = [p for p in range(40, 241) if 3600 % p == 0]
    for old in OUT.glob("air_*.png"):
        old.unlink()
    items, shafts = [], []

    def save(img, i):
        file = f"air_{i:02d}.png"
        img.save(OUT / file, optimize=True)
        return file

    def piece(spec):
        kit = kits.setdefault(spec[0], terrain.Kit(spec[0]))
        return kit, find_piece(kit, spec[1])

    def gained(img, gain):
        a = np.asarray(img).astype(np.float32)
        a[..., 3] = np.clip(a[..., 3] * gain, 0, 255)
        return Image.fromarray(a.round().astype(np.uint8), "RGBA")

    for i, spec in enumerate(AIR):
        kit, pc = piece(spec["piece"])
        motion = {"phase": round(float(rng.uniform(0, 2 * math.pi)), 3),
                  "breathe": [round(float(rng.uniform(0.1, 0.2)), 3), int(rng.choice(periods[:12]))]}
        if spec["kind"] == "shaft":
            (tx, ty), L, Wd = spec["top"], spec["length"], spec["width"]
            a = math.radians(SHAFT_ANGLE)
            down = np.array([math.sin(a), -math.cos(a)])
            cx, cy = np.array([tx, ty]) + down * L / 2
            # The game's beam is a soft round blob stretched 20-40 times: only its even middle
            # shows, the length of the shaft, fading out towards what it falls on.
            full = max(60.0, 3 * L)
            img = graded(kit, pc, cx, cy).resize((max(1, round(Wd * PPU)), round(full * PPU)), Image.LANCZOS)
            r0 = round((full - L) / 2 * PPU)
            a = np.asarray(img.crop((0, r0, img.width, r0 + round(L * PPU)))).astype(np.float32)
            rows = (np.arange(a.shape[0]) + 0.5) / PPU
            a[..., 3] *= (smoothstep(rows / 0.6) * smoothstep((L - rows) / (0.35 * L)))[:, None]
            img = gained(Image.fromarray(a.round().astype(np.uint8), "RGBA"), spec["gain"])
            img = img.rotate(SHAFT_ANGLE, resample=Image.BICUBIC, expand=True)
            w, h = img.width / PPU, img.height / PPU
            items.append({"kind": "shaft", "layer": "back", "file": save(img, i), "x": round(cx - w / 2, 3), "y": round(cy - h / 2, 3),
                          "w": round(w, 3), "h": round(h, 3), "drift": [0.0, 60], **motion})
            along, across = down * L * 0.4, np.array([-down[1], down[0]]) * Wd * 0.3
            shafts.append({"x": float(cx), "y": float(cy), "axes": [round(float(v), 4) for v in (*across, *along)],
                           "count": max(6, min(40, round(L * Wd * 0.45)))})
        elif spec["kind"] == "mist":
            x0, x1 = spec["x"]
            band = Image.new("RGBA", (round((x1 - x0) * PPU), round(spec["height"] * 1.6 * PPU)), (0, 0, 0, 0))
            x = x0 - spec["height"]
            while x < x1:
                k = spec["height"] / pc["height"] * rng.uniform(0.85, 1.2)
                w, h = pc["width"] * k, pc["height"] * k
                img = graded(kit, pc, x + w / 2, spec["y"] + h / 2).resize((round(w * PPU), round(h * PPU)), Image.LANCZOS)
                if rng.random() < 0.5:
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)
                px, py = round((x - x0) * PPU), band.height - img.height - round(rng.uniform(0, 0.15) * spec["height"] * PPU)
                if px + img.width > 0 and px < band.width:
                    band.alpha_composite(img, (max(px, 0), max(py, 0)), (max(-px, 0), max(-py, 0)))
                x += w * rng.uniform(0.35, 0.5)
            a = np.asarray(band).astype(np.float32)
            cols = (np.arange(band.width) + 0.5) / PPU
            fade = smoothstep(cols / 3.0) * smoothstep((x1 - x0 - cols) / 3.0)
            a[..., 3] *= fade[None, :] * spec["gain"]
            band = Image.fromarray(a.clip(0, 255).round().astype(np.uint8), "RGBA")
            w, h = band.width / PPU, band.height / PPU
            items.append({"kind": "mist", "layer": spec["layer"], "file": save(band, i), "x": x0, "y": round(spec["y"] - 0.1 * spec["height"], 3),
                          "w": round(w, 3), "h": round(h, 3),
                          "drift": [round(float(rng.uniform(0.8, 1.6)), 3), int(rng.choice(periods[-10:]))], **motion})
        else:
            (cx, cy), (w, h) = spec["at"], spec["size"]
            img = gained(graded(kit, pc, cx, cy).resize((round(w * PPU), round(h * PPU)), Image.LANCZOS), spec["gain"])
            items.append({"kind": "haze", "layer": spec["layer"], "file": save(img, i), "x": round(cx - w / 2, 3), "y": round(cy - h / 2, 3),
                          "w": w, "h": h, "drift": [round(float(rng.uniform(0.6, 1.4)), 3), int(rng.choice(periods[-12:]))], **motion})
    return items, shafts


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


# The clock in the great tree's round window, built from Cogwork Core parts (kit "cog", the
# cog.spriteatlas). Measured on the window: its ring's band runs at about 1.33 x 1.38 units from
# the centre (slightly oval), the glass inside it is about 1.1 across in radius.
#   marks: the Core's fleur clasps across the band at 12, 3, 6 and 9, bronze studs at the other
#          hours: set into the frame itself;
#   face:  the wooden glass darkened, so the bronze reads on it;
#   gears: (piece, centre offset, diameter, turns per minute (+ clockwise), shade, in the dial)
#          a big bronze one behind the frame showing its teeth around the ring, two steel ones in
#          the openings under the window, and a small train inside the dial behind the hands;
#   hands: two of the Core's ornate pointers.
CLOCK = {
    "zone": "great_tree", "ring": (0.04, 0.0, 1.33, 1.38), "glass": (1.1, 1.18), "shine": 1.9,
    "clasp": ("cog_plat_spin__0003_cp", 0.62), "stud": ("cog_cylinder_rivet0002", 0.24),
    "pointer": "cog_plat_spin__0007_cp_top", "pointer_hub": 0.685, "pointer_tail": 0.8,
    "hands": (("hour", 0.74, 1.5), ("minute", 1.12, 1.15)),  # name, tip to centre, thickness
    "gears": (("cog_plat_spin__0009_c1", 0.0, 0.0, 3.6, 1.0, 1.0, False),
              ("cog_plat_spin__0014_cp", -1.42, -1.95, 1.65, -2.18, 1.3, False),
              ("cog_plat_spin__0014_cp", 1.42, -1.95, 1.65, -2.18, 1.3, False),
              ("cog_plat_spin__0009_c1", 0.0, 0.0, 1.0, 0.5, 1.45, True),
              ("cog_plat_spin__0014_cp", -0.5, -0.56, 0.58, -0.86, 1.7, True),
              ("cog_lever_wind_up_0003_1", 0.52, 0.5, 0.52, -0.96, 1.9, True)),
}


def bake_clock(layers, canvases, metas, grades):
    """The face and the marks onto the window (mid layer); images for the hands and the gears,
    which the wallpaper turns. Returns what it needs to draw them."""
    from PIL import ImageDraw, ImageFilter
    anchor = metas[CLOCK["zone"]].get("anchors", {}).get("clock")
    if anchor is None:
        print("warning: no clock anchor in the great tree's render", file=sys.stderr)
        return None
    ox, oy, rx, ry = CLOCK["ring"]
    cx, cy = anchor[0] + ox, anchor[1] + oy
    cog = terrain.Kit("cog")
    g = grades[CLOCK["zone"]]
    lit = np.asarray(g.ambient_rgb()) * 2  # Sprites/Lit, as in the Core
    shine = CLOCK["shine"]  # the metal catches the light: it has to read on 2 cm of glass

    def part(name, width, rows=None, shade=1.0, scale=2):
        """A piece in the tree's colours, `width` units wide, at `scale` x the world's density."""
        img = cog.image(find_piece(cog, name))
        if rows:
            img = img.crop((0, round(rows[0] * img.height), img.width, round(rows[1] * img.height)))
        a = np.asarray(img).astype(np.float32) / 255
        a[..., :3] = g.apply((a[..., :3] * lit * shade).clip(0, 1))
        img = Image.fromarray((a * 255).round().astype(np.uint8), "RGBA")
        w = max(2, round(width * PPU * scale))
        return img.resize((w, max(2, round(w * img.height / img.width))), Image.LANCZOS)

    def shadowed(img, spread):
        """The image over a soft dark shadow of itself, so it stands out from what's behind."""
        pad = round(spread * 3)
        out = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
        shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
        shadow.paste((4, 8, 6, 255), (pad, pad), img.getchannel("A"))
        a = np.asarray(shadow.filter(ImageFilter.GaussianBlur(spread))).copy()
        a[..., 3] = (a[..., 3].astype(np.float32) * 0.8).astype(np.uint8)
        out.alpha_composite(Image.fromarray(a, "RGBA"))
        out.alpha_composite(img, (pad, pad))
        return out, pad

    # The face and the marks, drawn at 4x and brought down to the world's density.
    k = 4
    size = round(3.2 * PPU * k)
    face = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gx, gy = CLOCK["glass"]
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([size / 2 - gx * PPU * k, size / 2 - gy * PPU * k, size / 2 + gx * PPU * k, size / 2 + gy * PPU * k],
                             fill=150)
    m = m.filter(ImageFilter.GaussianBlur(0.08 * PPU * k))
    face.paste((6, 14, 12, 255), (0, 0), m)
    clasp_name, clasp_len = CLOCK["clasp"]
    stud_name, stud_d = CLOCK["stud"]
    clasp = part(clasp_name, clasp_len, shade=shine, scale=k)
    stud = part(stud_name, stud_d, shade=shine, scale=k)
    for h in range(12):
        a = math.radians(h * 30)
        x, y = size / 2 + math.sin(a) * rx * PPU * k, size / 2 - math.cos(a) * ry * PPU * k
        if h % 3 == 0:
            piece = clasp.rotate(90 - h * 30, expand=True, resample=Image.BICUBIC)  # across the band, radially
            piece, pad = shadowed(piece, 0.04 * PPU * k)
        else:
            piece, pad = shadowed(stud, 0.03 * PPU * k)
        face.alpha_composite(piece, (round(x - piece.width / 2), round(y - piece.height / 2)))
    face = face.resize((size // k, size // k), Image.LANCZOS)
    layers["mid"].alpha_composite(face, (round(cx * PPU - face.width / 2), round((WORLD[1] - cy) * PPU - face.height / 2)))

    # The hands: the pointer turned to point left (the wallpaper turns it about its hub), its tail
    # cut short, over a soft shadow. Twice the density, so they stay sharp as they turn.
    hub, tail = CLOCK["pointer_hub"], CLOCK["pointer_tail"]
    pointer = cog.image(find_piece(cog, CLOCK["pointer"]))
    hands = []
    for name, reach, thick in CLOCK["hands"]:
        length = reach / hub * tail  # tip to the end of the cut tail
        img = part(CLOCK["pointer"], length * pointer.width / (pointer.height * tail) * thick, rows=(0, tail), shade=shine)
        img = img.resize((img.width, round(length * PPU * 2)), Image.LANCZOS).rotate(90, expand=True)
        img, pad = shadowed(img, 0.035 * PPU * 2)
        img.save(OUT / f"clock_{name}.png")
        hands.append({"name": name, "file": f"clock_{name}.png", "length": round(img.width / (PPU * 2), 3),
                      "height": round(img.height / (PPU * 2), 3),
                      "pivot": [round((pad + hub / tail * (img.width - 2 * pad)) / img.width, 4), 0.5]})

    gears = []
    for i, (name, dx, dy, d, turns, shade, dial) in enumerate(CLOCK["gears"]):
        img = part(name, d, shade=shade)
        img.save(OUT / f"clock_gear{i}.png")
        gears.append({"file": f"clock_gear{i}.png", "x": round(cx + dx, 3), "y": round(cy + dy, 3), "size": d,
                      "turns": turns, "dial": dial})
    return {"x": round(cx, 3), "y": round(cy, 3), "hands": hands, "gears": gears}


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

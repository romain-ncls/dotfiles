#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy", "lz4"]
# ///
"""Bake wallpaper scenes from rooms of an installed Hollow Knight: Silksong.

A scene is a desk-sized window into one room, with its enemies, spikes and traps taken
out. Like the sprites from extract.py, everything lands in the player's own data folder,
~/.local/share/silksong-wallpaper/scenes/<id>/:

  back_NN.png, front_NN.png  the room behind and in front of Hornet, cut in tiles, already
                             in the room's colours (camera bloom, curves and saturation)
  hornet/*.png               Hornet's clips (from extract.py) in this room's colours, with the
                             camera bloom she gets in game baked around her
  light.png                  the light Hornet carries, as white over transparency
  Scene.qml                  sizes, tiles, the ground she walks on

Loading a room takes about 4 GB of memory: bake one scene at a time, ideally under a cap:
  systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 tools/bake.py mosshome
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import game
import room

DATA = Path.home() / ".local/share/silksong-wallpaper"

# A room and the bottom-left corner (game units) of the window the desk shows.
SCENES = {
    "mosshome": {"room": "mosstown_01", "left": 44.0, "bottom": 0.5},
}

# This desk at the wallpaper's default scale: three screens bottom-aligned, 15 mm apart,
# 16.3 mm per game unit (one monitor shows one game screen).
UNIT_MM = 16.3
DESK_MM = (476.2 + 344.0 + 476.2 + 2 * 15, 267.9)
TILE_PX = 1024
HERO_FEET = 1.552  # Hero_Hornet's BoxCollider2D bottom, below her pivot


def ground_profile(shapes, left, bottom, width, height, step=0.25, ppu=16):
    """Height of the ground above the window's bottom edge every `step` units across it, None over a pit."""
    below = 4  # look this far under the window for the floor
    w, h = int(width * ppu), int((height + below) * ppu)
    mask = Image.new("1", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    top = bottom + height
    for pts, closed in shapes:
        xy = [((x - left) * ppu, (top - y) * ppu) for x, y in pts]
        if closed and len(xy) >= 3:
            draw.polygon(xy, fill=1)
        else:
            draw.line(xy, fill=1, width=2)
    solid = np.array(mask)
    headroom = int(2.5 * ppu)  # Hornet is about 2.1 units tall
    ledge_row = int(height * 0.55 * ppu)  # surfaces in the top 55% of the window are ledges
    heights = []
    for i in range(int(width / step) + 1):
        col = solid[:, min(w - 1, int(i * step * ppu))]
        # Tops of solid runs (the first solid row under a free one). Terrain is often an outline
        # (edge colliders) with nothing filled under it, so the floor is the highest top with
        # room for Hornet above it, among those low enough to be ground rather than a ledge.
        tops = [r for r in range(1, h) if col[r] and not col[r - 1] and r >= ledge_row]
        surface = None
        for r in tops:
            above = col[:r][::-1]
            free = len(above) if not above.any() else int(np.argmax(above))
            if free >= headroom:
                surface = r
                break
        heights.append(None if surface is None else round(height - surface / ppu, 3))  # from the window's bottom
    return heights


def walk_span(heights, step, max_climb=0.6):
    """Longest run of ground without pits or steps taller than max_climb, as (x0, x1) units."""
    best, start = (0, 0), None
    for i, y in enumerate(heights + [None]):
        ok = y is not None and (start is None or abs(y - heights[i - 1]) <= max_climb)
        if ok and start is None:
            start = i
        elif not ok and start is not None:
            if i - 1 - start > best[1] - best[0]:
                best = (start, i - 1)
            start = i if y is not None else None
    return best[0] * step, best[1] * step


def save_tiles(img, out, prefix):
    tiles = []
    for i, x in enumerate(range(0, img.width, TILE_PX)):
        tile = img.crop((x, 0, min(img.width, x + TILE_PX), img.height))
        if tile.getchannel("A").getbbox() is None:
            continue  # nothing in front of Hornet here
        name = f"{prefix}_{i:02d}.png"
        tile.save(out / name, optimize=True)
        tiles.append({"file": name, "x": x, "width": tile.width})
    return tiles


def grade_layer(img, grade, ppu, with_bloom):
    """The camera: bloom (on the opaque back layer only), then curves and saturation."""
    a = np.asarray(img).astype(np.float32) / 255
    rgb = a[..., :3]
    if with_bloom:
        rgb = game.bloom(rgb, ppu)
    a[..., :3] = grade.apply(rgb)
    # Triangular dither before 8-bit, as the game's DebandEffect does for its dark gradients.
    rng = np.random.default_rng(0)
    a[..., :3] += (rng.random(rgb.shape, np.float32) - rng.random(rgb.shape, np.float32)) / 255
    return Image.fromarray((a.clip(0, 1) * 255).round().astype(np.uint8), "RGBA")


def bake_hornet(grade, out, sheet_ppu=64):
    """Hornet's sheets in this room's colours, with her share of the camera bloom around her."""
    src = DATA / "hornet"
    (out / "hornet").mkdir(exist_ok=True)
    for png in sorted(src.glob("*.png")):
        a = np.asarray(Image.open(png).convert("RGBA")).astype(np.float32) / 255
        alpha = a[..., 3:4]
        lit = grade.hero_shader(a[..., :3])
        bright = np.maximum(lit - game.BLOOM_THRESHOLD, 0) * game.BLOOM_INTENSITY * alpha
        halo = game.blur(bright, game.BLOOM_SIGMA_X * sheet_ppu, game.BLOOM_SIGMA_Y * sheet_ppu)
        # Additive light over a dark room is close to blending its hue at its brightest channel.
        h_alpha = halo.max(-1, keepdims=True).clip(0, 1)
        h_rgb = grade.apply(np.where(h_alpha > 0, halo / np.maximum(h_alpha, 1e-6), 0))
        body = np.concatenate([grade.apply(lit), alpha], -1)
        glow = np.concatenate([h_rgb, h_alpha], -1)
        out_a = body[..., 3:4] + glow[..., 3:4] * (1 - body[..., 3:4])
        out_rgb = (body[..., :3] * body[..., 3:4] + glow[..., :3] * glow[..., 3:4] * (1 - body[..., 3:4])) / np.maximum(out_a, 1e-6)
        sheet = np.concatenate([out_rgb, out_a], -1)
        Image.fromarray((sheet * 255).round().astype(np.uint8), "RGBA").save(out / "hornet" / png.name, optimize=True)


def bake_light(grade, out):
    """HeroLight is screen-blended, which for its near-grey colour is white at alpha = its brightness."""
    light = game.hero_light()
    tex = np.asarray(light["image"]).astype(np.float32) / 255
    room_color = np.array([grade.hero_light[c] for c in "rgba"])
    color = np.array(light["color"]) * room_color
    strength = (tex[..., :3] * color[:3]).max(-1) * tex[..., 3] * color[3]
    img = np.zeros(tex.shape, np.float32)
    img[..., :3] = grade.apply(np.ones(3))
    img[..., 3] = strength
    Image.fromarray((img * 255).round().astype(np.uint8), "RGBA").save(out / "light.png", optimize=True)
    x0, y0, x1, y1 = light["box"]
    sx, sy = light["scale"]
    ox, oy = light["offset"]
    return {"file": "light.png", "left": ox + x0 * sx, "bottom": oy + y0 * sy, "width": (x1 - x0) * sx, "height": (y1 - y0) * sy}


def bake(scene_id, ppu):
    recipe = SCENES[scene_id]
    out = DATA / "scenes" / scene_id
    out.mkdir(parents=True, exist_ok=True)
    width, height = DESK_MM[0] / UNIT_MM, DESK_MM[1] / UNIT_MM
    left, bottom = recipe["left"], recipe["bottom"]

    scene = room.Scene(recipe["room"])
    items = [it for it in room.collect(scene) if not room.is_unwanted(scene, it.go)]
    blur_z = next((float(scene.world(scene.go_transform[o.read().m_GameObject.path_id])[2, 3]) for o in scene.objects
                   if o.type.name == "MonoBehaviour" and game.script_class(o) == "BlurPlane"), None)
    back, front, grade = room.render(scene, items, room.Camera(left, bottom, width, height, ppu), blur_z=blur_z)
    print(f"{scene_id}: rendered {len(items)} sprites at {back.size}", file=sys.stderr)
    back = grade_layer(back, grade, ppu, with_bloom=True)
    front = grade_layer(front, grade, ppu, with_bloom=False)

    for old in out.glob("*_??.png"):
        old.unlink()
    layers = {"back": save_tiles(back, out, "back"), "front": save_tiles(front, out, "front")}
    preview = back.copy()
    preview.alpha_composite(front)
    preview.convert("RGB").save(out / "preview.jpg", quality=85)

    step = 0.25
    heights = ground_profile(room.terrain(scene), left, bottom, width, height, step)
    walk = walk_span(heights, step)
    bake_hornet(grade, out)
    light = bake_light(grade, out)

    data = {
        "id": scene_id,
        "room": recipe["room"],
        "width": round(width, 3),
        "height": round(height, 3),
        "pixelsPerUnit": ppu,
        "layers": layers,
        "groundStep": step,
        "ground": heights,
        "walk": walk,
        "heroFeet": HERO_FEET,
        "light": light,
    }
    (out / "Scene.qml").write_text(
        f"// Generated by packages/silksong-wallpaper/tools/bake.py from {recipe['room']}\n"
        "import QtQml\n\n"
        f"QtObject {{\n    readonly property var scene: ({json.dumps(data)})\n}}\n"
    )
    pits = sum(1 for h in heights if h is None)
    print(f"{scene_id}: {len(layers['back'])} back tiles, {len(layers['front'])} front tiles, "
          f"walk {walk[0]:.1f}-{walk[1]:.1f} of {width:.1f} units, {pits} pit samples -> {out}", file=sys.stderr)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("scenes", nargs="*", default=list(SCENES), help=f"scene ids (default: all of {', '.join(SCENES)})")
    p.add_argument("--ppu", type=int, default=91, help="pixels per game unit (default: the laptop panel's density)")
    args = p.parse_args()
    for s in args.scenes:
        bake(s, args.ppu)


if __name__ == "__main__":
    main()

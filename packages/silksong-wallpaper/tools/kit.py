#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy", "lz4"]
# ///
"""The pieces a room is dressed with, to dress the aquarium's own terrain.

    tools/kit.py harvest ROOM      every distinct sprite of a room, at its in-game size, into
                                   ~/.cache/silksong-wallpaper/kits/ROOM (pieces.json + PNGs)
                                   and a labelled contact sheet to choose from
    tools/kit.py atlas NAME        the sprites of a sprite atlas (sprites/_atlases/NAME.spriteatlas),
                                   e.g. "ring" for the Clawline rings, into kits/NAME

Pieces keep the tint and ambient light they have in their room; the colour grade is applied
when the world is composed, with the zone's own grade.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

KITS = Path.home() / ".cache/silksong-wallpaper/kits"


def harvest(room_name, save=None):
    import game
    import room

    out = KITS / room_name
    (out / "pieces").mkdir(parents=True, exist_ok=True)
    scene = room.Scene(room_name)
    room.apply_save_state(scene, save or {})
    items = [it for it in room.collect(scene) if not room.is_unwanted(scene, it.go)]
    grade = game.Grade(scene.manager)
    ambient = grade.ambient_rgb() * 2
    pieces = {}
    for it in items:
        base = re.sub(r" \(\d+\)$", "", it.name)
        key = f"{base}|{it.image.size}"
        sx = float(np.linalg.norm(it.matrix[:3, 0]))
        sy = float(np.linalg.norm(it.matrix[:3, 1]))
        w = abs(it.corners[1, 0] - it.corners[0, 0]) * sx
        h = abs(it.corners[2, 1] - it.corners[0, 1]) * sy
        p = pieces.get(key)
        if p is None:
            name = re.sub(r"[^A-Za-z0-9_.-]+", "_", base)[:60] + f"_{len(pieces)}"
            img = it.image
            lit = it.shader == "Sprites/Lit" or "Diffuse" in it.shader
            tint = np.array(it.color[:3]) * (ambient if lit else 1)
            a = np.asarray(img).astype(np.float32) / 255
            a[..., :3] = (a[..., :3] * tint).clip(0, 1)
            a[..., 3] *= it.color[3]
            Image.fromarray((a * 255).round().astype(np.uint8), "RGBA").save(out / "pieces" / f"{name}.png")
            p = pieces[key] = {
                "name": name, "object": base, "file": f"pieces/{name}.png", "count": 0,
                "width": round(w, 3), "height": round(h, 3), "z": [], "y": [], "shader": it.shader,
                # pivot: where the object's origin sits inside the image, as fractions from the bottom-left
                "pivot": [round(float(-it.corners[0, 0] / max(1e-6, it.corners[1, 0] - it.corners[0, 0])), 3),
                          round(float(-it.corners[0, 1] / max(1e-6, it.corners[2, 1] - it.corners[0, 1])), 3)],
            }
        p["count"] += 1
        p["z"].append(round(it.z, 2))
        p["y"].append(round(float(it.matrix[1, 3]), 2))
        p.setdefault("x", []).append(round(float(it.matrix[0, 3]), 2))
    listing = sorted(pieces.values(), key=lambda p: (-p["count"], p["name"]))
    for p in listing:
        p["zMedian"] = float(np.median(p["z"]))
        p["at"] = [p["x"][0], p["y"][0]]  # where (one of) them sits in the room
        del p["z"], p["y"], p["x"]
    (out / "grade.json").write_text(json.dumps({
        "lut": grade.lut.tolist(), "saturation": grade.saturation, "heroSaturation": grade.hero_saturation,
        "ambient": grade.ambient_rgb().tolist(), "heroLight": grade.hero_light}))
    (out / "pieces.json").write_text(json.dumps(listing, indent=1))
    sheet(out, listing)
    print(f"{room_name}: {len(listing)} distinct pieces from {len(items)} sprites -> {out}", file=sys.stderr)


def atlas(name):
    """Sprites that live in an atlas rather than in a room, as a kit (no room tint)."""
    import UnityPy
    import game
    bundle = (game.GAME / "Hollow Knight Silksong_Data/StreamingAssets/aa/StandaloneLinux64/atlases_assets_assets/sprites/_atlases"
              / f"{name}.spriteatlas.bundle")
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.0.50f1"
    env = UnityPy.load(str(bundle))
    out = KITS / name
    (out / "pieces").mkdir(parents=True, exist_ok=True)
    listing = []
    for o in env.objects:
        if o.type.name != "Sprite":
            continue
        sp = o.read()
        img = sp.image
        file = f"pieces/{sp.m_Name}.png"
        img.save(out / file)
        ppu = sp.m_PixelsToUnits or 64.0
        pivot = getattr(sp, "m_Pivot", None)
        listing.append({"name": sp.m_Name, "object": sp.m_Name, "file": file, "count": 1, "width": round(img.width / ppu, 3),
                        "height": round(img.height / ppu, 3), "shader": "Sprites/Default",
                        "pivot": [round(pivot.x, 3), round(pivot.y, 3)] if pivot else [0.5, 0.5], "zMedian": 0.0, "at": [0, 0]})
    listing.sort(key=lambda p: p["name"])
    (out / "pieces.json").write_text(json.dumps(listing, indent=1))
    sheet(out, listing)
    print(f"{name}: {len(listing)} sprites -> {out}", file=sys.stderr)


def sheet(out, listing, cell=150, cols=10):
    font = ImageFont.load_default()
    rows = math.ceil(len(listing) / cols)
    img = Image.new("RGB", (cols * cell, rows * (cell + 26)), (58, 58, 64))
    d = ImageDraw.Draw(img)
    for i, p in enumerate(listing):
        x, y = (i % cols) * cell, (i // cols) * (cell + 26)
        piece = Image.open(out / p["file"]).convert("RGBA")
        piece.thumbnail((cell - 8, cell - 8))
        bg = Image.new("RGBA", piece.size, (58, 58, 64, 255))
        bg.alpha_composite(piece)
        img.paste(bg.convert("RGB"), (x + (cell - piece.width) // 2, y + (cell - piece.height) // 2))
        d.text((x + 3, y + cell), f"{i} {p['object'][:20]}", fill=(255, 255, 255), font=font)
        d.text((x + 3, y + cell + 12), f"{p['width']:.1f}x{p['height']:.1f} z{p['zMedian']:.1f} n{p['count']}", fill=(180, 200, 255), font=font)
    img.save(out / "sheet.jpg", quality=82)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    h = sub.add_parser("harvest")
    h.add_argument("room")
    h.add_argument("--save", nargs="*", default=[], metavar="FLAG", help="save flags (PlayerData bools) to turn on")
    a = sub.add_parser("atlas")
    a.add_argument("name")
    args = p.parse_args()
    if args.cmd == "harvest":
        harvest(args.room, {f: True for f in args.save})
    elif args.cmd == "atlas":
        atlas(args.name)


if __name__ == "__main__":
    main()

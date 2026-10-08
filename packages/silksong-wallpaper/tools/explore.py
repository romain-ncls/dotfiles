#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy", "lz4"]
# ///
"""Map of a room for writing zone recipes: the room as a fresh save shows it, enemies and
hazards removed, with a grid in game units and the terrain outlines.

    tools/explore.py ROOM [--ppu 16] [--region LEFT BOTTOM WIDTH HEIGHT] [--out room.jpg]

Like bake.py, it loads a whole room (about 4 GB): run one at a time.
"""
import argparse

from PIL import ImageDraw, ImageFont

import game
import room


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("room")
    p.add_argument("--ppu", type=float, default=16)
    p.add_argument("--region", type=float, nargs=4, metavar=("LEFT", "BOTTOM", "WIDTH", "HEIGHT"))
    p.add_argument("--grid", type=float, default=5, help="grid spacing in units")
    p.add_argument("--no-terrain", action="store_true")
    p.add_argument("--keep", action="store_true", help="keep enemies and hazards")
    p.add_argument("--out")
    args = p.parse_args()

    scene = room.Scene(args.room)
    room.apply_save_state(scene)
    items = [it for it in room.collect(scene) if args.keep or not room.is_unwanted(scene, it.go)]
    tm = next((o.read_typetree() for o in scene.objects
               if o.type.name == "MonoBehaviour" and game.script_class(o) == "tk2dTileMap"), None)
    left, bottom, width, height = args.region or (0, 0, tm["width"], tm["height"])
    blur_z = next((float(scene.world(scene.go_transform[o.read().m_GameObject.path_id])[2, 3]) for o in scene.objects
                   if o.type.name == "MonoBehaviour" and game.script_class(o) == "BlurPlane"), None)
    ppu = args.ppu
    back, front, grade = room.render(scene, items, room.Camera(left, bottom, width, height, ppu), blur_z=blur_z)
    back.alpha_composite(front)
    img = game.grade_image(back, grade.apply, bloom_ppu=ppu).convert("RGB")

    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    top = bottom + height
    if not args.no_terrain:
        for pts, closed in room.terrain(scene):
            xy = [((x - left) * ppu, (top - y) * ppu) for x, y in pts]
            if closed:
                xy.append(xy[0])
            d.line(xy, fill=(255, 0, 255), width=1)
    g = args.grid
    x = (left // g + 1) * g
    while x < left + width:
        d.line([((x - left) * ppu, 0), ((x - left) * ppu, img.height)], fill=(90, 200, 255), width=1)
        d.text(((x - left) * ppu + 2, 2), f"{x:g}", fill=(90, 200, 255), font=font)
        x += g
    y = (bottom // g + 1) * g
    while y < top:
        d.line([(0, (top - y) * ppu), (img.width, (top - y) * ppu)], fill=(90, 200, 255), width=1)
        d.text((2, (top - y) * ppu + 2), f"{y:g}", fill=(90, 200, 255), font=font)
        y += g
    out = args.out or f"{args.room}.jpg"
    img.save(out, quality=88)
    print(f"{args.room}: {width:g} x {height:g} units -> {out} {img.size}")


if __name__ == "__main__":
    main()

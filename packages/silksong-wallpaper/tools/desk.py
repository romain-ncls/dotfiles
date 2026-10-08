#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Lay preview.qml's per-screen renders out as the screens sit on the desk.

Each render is shrunk to its physical size, bottom edges aligned, with the
bezel gap between screens, one row per time: anything that should be
continuous across screens (the diagonal, Hornet's size) has to look
continuous here.

    tools/desk.py OUT_DIR [--gap 15] [--scale 1.2]
"""
import argparse
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

# Left to right, physical size in mm.
DESK = [("DP-3", 476.2, 267.9), ("eDP-1", 344.0, 215.0), ("HDMI-A-1", 476.2, 267.9)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dir", type=Path)
    parser.add_argument("--gap", type=float, default=15, help="mm between picture areas")
    parser.add_argument("--scale", type=float, default=1.2, help="output pixels per mm")
    args = parser.parse_args()

    shots = defaultdict(dict)
    for f in args.dir.glob("*@*.png"):
        name, time = re.match(r"(.+)@(.+)\.png", f.name).groups()
        shots[time][name] = f

    k = args.scale
    width = round((sum(w for _, w, _ in DESK) + args.gap * (len(DESK) - 1)) * k) + 20
    row_h = round(max(h for _, _, h in DESK) * k) + 30
    out = Image.new("RGB", (width, row_h * len(shots)), (60, 60, 60))
    draw = ImageDraw.Draw(out)
    for row, time in enumerate(sorted(shots, key=lambda t: (len(t), t))):
        top = row * row_h + 20
        bottom = top + round(max(h for _, _, h in DESK) * k)
        draw.text((10, top - 16), f"t = {time}", fill=(230, 230, 230))
        x = 10.0
        for name, w, h in DESK:
            img = Image.open(shots[time][name]).convert("RGB").resize((round(w * k), round(h * k)), Image.LANCZOS)
            out.paste(img, (round(x), bottom - img.height))
            x += (w + args.gap) * k
    path = args.dir / "desk.png"
    out.save(path)
    print(path)


if __name__ == "__main__":
    main()

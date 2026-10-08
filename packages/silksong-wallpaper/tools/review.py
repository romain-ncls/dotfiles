#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Full-resolution review sheets of the composed world, to go through before showing it.

    tools/review.py OUT_DIR [IMAGE]     IMAGE: another rendering of the world (default preview.jpg),
                                        e.g. one with Hornet's walking line drawn on it

Cuts ~/.local/share/silksong-wallpaper/world/preview.jpg (backdrops, rock and foreground,
without Hornet or the time of day) into crops at the world's own resolution: every visible
part of each screen in overlapping tiles, then a strip centred on each bezel, where the two
screens' sides have to match. Writes OUT_DIR/index.txt listing each crop and what it covers,
in world units, so a defect found in a crop can be traced back to layout() or the dressing.

The checklist they are for (from the reviews of 2026-10-07):
  - nothing crossing a bezel changes shape, dressing or colour at the bezel;
  - no piece is cut with a straight edge, turned sideways on a platform end, or repeated;
  - no bare black rock where dressing should be, no stray piece where it shouldn't;
  - backdrops change gradually between screens;
  - nothing floats that looks walkable without being so, nothing walkable is hidden;
  - her walking line (review against nav overlay) follows the drawn ground everywhere.
"""
import sys
from pathlib import Path

from PIL import Image

WORLD = Path.home() / ".local/share/silksong-wallpaper/world"
PPU = 56
H = 26.79
SCREENS = [("left", 0.0, 47.62, H), ("laptop", 49.12, 83.52, 21.5), ("right", 85.02, 132.64, H)]
BEZELS = [(47.62, 49.12), (83.52, 85.02)]
TILE = (900, 640)  # pixels: about 16 x 11.4 units


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    img = Image.open(sys.argv[2] if len(sys.argv) > 2 else WORLD / "preview.jpg").convert("RGB")
    index = []

    def crop(name, x0, y0, x1, y1, what):
        """x, y in world units (y up)."""
        box = (round(x0 * PPU), round((H - y1) * PPU), round(x1 * PPU), round((H - y0) * PPU))
        img.crop(box).save(out / f"{name}.jpg", quality=92)
        index.append(f"{name}.jpg  x {x0:.1f}-{x1:.1f}, y {y0:.1f}-{y1:.1f}  {what}")

    tw, th = TILE[0] / PPU, TILE[1] / PPU
    for screen, x0, x1, top in SCREENS:
        cols = max(1, round((x1 - x0) / (tw * 0.85)))
        rows = max(1, round(top / (th * 0.85)))
        for r in range(rows):
            for c in range(cols):
                cx0 = x0 + (x1 - x0 - tw) * (c / max(1, cols - 1))
                cy0 = (top - th) * (r / max(1, rows - 1))
                crop(f"{screen}_{rows - 1 - r}{c}", cx0, cy0, cx0 + tw, cy0 + th,
                     f"{screen} screen, row {rows - r} from the top, column {c + 1}")
    for i, (a, b) in enumerate(BEZELS):
        mid = (a + b) / 2
        crop(f"bezel{i + 1}_low", mid - 8, 0.0, mid + 8, 11.0, f"bezel {i + 1}, lower half (screens meet at {a}-{b})")
        crop(f"bezel{i + 1}_high", mid - 8, 10.5, mid + 8, 21.5, f"bezel {i + 1}, upper half")
    (out / "index.txt").write_text("\n".join(index) + "\n")
    print(f"{len(index)} crops -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

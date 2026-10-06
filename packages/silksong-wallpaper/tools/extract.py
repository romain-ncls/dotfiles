#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy"]
# ///
"""Extract Hornet's animation clips from an installed Hollow Knight: Silksong.

The sprites stay out of the repo (they're Team Cherry's): this writes them,
plus a Sprites.qml manifest the wallpaper loads, to
~/.local/share/silksong-wallpaper.

Each clip becomes one PNG grid of equally sized cells. Every frame is drawn at
the same offset from the sprite's anchor, so the wallpaper only needs the
cell size and the anchor to place any frame.
"""
import argparse
import json
import math
import os
import warnings
from pathlib import Path

import numpy as np
import UnityPy
from PIL import Image

warnings.filterwarnings("ignore")
UnityPy.config.FALLBACK_UNITY_VERSION = "6000.0.50f1"

DEFAULT_GAME = Path.home() / ".local/share/Steam/steamapps/common/Hollow Knight Silksong"
DEFAULT_OUT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "silksong-wallpaper"
BUNDLES = ["herodynamic_assets_all.bundle", "herocollections_assets_shared.bundle"]
# Hornet's tk2dSpriteAnimation still carries Hollow Knight's name.
LIBRARY = "Knight"
CLIPS = [
    "Idle", "Walk", "Turn", "TurnWalk", "Walk To Idle", "Run", "Run To Idle",
    "Sit", "Sit Idle", "Sit Fall Asleep", "Sitting Asleep", "Wake To Sit",
    "SitLook 1", "SitLook 2", "SitLook 3", "SitLook 4",
    "NeedolinSit Start", "NeedolinSit Play", "NeedolinSit End",
    "LookUp", "LookingUp", "LookUpEnd", "Map Open", "Map Idle", "Map Away",
]
# Transparent border around each cell: keeps smooth scaling from bleeding a neighbour in, and
# leaves room for the bloom halo bake.py adds around Hornet (about 10 sheet pixels of sigma).
PADDING = 28
MAX_SHEET_WIDTH = 2048


def mono_behaviours(env, cls):
    """{GameObject name: [object]} for every MonoBehaviour of script class cls."""
    found = {}
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        try:
            mb = obj.read()
            if mb.m_Script.read().m_ClassName != cls:
                continue
            name = mb.m_GameObject.read().m_Name
        except Exception:
            continue
        found.setdefault(name, []).append(obj)
    return found


class Collections:
    """tk2dSpriteCollectionData lookups, with their atlases decoded once."""

    def __init__(self, env):
        self.objects = {o.path_id: o for objs in mono_behaviours(env, "tk2dSpriteCollectionData").values() for o in objs}
        self.trees, self.atlases = {}, {}

    def definition(self, ref, sprite_id):
        obj = self.objects[ref["m_PathID"]]
        if obj.path_id not in self.trees:
            self.trees[obj.path_id] = obj.read_typetree()
        return obj, self.trees[obj.path_id]["spriteDefinitions"][sprite_id]

    def atlas(self, obj, material_id):
        key = (obj.path_id, material_id)
        if key not in self.atlases:
            ref = self.trees[obj.path_id]["textures"][material_id]
            self.atlases[key] = obj.assets_file.objects[ref["m_PathID"]].read().image.convert("RGBA")
        return self.atlases[key]


def render(collections, obj, d):
    """Draw a sprite definition upright. Returns (image, left, top) in game units, y up."""
    atlas = collections.atlas(obj, d["materialId"])
    texel = d["texelSize"]["x"]
    pos = np.array([[p["x"], p["y"]] for p in d["positions"]])
    uv = np.array([[u["x"] * atlas.width, (1 - u["y"]) * atlas.height] for u in d["uvs"]])
    left, right = pos[:, 0].min(), pos[:, 0].max()
    bottom, top = pos[:, 1].min(), pos[:, 1].max()
    out = np.stack([(pos[:, 0] - left) / texel, (top - pos[:, 1]) / texel], 1)
    # The quad's vertex -> UV mapping also covers sprites packed rotated ("flipped").
    a = np.hstack([out[:3], np.ones((3, 1))])
    coeffs = (*np.linalg.solve(a, uv[:3, 0]), *np.linalg.solve(a, uv[:3, 1]))
    size = (round((right - left) / texel), round((top - bottom) / texel))
    return atlas.transform(size, Image.AFFINE, coeffs, resample=Image.NEAREST), left, top, texel


def extract_clip(collections, clip, out_dir):
    # Clips often hold a pose by repeating a sprite: draw each sprite once and
    # keep the playback order in "sequence".
    keys = [(f["spriteCollection"]["m_PathID"], f["spriteId"]) for f in clip["frames"]]
    unique = list(dict.fromkeys(keys))
    refs = {(f["spriteCollection"]["m_PathID"], f["spriteId"]): f["spriteCollection"] for f in clip["frames"]}
    cells = [render(collections, *collections.definition(refs[k], k[1])) for k in unique]
    texel = cells[0][3]
    left = min(c[1] for c in cells)
    top = max(c[2] for c in cells)
    right = max(c[1] + c[0].width * texel for c in cells)
    bottom = min(c[2] - c[0].height * texel for c in cells)
    cell_w = round((right - left) / texel) + 2 * PADDING
    cell_h = round((top - bottom) / texel) + 2 * PADDING
    columns = max(1, min(len(cells), MAX_SHEET_WIDTH // cell_w))
    sheet = Image.new("RGBA", (cell_w * columns, cell_h * math.ceil(len(cells) / columns)))
    for i, (img, l, t, _) in enumerate(cells):
        cx, cy = (i % columns) * cell_w, (i // columns) * cell_h
        sheet.alpha_composite(img, (cx + PADDING + round((l - left) / texel), cy + PADDING + round((top - t) / texel)))
    file = "hornet/" + clip["name"].replace(" ", "_") + ".png"
    sheet.save(out_dir / file, optimize=True)
    return {
        "file": file,
        "fps": clip["fps"],
        "wrapMode": clip["wrapMode"],  # tk2d: 0 loop, 1 loop section, 2 once, 3 ping-pong, 6 single
        "loopStart": clip["loopStart"],
        "frames": len(keys),
        "sequence": [unique.index(k) for k in keys],  # frame -> cell
        "columns": columns,
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "anchorX": PADDING + round(-left / texel),
        "anchorY": PADDING + round(top / texel),
        "pixelsPerUnit": round(1 / texel),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME, help=f"game install (default: {DEFAULT_GAME})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output folder (default: {DEFAULT_OUT})")
    parser.add_argument("--list", action="store_true", help="print every clip name in Hornet's library and exit")
    parser.add_argument("clips", nargs="*", default=CLIPS, help="clip names (default: the set the wallpaper uses)")
    args = parser.parse_args()

    bundles = args.game / "Hollow Knight Silksong_Data/StreamingAssets/aa/StandaloneLinux64"
    monoscripts = next(bundles.glob("*_monoscripts.bundle"))
    env = UnityPy.load(*[str(bundles / b) for b in BUNDLES], str(monoscripts))
    library = mono_behaviours(env, "tk2dSpriteAnimation")[LIBRARY][0].read_typetree()
    by_name = {c["name"]: c for c in library["clips"] if c["name"]}
    if args.list:
        print("\n".join(sorted(by_name)))
        return

    (args.out / "hornet").mkdir(parents=True, exist_ok=True)
    collections = Collections(env)
    manifest = {}
    for name in args.clips:
        manifest[name] = extract_clip(collections, by_name[name], args.out)
        print(f"{name}: {manifest[name]['frames']} frames, {max(manifest[name]['sequence']) + 1} unique")
    (args.out / "Sprites.qml").write_text(
        "// Generated by packages/silksong-wallpaper/tools/extract.py\n"
        "import QtQml\n\n"
        "QtObject {\n"
        f"    readonly property var clips: ({json.dumps(manifest, indent=1)})\n"
        "}\n"
    )
    print(f"wrote {len(manifest)} clips to {args.out}")


if __name__ == "__main__":
    main()

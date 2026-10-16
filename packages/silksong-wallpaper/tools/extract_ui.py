#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["UnityPy>=1.25", "pillow", "numpy"]
# ///
"""Extract the game's menu art and type the lock screen is drawn with.

Like extract.py, this reads an installed Hollow Knight: Silksong and keeps the result out of
the repo: it writes to ~/.local/share/silksong-wallpaper/ui

- fonts/: Trajan Pro (regular and bold) and Perpetua, the game's own font files;
- the frames of the ornaments that grow open (Hornet's dialogue fleur above the column, the
  weaver's prompt fleur below it) and of Hornet's needle (it ends the messages); the full stop
  the game ends other characters' lines with (one per character typed), the inventory's
  hairline (under the password), the menu's selection mark, and a pair of bug eyes, open and
  half-closed, for showing the password;
- Kit.qml, which lists them. lockscreen/LockScreen.qml uses the Silksong prompt only when it
  can read this file and it is of the version the prompt needs, and Plasma's own otherwise.
"""
import argparse
import json
import os
import re
import warnings
from pathlib import Path

import numpy as np
import UnityPy

warnings.filterwarnings("ignore")
UnityPy.config.FALLBACK_UNITY_VERSION = "6000.0.50f1"

DEFAULT_GAME = Path.home() / ".local/share/Steam/steamapps/common/Hollow Knight Silksong"
DEFAULT_OUT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "silksong-wallpaper" / "ui"
BUNDLES = "Hollow Knight Silksong_Data/StreamingAssets/aa/StandaloneLinux64"
FONTS = {"TrajanPro-Regular", "TrajanPro-Bold", "Perpetua"}
# Kit.qml key: (sprite atlas, frame name prefix). Each is every frame of that prefix, in order;
# the first frames of an ornament are a few pixels wide (it grows from its centre) and the
# all-empty ones are left out.
SEQUENCES = {
    "fleurTop": ("ui_dialogue", "Dialogue_fleur_top_Hornet"),
    "fleurBottom": ("titlefleurs", "prompt_fleur_weaver"),
    "needle": ("ui_dialogue", "arrow_down_hornet"),
}
# The full stop's last frame (the others are it growing in).
SINGLES = {"mark": ("ui", "RT_LT_arrow"), "hairline": ("ui", "Inv_0017_divider"),
           "dot": ("ui_dialogue", "Full_stop_NPC0003")}
# Kit.qml's version: raised whenever SilksongLockUi.qml needs art an older Kit.qml doesn't list
# (lockscreen/LockScreen.qml has the same number).
KIT_VERSION = 2
# The shaman's memory draws its bugs' eyes as a sheet of white pairs, top to bottom: open,
# half-closed, narrowed. The first two show and hide the password.
EYES = ("snail_memory", "Shaman_Memory_Eyes0010", ("eyesOpen", "eyesLidded"))


def atlas(root, name):
    found = list((root / "atlases_assets_assets").rglob(f"{name}.spriteatlas.bundle"))
    if not found:
        raise SystemExit(f"No sprite atlas {name} under {root}: is the game installed there?")
    return UnityPy.load(str(found[0]))


def sprites(env):
    return {obj.peek_name(): obj for obj in env.objects if obj.type.name == "Sprite"}


def rows(image):
    """The bands of rows that hold anything, top to bottom, as (top, bottom)."""
    alpha = np.asarray(image.getchannel("A")) > 8
    filled = alpha.any(axis=1)
    bands, start = [], None
    for y, f in enumerate(filled):
        if f and start is None:
            start = y
        elif not f and start is not None:
            bands.append((start, y))
            start = None
    if start is not None:
        bands.append((start, len(filled)))
    return bands


def save(image, path):
    tmp = path.with_name(f".{path.name}.tmp")
    image.save(tmp, format="PNG")
    os.replace(tmp, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--game", type=Path, default=DEFAULT_GAME, help=f"game install (default: {DEFAULT_GAME})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output folder (default: {DEFAULT_OUT})")
    args = parser.parse_args()
    root = args.game / BUNDLES
    (args.out / "fonts").mkdir(parents=True, exist_ok=True)

    env = UnityPy.load(str(root / "fonts_assets_english.bundle"))
    fonts = {}
    for obj in env.objects:
        if obj.type.name == "Font" and obj.peek_name() in FONTS:
            font = obj.read()
            data = bytes(font.m_FontData)
            name = f"{font.m_Name}.{'otf' if data[:4] == b'OTTO' else 'ttf'}"
            tmp = args.out / "fonts" / f".{name}.tmp"
            tmp.write_bytes(data)
            os.replace(tmp, args.out / "fonts" / name)
            fonts[font.m_Name] = f"fonts/{name}"
    if set(fonts) != FONTS:
        raise SystemExit(f"Fonts missing from the game: {sorted(FONTS - set(fonts))}")

    kit, written, envs = {}, set(), {}
    for key, (atlas_name, prefix) in SEQUENCES.items():
        if atlas_name not in envs:
            envs[atlas_name] = sprites(atlas(root, atlas_name))
        frames = sorted(n for n in envs[atlas_name] if re.fullmatch(re.escape(prefix) + r"\d{4}", n))
        kit[key] = []
        for name in frames:
            image = envs[atlas_name][name].read().image.convert("RGBA")
            if not rows(image):
                continue
            save(image, args.out / f"{name}.png")
            kit[key].append(f"{name}.png")
            written.add(f"{name}.png")
        if not kit[key]:
            raise SystemExit(f"No frames for {prefix} in {atlas_name}")
    for key, (atlas_name, name) in SINGLES.items():
        if atlas_name not in envs:
            envs[atlas_name] = sprites(atlas(root, atlas_name))
        save(envs[atlas_name][name].read().image.convert("RGBA"), args.out / f"{name}.png")
        kit[key] = f"{name}.png"
        written.add(f"{name}.png")

    atlas_name, name, keys = EYES
    sheet = sprites(atlas(root, atlas_name))[name].read().image.convert("RGBA")
    bands = rows(sheet)
    if len(bands) < len(keys):
        raise SystemExit(f"{name} no longer holds {len(keys)} pairs of eyes")
    for key, (top, bottom) in zip(keys, bands):
        band = sheet.crop((0, top, sheet.width, bottom))
        save(band.crop(band.getbbox()), args.out / f"{key}.png")
        kit[key] = f"{key}.png"
        written.add(f"{key}.png")

    for old in args.out.glob("*.png"):
        if old.name not in written:
            old.unlink()
    kit = {"version": KIT_VERSION, "fontTrajan": fonts["TrajanPro-Regular"],
           "fontTrajanBold": fonts["TrajanPro-Bold"], "fontPerpetua": fonts["Perpetua"], **kit}
    lines = ["// Written by tools/extract_ui.py: the lock screen's art, from the game.", "import QtQml", "",
             "QtObject {"]
    for key, value in kit.items():
        if isinstance(value, list):
            lines.append(f"    readonly property var {key}: [{', '.join(json.dumps(v) for v in value)}]")
        elif isinstance(value, int):
            lines.append(f"    readonly property int {key}: {value}")
        else:
            lines.append(f"    readonly property string {key}: {json.dumps(value)}")
    lines.append("}")
    tmp = args.out / ".Kit.qml.tmp"
    tmp.write_text("\n".join(lines) + "\n")
    os.replace(tmp, args.out / "Kit.qml")
    print(f"Wrote {len(written)} images, {len(fonts)} fonts and Kit.qml to {args.out}")


if __name__ == "__main__":
    main()

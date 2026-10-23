#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=11.3"]
# ///
"""What the wallpaper reads in place of the world's own images, to show sooner and hold less.

    tools/derive.py [WORLD_QML]

- QOI twins: the same pixels, in a format Qt reads 2-4 times faster than PNG with KDE's image
  formats (kimageformats, which Plasma has). For each image the wallpaper waits for as it loads
  (the tiles, the painting shown meanwhile, the air, the plants' and the floor bells' sheets, the
  sheets Sprites.qml lists, and the views and sheet sets below), X.qoi beside X.png, made again
  only once the PNG has changed.
- Views, in views/: for each screen of this desk (tools/desk.js), the texels each layer shows
  there, as Qt itself reads them from the tiles (tools/derive.qml): already scaled to the screen,
  and cut to the bands of rows that hold anything. A screen then reads those few rather than
  every tile it shows, whole, and keeps about half as many texels. The world's painting (which
  the lock screen shows in its first frame) as one image of each screen's size, and its timing.
- Sheet sets, in hornet@<density>/: each sheet Sprites.qml lists at each screen's density, at the
  size the wallpaper asks for it there, scaled by Qt itself: read as it is, rather than read whole
  and scaled down.
- Rows: the rows of each tile that hold anything, the only ones a screen keeps of it where it has
  no view (another desk, another gap between the screens).

Then world/Derived.qml lists them for the world's build. The wallpaper reads a twin only where Qt
can read QOI, a view only on the very screen it was made for, a sheet set only at its density, and
none of them for another build. tools/world.py runs it on the World.qml it is about to put in
place (WORLD_QML), so that a running wallpaper finds them together; on a world made before, run
it alone. Without Qt (tools/derive.qml, through nix) there are only the twins and the rows. Files
are only written again where they change; what is no longer listed goes (an earlier build's
twins, a screen or a density the desk no longer has). One run at a time, and not during a
tools/bench.py run (its lock).
"""
import argparse
import fcntl
import io
import json
import os
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "silksong-wallpaper"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
GAP = 32  # empty rows that part two bands of a view (fewer, and one band takes them in)


def manifest(path, prop):
    """What a generated QML file (World.qml, Sprites.qml) holds in its one property."""
    text = path.read_text()
    start = text.index("(", text.index(f"property var {prop}"))
    return json.loads(text[start + 1:text.rindex(")")])


def put(path, data):
    """Writes data to path unless it holds it already (so that its twin stays). Written aside
    and put in place in one step, so that nothing ever reads half of it."""
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def twin(png):
    """X.qoi beside X.png, unless the one there was made from this PNG (it carries the PNG's
    time). Written aside and put in place in one step, so that nothing ever reads half of one."""
    qoi = png.with_suffix(".qoi")
    stat = png.stat()
    if qoi.exists() and qoi.stat().st_mtime_ns == stat.st_mtime_ns:
        return False
    # RGBA but where the PNG is RGB (the views' backdrops, drawn as they are): Qt scales an RGB
    # image down by other means than an RGBA one, up to 8 levels off at some sizes, so the
    # backdrops' tiles, opaque throughout but RGBA, stay so.
    with Image.open(png) as img:
        pixels = img.convert("RGB" if img.mode == "RGB" else "RGBA")
    tmp = qoi.with_name(f".{qoi.name}.tmp")
    pixels.save(tmp, format="QOI", colorspace="sRGB")
    os.utime(tmp, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    os.replace(tmp, qoi)
    return True


def draw(world, sprites, out):
    """Has Qt draw this desk's texels and sheets into out (tools/derive.qml), offscreen on its
    software renderer, and returns what they are, as it logs them."""
    qtdeclarative = subprocess.run(["nix", "build", "--no-link", "--print-out-paths", "nixpkgs#qt6.qtdeclarative"],
                                   check=True, capture_output=True, text=True).stdout.split()[0]
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_SCALE_FACTOR="1",
               QT_FORCE_STDERR_LOGGING="1", QT_MESSAGE_PATTERN="%{message}")
    run = subprocess.run([f"{qtdeclarative}/bin/qml", HERE / "derive.qml", "--", world.resolve(), sprites.resolve(), out],
                         env=env, capture_output=True, text=True, timeout=600)
    for line in run.stderr.splitlines():
        if run.returncode == 0 and line.startswith("DERIVED "):
            return json.loads(line.removeprefix("DERIVED "))
    failed = [line.removeprefix("FAILED ") for line in run.stderr.splitlines() if line.startswith("FAILED ")]
    raise RuntimeError(failed[0] if failed else run.stderr.strip()[-300:] or f"qml exited with {run.returncode}")


def bands(img):
    """The parts of a screen's texels of a tile that hold anything, as boxes: its bands of rows
    that do, each as wide as what it holds, with one texel more on each side (the smoothing reads
    it, transparent where the whole tile is)."""
    width, height = img.size
    if img.mode != "RGBA":
        return [(0, 0, width, height)]
    alpha = img.getchannel("A")
    data = alpha.tobytes()
    runs = []
    for y in range(height):
        if data.count(0, y * width, (y + 1) * width) == width:
            continue
        if runs and y - runs[-1][1] <= GAP:
            runs[-1][1] = y + 1
        else:
            runs.append([y, y + 1])
    boxes = []
    for top, bottom in runs:
        left, _, right, _ = alpha.crop((0, top, width, bottom)).getbbox()
        boxes.append((max(0, left - 1), max(0, top - 1), min(width, right + 1), min(height, bottom + 1)))
    return boxes


def cut(drawn, out, folder):
    """A screen's view of a layer, its pieces written in folder (views/) as { file, x, y, w, h },
    in its pixels: where the texels it holds go, as WorldScene would place them from the tile."""
    pieces = []
    for texels in drawn:
        with Image.open(out / texels["file"]) as img:
            img.load()
        for left, top, right, bottom in bands(img):
            file = f"views/{texels['file'].rsplit('_', 1)[0]}_{len(pieces)}.png"
            data = io.BytesIO()
            img.crop((left, top, right, bottom)).save(data, format="PNG")
            put(folder / file, data.getvalue())
            pieces.append({"file": file, "x": texels["fx"] + (texels["tx"] + left) * texels["sx"],
                           "y": texels["fy"] + (texels["ty"] + top) * texels["sy"],
                           "w": (right - left) * texels["sx"], "h": (bottom - top) * texels["sy"]})
    return pieces


def whole_view(drawn, size, out, folder, stem, scale=1.0):
    """A screen's view of an opaque image laid as tiles (the world's painting, its timing) in one
    image of its size, views/<stem>.png: the texels it shows of each tile, where they go. There's
    nothing to cut away; one image is read sooner than several. Smaller by scale where it's smooth
    (the painting's timing, a quarter): stretched back as it's drawn."""
    img = Image.new("RGBA", tuple(size), (0, 0, 0, 255))
    for texels in drawn:
        with Image.open(out / texels["file"]) as piece:
            piece.load()
        w, h = round(piece.width * texels["sx"]), round(piece.height * texels["sy"])
        if (w, h) != piece.size:
            piece = piece.resize((w, h), Image.BILINEAR)
        img.paste(piece, (round(texels["fx"] + texels["tx"] * texels["sx"]), round(texels["fy"] + texels["ty"] * texels["sy"])))
    if scale != 1.0:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    file = f"views/{stem}.png"
    data = io.BytesIO()
    img.save(data, format="PNG")
    put(folder / file, data.getvalue())
    return file


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("world", nargs="?", type=Path, default=DATA / "world/World.qml",
                        help="the world to make them for (default: %(default)s)")
    args = parser.parse_args()

    lock = open(RUNTIME / "silksong-bench.flock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    folder = args.world.parent
    world = manifest(args.world, "world")
    sprites = folder.parent / "Sprites.qml"
    clips = manifest(sprites, "clips") if sprites.exists() else {}

    views, sheet_sets, sheets = [], {}, []
    with tempfile.TemporaryDirectory(prefix="silksong-derive-") as out:
        out = Path(out)
        try:
            drawn = draw(args.world, sprites, out)
        except (OSError, subprocess.SubprocessError, RuntimeError) as e:
            print(f"No views nor sheet sets: Qt couldn't draw them ({e})")
            drawn = {"views": [], "sheetSets": {}}
        for i, view in enumerate(drawn["views"]):
            layers = dict(view["layers"])
            paint, time_ = layers.pop("paint", []), layers.pop("time", [])
            views.append(dict(view, layers={name: cut(texels, out, folder) for name, texels in layers.items()}))
            if paint and time_:
                views[-1]["painting"] = {"paint": whole_view(paint, view["px"], out, folder, f"painting_{i}"),
                                         "time": whole_view(time_, view["px"], out, folder, f"painting_time_{i}", 0.25)}
        for set_folder, px_per_unit in drawn["sheetSets"].items():
            sheet_sets[set_folder] = px_per_unit
            for name in dict.fromkeys(Path(clip["file"]).name for clip in clips.values()):
                put(folder / set_folder / name, (out / f"{set_folder}_{name}").read_bytes())
                sheets.append(f"{set_folder}/{name}")

    rows = {}
    for tile in [tile for tiles in world["layers"].values() for tile in tiles if (folder / tile["file"]).exists()]:
        with Image.open(folder / tile["file"]) as img:
            if img.mode == "RGBA" and (box := img.getchannel("A").getbbox()) and (box[1], box[3]) != (0, img.height):
                rows[tile["file"]] = {"rows": [box[1], box[3]]}

    files = [tile["file"] for tiles in world["layers"].values() for tile in tiles]
    files += [a["file"] for a in world.get("air", [])]
    files += [tile["file"] for tiles in (world.get("painting") or {}).values() for tile in tiles]
    files += [world["sway"]["atlas"]] if world.get("sway") else []
    files += [a["sheet"] for a in world.get("animated", [])]
    files += [clip["file"] for clip in clips.values()]
    files += [piece["file"] for view in views for pieces in view["layers"].values() for piece in pieces]
    files += [file for view in views for file in view.get("painting", {}).values()]
    files += sheets

    made, twins = 0, {}
    for file in dict.fromkeys(files):
        png = folder / file
        if png.suffix == ".png" and png.exists():
            made += twin(png)
            twins[file] = True

    derived = json.dumps({"build": world["build"], "qoi": twins, "views": views, "sheetSets": sheet_sets, "tiles": rows})
    text = ("// Generated by packages/silksong-wallpaper/tools/derive.py\nimport QtQml\n\n"
            f"QtObject {{\n    readonly property var derived: ({derived})\n}}\n")
    put(folder / "Derived.qml", text.encode())

    # Then what it no longer lists: the views and sheet sets of screens and densities the desk no
    # longer has, and twins whose PNG is gone.
    listed = set(files)
    gone = [png for png in [*folder.glob("views/*.png"), *folder.glob("hornet@*/*.png")]
            if png.relative_to(folder).as_posix() not in listed]
    for png in gone:
        png.unlink()
    stale = [qoi for qoi in folder.rglob("*.qoi") if not qoi.with_suffix(".png").exists()]
    for qoi in stale:
        qoi.unlink()
    for empty in [d for d in [folder / "views", *folder.glob("hornet@*")] if d.is_dir() and not any(d.iterdir())]:
        empty.rmdir()

    print(f"QOI twins: {made} made, {len(twins) - made} up to date, {len(stale)} removed; views of {len(views)}"
          f" screens, sheet sets {', '.join(sheet_sets) or 'none'} ({len(gone)} files removed); rows of"
          f" {len(rows)} tiles; for build {world['build']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy"]
# ///
"""Compare two sets of preview.qml renders, image by image: a change meant to leave the look
alone has to come out at a maximum difference of 1 (the renders are deterministic).

    tools/viscmp.py REF_DIR NEW_DIR

For each render of REF_DIR: the largest difference of any channel of any pixel (0-255), the
mean difference and how many pixels differ by more than 2. Exits with an error when a render is
missing or differs by more than 1 anywhere.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ref", type=Path)
    parser.add_argument("new", type=Path)
    args = parser.parse_args()

    refs = sorted(args.ref.glob("*.png"))
    if not refs:
        sys.exit(f"no renders in {args.ref}")
    worst, changed, bad = 0, 0, 0
    for ref in refs:
        new = args.new / ref.name
        if not new.exists():
            print(f"{ref.name:28s} missing")
            bad += 1
            continue
        a = np.asarray(Image.open(ref).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(new).convert("RGB"), dtype=np.int16)
        if a.shape != b.shape:
            print(f"{ref.name:28s} size {a.shape[1]}x{a.shape[0]} -> {b.shape[1]}x{b.shape[0]}")
            bad += 1
            continue
        d = np.abs(a - b).max(axis=2)
        over = int((d > 2).sum())
        worst, changed = max(worst, int(d.max())), max(changed, over)
        print(f"{ref.name:28s} max {int(d.max()):3d} mean {d.mean():.4f} px>2 {over}")
    print(f"worst: max {worst}, px>2 {changed}")
    return 1 if bad or worst > 1 else 0


if __name__ == "__main__":
    sys.exit(main())

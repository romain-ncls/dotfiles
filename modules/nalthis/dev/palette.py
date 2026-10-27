#!/usr/bin/env python3
"""Nalthis palette prototype: four knobs -> a KDE color scheme.

    palette.py colors <name> [hue tint depth accent-hue] > Name.colors
    palette.py merge <kdeglobals> <scheme.colors>   (prints kdeglobals with the scheme's groups)

The knobs are the ones from the design page: grey hue (degrees), tint (chroma
multiplier), depth (lightness shift) and accent hue. Surfaces are an OKLCH
ramp; the defaults are the "Custom from Nocturne" pick. Calm chrome (layout A):
content views are the darkest surface, windows and dialogs one step up, and
the header (toolbar + title bar, merged) one more.
"""
import math
import re
import sys

L_SURFACES = [0.199, 0.229, 0.266, 0.299, 0.341]  # frame, base, pane, raised, overlay
CHROMA_RAMP = [0.9, 1, 1.15, 1.3, 1.5]
BASE_CHROMA = 0.013


def oklch(l, c, h):
    h = math.radians(h)
    a, b = c * math.cos(h), c * math.sin(h)
    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b
    l3, m3, s3 = l_ ** 3, m_ ** 3, s_ ** 3
    rgb = [4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
           -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
           -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3]

    def srgb(v):
        v = min(1, max(0, v))
        return round(255 * (12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))
    return tuple(srgb(v) for v in rgb)


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def scheme(name, hue=255, tint=1, depth=0, accent_hue=250):
    c = BASE_CHROMA * tint
    frame, base, pane, raised, overlay = [oklch(l + depth, c * r, hue) for l, r in zip(L_SURFACES, CHROMA_RAMP)]
    fg, fg2, fg3 = oklch(0.94, c * 0.8, hue), oklch(0.76, c * 1.5, hue), oklch(0.58, c * 1.5, hue)
    acc, on_acc = oklch(0.72, 0.13, accent_hue), oklch(0.2, c * 0.9, hue)
    link, visited = oklch(0.75, 0.12, accent_hue), oklch(0.74, 0.12, 305)
    neg, neu, pos = oklch(0.70, 0.14, 20), oklch(0.80, 0.12, 75), oklch(0.78, 0.12, 150)

    def group(bg, alt, text=fg):
        return {"BackgroundNormal": bg, "BackgroundAlternate": alt, "DecorationFocus": acc, "DecorationHover": acc,
                "ForegroundActive": acc, "ForegroundInactive": fg2, "ForegroundLink": link,
                "ForegroundNegative": neg, "ForegroundNeutral": neu, "ForegroundNormal": text,
                "ForegroundPositive": pos, "ForegroundVisited": visited}
    selection = group(acc, mix(acc, base, 0.4), on_acc)
    selection.update(ForegroundInactive=mix(on_acc, acc, 0.35), ForegroundActive=on_acc,
                     ForegroundLink=on_acc, ForegroundVisited=on_acc)
    return {
        "General": {"Name": name, "ColorScheme": name},
        "Colors:Window": group(pane, raised),
        "Colors:View": group(base, mix(base, pane, 0.5)),
        "Colors:Button": group(raised, overlay),
        "Colors:Selection": selection,
        "Colors:Tooltip": group(overlay, raised),
        "Colors:Complementary": group(frame, base),
        "Colors:Header": group(raised, overlay),
        "Colors:Header][Inactive": group(pane, raised),
        "WM": {"activeBackground": raised, "activeBlend": fg, "activeForeground": fg,
               "inactiveBackground": pane, "inactiveBlend": fg3, "inactiveForeground": fg3},
    }


def fmt(v):
    return ",".join(map(str, v)) if isinstance(v, tuple) else str(v)


def to_ini(groups):
    return "".join(f"[{g}]\n" + "".join(f"{k}={fmt(v)}\n" for k, v in kv.items()) + "\n" for g, kv in groups.items())


def parse_ini(text):
    groups, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"^\[(.*)\]$", line)
        if m:
            cur = groups.setdefault(m.group(1), {})
        elif cur is not None and "=" in line:
            k, v = line.split("=", 1)
            cur[k] = v
    return groups


def merge(kdeglobals, colors):
    """kdeglobals with every color group replaced by the scheme's (General only gets ColorScheme)."""
    out, new = parse_ini(kdeglobals), parse_ini(colors)
    for g, kv in new.items():
        if g == "General":
            out.setdefault("General", {})["ColorScheme"] = kv.get("ColorScheme", kv.get("Name", ""))
        else:
            out[g] = kv
    return to_ini(out)


if __name__ == "__main__":
    if sys.argv[1] == "colors":
        knobs = [float(x) for x in sys.argv[3:7]]
        sys.stdout.write(to_ini(scheme(sys.argv[2], *knobs)))
    elif sys.argv[1] == "merge":
        sys.stdout.write(merge(open(sys.argv[2]).read(), open(sys.argv[3]).read()))

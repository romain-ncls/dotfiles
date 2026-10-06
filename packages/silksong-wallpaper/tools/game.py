"""Shared helpers for reading Hollow Knight: Silksong's Unity data."""
import json
import os
import struct
import warnings
from pathlib import Path

import lz4.block
import numpy as np
import UnityPy
from PIL import Image

warnings.filterwarnings("ignore")
UnityPy.config.FALLBACK_UNITY_VERSION = "6000.0.50f1"

GAME = Path.home() / ".local/share/Steam/steamapps/common/Hollow Knight Silksong"
DATA = GAME / "Hollow Knight Silksong_Data"
BUNDLES = DATA / "StreamingAssets/aa/StandaloneLinux64"
CAM_Z = 38.1  # Constants.CAM_Z_DEFAULT
VIEW_W, VIEW_H = 29.2, 16.6  # 2 * Constants.CAM_BOUND_X / Y


def _cstr(f):
    out = b""
    while (c := f.read(1)) != b"\0":
        out += c
    return out.decode()


def bundle_nodes(path):
    """CAB names inside a UnityFS bundle, read from the header only."""
    with open(path, "rb") as f:
        if f.read(8) != b"UnityFS\0":
            return []
        version = struct.unpack(">I", f.read(4))[0]
        _cstr(f)
        _cstr(f)
        size, csize, usize, flags = struct.unpack(">qIII", f.read(20))
        if version >= 7:
            f.seek((f.tell() + 15) // 16 * 16)
        if flags & 0x80:
            f.seek(size - csize)
        data = f.read(csize)
        if flags & 0x3F in (2, 3):
            data = lz4.block.decompress(data, uncompressed_size=usize)
        o = 16
        (nblocks,) = struct.unpack_from(">i", data, o)
        o += 4 + nblocks * 10
        (nnodes,) = struct.unpack_from(">i", data, o)
        o += 4
        names = []
        for _ in range(nnodes):
            o += 20
            end = data.index(b"\0", o)
            names.append(data[o:end].decode())
            o = end + 1
        return names


_cab_index = None


def cab_index():
    global _cab_index
    if _cab_index is None:
        _cab_index = {}
        for root, _, files in os.walk(BUNDLES):
            for fn in files:
                if fn.endswith(".bundle"):
                    p = os.path.join(root, fn)
                    for n in bundle_nodes(p):
                        _cab_index[n.split(".")[0]] = p
    return _cab_index


def load_with_deps(bundle, max_depth=3):
    """Load a bundle and, transitively, the bundles its objects point into."""
    index = cab_index()
    paths = [str(BUNDLES / bundle)]
    seen = set(paths)
    env = UnityPy.load(*paths)
    frontier = list(env.files.values())
    for _ in range(max_depth):
        new = []
        for f in frontier:
            for sf in getattr(f, "files", {}).values():
                for ext in getattr(sf, "externals", []):
                    p = index.get(ext.path.split("/")[-1].split(".")[0])
                    if p and p not in seen:
                        seen.add(p)
                        new.append(p)
        if not new:
            break
        before = set(env.files)
        for p in new:
            env.load_file(p)
        frontier = [env.files[k] for k in env.files if k not in before]
    monoscripts = next(BUNDLES.glob("*_monoscripts.bundle"))
    if str(monoscripts) not in seen:
        env.load_file(str(monoscripts))
    return env


def script_class(obj):
    try:
        return obj.read().m_Script.read().m_ClassName
    except Exception:
        return None


def resolve(obj, ref):
    """Follow a PPtr dict from obj's file; None when it is null or unresolvable."""
    if not ref or ref.get("m_PathID", 0) == 0:
        return None
    sf = obj.assets_file
    try:
        if ref["m_FileID"] == 0:
            return sf.objects[ref["m_PathID"]]
        ext = sf.externals[ref["m_FileID"] - 1].path.split("/")[-1].lower()
        target = sf.environment.get_cab(ext) if hasattr(sf.environment, "get_cab") else None
        if target is None:
            for f in sf.environment.files.values():
                for name, inner in getattr(f, "files", {}).items():
                    if name.lower() == ext:
                        target = inner
        return target.objects[ref["m_PathID"]] if target else None
    except (KeyError, IndexError, AttributeError):
        return None


def eval_curve(curve, t):
    """Evaluate a Unity AnimationCurve (Hermite, unweighted) at t."""
    keys = curve["m_Curve"]
    if not keys:
        return t
    if t <= keys[0]["time"]:
        return keys[0]["value"]
    if t >= keys[-1]["time"]:
        return keys[-1]["value"]
    for a, b in zip(keys, keys[1:]):
        if a["time"] <= t <= b["time"]:
            dt = b["time"] - a["time"]
            if dt <= 0:
                return b["value"]
            s = (t - a["time"]) / dt
            m0 = a["outSlope"] * dt
            m1 = b["inSlope"] * dt
            if not (np.isfinite(m0) and np.isfinite(m1)):
                return a["value"]
            s2, s3 = s * s, s * s * s
            return (2 * s3 - 3 * s2 + 1) * a["value"] + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * b["value"] + (s3 - s2) * m1
    return t


LUMA = np.array([0.22, 0.707, 0.071])  # Unity's Luminance() in gamma space


class Grade:
    """A room's camera colour grade: ColorCorrectionCurves then saturation."""

    def __init__(self, scene_manager):
        sm = scene_manager
        self.xs = np.linspace(0, 1, 256)
        self.lut = np.stack([[eval_curve(sm[c], x) for x in self.xs] for c in ("redChannel", "greenChannel", "blueChannel")], 1).clip(0, 1)
        self.saturation = sm["saturation"] + 0.4  # CustomSceneManager.AdjustSaturationForPlatform
        self.hero_saturation = 1 + sm["heroSaturationOffset"] + 0.5  # _HeroDesaturation = -(offset + 0.5)
        self.hero_light = sm["heroLightColor"]
        self.ambient = sm["defaultColor"], sm["defaultIntensity"]

    def apply(self, rgb):
        """rgb: float array (..., 3) in 0..1."""
        out = np.stack([np.interp(rgb[..., i].clip(0, 1), self.xs, self.lut[:, i]) for i in range(3)], -1)
        lum = (out @ LUMA)[..., None]
        return (lum + (out - lum) * self.saturation).clip(0, 1)

    def ambient_rgb(self):
        """RenderSettings.ambientLight as CustomSceneManager.SetLighting sets it."""
        color, intensity = self.ambient
        k = 1 + (intensity - 1) * 0.5  # Mathf.Lerp(1, intensity, AmbientIntesityMix = 0.5)
        return np.array([color["r"], color["g"], color["b"]]) * k

    def hero_shader(self, rgb):
        """Sprites/Default-ColorFlash with IS_HERO + IS_CHARACTER: 40% ambient, then the
        _HeroDesaturation boost. The camera grade comes on top (apply)."""
        rgb = rgb + (rgb * self.ambient_rgb() * 2 - rgb) * 0.4
        lum = (rgb @ LUMA).clip(0, 1)[..., None]
        return (lum + (rgb - lum) * self.hero_saturation).clip(0, 1)

    def apply_hero(self, rgb):
        return self.apply(self.hero_shader(rgb))


def grade_image(img, fn, bloom_ppu=None):
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255
    if bloom_ppu:
        a[..., :3] = bloom(a[..., :3], bloom_ppu)
    a[..., :3] = fn(a[..., :3])
    return Image.fromarray((a * 255).round().astype(np.uint8), "RGBA")


def gaussian_1d(sigma):
    r = max(1, int(3 * sigma))
    x = np.arange(-r, r + 1)
    k = np.exp(-0.5 * (x / max(sigma, 1e-3)) ** 2)
    return k / k.sum()


def blur(a, sx, sy):
    """Separable Gaussian blur of a float array (H, W, C); sigmas in pixels."""
    out = a
    if sx > 0.2:
        k = gaussian_1d(sx)
        pad = len(k) // 2
        p = np.pad(out, ((0, 0), (pad, pad), (0, 0)), mode="edge")
        out = sum(k[i] * p[:, i:i + out.shape[1]] for i in range(len(k)))
    if sy > 0.2:
        k = gaussian_1d(sy)
        pad = len(k) // 2
        p = np.pad(out, ((pad, pad), (0, 0), (0, 0)), mode="edge")
        out = sum(k[i] * p[i:i + out.shape[0]] for i in range(len(k)))
    return out


# Main camera BloomOptimized: threshold 0.35, intensity 0.43, blurSize 2, 2 iterations, blurShape 0.5,
# Resolution.Low (quarter-size buffer). At 1080p (65 px per unit) its two 7-tap passes spread about
# 2.7 buffer texels horizontally, half that vertically.
BLOOM_THRESHOLD, BLOOM_INTENSITY = 0.35, 0.43
BLOOM_SIGMA_X, BLOOM_SIGMA_Y = 0.165, 0.083  # game units


def bloom(rgb, ppu):
    """Add the camera's bloom to a float RGB image rendered at ppu pixels per game unit."""
    bright = np.maximum(rgb - BLOOM_THRESHOLD, 0) * BLOOM_INTENSITY
    return rgb + blur(bright, BLOOM_SIGMA_X * ppu, BLOOM_SIGMA_Y * ppu)


def hero_light():
    """The light Hornet carries (HeroController.heroLight): sprite, place and blend."""
    from UnityPy.helpers.MeshHelper import MeshHandler
    atlas = next(BUNDLES.glob("atlases_assets_assets/sprites/_atlases/core_glows.spriteatlas.bundle"))
    monoscripts = next(BUNDLES.glob("*_monoscripts.bundle"))
    env = UnityPy.load(str(BUNDLES / "heroloading_assets_all.bundle"), str(atlas), str(monoscripts))
    light = next(o for o in env.objects if o.type.name == "MonoBehaviour" and script_class(o) == "HeroLight")
    sr = resolve(light, light.read_typetree()["spriteRenderer"]).read()
    sprite = sr.m_Sprite.read()
    mesh = MeshHandler(sprite.m_RD, sprite.object_reader.version)
    mesh.process()
    v = np.array(mesh.m_Vertices)[:, :2]
    tr = next(c.read() for c in sr.m_GameObject.read().m_Components if c.read().object_reader.type.name == "Transform")
    return {
        "image": sprite.image.convert("RGBA"),
        "box": (v[:, 0].min(), v[:, 1].min(), v[:, 0].max(), v[:, 1].max()),  # local units, around the pivot
        "offset": (tr.m_LocalPosition.x, tr.m_LocalPosition.y),  # from Hornet's pivot
        "scale": (tr.m_LocalScale.x, tr.m_LocalScale.y),
        "color": (sr.m_Color.r, sr.m_Color.g, sr.m_Color.b, sr.m_Color.a),  # times the room's heroLightColor
    }

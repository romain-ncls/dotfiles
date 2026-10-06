"""Render a Silksong room from its scene data, the way the game's camera sees it.

Sprites (Unity SpriteRenderers and tk2d sprites) are drawn with the game's perspective
camera, its ambient-lit sprite shader, and the background blur behind the room's
BlurPlane. Colour grading and bloom are applied by the caller (see game.Grade, game.bloom).
"""
import argparse
import math
import sys
import time
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter
from UnityPy.helpers.MeshHelper import MeshHandler

import game

SORTING_LAYERS = {0: 0, 3315419377: 1, 1459018367: 2, 4015848369: 3, 2917268371: 4, 1270309357: 5, 3557629463: 6,
                  3868594333: 7, 3784110789: 8, 31172181: 9, 1017658613: 10, 2577183099: 11, 1038907033: 12,
                  3945752401: 13, 629535577: 14, 59515797: 15}
HERO_Z = 0.004  # Hero_Hornet sits on the Default sorting layer, order 0, at this depth
SKIP_LAYERS = {10, 12, 13, 14, 15}  # scene border, vignette, over, HUD


def quat_matrix(q):
    x, y, z, w = q.x, q.y, q.z, q.w
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


class Scene:
    def __init__(self, name):
        t0 = time.time()
        self.env = game.load_with_deps(f"scenes_scenes_scenes/{name}.bundle")
        bundle = next(f for k, f in self.env.files.items() if k.endswith(f"/{name}.bundle"))
        self.objects = [o for sf in bundle.files.values() if hasattr(sf, "objects") for o in sf.objects.values()]
        self.transforms, self.gameobjects = {}, {}
        for o in self.objects:
            if o.type.name in ("Transform", "RectTransform"):
                self.transforms[o.path_id] = o.read()
            elif o.type.name == "GameObject":
                self.gameobjects[o.path_id] = o.read()
        self.go_transform = {t.m_GameObject.path_id: pid for pid, t in self.transforms.items()}
        self._world, self._active = {}, {}
        self.manager = next((o.read_typetree() for o in self.objects
                             if o.type.name == "MonoBehaviour" and game.script_class(o) == "CustomSceneManager"), None)
        print(f"{name}: {len(self.objects)} objects, {len(self.env.files)} files, {time.time() - t0:.1f}s", file=sys.stderr)

    def world(self, tid):
        if tid not in self._world:
            t = self.transforms[tid]
            local = np.eye(4)
            local[:3, :3] = quat_matrix(t.m_LocalRotation) * np.array([t.m_LocalScale.x, t.m_LocalScale.y, t.m_LocalScale.z])
            local[:3, 3] = [t.m_LocalPosition.x, t.m_LocalPosition.y, t.m_LocalPosition.z]
            father = t.m_Father.path_id
            self._world[tid] = (self.world(father) @ local) if father and father in self.transforms else local
        return self._world[tid]

    def active(self, go_id):
        if go_id not in self._active:
            go = self.gameobjects.get(go_id)
            if go is None or not go.m_IsActive:
                self._active[go_id] = False
            else:
                father = self.transforms[self.go_transform[go_id]].m_Father.path_id
                self._active[go_id] = self.active(self.transforms[father].m_GameObject.path_id) if father in self.transforms else True
        return self._active[go_id]


@dataclass
class Item:
    image: Image.Image  # upright sprite image
    corners: np.ndarray  # local (x, y) of image bottom-left, bottom-right, top-left
    matrix: np.ndarray  # 4x4 world
    color: tuple
    shader: str
    layer: int
    order: int
    z: float
    name: str
    go: int = 0


_sprite_cache = {}


def sprite_item_parts(sprite_ptr):
    key = (sprite_ptr.assetsfile.name if sprite_ptr.assetsfile else None, sprite_ptr.path_id)
    if key not in _sprite_cache:
        try:
            sp = sprite_ptr.read()
            img = sp.image.convert("RGBA")
            mesh = MeshHandler(sp.m_RD, sp.object_reader.version)
            mesh.process()
            v = np.array(mesh.m_Vertices)[:, :2]
            _sprite_cache[key] = (img, v[:, 0].min(), v[:, 0].max(), v[:, 1].min(), v[:, 1].max(), sp.m_Name)
        except Exception as e:
            _sprite_cache[key] = None
    return _sprite_cache[key]


def material_info(sr):
    color, shader = (1, 1, 1, 1), "?"
    for m in sr.m_Materials[:1]:
        try:
            mat = m.read()
            shader = mat.m_Shader.read().m_ParsedForm.m_Name
            for k, c in mat.m_SavedProperties.m_Colors:
                if k == "_Color":
                    color = (c.r, c.g, c.b, c.a)
        except Exception:
            pass
    return color, shader


def collect(scene):
    items = []
    for o in scene.objects:
        if o.type.name != "SpriteRenderer":
            continue
        sr = o.read()
        go = sr.m_GameObject.path_id
        if not sr.m_Enabled or not scene.active(go):
            continue
        layer = SORTING_LAYERS.get(sr.m_SortingLayerID & 0xFFFFFFFF, 0)
        if layer in SKIP_LAYERS:
            continue
        parts = sprite_item_parts(sr.m_Sprite)
        if parts is None:
            continue
        img, x0, x1, y0, y1, name = parts
        if sr.m_FlipX:
            x0, x1 = -x0, -x1
        if sr.m_FlipY:
            y0, y1 = -y0, -y1
        mcol, shader = material_info(sr)
        c = sr.m_Color
        color = (c.r * mcol[0], c.g * mcol[1], c.b * mcol[2], c.a * mcol[3])
        m = scene.world(scene.go_transform[go])
        items.append(Item(img, np.array([[x0, y0], [x1, y0], [x0, y1]]), m, color, shader, layer,
                          sr.m_SortingOrder, float(m[2, 3]), scene.gameobjects[go].m_Name, go))
    items.extend(collect_tk2d(scene))
    return items


_tk2d_cache = {}


def tk2d_def_image(coll_obj, coll, sprite_id):
    """Upright image of a tk2d sprite definition plus its local box (left, bottom, right, top)."""
    key = (coll_obj.assets_file.name, coll_obj.path_id, sprite_id)
    if key not in _tk2d_cache:
        d = coll["spriteDefinitions"][sprite_id]
        tex_obj = game.resolve(coll_obj, coll["textures"][d["materialId"]])
        atlas = tex_obj.read().image.convert("RGBA")
        texel = d["texelSize"]["x"]
        pos = np.array([[p["x"], p["y"]] for p in d["positions"]])
        uv = np.array([[u["x"] * atlas.width, (1 - u["y"]) * atlas.height] for u in d["uvs"]])
        left, right, bottom, top = pos[:, 0].min(), pos[:, 0].max(), pos[:, 1].min(), pos[:, 1].max()
        out = np.stack([(pos[:, 0] - left) / texel, (top - pos[:, 1]) / texel], 1)
        a = np.hstack([out[:3], np.ones((3, 1))])
        coeffs = (*np.linalg.solve(a, uv[:3, 0]), *np.linalg.solve(a, uv[:3, 1]))
        size = (max(1, round((right - left) / texel)), max(1, round((top - bottom) / texel)))
        img = atlas.transform(size, Image.AFFINE, coeffs, resample=Image.BICUBIC)
        _tk2d_cache[key] = (img, left, bottom, right, top, d["name"])
    return _tk2d_cache[key]


def _class_of(mb):
    try:
        return mb.m_Script.read().m_ClassName
    except Exception:
        return None


def collect_tk2d(scene):
    items = []
    for o in scene.objects:
        if o.type.name != "MonoBehaviour" or game.script_class(o) != "tk2dSprite":
            continue
        try:
            mb = o.read()
            go_id = mb.m_GameObject.path_id
            if not mb.m_Enabled or not scene.active(go_id):
                continue
            comps = [c.read() for c in scene.gameobjects[go_id].m_Components]
            if any(c.object_reader.type.name == "MonoBehaviour" and _class_of(c) == "HealthManager" for c in comps):
                continue  # enemies
            renderer = next((c for c in comps if c.object_reader.type.name == "MeshRenderer"), None)
            if renderer is None or not renderer.m_Enabled:
                continue
            layer = SORTING_LAYERS.get(renderer.m_SortingLayerID & 0xFFFFFFFF, 0)
            if layer in SKIP_LAYERS:
                continue
            t = o.read_typetree()
            coll_obj = game.resolve(o, t["collection"])
            if coll_obj is None:
                continue
            coll = coll_obj.read_typetree()
            img, left, bottom, right, top, name = tk2d_def_image(coll_obj, coll, t["_spriteId"])
            sx, sy = t["_scale"]["x"], t["_scale"]["y"]
            mcol, shader = material_info(renderer)
            c = t["_color"]
            color = (c["r"] * mcol[0], c["g"] * mcol[1], c["b"] * mcol[2], c["a"] * mcol[3])
            m = scene.world(scene.go_transform[go_id])
            corners = np.array([[left * sx, bottom * sy], [right * sx, bottom * sy], [left * sx, top * sy]])
            items.append(Item(img, corners, m, color, shader, layer, renderer.m_SortingOrder, float(m[2, 3]),
                              scene.gameobjects[go_id].m_Name, go_id))
        except Exception as e:
            print("tk2d skip", type(e).__name__, e, file=sys.stderr)
    return items


class Camera:
    """The game's perspective camera swept across a region, so every depth layer
    covers the region the way it would while scrolling through the room."""

    def __init__(self, left, bottom, width, height, ppu):
        self.left, self.bottom, self.width, self.height, self.ppu = left, bottom, width, height, ppu

    def axis(self, lo, size, view, c, s):
        b = (size - view + view / s) / size if size > view else 1 / s
        a = lo + view / 2 - view / (2 * s) if size > view else (lo + size / 2) - (size / 2) / s
        return (c - a) / b + lo

    def project(self, x, y, z, cx, cy):
        """World point (x, y) on a sprite whose centre is (cx, cy) at depth z -> output pixels."""
        s = game.CAM_Z / (game.CAM_Z + z)
        u = self.axis(self.left, self.width, game.VIEW_W, cx, s) + (x - cx) * s
        v = self.axis(self.bottom, self.height, game.VIEW_H, cy, s) + (y - cy) * s
        return (u - self.left) * self.ppu, (self.bottom + self.height - v) * self.ppu


def draw(canvas, item, cam, tint):
    w = item.matrix
    pts = np.array([w @ np.array([x, y, 0, 1]) for x, y in item.corners])
    centre = pts[:, :3].mean(0) if False else (w @ np.array([item.corners[:, 0].mean(), item.corners[:, 1].mean(), 0, 1]))
    z = float(centre[2])
    if game.CAM_Z + z <= 1:
        return
    out = np.array([cam.project(p[0], p[1], z, centre[0], centre[1]) for p in pts])  # BL, BR, TL in pixels
    img = item.image
    iw, ih = img.size
    # image pixel (0, ih) is BL, (iw, ih) BR, (0, 0) TL
    src = np.array([[0, ih], [iw, ih], [0, 0]], float)
    ex = out[1] - out[0]
    ey = out[2] - out[0]
    corners = np.array([out[0], out[1], out[2], out[1] + ey])
    x0, y0 = np.floor(corners.min(0)).astype(int)
    x1, y1 = np.ceil(corners.max(0)).astype(int)
    cw, ch = canvas.size
    if x1 <= 0 or y1 <= 0 or x0 >= cw or y0 >= ch or x1 - x0 > 4 * cw or y1 - y0 > 4 * ch:
        return
    scale = math.hypot(*ex) / iw
    if scale < 0.5 and iw > 4:
        f = max(1, int(1 / scale))
        img = img.reduce(f)
        src = src * (np.array(img.size) / np.array([iw, ih]))
    # output -> input affine
    a = np.hstack([out - [x0, y0], np.ones((3, 1))])
    coeffs = (*np.linalg.solve(a, src[:, 0]), *np.linalg.solve(a, src[:, 1]))
    piece = img.transform((x1 - x0, y1 - y0), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    r, g, b, al = tint
    if (r, g, b, al) != (1, 1, 1, 1):
        arr = np.asarray(piece).astype(np.float32)
        arr *= np.array([r, g, b, al], np.float32)
        piece = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
    if "Screen" in item.shader:
        # Screen blending lerps the destination towards white by the source colour, which is
        # alpha blending its hue at alpha = its brightest channel. Unlike the formula itself,
        # this also survives on the transparent front layer.
        arr = np.asarray(piece).astype(np.float32) / 255
        light = arr[..., :3] * arr[..., 3:4]
        alpha = light.max(-1, keepdims=True)
        rgb = np.where(alpha > 0, light / np.maximum(alpha, 1e-6), 0)
        piece = Image.fromarray((np.concatenate([rgb, alpha], -1) * 255).round().astype(np.uint8), "RGBA")
    canvas.alpha_composite(piece, (x0, y0)) if x0 >= 0 and y0 >= 0 else canvas.alpha_composite(piece, (max(x0, 0), max(y0, 0)), (max(-x0, 0), max(-y0, 0)))


def render(scene, items, cam, ambient_scale=2.0, blur_z=None, blur_units=0.13):
    """Back (behind Hornet) and front layers, ungraded. Layers behind the blur plane get the
    background camera's blur (360 px tall buffer, LightBlur passes): about blur_units of sigma."""
    grade = game.Grade(scene.manager)
    ambient = grade.ambient_rgb() * ambient_scale  # Sprites/Lit: texture * colour * ambient * 2
    size = (round(cam.width * cam.ppu), round(cam.height * cam.ppu))
    far = Image.new("RGBA", size, (0, 0, 0, 255))
    back = Image.new("RGBA", size, (0, 0, 0, 0))
    front = Image.new("RGBA", size, (0, 0, 0, 0))
    hero_key = (0, 0, -HERO_Z)
    items = sorted(items, key=lambda i: (i.layer, i.order, -i.z))
    for it in items:
        tint = it.color
        if it.shader == "Sprites/Lit" or "Diffuse" in it.shader:
            tint = (tint[0] * ambient[0], tint[1] * ambient[1], tint[2] * ambient[2], tint[3])
        key = (it.layer, it.order, -it.z)
        if blur_z is not None and it.z > blur_z and it.layer == 0:
            target = far
        elif key < hero_key:
            target = back
        else:
            target = front
        draw(target, it, cam, tint)
    if blur_units:
        far = far.filter(ImageFilter.GaussianBlur(blur_units * cam.ppu))
    far.alpha_composite(back)
    return far, front, grade


TERRAIN_LAYERS = {8, 25}  # Terrain, Soft Terrain


def terrain(scene, layers=TERRAIN_LAYERS):
    """Solid terrain as world-space shapes: [(points (N, 2), closed)]."""
    shapes = []
    for o in scene.objects:
        kind = o.type.name
        if kind not in ("BoxCollider2D", "PolygonCollider2D", "EdgeCollider2D"):
            continue
        t = o.read_typetree()
        go_id = t["m_GameObject"]["m_PathID"]
        go = scene.gameobjects.get(go_id)
        if go is None or go.m_Layer not in layers or not t.get("m_Enabled", 1) or t.get("m_IsTrigger") or not scene.active(go_id):
            continue
        m = scene.world(scene.go_transform[go_id])
        off = np.array([t["m_Offset"]["x"], t["m_Offset"]["y"]])
        paths, closed = [], True
        if kind == "BoxCollider2D":
            sx, sy = t["m_Size"]["x"] / 2, t["m_Size"]["y"] / 2
            paths = [np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]])]
        elif kind == "PolygonCollider2D":
            paths = [np.array([[p["x"], p["y"]] for p in path]) for path in t["m_Points"]["m_Paths"]]
        else:
            paths, closed = [np.array([[p["x"], p["y"]] for p in t["m_Points"]])], False
        for p in paths:
            if len(p) < 2:
                continue
            p = p + off
            w = (m @ np.hstack([p, np.zeros((len(p), 1)), np.ones((len(p), 1))]).T).T[:, :2]
            shapes.append((w, closed))
    return shapes


def is_unwanted(scene, go_id, _cache={}):
    """Enemies, hazards and traps, judged on the object and its ancestors."""
    key = (id(scene), go_id)
    if key in _cache:
        return _cache[key]
    go = scene.gameobjects.get(go_id)
    bad = False
    if go is not None:
        name = go.m_Name.lower()
        if go.m_Layer in (11, 22) or any(w in name for w in ("spike", "thorn", "hazard", "trap", "acid", "saw", "enemy")):
            bad = True
        else:
            for c in go.m_Components:
                r = c.read()
                if r.object_reader.type.name == "MonoBehaviour" and _class_of(r) in ("HealthManager", "DamageHero", "TinkEffect"):
                    bad = True
                    break
        if not bad:
            father = scene.transforms[scene.go_transform[go_id]].m_Father.path_id
            if father in scene.transforms:
                bad = is_unwanted(scene, scene.transforms[father].m_GameObject.path_id)
    _cache[key] = bad
    return bad

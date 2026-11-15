# Purpose: developer-time script. Renders the item icons of the gun side (sea step 2, director: "greatly improve icons
# ... currently looks like clip art"): every armour piece modelled here and rendered once per gun tier (its trim metal,
# accent colour, gems and wear change with the tier: worn iron at Common up to gilded / prismatic / pearl at the top),
# and every gun body rendered side-on from its own model (assets/models/weapons/<id>.gltf). Cycles on the CPU,
# transparent background, a warm key, cool fill and rim light. Output: assets/ui/icons/items/<id>_<tier>.png
# (armour, 192 px), <id>.png (single-look items, 192 px), assets/ui/icons/guns/<id>.png (384 x 160) and
# assets/ui/icons/knives/<type>.png (384 x 160; run tools/knife_icons.tscn in Godot first: it writes the knife models).
# The game draws them through game/item_icons.gd (with the tier plate and the level badge).
# Run: python3 tools/blender/icons.py [ids ...]   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT_ITEMS = os.path.join(ROOT, "assets", "ui", "icons", "items")
OUT_GUNS = os.path.join(ROOT, "assets", "ui", "icons", "guns")
OUT_KNIVES = os.path.join(ROOT, "assets", "ui", "icons", "knives")
KNIFE_MODELS = os.path.join(ROOT, "tools", "tmp", "knives")  # written by tools/knife_icons.tscn (Godot)
TIERS = ["grey", "green", "blue", "purple", "gold", "orange", "rainbow", "pony"]
GEM_FROM = 3  # purple and up wear gems

# trim metal per tier: (colour, metallic, roughness, thin film nm, coat)
TRIM = {"grey": ((0.33, 0.31, 0.29), 0.75, 0.7, 0, 0), "green": ((0.55, 0.56, 0.58), 0.9, 0.42, 0, 0),
    "blue": ((0.78, 0.81, 0.86), 1.0, 0.22, 0, 0), "purple": ((0.34, 0.32, 0.4), 1.0, 0.25, 0, 0.4),
    "gold": ((1.0, 0.74, 0.3), 1.0, 0.2, 0, 0), "orange": ((0.96, 0.46, 0.28), 1.0, 0.24, 0, 0),
    "rainbow": ((0.95, 0.95, 0.97), 1.0, 0.08, 520, 0), "pony": ((0.99, 0.88, 0.95), 0.35, 0.18, 380, 1.0)}
ACCENT = {"grey": (0.32, 0.31, 0.3), "green": (0.2, 0.55, 0.22), "blue": (0.12, 0.3, 0.85), "purple": (0.42, 0.12, 0.78),
    "gold": (0.95, 0.66, 0.08), "orange": (0.98, 0.32, 0.04), "rainbow": (0.9, 0.9, 0.95), "pony": (0.98, 0.5, 0.82)}
GEM = {"purple": (0.55, 0.15, 1.0), "gold": (1.0, 0.75, 0.1), "orange": (1.0, 0.35, 0.05), "rainbow": (0.95, 0.97, 1.0), "pony": (1.0, 0.45, 0.8)}
KINDS = {  # main material kinds: (metallic, roughness, bump strength, bump scale)
    "metal": (0.9, 0.38, 0.15, 40.0), "cloth": (0.0, 0.85, 0.35, 260.0), "leather": (0.0, 0.55, 0.25, 90.0),
    "gloss": (0.0, 0.3, 0.05, 30.0), "glass": (0.0, 0.05, 0.0, 10.0), "pearl": (0.1, 0.2, 0.02, 20.0),
    "rope": (0.0, 0.8, 0.5, 120.0), "felt": (0.0, 0.9, 0.3, 200.0), "rubber": (0.0, 0.6, 0.1, 60.0), "stone": (0.0, 0.25, 0.05, 20.0)}


class Mats:
    """Role materials shared by every model: their values change per tier (set_tier) and per item (set_main)."""

    def __init__(self):
        self.m = {}
        for role in ("main", "trim", "accent", "gem", "glass", "dark", "light", "fixed1", "fixed2", "glow"):
            self.m[role] = self._make(role)

    def _make(self, role):
        mat = bpy.data.materials.new(role)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.name = "noise"
        noise.inputs["Scale"].default_value = 40.0
        noise.inputs["Detail"].default_value = 6.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.name = "bump"
        bump.inputs["Strength"].default_value = 0.15
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        dirt = nt.nodes.new("ShaderNodeMixRGB")  # wear: darker blotches (Common tier gear is grubby)
        dirt.name = "dirt"
        dirt.blend_type = "MULTIPLY"
        dirt.inputs["Fac"].default_value = 0.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.4
        ramp.color_ramp.elements[0].color = (0.45, 0.4, 0.35, 1)
        ramp.color_ramp.elements[1].position = 0.65
        ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
        big = nt.nodes.new("ShaderNodeTexNoise")
        big.inputs["Scale"].default_value = 6.0
        nt.links.new(big.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], dirt.inputs["Color2"])
        nt.links.new(dirt.outputs["Color"], bsdf.inputs["Base Color"])
        coords = nt.nodes.new("ShaderNodeTexCoord")  # the prismatic tier: a rainbow running across the piece
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coords.outputs["Generated"], sep.inputs["Vector"])
        spectrum = nt.nodes.new("ShaderNodeValToRGB")
        cr = spectrum.color_ramp
        cr.elements[0].color = (1.0, 0.05, 0.05, 1)
        cr.elements[1].position = 1.0
        cr.elements[1].color = (0.6, 0.05, 1.0, 1)
        for pos, col in ((0.2, (1.0, 0.5, 0.0)), (0.4, (1.0, 1.0, 0.05)), (0.6, (0.05, 1.0, 0.2)), (0.8, (0.05, 0.4, 1.0))):
            e = cr.elements.new(pos)
            e.color = (*col, 1)
        mix_x = nt.nodes.new("ShaderNodeMath")
        mix_x.operation = "ADD"
        nt.links.new(sep.outputs["X"], mix_x.inputs[0])
        nt.links.new(sep.outputs["Z"], mix_x.inputs[1])
        half = nt.nodes.new("ShaderNodeMath")
        half.operation = "MULTIPLY"
        half.inputs[1].default_value = 0.5
        nt.links.new(mix_x.outputs[0], half.inputs[0])
        nt.links.new(half.outputs[0], spectrum.inputs["Fac"])
        rb = nt.nodes.new("ShaderNodeMixRGB")
        rb.name = "rainbow"
        rb.inputs["Fac"].default_value = 0.0
        nt.links.new(spectrum.outputs["Color"], rb.inputs["Color2"])
        nt.links.new(rb.outputs["Color"], dirt.inputs["Color1"])
        return mat

    def _set(self, role, color, metal, rough, bump=0.1, scale=40.0, film=0, coat=0.0, trans=0.0, emit=0.0, wear=0.0):
        color = tuple(c ** 2.2 for c in color)  # colours are written as seen (sRGB); the renderer works in linear light
        nt = self.m[role].node_tree
        bsdf = nt.nodes["Principled BSDF"]
        nt.nodes["rainbow"].inputs["Color1"].default_value = (*color, 1.0)
        nt.nodes["rainbow"].inputs["Fac"].default_value = 0.0
        nt.nodes["dirt"].inputs["Fac"].default_value = wear
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Thin Film Thickness"].default_value = film
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Transmission Weight"].default_value = trans
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
        nt.nodes["bump"].inputs["Strength"].default_value = bump
        nt.nodes["noise"].inputs["Scale"].default_value = scale

    def set_tier(self, tier):
        i = TIERS.index(tier)
        c, metal, rough, film, coat = TRIM[tier]
        self._set("trim", c, metal, rough, 0.08, 60.0, film, coat, wear=0.6 if tier == "grey" else 0.0)
        acc = ACCENT[tier]
        self._set("accent", acc, 0.0, 0.5, 0.2, 200.0, 0, 0.6 if tier in ("pony", "rainbow") else 0.0)
        if tier == "rainbow":
            self.m["accent"].node_tree.nodes["rainbow"].inputs["Fac"].default_value = 1.0
        g = GEM.get(tier, (0.5, 0.5, 0.5))
        self._set("gem", g, 0.0, 0.03, 0.0, 10.0, 0, 1.0, 0.85, 1.2 if i >= GEM_FROM else 0.0)
        if tier == "rainbow":
            self.m["gem"].node_tree.nodes["rainbow"].inputs["Fac"].default_value = 1.0
        self._set("glass", (0.75, 0.88, 0.95), 0.0, 0.03, 0.0, 10.0, 0, 0.0, 0.9)
        self._set("dark", (0.04, 0.04, 0.045), 0.3, 0.5)
        self._set("light", (0.92, 0.9, 0.85), 0.0, 0.6, 0.1)
        self._set("glow", (1.0, 0.45, 0.12), 0.0, 0.5, 0.0, 10.0, emit=6.0)
        self.tier_wear = 0.55 if tier == "grey" else (0.2 if tier == "green" else 0.0)
        self.tier_index = i

    def set_main(self, color, kind):
        metal, rough, bump, scale = KINDS[kind]
        if kind == "glass":
            self._set("main", color, 0.0, 0.03, 0.0, 10.0, 0, 0.0, 0.85)
            return
        if kind == "pearl":
            self._set("main", color, 0.1, 0.18, 0.02, 20.0, 300, 1.0)
            return
        polish = max(0.0, 0.06 * (self.tier_index - 2)) if kind == "metal" else 0.0  # higher tiers: the metal shines more
        self._set("main", color, metal, max(0.08, rough - polish + (0.2 if self.tier_index == 0 else 0.0)), bump, scale, wear=self.tier_wear)

    def set_fixed(self, role, color, kind):
        metal, rough, bump, scale = KINDS[kind]
        self._set(role, color, metal, rough, bump, scale, wear=self.tier_wear * 0.6)


# ------------------------------------------------------------------ the scene
def setup_scene(width, height):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"  # AgX washed the item colours out
    sc.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.28, 0.3, 0.34, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sc.world = world
    for name, loc, energy, color, size in (("key", (2.5, 3.0, 3.5), 900, (1.0, 0.92, 0.82), 2.5),
            ("fill", (-3.5, 2.0, 1.0), 320, (0.75, 0.85, 1.0), 3.0), ("rim", (-1.0, -3.5, 2.5), 700, (1.0, 1.0, 1.0), 1.5)):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.color = color
        light.data.size = size
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(light)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def frame(cam, objects, direction, pad=1.12):
    """Points the orthographic camera along `direction` at the objects and fits them."""
    rot = (-Vector(direction)).to_track_quat("-Z", "Y")
    cam.rotation_euler = rot.to_euler()
    inv = rot.to_matrix().inverted()
    pts = []
    for obj in objects:
        if obj.type != "MESH" or not obj.visible_get():
            continue
        for corner in obj.bound_box:
            pts.append(obj.matrix_world @ Vector(corner))
    local = [inv @ p for p in pts]
    xs = [p.x for p in local]
    ys = [p.y for p in local]
    zs = [p.z for p in local]
    mid = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, max(zs) + 5.0))
    cam.location = rot.to_matrix() @ mid
    aspect = bpy.context.scene.render.resolution_x / bpy.context.scene.render.resolution_y
    cam.data.ortho_scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * aspect) * pad
    cam.data.clip_end = 100.0


def objects_from(model):
    """kit.Model's parts as objects in the scene (what export() does, without writing a file)."""
    made = []
    for node, (bm, mats) in model.nodes.items():
        bmesh_mod = __import__("bmesh")
        bmesh_mod.ops.triangulate(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(node)
        bm.to_mesh(mesh)
        bm.free()
        for mat in mats:
            mesh.materials.append(mat)
        for poly in mesh.polygons:
            poly.use_smooth = True
        mesh.set_sharp_from_angle(angle=math.radians(40))
        obj = bpy.data.objects.new(node, mesh)
        bpy.context.scene.collection.objects.link(obj)
        made.append(obj)
    return made


def clear_items():
    for obj in list(bpy.data.objects):
        if obj.type in ("MESH", "EMPTY"):
            bpy.data.objects.remove(obj)


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ shapes
def ring(m, mat, r, tube, at=(0, 0, 0), axis="y", segs=28, node="Body"):
    """A torus of radius r and tube radius `tube` round `axis` ("y" = lying flat, "f" = facing forward) through `at`."""
    import bmesh
    bm = bmesh.new()
    sides = 10
    grid = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for k in range(sides):
            b = 2 * math.pi * k / sides
            rr = r + tube * math.cos(b)
            h = tube * math.sin(b)
            if axis == "f":  # in the x-y plane (kit space): Blender (x, f, y) = (rr cos a, h, rr sin a)
                co = (at[0] + rr * math.cos(a), at[2] + h, at[1] + rr * math.sin(a))
            else:  # flat: in the x-f plane, height along y
                co = (at[0] + rr * math.cos(a), at[2] + rr * math.sin(a), at[1] + h)
            row.append(bm.verts.new(co))
        grid.append(row)
    for i in range(segs):
        for k in range(sides):
            bm.faces.new((grid[i][k], grid[(i + 1) % segs][k], grid[(i + 1) % segs][(k + 1) % sides], grid[i][(k + 1) % sides]))
    m._add(bm, mat, node, 0)


def shirt_outline(w=0.5, h=0.62, sleeve=0.2, neck=0.09):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2 - 0.16), (w / 2 + sleeve, h / 2 - 0.22), (w / 2 + sleeve + 0.04, h / 2 - 0.05),
        (w / 2 - 0.02, h / 2 + 0.02), (neck, h / 2 + 0.03), (0, h / 2 - 0.05), (-neck, h / 2 + 0.03), (-w / 2 + 0.02, h / 2 + 0.02),
        (-w / 2 - sleeve - 0.04, h / 2 - 0.05), (-w / 2 - sleeve, h / 2 - 0.22), (-w / 2, h / 2 - 0.16)]


def boot(m, main, sole, tall=0.34, toe=0.22, flare=1.0):
    m.loft(main, [(0, tall, -0.03, 0.068 * flare, 0.075 * flare), (0, tall * 0.55, -0.03, 0.06, 0.068), (0, 0.11, -0.02, 0.064, 0.075)], segs=16)  # shaft
    m.loft(main, [(0, 0.075, -0.06, 0.066, 0.06), (0, 0.065, 0.05, 0.066, 0.05), (0, 0.055, toe - 0.03, 0.06, 0.04), (0, 0.05, toe, 0.045, 0.032)], segs=16)  # foot
    m.box(sole, (0.14, 0.022, toe + 0.15), (0, 0.012, toe * 0.45 - 0.02), bevel=0.008)
    m.box(sole, (0.13, 0.04, 0.08), (0, 0.02, -0.07), bevel=0.008)  # heel


# ------------------------------------------------------------------ the pieces
# Each: (main colour from data/items.json, main kind, builder(m, M)). M = role materials.
def tin_hat(m, M):
    m.lathe(M["main"], [(0.0, 0.16), (0.08, 0.155), (0.13, 0.12), (0.15, 0.06), (0.155, 0.02), (0.24, 0.0), (0.245, -0.012), (0.0, -0.012)], (0, 0, 0), segs=32)
    ring(m, M["trim"], 0.152, 0.012, (0, 0.03, 0), segs=32)
    for k in range(10):
        a = 2 * math.pi * k / 10
        m.ball(M["trim"], 0.008, (0.235 * math.cos(a), 0.0, 0.235 * math.sin(a)))
    m.box(M["main"], (0.06, 0.04, 0.012), (0.05, 0.13, 0.08), tilt=30, bevel=0.004)  # a dent's patch
    m.ball(M["gem"], 0.022, (0, 0.06, 0.15), node="Gem")


def captains_tricorn(m, M):
    m.ball(M["main"], (0.13, 0.17, 0.13), (0, 0.09, 0))  # crown, standing well above the brim
    m.lathe(M["main"], [(0.1, 0.0), (0.18, 0.01), (0.27, 0.09), (0.28, 0.11), (0.265, 0.11), (0.17, 0.035), (0.1, 0.02)], (0, 0, 0), segs=3)  # brim turned up into three corners
    m.lathe(M["trim"], [(0.265, 0.105), (0.285, 0.105), (0.285, 0.12), (0.265, 0.12)], (0, 0, 0), segs=3)  # braid along the edge
    m.loft(M["accent"], [(0.08, 0.2, 0.05, 0.02, 0.01), (0.13, 0.3, -0.02, 0.035, 0.012), (0.11, 0.38, -0.1, 0.02, 0.008)], segs=10)  # plume
    m.lathe(M["trim"], [(0.0, 0.0), (0.035, 0.0), (0.04, 0.01), (0.0, 0.012)], (0.0, 0.16, 0.12), axis="f", segs=16)  # cockade
    m.ball(M["gem"], 0.022, (0.0, 0.16, 0.135), node="Gem")


def iron_helm(m, M):
    m.lathe(M["main"], [(0.0, 0.34), (0.08, 0.335), (0.13, 0.31), (0.15, 0.26), (0.155, 0.0), (0.0, 0.0)], (0, 0, 0), segs=32)
    m.box(M["dark"], (0.2, 0.018, 0.05), (0, 0.2, 0.15), bevel=0.004)  # eye slit
    for i in range(3):
        for k in range(4):
            m.cyl(M["dark"], 0.006, 0.145, 0.16, 0.08 + 0.025 * i, x=-0.045 + 0.03 * k, segs=8)
    for y in (0.02, 0.25):
        ring(m, M["trim"], 0.156, 0.01, (0, y, 0), segs=32)
    m.box(M["trim"], (0.02, 0.3, 0.02), (0, 0.16, 0.157), bevel=0.005)  # nasal ridge
    m.loft(M["accent"], [(0, 0.33, -0.12, 0.015, 0.05), (0, 0.38, 0.0, 0.02, 0.07), (0, 0.36, 0.12, 0.015, 0.05)], segs=10)  # crest
    m.ball(M["gem"], 0.022, (0, 0.28, 0.16), node="Gem")


def diving_helm(m, M):
    m.ball(M["main"], 0.2, (0, 0.2, 0))
    m.lathe(M["main"], [(0.0, -0.02), (0.22, -0.02), (0.24, 0.02), (0.15, 0.06), (0.0, 0.06)], (0, 0, 0), segs=32)  # collar
    m.cyl(M["trim"], 0.105, 0.17, 0.22, 0.2, segs=28)  # front port
    m.cyl(M["glass"], 0.085, 0.2, 0.225, 0.2, segs=28)
    for k in range(8):
        a = 2 * math.pi * k / 8
        m.ball(M["trim"], 0.012, (0.095 * math.cos(a), 0.2 + 0.095 * math.sin(a), 0.222))
    for side in (-1, 1):
        m.cylx(M["trim"], 0.055, side * 0.17, side * 0.21, 0.0, 0.2, segs=20)
        m.cylx(M["glass"], 0.04, side * 0.2, side * 0.215, 0.0, 0.2, segs=20)
    m.box(M["accent"], (0.3, 0.02, 0.02), (0, 0.04, 0.2), bevel=0.006)
    m.ball(M["gem"], 0.03, (0, 0.4, 0.05), node="Gem")


def gold_hoops(m, M):
    for side in (-1, 1):
        ring(m, M["main"], 0.09, 0.014, (side * 0.13, 0.12, 0), axis="f", segs=28)
        m.ball(M["trim"], 0.02, (side * 0.13, 0.215, 0))
        m.ball(M["gem"], 0.022, (side * 0.13, 0.03, 0.0), node="Gem")


def pearl_studs(m, M):
    for side in (-1, 1):
        m.ball(M["main"], 0.07, (side * 0.11, 0.1, 0.0), u=24, v=16)
        m.lathe(M["trim"], [(0.0, -0.02), (0.035, -0.02), (0.04, 0.0), (0.0, 0.005)], (side * 0.11, 0.1, -0.075), axis="f")
        for k in range(4):
            a = 2 * math.pi * k / 4 + 0.4
            m.ball(M["gem"], 0.014, (side * 0.11 + 0.075 * math.cos(a), 0.1 + 0.075 * math.sin(a), -0.03), node="Gem")


def chain(m, M, pts, r=0.008):
    for (x0, y0, z0), (x1, y1, z1) in zip(pts, pts[1:]):
        for t in (0.0, 0.5):
            m.ball(M["trim"], r * 1.4, (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t), u=8, v=6)


def arc_points(n=14, w=0.22, top=0.4, low=0.12):
    return [(w * math.sin(math.pi * (i / (n - 1) - 0.5)), low + (top - low) * math.cos(math.pi * (i / (n - 1) - 0.5)), 0.0) for i in range(n)]


def frost_amulet(m, M):
    chain(m, M, arc_points())
    m.lathe(M["main"], [(0.0, -0.17), (0.05, -0.12), (0.055, 0.0), (0.04, 0.03), (0.0, 0.035)], (0, 0.08, 0), segs=6)  # hex crystal
    m.lathe(M["trim"], [(0.0, 0.0), (0.045, 0.0), (0.05, 0.025), (0.0, 0.035)], (0, 0.1, 0), segs=16)
    m.ball(M["gem"], 0.018, (0, 0.14, 0.03), node="Gem")


def compass_pendant(m, M):
    chain(m, M, arc_points())
    m.lathe(M["main"], [(0.0, -0.02), (0.08, -0.02), (0.088, 0.0), (0.085, 0.02), (0.0, 0.022)], (0, 0.02, 0), axis="f", segs=32)
    m.cyl(M["light"], 0.07, 0.02, 0.025, 0.02, segs=28)
    m.box(M["accent"], (0.012, 0.11, 0.004), (0, 0.02, 0.028), tilt=0, bevel=0.002)  # needle
    m.box(M["dark"], (0.012, 0.05, 0.004), (0, -0.005, 0.029), bevel=0.002)
    m.cyl(M["glass"], 0.072, 0.03, 0.034, 0.02, segs=28)
    ring(m, M["trim"], 0.016, 0.005, (0, 0.115, 0), axis="f")
    m.ball(M["gem"], 0.016, (0, 0.105, 0.025), node="Gem")


def cool_shades(m, M):
    for side in (-1, 1):
        m.prof(M["glass"] if False else M["dark"], 0.01, [(side * 0.03, 0.0), (side * 0.15, 0.01), (side * 0.155, 0.06), (side * 0.12, 0.08), (side * 0.03, 0.07)], across="f", bevel=0.004)
        m.strip(M["main"], 0.012, 0.01, [(0.0, 0.07), (-0.25, 0.06)], x=side * 0.155)  # temples
    m.box(M["main"], (0.07, 0.014, 0.014), (0, 0.065, 0.0), bevel=0.004)
    for side in (-1, 1):
        m.ball(M["gem"], 0.011, (side * 0.15, 0.072, 0.012), node="Gem")
        m.box(M["trim"], (0.016, 0.03, 0.02), (side * 0.155, 0.065, -0.005), bevel=0.004)


def storm_goggles(m, M):
    for side in (-1, 1):
        m.cyl(M["trim"], 0.07, -0.02, 0.04, 0.0, x=side * 0.09, segs=24)
        m.cyl(M["accent"], 0.058, 0.04, 0.046, 0.0, x=side * 0.09, segs=24)
        m.cyl(M["glass"], 0.058, 0.046, 0.05, 0.0, x=side * 0.09, segs=24)
    m.box(M["trim"], (0.05, 0.02, 0.02), (0, 0.0, 0.01), bevel=0.006)
    m.loft(M["main"], [(-0.16, 0.0, 0.0, 0.006, 0.03), (-0.24, 0.0, -0.14, 0.006, 0.03), (0.0, 0.0, -0.24, 0.006, 0.03), (0.24, 0.0, -0.14, 0.006, 0.03), (0.16, 0.0, 0.0, 0.006, 0.03)], segs=8, flat=True)
    m.ball(M["gem"], 0.014, (0, 0.03, 0.03), node="Gem")


def cigarette(m, M):
    m.cyl(M["light"], 0.018, -0.16, 0.12, 0.0, segs=16)
    m.cyl(M["main"], 0.0185, -0.2, -0.16, 0.0, segs=16)
    m.cyl(M["dark"], 0.017, 0.12, 0.135, 0.0, segs=16)
    m.ball(M["glow"], 0.016, (0, 0.0, 0.137))


def cigarette_butt(m, M):
    m.cyl(M["main"], 0.0185, -0.06, -0.02, 0.0, segs=16)
    m.cyl(M["light"], 0.018, -0.02, 0.03, 0.0, segs=16)
    m.cyl(M["dark"], 0.019, 0.03, 0.045, 0.0, segs=16)


def bosuns_whistle(m, M):
    m.cyl(M["main"], 0.014, -0.18, 0.06, 0.0, segs=16, r2=0.012)
    m.ball(M["main"], 0.05, (0, -0.01, 0.1))
    m.box(M["dark"], (0.03, 0.01, 0.02), (0, 0.04, 0.09), bevel=0.003)
    m.strip(M["trim"], 0.01, 0.008, [(-0.05, 0.0), (-0.1, -0.06), (0.05, -0.06), (0.05, 0.0)])  # keel
    ring(m, M["trim"], 0.025, 0.006, (0, -0.07, 0.0), axis="f")
    m.ball(M["gem"], 0.014, (0, 0.035, 0.1), node="Gem")


def band_shirt(m, M):
    m.prof(M["main"], 0.05, shirt_outline(), across="f", bevel=0.012)
    m.box(M["accent"], (0.2, 0.16, 0.008), (0, 0.04, 0.028), bevel=0.003)  # the band print
    m.box(M["trim"], (0.14, 0.02, 0.006), (0, 0.13, 0.034), bevel=0.002)
    m.ball(M["gem"], 0.02, (0, 0.04, 0.035), node="Gem")


def sailor_stripes(m, M):
    m.prof(M["main"], 0.05, shirt_outline(), across="f", bevel=0.012)
    for i in range(6):
        m.box(M["dark"], (0.52, 0.025, 0.006), (0, -0.26 + 0.075 * i, 0.027), bevel=0.0)
    m.prof(M["accent"], 0.012, [(-0.12, 0.31), (0.12, 0.31), (0.02, 0.18), (0.0, 0.12), (-0.02, 0.18)], across="f", x=0.03, bevel=0.004)  # neckerchief
    m.ball(M["trim"], 0.018, (0, 0.18, 0.04))
    m.ball(M["gem"], 0.016, (0, 0.2, 0.045), node="Gem")


def chest_plate(m, M, ridge=True):
    m.loft(M["main"], [(0, -0.22, 0.0, 0.2, 0.09), (0, -0.05, 0.03, 0.22, 0.12), (0, 0.12, 0.03, 0.21, 0.12), (0, 0.24, 0.0, 0.17, 0.08)], segs=20, steps=4)
    if ridge:
        m.box(M["trim"], (0.02, 0.42, 0.02), (0, 0.0, 0.15), bevel=0.006)
    for y in (-0.2, 0.2):
        for side in (-1, 1):
            m.ball(M["trim"], 0.014, (side * 0.15, y, 0.1))


def steel_chestplate(m, M):
    chest_plate(m, M)
    m.loft(M["accent"], [(0, -0.4, 0.06, 0.08, 0.01), (0, -0.25, 0.1, 0.09, 0.012)], segs=10, flat=True)  # tabard tail
    m.ball(M["gem"], 0.028, (0, 0.08, 0.16), node="Gem")
    for side in (-1, 1):
        m.loft(M["trim"], [(side * 0.17, 0.24, 0.0, 0.06, 0.04), (side * 0.26, 0.2, 0.0, 0.07, 0.05)], segs=12)  # pauldron caps


def coral_cuirass(m, M):
    chest_plate(m, M, ridge=False)
    branches = [((-0.1, 0.05), (-0.18, 0.2)), ((-0.12, -0.08), (-0.22, -0.02)), ((0.08, 0.1), (0.16, 0.24)), ((0.1, -0.1), (0.2, -0.15)), ((0.0, -0.15), (0.03, -0.28))]
    for (x0, y0), (x1, y1) in branches:
        m.rod(M["main"], 0.018, (x0, y0, 0.13), (x1, y1, 0.16), r2=0.008, segs=8)
        m.ball(M["main"], 0.016, (x1, y1, 0.16), u=8, v=6)
    for x, y in ((0.05, 0.15), (-0.06, -0.15), (0.12, 0.0)):
        m.lathe(M["trim"], [(0.0, 0.0), (0.03, 0.0), (0.0, 0.03)], (x, y, 0.15), axis="f", segs=10)  # shells
    m.ball(M["gem"], 0.026, (0, 0.05, 0.16), node="Gem")


def gauntlet(m, M, main, plates=True):
    m.lathe(main, [(0.07, -0.18), (0.085, -0.1), (0.06, 0.0), (0.0, 0.0)], (0, 0, 0), segs=20)  # cuff
    m.box(main, (0.13, 0.12, 0.05), (0, 0.06, 0.0), bevel=0.02)  # back of the hand
    for i in range(4):
        x = -0.045 + 0.03 * i
        m.rod(main, 0.012, (x, 0.12, 0.0), (x, 0.2, 0.01), segs=8)
        m.rod(main, 0.011, (x, 0.2, 0.01), (x, 0.25, 0.03), segs=8)
    m.rod(main, 0.013, (0.065, 0.05, 0.0), (0.11, 0.12, 0.03), segs=8)  # thumb
    if plates:
        for i in range(3):
            m.box(M["trim"], (0.14, 0.012, 0.06), (0, 0.02 + 0.03 * i, 0.012), bevel=0.004)


def iron_gauntlets(m, M):
    gauntlet(m, M, M["main"])
    ring(m, M["accent"], 0.085, 0.012, (0, -0.12, 0), segs=24)
    m.ball(M["gem"], 0.02, (0, 0.06, 0.04), node="Gem")


def sharkskin_gloves(m, M):
    gauntlet(m, M, M["main"], plates=False)
    ring(m, M["accent"], 0.08, 0.014, (0, -0.15, 0), segs=24)
    m.ball(M["trim"], 0.014, (0, -0.05, 0.075))
    m.ball(M["gem"], 0.02, (0, 0.06, 0.035), node="Gem")


def ring_piece(m, M, stone=None):
    ring(m, M["trim"], 0.09, 0.018, (0, 0, 0), axis="f", segs=32)
    m.lathe(M["trim"], [(0.0, 0.0), (0.04, 0.0), (0.035, 0.02), (0.0, 0.02)], (0, 0.1, 0), segs=16)  # setting
    for k in range(2):
        a = math.pi / 2 + (k - 0.5) * 0.7
        m.ball(M["gem"], 0.014, (0.105 * math.cos(a), 0.105 * math.sin(a) - 0.005, 0.012), node="Gem")


def ember_ring(m, M):
    ring_piece(m, M)
    m.lathe(M["main"], [(0.0, 0.0), (0.035, 0.0), (0.03, 0.03), (0.0, 0.045)], (0, 0.115, 0), segs=8)  # faceted stone


def venom_ring(m, M):
    ring_piece(m, M)
    m.ball(M["main"], (0.035, 0.025, 0.03), (0, 0.13, 0))
    m.loft(M["accent"], [(-0.09, 0.0, 0.02, 0.01, 0.01), (-0.06, 0.07, 0.025, 0.012, 0.012), (-0.02, 0.12, 0.03, 0.01, 0.01)], segs=8)  # the snake


def anchor_signet(m, M):
    ring_piece(m, M)
    m.cyl(M["main"], 0.045, -0.015, 0.015, 0.12, segs=24)
    m.box(M["accent"], (0.008, 0.05, 0.006), (0, 0.12, 0.018), bevel=0.001)  # the anchor
    m.box(M["accent"], (0.03, 0.006, 0.006), (0, 0.135, 0.018), bevel=0.001)
    m.strip(M["accent"], 0.006, 0.006, [(-0.02, 0.105), (0.0, 0.098), (0.02, 0.105)])


def kraken_band(m, M):
    ring_piece(m, M)
    m.ball(M["main"], 0.035, (0, 0.14, 0))
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        m.rod(M["accent"], 0.007, (0.0, 0.1, 0.0), (0.035 * math.cos(a), 0.14 + 0.035 * math.sin(a), 0.03), segs=6)


def charm_bracelet(m, M):
    pts = [(0.13 * math.cos(2 * math.pi * k / 20), 0.13 * math.sin(2 * math.pi * k / 20), 0.0) for k in range(21)]
    chain(m, M, pts, 0.01)
    m.prof(M["main"], 0.012, [(0.0, -0.05), (0.035, 0.0), (0.02, 0.025), (0.0, 0.01), (-0.02, 0.025), (-0.035, 0.0)], across="f", x=0.0, bevel=0.004)
    m.ball(M["accent"], 0.02, (0.1, -0.08, 0.0))
    m.lathe(M["trim"], [(0.0, 0.0), (0.02, 0.0), (0.0, 0.03)], (-0.1, -0.09, 0.0), segs=5)
    m.ball(M["gem"], 0.018, (0.0, -0.13, 0.02), node="Gem")


def rope_bracelet(m, M):
    for k in range(3):
        off = 2 * math.pi * k / 3
        pts = []
        for i in range(73):
            a = 2 * math.pi * i / 72
            twist = a * 6 + off
            r = 0.12 + 0.012 * math.cos(twist)
            pts.append((r * math.cos(a), r * math.sin(a), 0.012 * math.sin(twist)))
        for p0, p1 in zip(pts, pts[1:]):
            m.rod(M["main"], 0.011, p0, p1, segs=6)
    m.ball(M["trim"], 0.03, (0, -0.125, 0.0))
    m.ball(M["gem"], 0.016, (0, -0.125, 0.03), node="Gem")


def pants(m, M, main, cuffs=True):
    m.prof(main, 0.06, [(-0.2, 0.3), (0.2, 0.3), (0.21, -0.35), (0.04, -0.35), (0.0, 0.05), (-0.04, -0.35), (-0.21, -0.35)], across="f", bevel=0.015)
    m.box(M["trim"], (0.42, 0.05, 0.07), (0, 0.28, 0.0), bevel=0.01)  # waistband
    m.cyl(M["trim"], 0.018, 0.03, 0.045, 0.28, segs=12)  # button


def cargo_pants(m, M):
    pants(m, M, M["main"])
    for side in (-1, 1):
        m.box(M["main"], (0.11, 0.12, 0.03), (side * 0.13, -0.08, 0.035), bevel=0.01)
        m.box(M["accent"], (0.11, 0.025, 0.035), (side * 0.13, -0.015, 0.038), bevel=0.006)
    m.ball(M["gem"], 0.018, (0, 0.28, 0.05), node="Gem")


def oilskin_trousers(m, M):
    pants(m, M, M["main"])
    for side in (-1, 1):
        m.box(M["accent"], (0.035, 0.2, 0.012), (side * 0.12, 0.4, 0.035), bevel=0.004)  # braces going up from the waistband
        m.ball(M["trim"], 0.016, (side * 0.12, 0.31, 0.045))
    m.ball(M["gem"], 0.018, (0, 0.2, 0.04), node="Gem")


def greave(m, M, main):
    m.loft(main, [(0, -0.22, 0.02, 0.075, 0.05), (0, -0.05, 0.035, 0.085, 0.06), (0, 0.12, 0.03, 0.08, 0.055)], segs=16)
    m.ball(M["trim"], (0.075, 0.07, 0.06), (0, 0.17, 0.03))  # knee cop
    for y in (-0.15, 0.05):
        ring(m, M["dark"], 0.075, 0.012, (0, y, 0.02), segs=20)  # straps round the leg
        m.box(M["trim"], (0.03, 0.03, 0.02), (0.075, y, 0.06), bevel=0.005)


def iron_greaves(m, M):
    greave(m, M, M["main"])
    m.box(M["accent"], (0.02, 0.3, 0.012), (0, -0.05, 0.095), bevel=0.004)
    m.ball(M["gem"], 0.02, (0, 0.17, 0.1), node="Gem")


def barnacle_greaves(m, M):
    greave(m, M, M["main"])
    for x, y in ((-0.03, -0.12), (0.04, -0.02), (-0.04, 0.06), (0.03, -0.17), (0.0, 0.02)):
        m.lathe(M["light"], [(0.0, 0.0), (0.022, 0.0), (0.012, 0.025), (0.0, 0.02)], (x, y, 0.085), axis="f", segs=8)
    m.ball(M["gem"], 0.02, (0, 0.17, 0.1), node="Gem")


def cape(m, M, tattered=True, hood=False):
    bottom = [(0.26, -0.36), (0.16, -0.3), (0.1, -0.4), (0.0, -0.32), (-0.08, -0.42), (-0.16, -0.31), (-0.26, -0.37)] if tattered else [(0.27, -0.38), (0.0, -0.42), (-0.27, -0.38)]
    m.prof(M["main"], 0.03, [(-0.14, 0.32), (0.14, 0.32)] + bottom, across="f", bevel=0.01)
    for i, x in enumerate((-0.18, -0.06, 0.06, 0.18)):
        m.box(M["main"], (0.03, 0.62, 0.02), (x, -0.04, 0.02), bevel=0.008)  # folds
    m.box(M["accent"], (0.3, 0.04, 0.02), (0, 0.3, 0.025), bevel=0.006)  # collar lining
    for side in (-1, 1):
        m.cyl(M["trim"], 0.03, 0.02, 0.04, 0.3, x=side * 0.1, segs=16)
    m.strip(M["trim"], 0.008, 0.006, [(0.0, 0.3), (0.0, 0.3)], x=0.0)
    if hood:
        m.ball(M["main"], (0.16, 0.12, 0.08), (0, 0.36, -0.03))
    m.ball(M["gem"], 0.022, (0.1, 0.3, 0.05), node="Gem")


def tattered_cape(m, M):
    cape(m, M)


def storm_cloak(m, M):
    cape(m, M, tattered=False, hood=True)


def belt(m, M, main):
    m.loft(main, [(-0.3, 0.0, -0.02, 0.004, 0.035), (-0.15, 0.0, 0.03, 0.004, 0.035), (0.15, 0.0, 0.03, 0.004, 0.035), (0.3, 0.0, -0.02, 0.004, 0.035)], segs=8, flat=True)


def leather_belt(m, M):
    belt(m, M, M["main"])
    m.prof(M["trim"], 0.012, [(-0.05, -0.05), (0.05, -0.05), (0.05, 0.05), (-0.05, 0.05)], across="f", x=0.045, bevel=0.008)
    m.box(M["main"], (0.07, 0.05, 0.012), (0, 0.0, 0.05), bevel=0.004)
    m.box(M["trim"], (0.01, 0.06, 0.01), (0.0, 0.0, 0.058), bevel=0.002)
    for x in (0.12, 0.18, 0.24):
        m.cyl(M["dark"], 0.006, 0.02, 0.035, 0.0, x=x, segs=8)
    m.ball(M["gem"], 0.016, (-0.12, 0.0, 0.04), node="Gem")


def cutlass_sash(m, M):
    belt(m, M, M["main"])
    m.ball(M["main"], (0.05, 0.045, 0.03), (0.0, 0.0, 0.04))  # the knot
    for side in (-1, 1):
        m.loft(M["main"], [(side * 0.02, -0.02, 0.05, 0.025, 0.006), (side * 0.06, -0.15, 0.06, 0.03, 0.006), (side * 0.05, -0.26, 0.05, 0.028, 0.006)], segs=8, flat=True)
    ring(m, M["trim"], 0.035, 0.008, (0.13, 0.0, 0.035), axis="f")
    m.ball(M["gem"], 0.016, (0.0, 0.0, 0.075), node="Gem")


def work_boots(m, M):
    boot(m, M["main"], M["dark"])
    for i in range(4):
        m.box(M["accent"], (0.1, 0.008, 0.008), (0, 0.12 + 0.045 * i, 0.06), bevel=0.002)  # laces
    m.ball(M["trim"], 0.012, (0.06, 0.29, 0.03))
    m.ball(M["gem"], 0.016, (0.0, 0.31, 0.065), node="Gem")


def sea_boots(m, M):
    boot(m, M["main"], M["dark"], tall=0.42)
    m.lathe(M["main"], [(0.0, 0.0), (0.095, 0.0), (0.1, 0.06), (0.0, 0.06)], (0, 0.38, -0.02), segs=20)  # folded top
    ring(m, M["accent"], 0.09, 0.01, (0, 0.3, -0.02), segs=20)
    m.ball(M["gem"], 0.016, (0.0, 0.41, 0.08), node="Gem")


def phoons_treasure(m, M):
    boot(m, M["main"], M["trim"], tall=0.26)
    for side in (-1, 1):
        for i in range(3):
            m.loft(M["light"], [(side * 0.07, 0.2, -0.02, 0.01, 0.02), (side * (0.16 + 0.03 * i), 0.24 + 0.04 * i, -0.08 - 0.03 * i, 0.012, 0.035), (side * (0.2 + 0.03 * i), 0.22 + 0.05 * i, -0.15 - 0.04 * i, 0.008, 0.02)], segs=8, flat=True)
    m.ball(M["gem"], 0.02, (0.0, 0.22, 0.075), node="Gem")


def sabatons(m, M, main):
    for i in range(5):
        m.loft(main, [(0, 0.08 - 0.01 * i, 0.02 + 0.05 * i, 0.07, 0.03), (0, 0.075 - 0.012 * i, 0.06 + 0.05 * i, 0.065, 0.028)], segs=14)
    m.loft(main, [(0, 0.04, 0.26, 0.05, 0.02), (0, 0.025, 0.33, 0.012, 0.01)], segs=12)  # pointed toe
    m.lathe(main, [(0.075, 0.0), (0.08, 0.12), (0.0, 0.12)], (0, 0.06, -0.02), segs=20)  # ankle
    for i in range(5):
        m.ball(M["trim"], 0.008, (0.07, 0.085 - 0.01 * i, 0.03 + 0.05 * i))


def iron_sabatons(m, M):
    sabatons(m, M, M["main"])
    m.box(M["accent"], (0.15, 0.02, 0.03), (0, 0.18, -0.02), bevel=0.005)
    m.ball(M["gem"], 0.016, (0.0, 0.1, 0.07), node="Gem")


def brass_sabatons(m, M):
    sabatons(m, M, M["main"])
    for i in range(3):
        ring(m, M["trim"], 0.08, 0.006, (0, 0.08 + 0.03 * i, -0.02), segs=20)
    m.ball(M["gem"], 0.016, (0.0, 0.1, 0.07), node="Gem")


PIECES = {  # item id: (main kind, builder); the main colour comes from data/items.json
    "tin_hat": ("metal", tin_hat), "captains_tricorn": ("felt", captains_tricorn), "iron_helm": ("metal", iron_helm),
    "diving_helm": ("metal", diving_helm), "gold_hoops": ("metal", gold_hoops), "pearl_studs": ("pearl", pearl_studs),
    "frost_amulet": ("glass", frost_amulet), "compass_pendant": ("metal", compass_pendant), "cool_shades": ("gloss", cool_shades),
    "storm_goggles": ("leather", storm_goggles), "bosuns_whistle": ("metal", bosuns_whistle), "band_shirt": ("cloth", band_shirt),
    "sailor_stripes": ("cloth", sailor_stripes), "steel_chestplate": ("metal", steel_chestplate), "coral_cuirass": ("stone", coral_cuirass),
    "iron_gauntlets": ("metal", iron_gauntlets), "sharkskin_gloves": ("leather", sharkskin_gloves), "ember_ring": ("stone", ember_ring),
    "venom_ring": ("stone", venom_ring), "anchor_signet": ("metal", anchor_signet), "kraken_band": ("stone", kraken_band),
    "charm_bracelet": ("gloss", charm_bracelet), "rope_bracelet": ("rope", rope_bracelet), "cargo_pants": ("cloth", cargo_pants),
    "oilskin_trousers": ("gloss", oilskin_trousers), "iron_greaves": ("metal", iron_greaves), "barnacle_greaves": ("stone", barnacle_greaves),
    "tattered_cape": ("cloth", tattered_cape), "storm_cloak": ("cloth", storm_cloak), "leather_belt": ("leather", leather_belt),
    "cutlass_sash": ("cloth", cutlass_sash), "work_boots": ("leather", work_boots), "sea_boots": ("rubber", sea_boots),
    "iron_sabatons": ("metal", iron_sabatons), "brass_sabatons": ("metal", brass_sabatons),
}
SINGLE = {"cigarette": ("cloth", cigarette, (0.85, 0.55, 0.2)), "cigarette_butt": ("cloth", cigarette_butt, (0.85, 0.55, 0.2)),
    "phoons_treasure": ("metal", phoons_treasure, (0.95, 0.75, 0.25))}  # one look only (they never roll)
GUNS = ["pistol_basic", "sniper_basic", "ak47", "m16", "m60", "shotgun_double", "rocket_launcher", "grenade_launcher",
    "smg", "revolver", "lever_rifle", "harpoon_gun", "flare_gun", "flamethrower", "crossbow", "blunderbuss"]
VIEW = (1.0, 1.7, 0.95)  # the armour camera looks from front-right-above (fronts face +f)


METALS = ("steel", "dark_steel", "blue_steel", "brass")


def dress_knife(obj):
    """The knife's plain materials made rich: rounded edges everywhere (Cycles bevel), brushed and scratched metal,
    grain in wood, pores in leather."""
    names = [slot.material.name.split(".")[0] if slot.material else "" for slot in obj.material_slots]
    for poly in obj.data.polygons:  # handles round and soft, blades crisp
        poly.use_smooth = names[poly.material_index] not in METALS if poly.material_index < len(names) else False
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or mat.get("dressed"):
            continue
        mat["dressed"] = True
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        name = mat.name.split(".")[0]
        bevel = nt.nodes.new("ShaderNodeBevel")
        bevel.inputs["Radius"].default_value = 0.0025
        bump = nt.nodes.new("ShaderNodeBump")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        nt.links.new(bevel.outputs["Normal"], bump.inputs["Normal"])
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        if name in METALS:
            mapping = nt.nodes.new("ShaderNodeMapping")
            coords = nt.nodes.new("ShaderNodeTexCoord")
            mapping.inputs["Scale"].default_value = (1.0, 1.0, 400.0)  # long streaks: brushed along the blade
            nt.links.new(coords.outputs["Object"], mapping.inputs["Vector"])
            nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
            noise.inputs["Scale"].default_value = 30.0
            bump.inputs["Strength"].default_value = 0.08
            bsdf.inputs["Metallic"].default_value = 1.0
            bsdf.inputs["Roughness"].default_value = 0.22 if name == "steel" else 0.3
            bsdf.inputs["Anisotropic"].default_value = 0.6
        else:
            noise.inputs["Scale"].default_value = 220.0 if name in ("leather", "tan", "olive") else 60.0
            noise.inputs["Detail"].default_value = 8.0
            bump.inputs["Strength"].default_value = 0.25


def main():
    import json
    only = sys.argv[1:]
    items = json.load(open(os.path.join(ROOT, "data", "items.json")))["items"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_ITEMS, exist_ok=True)
    os.makedirs(OUT_GUNS, exist_ok=True)
    cam = setup_scene(192, 192)
    mats = Mats()
    M = mats.m
    for item_id, (kind, build) in list(PIECES.items()) + [(k, (v[0], v[1])) for k, v in SINGLE.items()]:
        if only and item_id not in only:
            continue
        clear_items()
        model = kit.Model(item_id)
        build(model, M)
        objects = objects_from(model)
        gem_objects = [o for o in objects if o.name.startswith("Gem")]
        color = tuple(items.get(item_id, {}).get("color") or SINGLE.get(item_id, (0, 0, (0.8, 0.8, 0.8)))[2])
        tiers = TIERS if item_id in PIECES else ["gold" if item_id == "phoons_treasure" else "green"]
        for tier in tiers:
            mats.set_tier(tier)
            mats.set_main(color, kind)
            for g in gem_objects:
                g.hide_render = TIERS.index(tier) < GEM_FROM
                g.hide_set(TIERS.index(tier) < GEM_FROM)
            frame(cam, objects, VIEW)
            name = item_id + ("_" + tier if item_id in PIECES else "")
            render(os.path.join(OUT_ITEMS, name + ".png"))
            print("icon", name)
    bpy.context.scene.render.resolution_x = 384
    bpy.context.scene.render.resolution_y = 160
    for gun_id in GUNS:
        if only and gun_id not in only:
            continue
        clear_items()
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "models", "weapons", gun_id + ".gltf"))
        objects = [o for o in bpy.data.objects if o.type == "MESH"]
        for o in objects:
            if o.name.startswith("StringLoose"):
                o.hide_render = True
                o.hide_set(True)
        frame(cam, objects, (1.0, -0.12, 0.22), 1.06)
        render(os.path.join(OUT_GUNS, gun_id + ".png"))
        print("icon gun", gun_id)
    os.makedirs(OUT_KNIVES, exist_ok=True)
    for name in sorted(os.listdir(KNIFE_MODELS)) if os.path.isdir(KNIFE_MODELS) else []:
        knife_id = name[:-4]
        if not name.endswith(".glb") or (only and knife_id not in only):
            continue
        clear_items()
        bpy.ops.import_scene.gltf(filepath=os.path.join(KNIFE_MODELS, name))
        objects = [o for o in bpy.data.objects if o.type == "MESH"]
        for o in objects:
            dress_knife(o)
        frame(cam, objects, (1.0, 0.1, 0.25), 1.08)
        render(os.path.join(OUT_KNIVES, knife_id + ".png"))
        print("icon knife", knife_id)


if __name__ == "__main__":
    main()

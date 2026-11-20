# Purpose: developer-time script (polish1 item 72): the casino's gun crates as real models instead of glowing cubes,
# one look per crate so each reads at a glance: BRONZE = a wooden ammo crate with bronze corners and rope handles,
# SILVER = a ribbed steel weapon case with latches and a carry handle, GOLD = an ornate treasure chest with a domed lid,
# gilded bands and gems. Our own designs. Into assets/models/fantasy/crate_<id>.gltf; nodes: "Body" (its colours),
# "Lid" (the part that opens, pivot at its back hinge), "Glow" (the game paints it in the crate's colour, unshaded).
# Then pictures for the CASES tab and the opening screen: assets/ui/cases/<id>.png (the whole crate) and
# <id>_body.png + <id>_lid.png (the same view, without and only the lid, so the screen can lift the lid off).
# Run: python3 tools/blender/crates.py [ids ...]   (pictures: Cycles on the CPU, a few seconds each)
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. Used by game/gun_vendor.gd and game/case_tab.gd.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector

import kit
import fantasy_kit as fk
from fantasy_kit import K

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "models", "fantasy")
PICS = os.path.join(HERE, "..", "..", "assets", "ui", "cases")
WHITE = (0.92, 0.91, 0.88)
DARK = (0.12, 0.11, 0.12)


def bronze(m):  # a wooden ammo crate, bronze corners, rope handles, a stencilled plate
    wood = K("wood", (0.5, 0.3, 0.12))
    dark = K("wood", (0.28, 0.16, 0.07))
    metal = K("metal", (0.85, 0.42, 0.14))
    w, h, d = 0.86, 0.46, 0.56
    m.box(wood, (w, h, d), (0.0, h * 0.5, 0.0))
    for y in (0.1, 0.24, 0.38):  # plank seams
        m.box(dark, (w + 0.005, 0.012, d + 0.005), (0.0, y, 0.0))
    for x in (-w * 0.5 + 0.03, w * 0.5 - 0.03):
        for f in (-d * 0.5 + 0.03, d * 0.5 - 0.03):
            m.box(metal, (0.08, h + 0.01, 0.08), (x, h * 0.5, f))  # bronze corners
    for x in (-w * 0.5, w * 0.5):
        m.rod(K("cloth", (0.75, 0.66, 0.45)), 0.018, (x * 1.04, 0.32, -0.1), (x * 1.09, 0.25, 0.0))
        m.rod(K("cloth", (0.75, 0.66, 0.45)), 0.018, (x * 1.09, 0.25, 0.0), (x * 1.04, 0.32, 0.1))
    m.box(K("paint", WHITE), (0.34, 0.14, 0.012), (0.0, 0.23, -d * 0.5 - 0.006), node="Glow")
    lid_y = h + 0.05
    m.box(wood, (w + 0.04, 0.09, d + 0.04), (0.0, lid_y, 0.0), node="Lid")
    m.box(dark, (w + 0.05, 0.012, 0.06), (0.0, lid_y + 0.045, 0.0), node="Lid")
    for x in (-w * 0.5 + 0.02, w * 0.5 - 0.02):
        m.box(metal, (0.1, 0.1, d + 0.06), (x, lid_y, 0.0), node="Lid")


def silver(m):  # a ribbed steel weapon case, two latches, a carry handle, a glowing seam
    steel = K("metal", (0.58, 0.62, 0.68))
    dark = K("metal", (0.22, 0.23, 0.26))
    w, d = 1.06, 0.5
    base_h, lid_h = 0.24, 0.2
    m.box(steel, (w, base_h, d), (0.0, base_h * 0.5, 0.0))
    for x in (-0.36, 0.0, 0.36):  # ribs
        m.box(dark, (0.05, base_h + 0.01, d + 0.02), (x, base_h * 0.5, 0.0))
    m.box(K("paint", WHITE), (w - 0.06, 0.02, 0.01), (0.0, base_h - 0.02, -d * 0.5 - 0.012), node="Glow")
    for x in (-0.3, 0.3):  # latches
        m.box(dark, (0.1, 0.12, 0.03), (x, base_h - 0.01, -d * 0.5 - 0.02))
    y0 = base_h + lid_h * 0.5
    m.box(steel, (w + 0.01, lid_h, d + 0.01), (0.0, y0, 0.0), node="Lid")
    for x in (-0.36, 0.0, 0.36):
        m.box(dark, (0.05, lid_h + 0.01, d + 0.03), (x, y0, 0.0), node="Lid")
    m.box(dark, (w - 0.2, 0.02, d - 0.14), (0.0, base_h + lid_h + 0.01, 0.0), node="Lid")
    top = base_h + lid_h + 0.02
    m.rod(dark, 0.022, (-0.16, top, 0.0), (-0.12, top + 0.08, 0.0), node="Lid")
    m.rod(dark, 0.022, (-0.12, top + 0.08, 0.0), (0.12, top + 0.08, 0.0), node="Lid")
    m.rod(dark, 0.022, (0.12, top + 0.08, 0.0), (0.16, top, 0.0), node="Lid")


def dome(r, y0=0.42, n=14):
    """A half circle standing on y0 as a side profile [(f, y), ...] (the gold chest's lid and its bands)."""
    return [(math.cos(math.pi * k / n) * r, y0 + math.sin(math.pi * k / n) * r) for k in range(n + 1)]


def half_round(m, mat, w, r, x):
    """The lid's half-round shape across the chest, closed at both ends (built as its own mesh: kit's profile
    extrusion leaves its ends open)."""
    import bmesh
    bm = bmesh.new()
    pts = dome(r)
    ends = [[bm.verts.new((x + side * w * 0.5, f, y)) for f, y in pts] for side in (-1.0, 1.0)]
    caps = [[bm.verts.new((x + side * (w * 0.5 + 0.0004), f, y)) for f, y in pts] for side in (-1.0, 1.0)]  # own corners: flat, not smoothed into the sides
    bm.faces.new(list(reversed(caps[0])))  # wound to face outward (-x and +x)
    bm.faces.new(caps[1])
    n = len(pts)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new([ends[0][k], ends[1][k], ends[1][j], ends[0][j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    m._add(bm, mat, "Lid", 0.003)


def gold(m):  # an ornate treasure chest: deep red wood, gilded bands, a domed lid, gems and a glowing keyhole
    wood = K("wood", (0.45, 0.08, 0.07))
    gilt = K("metal", (1.0, 0.72, 0.15))
    w, h, d = 0.9, 0.42, 0.58
    m.box(wood, (w, h, d), (0.0, h * 0.5, 0.0))
    m.box(gilt, (w + 0.03, 0.05, d + 0.03), (0.0, 0.025, 0.0))
    m.box(gilt, (w + 0.03, 0.04, d + 0.03), (0.0, h - 0.02, 0.0))
    for x in (-0.3, 0.3):
        m.box(gilt, (0.06, h, d + 0.02), (x, h * 0.5, 0.0))
    m.box(gilt, (0.18, 0.2, 0.03), (0.0, h - 0.12, -d * 0.5 - 0.015))
    m.box(K("paint", WHITE), (0.04, 0.08, 0.01), (0.0, h - 0.14, -d * 0.5 - 0.032), node="Glow")
    for x in (-0.3, 0.3):
        m.ball(K("ice", (0.15, 0.55, 1.0)), (0.035, 0.035, 0.035), (x, h * 0.5, -d * 0.5 - 0.02))
    half_round(m, wood, w, d * 0.5, 0.0)  # a half-round lid on the box
    for x in (-w * 0.5 + 0.03, -0.3, 0.3, w * 0.5 - 0.03):
        half_round(m, gilt, 0.06, d * 0.5 + 0.015, x)
    m.ball(K("ice", (1.0, 0.2, 0.3)), (0.05, 0.05, 0.05), (0.0, h + d * 0.36, -d * 0.36), node="Lid")


SHAPES = {"bronze": (bronze, 0.5), "silver": (silver, 0.44), "gold": (gold, 0.42)}  # build, lid hinge height


def build(cid):
    make, hinge = SHAPES[cid]
    m = kit.Model("crate_" + cid, uv_scale=2.0, colored=True)
    m.node("Glow", (0.0, 0.0, 0.0))
    m.node("Lid", (0.0, hinge, 0.3))
    make(m)
    return m


def pictures(cid):
    """Renders crate_<cid>.gltf from the front three-quarter view: whole, body only, lid only (same framing)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "crate_%s.gltf" % cid))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 40
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.3, 0.34, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    sc.world = world
    glow = {"bronze": (1.0, 0.6, 0.25, 1), "silver": (0.75, 0.9, 1.0, 1), "gold": (1.0, 0.85, 0.3, 1)}[cid]
    for mat in bpy.data.materials:  # the vertex colours carry the look; Glow parts shine in the crate's colour
        nt = mat.node_tree
        if nt is None:
            continue
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        col = nt.nodes.new("ShaderNodeVertexColor")
        gamma = nt.nodes.new("ShaderNodeGamma")  # the colours are stored screen-encoded (the game reads them as sRGB)
        gamma.inputs["Gamma"].default_value = 2.2
        nt.links.new(col.outputs["Color"], gamma.inputs["Color"])
        nt.links.new(gamma.outputs["Color"], bsdf.inputs["Base Color"])
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith("Glow"):
            em = bpy.data.materials.new("glow_pic")
            em.use_nodes = True
            b = em.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = glow
            b.inputs["Emission Color"].default_value = glow
            b.inputs["Emission Strength"].default_value = 4.0
            obj.data.materials.clear()
            obj.data.materials.append(em)
    for name, loc, energy, color in (("key", (2.0, -2.5, 3.0), 500, (1.0, 0.93, 0.85)), ("fill", (-3.0, -1.5, 1.5), 180, (0.75, 0.85, 1.0)), ("rim", (0.5, 3.0, 2.0), 400, (1.0, 1.0, 1.0))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        light.data.energy = energy
        light.data.color = color
        light.data.size = 2.0
        light.location = loc
        light.rotation_euler = (Vector((0, 0, 0.3)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(light)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.55
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = Vector((1.6, -2.4, 1.75))  # glTF import: the game's +Z (the crate's front) is Blender's -Y
    cam.rotation_euler = (Vector((0.0, 0.0, 0.33)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    lid = [o for o in meshes if o.name.startswith("Lid") or (o.parent is not None and o.parent.name.startswith("Lid"))]
    os.makedirs(PICS, exist_ok=True)
    for suffix, shown in (("", meshes), ("_body", [o for o in meshes if o not in lid]), ("_lid", lid)):
        for o in meshes:
            o.hide_render = o not in shown
        sc.render.filepath = os.path.join(PICS, cid + suffix + ".png")
        bpy.ops.render.render(write_still=True)


def main():
    only = sys.argv[1:]
    fk.init()
    os.makedirs(OUT, exist_ok=True)
    ids = [i for i in SHAPES if not only or i in only]
    for cid in ids:
        print("crate_" + cid, build(cid).export(OUT))
    for cid in ids:
        pictures(cid)
        fk.init()  # the factory reset of the picture scene dropped the kit's materials


if __name__ == "__main__":
    main()

# Purpose: developer-time. Turns a scripted mask sculpt (tools/blender/mask_<id>.py, built by diary/MASK_PROCESS.md
# = the HIGH poly) into the game mask (MASK_PROCESS step 12): a LOW poly in two levels (hi / lo), UVs, and textures
# baked from the high poly: colour, tangent normal, ORM (R 1, G roughness, B metal) and FX (R left eye glow, G right eye
# glow). Written to assets/masks/<id>/ as OBJ (already in the head anchor's space: metres, -Z forward, Y up) + PNG at
# full size and half size (the lower quality tiers). Small parts (stitches, studs, eyelets, lacing) live only in the
# baked maps; glass is left out (the game draws the lens). Thick sheets (solidified leather, brim) are one sheet in
# the low poly: the game draws masks two-sided. Effects (mist, flies) are the game's (game/mask_model.gd).
# Run: python3 tools/blender/mask_bake.py <id> [texture px, 2048] [hi triangles, 14000] [lo triangles, 4500]
# Needs pip bpy (5.x), numpy, pillow. ~5-15 min a mask on the CPU.
import sys
import os
import math

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ID = sys.argv[1]
TEX = int(sys.argv[2]) if len(sys.argv) > 2 else 2048
TRIS_HI = int(sys.argv[3]) if len(sys.argv) > 3 else 14000
TRIS_LO = int(sys.argv[4]) if len(sys.argv) > 4 else 4500
OUT = os.path.join(ROOT, "assets", "masks", ID)
os.makedirs(OUT, exist_ok=True)

script = os.path.join(HERE, "mask_%s.py" % ID)
os.environ["MASK_GAME"] = "1"
sys.argv = [script, "/tmp/mask_unused"]
NS = {"__name__": "mask_build"}
try:
    exec(compile(open(script).read(), script, "exec"), NS)
except SystemExit:
    pass

import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

SC = bpy.context.scene
FIT = NS.get("GAME_FIT", {"scale": 0.13, "lift": 0.1, "back": 0.0})
METAL_MATS = ("brass", "iron")
THIN = 0.025  # parts thinner than this (sculpt units) or smaller than SMALL live only in the baked maps
SMALL = 0.15


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


# ------------------------------------------------------------------ every part as a plain mesh (modifiers applied)
for m in bpy.data.materials:  # dirt from ambient occlusion only sees its own part (not the low poly laid over it)
    if m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "AMBIENT_OCCLUSION":
                n.only_local = True
def evaluated(o):
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
    me.transform(o.matrix_world)
    return me


high_parts, low_parts = [], []
for o in list(SC.objects):
    if o.type not in ("MESH", "CURVE") or o.name.startswith("glass"):
        continue
    me = evaluated(o)
    if len(me.vertices) == 0:
        continue
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    dims = co.max(0) - co.min(0)
    high_parts.append(me)
    keep = o.name.startswith("glow_") or (dims.max() >= SMALL and dims.min() >= THIN and not o.name.startswith("stitch"))
    if keep:  # the low poly is one sheet where the sculpt has thickness (the game draws both sides): no hidden inner shells
        solid = [m for m in o.modifiers if m.type == "SOLIDIFY"]
        for m in solid:
            m.show_viewport = False
        low_parts.append(evaluated(o) if solid else me.copy())
        for m in solid:
            m.show_viewport = True
for o in list(SC.objects):
    bpy.data.objects.remove(o, do_unlink=True)


def joined(name, meshes):
    bm = bmesh.new()
    mats = []
    for me in meshes:
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tmp = bmesh.new(); tmp.from_mesh(me)
        for f in tmp.faces:
            f.material_index = remap[f.material_index] if remap else 0
        out = bpy.data.meshes.new("t"); tmp.to_mesh(out); tmp.free()
        bm.from_mesh(out)
        bpy.data.meshes.remove(out)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for m in mats:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    SC.collection.objects.link(o)
    return o


high = joined("high", high_parts)
low = joined("low", low_parts)
print("MASK high %d tris, low before decimate %d tris" % (tri_count(high.data), tri_count(low.data)))


def select_only(o):
    for x in SC.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def decimate(o, tris):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0008)
    bm.to_mesh(o.data); bm.free()
    have = tri_count(o.data)
    if have > tris:
        md = o.modifiers.new("dec", "DECIMATE"); md.ratio = tris / have; md.use_collapse_triangulate = True
        select_only(o); bpy.ops.object.modifier_apply(modifier="dec")
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()
    for p in o.data.polygons:
        p.use_smooth = True


decimate(low, TRIS_HI)
low.data.materials.clear()
select_only(low)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
bpy.ops.object.mode_set(mode="OBJECT")
print("MASK low %d tris" % tri_count(low.data))

# ------------------------------------------------------------------ bake
SC.render.engine = "CYCLES"
SC.cycles.device = "CPU"
SC.cycles.use_denoising = False
bk = SC.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = 0.05
bk.max_ray_distance = 0.12
bk.margin = 6
target = bpy.data.materials.new("bake_target"); target.use_nodes = True
img_node = target.node_tree.nodes.new("ShaderNodeTexImage")
target.node_tree.nodes.active = img_node
low.data.materials.append(target)


def bake(kind, file, samples, colorspace="sRGB", **kw):
    img = bpy.data.images.new(file, TEX, TEX, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    img_node.image = img
    SC.cycles.samples = samples
    for x in SC.objects:
        x.select_set(False)
    high.select_set(True); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type=kind, **kw)
    path = os.path.join(OUT, file + ".png")
    img.filepath_raw = path; img.file_format = "PNG"; img.save()
    print("MASK baked", file)
    return path


def principled(m):
    return next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m.node_tree else None


def emit_swap(color_of):
    saved = []
    for m in high.data.materials:
        nt = m.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        old = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].links else None
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs["Color"].default_value = (*color_of(m.name), 1.0)
        e.inputs["Strength"].default_value = 1.0
        nt.links.new(e.outputs[0], out.inputs["Surface"])
        saved.append((nt, out, old, e))
    return saved


def emit_restore(saved):
    for nt, out, old, e in saved:
        nt.nodes.remove(e)
        if old is not None:
            nt.links.new(old, out.inputs["Surface"])


normal_png = bake("NORMAL", "nrm", 4, "Non-Color", normal_space="TANGENT")
metal_saved = {}
for m in high.data.materials:  # colour without the metal look: metals keep their base colour
    p = principled(m)
    if p is not None:
        metal_saved[m.name] = p.inputs["Metallic"].default_value
        p.inputs["Metallic"].default_value = 0.0
col_png = bake("DIFFUSE", "col", 8, pass_filter={"COLOR"})
for m in high.data.materials:
    p = principled(m)
    if p is not None:
        p.inputs["Metallic"].default_value = metal_saved[m.name]
rough_png = bake("ROUGHNESS", "rough", 4, "Non-Color")
s = emit_swap(lambda n: (1.0, 1.0, 1.0) if n.split(".")[0] in METAL_MATS else (0.0, 0.0, 0.0))
metal_png = bake("EMIT", "metal", 2, "Non-Color")
emit_restore(s)
s = emit_swap(lambda n: (1.0, 0.0, 0.0) if n == "lensglow28" else ((0.0, 1.0, 0.0) if n == "lensglow5" else (0.0, 0.0, 0.0)))
fx_png = bake("EMIT", "fx_raw", 2, "Non-Color")
emit_restore(s)

# ------------------------------------------------------------------ pack ORM / FX, half-size copies
def load(path):
    return np.array(Image.open(path).convert("RGB"), dtype=np.uint8)


r = load(rough_png)[:, :, 0]
mt = load(metal_png)[:, :, 0]
orm = np.stack([np.full_like(r, 255), r, mt], -1)
Image.fromarray(orm).save(os.path.join(OUT, "orm.png"))
fx = load(fx_png)
fx[:, :, 2] = 0
Image.fromarray(fx).save(os.path.join(OUT, "fx.png"))
for f in ("rough", "metal", "fx_raw"):
    os.remove(os.path.join(OUT, f + ".png"))
for f in ("col", "nrm", "orm", "fx"):
    Image.open(os.path.join(OUT, f + ".png")).resize((TEX // 2, TEX // 2), Image.LANCZOS).save(os.path.join(OUT, f + "_half.png"))


# ------------------------------------------------------------------ OBJ in the head anchor's space
def write_obj(o, path):
    me = o.data
    me.calc_loop_triangles()
    s, lift, back = float(FIT["scale"]), float(FIT["lift"]), float(FIT["back"])
    uv = me.uv_layers.active.data
    nrm = me.corner_normals
    lines = ["# %s game mask (tools/blender/mask_bake.py): metres, head anchor space, -Z forward" % ID]
    for v in me.vertices:  # sculpt (x right of the viewer, -y forward, z up) -> anchor (-x, z, y)
        lines.append("v %.5f %.5f %.5f" % (-v.co.x * s, v.co.z * s + lift, v.co.y * s + back))
    for lp in me.loops:
        lines.append("vt %.5f %.5f" % tuple(uv[lp.index].uv))
    for lp in me.loops:
        n = nrm[lp.index].vector
        lines.append("vn %.4f %.4f %.4f" % (-n.x, n.z, n.y))
    for p in me.polygons:
        lines.append("f " + " ".join("%d/%d/%d" % (me.loops[li].vertex_index + 1, li + 1, li + 1) for li in p.loop_indices))
    open(path, "w").write("\n".join(lines) + "\n")


write_obj(low, os.path.join(OUT, "hi.obj"))
decimate(low, TRIS_LO)
write_obj(low, os.path.join(OUT, "lo.obj"))
print("MASK lo %d tris" % tri_count(low.data))
print("MASK_BAKE_DONE", OUT)

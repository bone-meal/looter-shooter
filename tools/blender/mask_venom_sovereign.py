# Venom Sovereign mask (boss mask 3, diary/DECISIONS_SKINS.md A3 + diary/MASK_PROCESS.md section 5): a king cobra's
# head worn as a helmet. Silhouette plan: FRONT = the flared hood framing the head + two long fangs dripping glowing
# venom; SIDE = the long flat snout over the face, brow shields, scale rows stepping in size, the hood's edge; BACK =
# the hood's ribs and its spectacle mark. Behaviour: head shields as grooved plates, overlapping scales in the surface
# (baked into the normal map), wet slit-pupil eyes under heavy brows, venom drops as meshes, a forked tongue.
# Game: eyes (fxR_) blink one at a time, venom (fxG_) glows, the tongue (fxB_) flicks out (game/mask_model.gd).
# Run: python3 tools/blender/mask_venom_sovereign.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py venom_sovereign
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(23)


def scale_mat(name, dark, light, belly=None, size=26.0, spectacle=False):
    """Snake skin: overlapping scales (Voronoi cells shaded from their front edge to the next scale's overlap, a dark
    gap between), iridescent sheen, optional pale belly below `belly` z, optional cobra spectacle mark on the back."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1.0, 1.0, 0.62)
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = size
    vo.inputs["Randomness"].default_value = 0.55
    L.new(mp.outputs["Vector"], vo.inputs["Vector"])
    edge = N.new("ShaderNodeTexVoronoi"); edge.feature = "DISTANCE_TO_EDGE"; edge.inputs["Scale"].default_value = size
    edge.inputs["Randomness"].default_value = 0.55
    L.new(mp.outputs["Vector"], edge.inputs["Vector"])
    gap = N.new("ShaderNodeMapRange"); gap.inputs["From Min"].default_value = 0.0; gap.inputs["From Max"].default_value = 0.08
    L.new(edge.outputs["Distance"], gap.inputs["Value"])
    # overlap: each scale rises toward its back edge (cell position vs point in z)
    sep_p = N.new("ShaderNodeSeparateXYZ"); L.new(mp.outputs["Vector"], sep_p.inputs[0])
    sep_c = N.new("ShaderNodeSeparateXYZ"); L.new(vo.outputs["Position"], sep_c.inputs[0])
    dz = N.new("ShaderNodeMath"); dz.operation = "SUBTRACT"
    L.new(sep_p.outputs["Z"], dz.inputs[0]); L.new(sep_c.outputs["Z"], dz.inputs[1])
    rise = N.new("ShaderNodeMath"); rise.operation = "MULTIPLY"; rise.inputs[1].default_value = size * 0.9
    L.new(dz.outputs[0], rise.inputs[0])
    h = N.new("ShaderNodeMath"); h.operation = "MULTIPLY"
    L.new(gap.outputs["Result"], h.inputs[0])
    rr = N.new("ShaderNodeMath"); rr.operation = "ADD"; rr.inputs[1].default_value = 0.6
    L.new(rise.outputs[0], rr.inputs[0]); L.new(rr.outputs[0], h.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.55; bump.inputs["Distance"].default_value = 0.01
    L.new(h.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    # colour: dark scale, lighter scale centres, dark gaps, cell-to-cell variation
    cv = N.new("ShaderNodeMix"); cv.data_type = "RGBA"
    L.new(vo.outputs["Color"], cv.inputs[0])
    cv.inputs[6].default_value = (*dark, 1); cv.inputs[7].default_value = (*light, 1)
    gm = N.new("ShaderNodeMix"); gm.data_type = "RGBA"
    L.new(gap.outputs["Result"], gm.inputs[0])
    gm.inputs[6].default_value = (0.004, 0.006, 0.004, 1); L.new(cv.outputs[2], gm.inputs[7])
    col = gm.outputs[2]
    if belly is not None:
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
        bm = N.new("ShaderNodeMapRange"); bm.inputs["From Min"].default_value = belly + 0.04; bm.inputs["From Max"].default_value = belly - 0.04
        L.new(sep.outputs["Z"], bm.inputs["Value"])
        bmix = N.new("ShaderNodeMix"); bmix.data_type = "RGBA"
        L.new(bm.outputs["Result"], bmix.inputs[0]); L.new(col, bmix.inputs[6])
        bmix.inputs[7].default_value = (0.36, 0.3, 0.12, 1)
        col = bmix.outputs[2]
    if spectacle:  # the cobra's spectacle mark: two pale rings joined by a bar, on the back of the hood
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
        mark = N.new("ShaderNodeMath"); mark.operation = "ADD"
        rings = []
        for s in (-1, 1):
            off = N.new("ShaderNodeVectorMath"); off.operation = "SUBTRACT"
            L.new(tc.outputs["Object"], off.inputs[0]); off.inputs[1].default_value = (s * 0.42, 0.9, 0.05)
            ln = N.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"; L.new(off.outputs[0], ln.inputs[0])
            band = N.new("ShaderNodeMapRange"); band.inputs["From Min"].default_value = 0.0; band.inputs["From Max"].default_value = 0.05
            dd = N.new("ShaderNodeMath"); dd.operation = "ABSOLUTE"
            sub = N.new("ShaderNodeMath"); sub.operation = "SUBTRACT"; sub.inputs[1].default_value = 0.2
            L.new(ln.outputs["Value"], sub.inputs[0]); L.new(sub.outputs[0], dd.inputs[0]); L.new(dd.outputs[0], band.inputs["Value"])
            inv = N.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
            L.new(band.outputs["Result"], inv.inputs[1])
            rings.append(inv)
        L.new(rings[0].outputs[0], mark.inputs[0]); L.new(rings[1].outputs[0], mark.inputs[1])
        back = N.new("ShaderNodeMapRange"); back.inputs["From Min"].default_value = 0.5; back.inputs["From Max"].default_value = 0.8
        L.new(sep.outputs["Y"], back.inputs["Value"])
        mm = N.new("ShaderNodeMath"); mm.operation = "MULTIPLY"
        L.new(mark.outputs[0], mm.inputs[0]); L.new(back.outputs["Result"], mm.inputs[1])
        smix = N.new("ShaderNodeMix"); smix.data_type = "RGBA"
        L.new(mm.outputs[0], smix.inputs[0]); L.new(col, smix.inputs[6]); smix.inputs[7].default_value = (0.42, 0.36, 0.14, 1)
        col = smix.outputs[2]
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.38
    b.inputs["Coat Weight"].default_value = 0.35
    b.inputs["Coat Roughness"].default_value = 0.25
    b.inputs["Specular IOR Level"].default_value = 0.5
    b.inputs["Thin Film Thickness"].default_value = 420.0  # oily iridescence
    return m


SKIN = scale_mat("scales", (0.012, 0.035, 0.02), (0.05, 0.13, 0.06), size=28.0)
BELLY = scale_mat("jaw_scales", (0.012, 0.035, 0.02), (0.05, 0.13, 0.06), belly=-0.3, size=24.0)
SHIELD = scale_mat("shields", (0.014, 0.04, 0.024), (0.06, 0.15, 0.07), size=7.0)
HOOD = scale_mat("hood_scales", (0.02, 0.045, 0.026), (0.07, 0.15, 0.07), size=22.0, spectacle=True)
HOOD_IN = scale_mat("hood_inner", (0.12, 0.1, 0.04), (0.3, 0.26, 0.1), size=18.0)
FANG = K.simple("fang", (0.62, 0.58, 0.48), 0.25)
GUM = K.simple("gum", (0.28, 0.05, 0.07), 0.35)
MOUTH = K.simple("mouth", (0.06, 0.008, 0.012), 0.5)
TONGUE = K.simple("fxB_tongue", (0.35, 0.02, 0.05), 0.3)
EYE = K.simple("fxR_eye", (0.5, 0.42, 0.05), 0.08, emit=(0.75, 1.0, 0.1), es=6.0)
PUPIL = K.simple("pupil", (0.0, 0.0, 0.0), 0.05)
VENOM = K.glow("fxG_venom", (0.35, 1.0, 0.15), 14.0, base=(0.1, 0.4, 0.05))


# ------------------------------------------------------------------ the head: domed crown, long flat snout, jaws
def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, -0.02, 0.3), (0.84, 0.94, 0.82))  # crown over the wearer's head (its back stays inside the hood)
    d = smax(d, z - 1.02, 0.12)  # a snake's flat top
    d = smin(d, sd_ellipsoid(P, (0, -0.95, 0.2), (0.56, 0.95, 0.34)), 0.3)  # upper jaw / snout
    d = smin(d, sd_ellipsoid(P, (0, -1.62, 0.18), (0.3, 0.34, 0.2)), 0.18)  # rounded snout tip
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.7, -0.66, 0.46), (s * 0.4, -1.16, 0.37), 0.08), 0.06)  # supraocular ridge, angled down to the snout
        d = smax(d, -sd_ellipsoid(P, (s * 0.6, -0.95, 0.28), (0.13, 0.16, 0.12)), 0.03)  # eye socket
        d = smax(d, -sd_ellipsoid(P, (s * 0.12, -1.86, 0.25), (0.035, 0.05, 0.035)), 0.01)  # nostril
        d = smin(d, sd_ellipsoid(P, (s * 0.7, -0.35, 0.05), (0.22, 0.42, 0.3)), 0.2)  # jaw muscles behind the eyes
    d = smax(d, -sd_box(P, (0, -1.25, -0.06), (0.55, 0.75, 0.07), 0.05), 0.04)  # the mouth, a little open
    d = smin(d, sd_capsule(P, (0, 0.12, -0.55), (0, 0.15, -1.0), 0.55), 0.18)  # neck under the hood
    # head shields: grooves where the snake's big crown scales meet (stepped, overlapping)
    top = 1.0 / (1.0 + np.exp(-(z - 0.5) / 0.03))
    d = groove(d, (np.abs(x) - 0.0) * top + (1 - top) * 9.0, 0.012, 0.016, 0.0)  # midline
    d = groove(d, (y + 0.45) * top + (1 - top) * 9.0, 0.012, 0.016, 0.008 * top)  # frontals / parietals
    d = groove(d, (y + 1.2) * top + (1 - top) * 9.0, 0.01, 0.014, 0.006 * top)  # internasals
    for s in (-1, 1):
        d = groove(d, (s * x - 0.3) * top + (1 - top) * 9.0, 0.01, 0.014, -0.006 * top)
    return d


def lower_jaw(P):
    d = sd_ellipsoid(P, (0, -0.9, -0.24), (0.48, 0.9, 0.16))
    d = smin(d, sd_ellipsoid(P, (0, -0.25, -0.35), (0.6, 0.5, 0.25)), 0.25)
    d = smax(d, -sd_box(P, (0, -1.0, -0.06), (0.4, 0.75, 0.08), 0.05), 0.04)  # mouth floor
    return d


skull = K.sdf_mesh("hood", head, (-1.0, -2.05, -1.1), (1.0, 1.05, 1.12), 0.016, SKIN)
jaw = K.sdf_mesh("jaw", lower_jaw, (-0.75, -1.85, -0.5), (0.75, 0.05, -0.05), 0.014, BELLY)


def onto(o, origin, direction):
    return K.ray_onto(o, origin, direction)


# shields on the crown get the big-scale material: a thin copy of the top
crown = K.sdf_mesh("crown_shields", lambda P: smax(head(P) + 0.006, 0.55 - P[..., 2], 0.05), (-1.0, -2.05, 0.4), (1.0, 1.05, 1.12), 0.016, SHIELD)

# ------------------------------------------------------------------ the cobra hood: a ribbed flare round the back of the head
def hood_shape(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    outer = sd_ellipsoid(P, (0, 0.66, -0.15), (1.75, 0.36, 1.25))
    inner = sd_ellipsoid(P, (0, 0.6, -0.15), (1.68, 0.33, 1.18))
    d = smax(outer, -inner, 0.02)  # a thin curved sheet, convex at the back
    d = smax(d, -(y - 0.52), 0.04)  # only its back half: it flares out behind and beside the head
    # the hood's outline: rounded top, widest at the temples, narrowing down to the neck
    u = np.clip((z - 0.05) / 1.05, -1.0, 1.0)
    w = np.where(z > 0.05, 1.72 * np.sqrt(np.maximum(1.0 - u ** 2, 0.0)) ** 0.8, 0.62 + 1.1 * np.clip(1.0 + (z - 0.05) / 1.05, 0.0, 1.0) ** 1.6)
    d = smax(d, np.abs(x) - w, 0.06)
    d = smax(d, -(z + 1.0), 0.05)
    return d


hood_flare = K.sdf_mesh("cobra_hood", hood_shape, (-1.8, 0.3, -1.2), (1.8, 1.1, 1.15), 0.016, HOOD)
# ribs: raised lines radiating over the back of the hood
for k in range(-4, 5):
    ang = k * 0.32
    pts = []
    for t in np.linspace(0.15, 1.0, 10):
        o = Vector((math.sin(ang) * 3 * t, 3, -0.12 + math.cos(ang) * 0.95 * t))
        loc, n = onto(hood_flare, (o.x * 0.47, 3, o.z), (0, -1, 0))
        if loc is not None:
            pts.append(loc + n * 0.012)
    if len(pts) > 2:
        K.tube("hood_rib", K.smooth_path(pts, 16), 0.022, HOOD, res=4, taper=lambda t: 1.0 - 0.6 * t)
# the hood's inner (front-facing) side is pale and banded: faces turned toward the front get the second material
hood_flare.data.materials.append(HOOD_IN)
for poly in hood_flare.data.polygons:
    if poly.normal.y < -0.25:
        poly.material_index = 1

# ------------------------------------------------------------------ eyes: wet, slit pupils, heavy lids
for s in (-1, 1):
    c = Vector((s * 0.6, -0.95, 0.28))
    eye = K.ball("eye", 0.115, c, EYE, (1.0, 1.0, 0.9), 24)
    look = Vector((s * 0.72, -0.7, 0.05)).normalized()
    pupil = K.box("pupil", (1, 1, 1), c + look * 0.108, mat=PUPIL, bev=0.006)
    K.align(pupil, look)
    pupil.scale = (0.022, 0.16, 0.012)  # a vertical slit on the eye's surface

# ------------------------------------------------------------------ fangs, gums, venom drops, forked tongue
for s in (-1, 1):
    root = Vector((s * 0.2, -1.42, -0.0))
    tip = Vector((s * 0.15, -1.56, -0.56))
    fang = K.loft("fang", lambda t, r=root, e=tip: r.lerp(e, t) + Vector((0, -0.06 * math.sin(math.pi * t), 0)),
                  lambda t: 0.058 * (1 - t) ** 0.8 + 0.004, 40, 12, mat=FANG)
    K.ball("gum", 0.07, root + Vector((0, 0.02, 0.03)), GUM, (1.0, 1.2, 0.6), 14)
    for k, dz in enumerate((0.05, 0.13)):  # venom drops hanging off the tip
        drop = K.ball("venom", 0.024 - 0.006 * k, tip + Vector((0, -0.005, -dz)), VENOM, (1.0, 1.0, 1.5), 12)
    K.tube("venom_string", [tip, tip + Vector((0, -0.004, -0.05))], 0.008, VENOM)
for s in (-1, 1):  # a row of small teeth along each side of the upper jaw
    for k in range(6):
        p = Vector((s * (0.36 - 0.03 * k), -1.25 + 0.14 * k, -0.02))
        K.loft("tooth", lambda t, p=p: p + Vector((0, 0, -0.07 * t)), lambda t: 0.018 * (1 - t) + 0.002, 8, 8, mat=FANG)
K.box("mouth_dark", (0.42, 0.7, 0.03), (0, -0.95, -0.07), mat=MOUTH, bev=0.01)
tongue_pts = [Vector((0, -0.6, -0.08)), Vector((0, -1.3, -0.09)), Vector((0, -1.75, -0.1))]
K.tube("tongue", K.smooth_path(tongue_pts, 12), 0.03, TONGUE, taper=lambda t: 1.0 - 0.5 * t)
for s in (-1, 1):
    fork = [Vector((0, -1.75, -0.1)), Vector((s * 0.05, -1.92, -0.12)), Vector((s * 0.1, -2.0, -0.16))]
    K.tube("tongue_fork", K.smooth_path(fork, 8), 0.015, TONGUE, taper=lambda t: 1.0 - 0.8 * t)

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

random.seed(5)
for i in range(10):  # preview: a few falling venom drops
    p = Vector((random.choice((-0.15, 0.15)) + random.uniform(-0.03, 0.03), -1.56, random.uniform(-1.7, -0.75)))
    K.ball("drip", 0.016, p, VENOM, (1, 1, 1.6), 8)
K.stage(head=False)
K.shoot_views("venom_sovereign")
print("ok")

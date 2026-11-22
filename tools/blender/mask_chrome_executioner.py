# Chrome Executioner mask (boss mask 9, diary/DECISIONS_SKINS.md A9 + diary/MASK_PROCESS.md section 5): a featureless
# (base 9) mirror-chrome face plate - two faceted planes meeting at a knife-sharp centre ridge, no eyes, no mouth -
# set deep inside an executioner's hood of black leather with a thick rolled frame round the opening.
# Silhouette plan: FRONT = the centre ridge splitting two faceted planes + the deep hood frame; SIDE = the blade-like
# profile ridge + the thick rim + a strap; BACK = the hood (its tip, folds) + the strap's buckle.
# Behaviour: mirror planes; liquid-metal tears running down from where eyes would be (meshes here; drips in the game).
# Run: python3 tools/blender/mask_chrome_executioner.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py chrome_executioner
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(97)

CHROME = K.simple("chrome", (0.92, 0.92, 0.94), 0.05, metal=1.0)
TEAR = K.simple("liquid_chrome", (0.95, 0.95, 0.97), 0.02, metal=1.0)


def leather(name, col=(0.03, 0.026, 0.028)):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    v = N.new("ShaderNodeTexVoronoi"); v.inputs["Scale"].default_value = 90.0
    L.new(tc.outputs["Object"], v.inputs["Vector"])
    wr = N.new("ShaderNodeTexNoise"); wr.inputs["Scale"].default_value = 6.0; wr.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], wr.inputs["Vector"])
    hh = N.new("ShaderNodeMath"); hh.operation = "MULTIPLY_ADD"; hh.inputs[1].default_value = 0.25
    L.new(v.outputs["Distance"], hh.inputs[0]); L.new(wr.outputs["Fac"], hh.inputs[2])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = 0.004
    L.new(hh.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    col_s, ao = K._ao_mix(N, L, K._const(N, col), (0.008, 0.007, 0.007), 0.06)
    L.new(col_s, b.inputs["Base Color"])
    rg = N.new("ShaderNodeMapRange"); rg.inputs["To Min"].default_value = 0.42; rg.inputs["To Max"].default_value = 0.75
    L.new(wr.outputs["Fac"], rg.inputs["Value"]); L.new(rg.outputs["Result"], b.inputs["Roughness"])
    return m


HOOD = leather("hood_leather")
STRAP = leather("strap_leather", (0.05, 0.03, 0.02))
STEEL = K.steel("buckle_steel", base=(0.3, 0.31, 0.32), heat=0.0, rust=0.0, rough=0.3)


def plane(P, n, k):
    n = np.array(n, dtype=float); n = n / np.linalg.norm(n)
    return P @ n - k


# ------------------------------------------------------------------ the hood
OPEN_C = np.array([0.0, -0.98, 0.14])
OPEN_R = (0.58, 0.8)  # half width / half height of the opening


def hood_outer(P):
    z = P[..., 2]
    d = sd_ellipsoid(P, (0, 0.0, 0.2), (0.84, 1.0, 0.95))
    d = smin(d, sd_capsule(P, (0, 0.05, 0.55), (0, 0.18, 1.05), 0.46), 0.3)  # a cowl rising to a point, leaning back
    d = smin(d, sd_capsule(P, (0, 0.18, 1.05), (0, 0.42, 1.5), 0.14), 0.3)
    d = smax(d, -(z + 0.97), 0.03)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.55), 0.18)  # falls to the collar
    return d


def recess_sd(P):
    q = (P - OPEN_C) / np.array([OPEN_R[0], 1.0, OPEN_R[1]])
    rad = np.sqrt(q[..., 0] ** 2 + q[..., 2] ** 2)
    return np.maximum((rad - 1.0) * 0.56, P[..., 1] + 0.55)  # a tunnel into the hood from the front


def hood(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    outer = hood_outer(P)
    rec = recess_sd(P)
    d = smax(outer, -rec, 0.03)
    rim = np.sqrt(outer ** 2 + rec ** 2) - 0.06  # the thick rolled frame: a tube along the opening's edge on the hood
    d = smin(d, rim, 0.03)
    # a few loose creases falling from the tip toward the sides (even ribs had read as a garlic bulb)
    for (sx, tilt, depth, width) in ((1, 0.55, 0.02, 0.06), (-1, 0.42, 0.016, 0.07), (1, 1.05, 0.012, 0.08)):
        pd = (sx * x) * math.cos(tilt) - (z - 1.2) * math.sin(tilt) * 0.0 - (y - 0.35) * math.sin(tilt)
        w = np.clip((y + 0.1) / 0.3, 0.0, 1.0) * np.clip((1.3 - z) / 0.4, 0.0, 1.0) * np.clip((z + 0.4) / 0.3, 0.0, 1.0)
        d = d + depth * w * np.exp(-(pd / width) ** 2)
    d = groove(d, x, 0.008, 0.01, 0.0)  # the centre seam over the top and down the back
    return d


hood_mesh = K.sdf_mesh("hood", hood, (-1.05, -1.15, -1.0), (1.05, 1.1, 1.75), 0.012, HOOD)


# ------------------------------------------------------------------ the chrome face plate
def plate(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, -0.84, 0.14), (0.6, 0.45, 0.84))
    for s in (-1, 1):
        d = smax(d, plane(P, (s * 0.4, -0.92, 0.0), 1.06), 0.004)  # the two broad main planes meeting at the ridge (proud of the frame)
        d = smax(d, plane(P, (s * 0.3, -0.7, 0.65), 1.03), 0.004)  # brow facets
        d = smax(d, plane(P, (s * 0.3, -0.72, -0.63), 0.97), 0.004)  # chin facets
        d = smax(d, plane(P, (s * 0.85, -0.45, 0.28), 0.82), 0.004)  # cheek facets
        d = smax(d, plane(P, (s * 0.83, -0.47, -0.3), 0.8), 0.004)
    d = smax(d, y + 0.5, 0.01)  # a plate, not a head: cut off behind
    return d


face = K.sdf_mesh("face_plate", plate, (-0.65, -1.32, -0.75), (0.65, -0.45, 1.05), 0.006, CHROME, relax=0)
face.data.polygons.foreach_set("use_smooth", [False] * len(face.data.polygons))  # crisp facets
# the ridge as a raised blade along the middle
ridge_pts = []
for zz in np.linspace(-0.55, 0.88, 30):
    loc, n = K.ray_onto(face, Vector((0, -2.0, zz)), Vector((0, 1, 0)))
    if loc:
        ridge_pts.append(loc)
if len(ridge_pts) > 2:
    K.loft("ridge_blade", K.path_fn(ridge_pts), lambda t: 0.04 * math.sin(math.pi * min(1.0, 0.08 + 0.92 * t)) + 0.008, 60, 4,
           profile=lambda th, t: (0.35, 1.0), mat=CHROME)

# liquid-metal tears from where eyes would be, a drop hanging at the end of each
for s in (-1, 1):
    pts = []
    for k, zz in enumerate(np.linspace(0.34, -0.12 - 0.06 * (s > 0), 14)):
        xx = s * (0.2 + 0.015 * math.sin(k * 0.9))
        loc, n = K.ray_onto(face, Vector((xx, -2.0, zz)), Vector((0, 1, 0)))
        if loc:
            pts.append(loc + n * 0.004)
    if len(pts) > 2:
        K.tube("tear", pts, 0.013, TEAR, res=3, taper=lambda t: 0.6 + 0.4 * math.sin(math.pi * t * 3) ** 2)
        K.ball("tear_drop", 0.03, pts[-1] + Vector((0, -0.008, -0.025)), TEAR, (1.0, 0.85, 1.25), 16)
        K.ball("tear_well", 0.022, pts[0] + Vector((0, -0.004, 0.0)), TEAR, (1.6, 0.7, 0.8), 16)

# ------------------------------------------------------------------ the strap round the back + buckle
strap = []
for a in np.linspace(-0.95, 0.95, 41):
    ang = math.pi * a  # from one side of the plate round the back to the other
    loc, n = K.ray_onto(hood_mesh, Vector((2.0 * math.sin(ang), -2.0 * math.cos(ang) * -1.0, 0.12)) * 1.0, -Vector((math.sin(ang), math.cos(ang), 0.0)))
    if loc and loc.y > -0.75:
        strap.append(loc + n * 0.03)
if len(strap) > 3:
    K.loft("strap", K.path_fn(strap), lambda t: 0.075, 80, 8, profile=lambda th, t: (0.32, 1.0), mat=STRAP)  # thin against the hood, tall: a strap, not a brim
    mid = strap[len(strap) // 2]
    out = (mid - Vector((0, 0, 0.12))).normalized()
    b = K.box("buckle", (0.3, 0.04, 0.24), mid + out * 0.025, mat=STEEL, bev=0.015)
    hole = K.box("buckle_hole", (0.2, 0.05, 0.14), mid + out * 0.035, mat=STRAP, bev=0.01)
    K.box("buckle_prong", (0.03, 0.03, 0.18), mid + out * 0.06, mat=STEEL, bev=0.008)
    for e in (strap[1], strap[-2]):  # rivets where the strap meets the plate
        K.ball("rivet", 0.025, e + Vector((0, 0, 0.0)), STEEL, (1, 1, 0.6), 12)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("chrome_executioner")
print("ok")

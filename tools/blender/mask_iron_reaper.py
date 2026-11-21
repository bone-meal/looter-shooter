# Iron Reaper mask (boss mask 2, diary/DECISIONS_SKINS.md A2 + diary/MASK_PROCESS.md section 5): a heavy industrial
# skull welded together from steel plates. Silhouette plan: FRONT = a heavy brow ridge with bolts, deep orbits with
# molten-orange glow behind visor slats, jutting cheekbones, a nasal cavity bridged by plates, rebar teeth, a separate
# welded jaw; SIDE = sunken temples behind the cheekbones, stepped cranium plates with weld beads, hydraulic jaw pistons
# standing off the cheeks, exhaust stacks; BACK = a bolted spine plate, a cable bundle into the gorget, the exhausts.
# The skull is sculpted as a signed distance field (anatomical landmarks: cranium, occiput, brow ridge, orbits,
# zygomatic arches, temporal hollows, maxilla, nasal cavity) and cut by seams into overlapping plates.
# Run: python3 tools/blender/mask_iron_reaper.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py iron_reaper
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

SC = K.setup(11)
PLATE = K.steel("plate", (0.095, 0.098, 0.105), heat=0.45, rust=0.5, scale=1.2)
STEEL = K.steel("steel", (0.085, 0.09, 0.098), heat=0.55, rust=0.45)
JAW = K.steel("fxB_jaw", (0.09, 0.092, 0.1), heat=0.5, rust=0.5)
WELD = K.steel("weld", (0.16, 0.15, 0.14), heat=1.0, rust=0.2, scale=3.0, rough=0.55)
BOLT = K.steel("bolt", (0.2, 0.2, 0.21), heat=0.2, rust=0.35, scale=2.0, rough=0.3)
HOT = K.steel("exhaust", (0.12, 0.1, 0.1), heat=1.0, rust=0.3)
RUBBER = K.rubber("cable")
EYE = K.glow("fxR_eyes", (1.0, 0.42, 0.05), 40.0)
MAW = K.glow("fxG_maw", (1.0, 0.3, 0.03), 14.0)


# ------------------------------------------------------------------ the skull (signed distance field)
def skull(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.06, 0.32), (0.84, 1.0, 0.84))  # cranium
    d = smin(d, sd_ellipsoid(P, (0, 0.34, 0.0), (0.72, 0.72, 0.66)), 0.25)  # occiput
    d = smin(d, sd_box(P, (0, -0.52, -0.36), (0.44, 0.36, 0.3), 0.14), 0.18)  # maxilla / face block
    d = smin(d, sd_capsule(P, (-0.58, -0.86, 0.3), (0.58, -0.86, 0.3), 0.12), 0.1)  # brow ridge
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.34, -0.8, -0.12), (s * 0.82, -0.26, -0.06), 0.1), 0.08)  # zygomatic arch
        d = smax(d, -sd_ellipsoid(P, (s * 1.02, -0.42, 0.06), (0.3, 0.36, 0.36)), 0.12)  # temporal hollow
        d = smax(d, -sd_ellipsoid(P, (s * 0.31, -1.02, 0.07), (0.23, 0.36, 0.21)), 0.05)  # orbit
    d = smax(d, -sd_ellipsoid(P, (0, -0.98, -0.24), (0.1, 0.26, 0.16)), 0.03)  # nasal cavity
    d = smax(d, -sd_box(P, (0, -0.98, -0.62), (0.34, 0.3, 0.07), 0.04), 0.03)  # mouth slot behind the teeth
    d = smin(d, sd_capsule(P, (0, 0.1, -0.6), (0, 0.15, -1.0), 0.56), 0.15)  # neck under the gorget
    # plates: seams where planes cross the skull, one side of each raised (overlapping plates)
    top = 1.0 / (1.0 + np.exp(-(z - 0.25) / 0.03))
    d = groove(d, (y - 0.12) * top + (1 - top) * 9.0, 0.016, 0.02, 0.012 * top)  # coronal seam
    for s in (-1, 1):
        d = groove(d, (s * x - 0.36) + 0.25 * (1 - top), 0.014, 0.018, -0.01)  # side seams
    back = 1.0 / (1.0 + np.exp(-(y - 0.3) / 0.04))
    d = groove(d, (z + 0.05) * back + (1 - back) * 9.0, 0.014, 0.018, 0.01 * back)  # back seam
    return d


hood = K.sdf_mesh("hood", skull, (-1.0, -1.25, -1.1), (1.0, 1.05, 1.22), 0.016, PLATE)
K.displace(hood, "CLOUDS", 0.3, 0.006, 3)


def onto(origin, direction):
    return K.ray_onto(hood, origin, direction)


def weld_line(points_origin_dir, r=0.026):
    pts = []
    for o, d in points_origin_dir:
        loc, n = onto(o, d)
        if loc is not None:
            pts.append(loc + n * 0.008)
    if len(pts) >= 2:
        K.weld("weld", pts, r, WELD)


# weld beads along the seams (rays from outside onto the skull)
weld_line([((math.sin(a) * 3, 0.12, math.cos(a) * 3 + 0.3), (-math.sin(a), 0, -math.cos(a))) for a in np.linspace(-1.2, 1.2, 14)])
for s in (-1, 1):
    weld_line([((s * 0.36, y, 3), (0, 0, -1)) for y in np.linspace(-0.55, 0.12, 6)], 0.022)
weld_line([((math.cos(a) * 3, 3 * math.sin(a), -0.05), (-math.cos(a), -math.sin(a), 0)) for a in np.linspace(0.35, math.pi - 0.35, 12)])

# bolts: along the brow, at the temples
for x in (-0.42, -0.14, 0.14, 0.42):
    loc, n = onto((x, -3, 0.33), (0, 1, 0))
    if loc is not None:
        K.bolt(loc, n, 0.038, BOLT)
for o, d in [((s * 3, -0.3, 0.42), (-s, 0, 0)) for s in (-1, 1)] + [((s * 3, 0.3, 0.6), (-s, 0, 0)) for s in (-1, 1)]:
    loc, n = onto(o, d)
    if loc is not None:
        K.bolt(loc, n, 0.045, BOLT)

# ------------------------------------------------------------------ sagittal crest: a riveted ridge plate from the brow over to the occiput
crest_pts = []
for a in np.linspace(-0.95, 1.55, 18):
    loc, n = onto((0, -3 * math.cos(a), 3 * math.sin(a) + 0.3), (0, math.cos(a), -math.sin(a)))
    if loc is not None:
        crest_pts.append(loc + n * 0.05)
if len(crest_pts) > 3:
    cpath = K.smooth_path(crest_pts, 80)
    K.loft("crest", K.path_fn(cpath), lambda t: 0.085 * (0.55 + 0.45 * math.sin(math.pi * t)), 80, 10,
           profile=lambda th, t: (1.0, 0.55 + 0.5 * max(0.0, math.sin(th)) ** 3), mat=STEEL)
    for p in crest_pts[1:-1:2]:
        for s in (-1, 1):
            K.bolt(p + Vector((s * 0.08, 0, -0.01)), (s * 0.4, 0, 1), 0.022, BOLT)

# a patch plate bolted over an old breach on one side of the cranium (asymmetry)
loc, n = onto((-3, -0.15, 0.62), (1, 0, -0.1))
if loc is not None:
    patch = K.box("patch_plate", (1, 1, 1), loc + n * 0.02, mat=PLATE, bev=0.012)
    K.align(patch, n)
    patch.scale = (0.34, 0.26, 0.035)
    patch.rotation_euler.rotate_axis("Z", 0.35)
    for k in range(6):
        ang = 2 * math.pi * k / 6 + 0.35
        off = Vector((0, math.cos(ang) * 0.15, math.sin(ang) * 0.11))
        K.bolt(loc + n * 0.04 + off, n, 0.02, BOLT)

# ------------------------------------------------------------------ orbits: molten glow behind visor slats
for s in (-1, 1):
    bottom, n = onto((s * 0.31, -3, 0.07), (0, 1, 0))
    if bottom is None:
        continue
    glow_at = bottom + Vector((0, -0.03, 0))
    slit = K.box("eye_glow", (1, 1, 1), glow_at, mat=EYE, bev=0.015)
    slit.scale = (0.28, 0.03, 0.11)
    for k in (-1, 0, 1):
        bar = K.box("slat", (1, 1, 1), glow_at + Vector((0, -0.09, 0.07 * k)), mat=STEEL, bev=0.006)
        bar.scale = (0.4, 0.035, 0.03)
    K.weld("weld_slat", [glow_at + Vector((s * 0.2, -0.09, 0.1)), glow_at + Vector((s * 0.21, -0.09, -0.1))], 0.02, WELD)

# ------------------------------------------------------------------ nasal bridge plates + rebar teeth + glowing maw
nose, _ = onto((0, -3, -0.2), (0, 1, 0))
if nose is not None:
    for s in (-1, 1):
        a, b = nose + Vector((s * 0.15, -0.06, 0.16)), nose + Vector((s * 0.02, -0.05, -0.2))
        bar = K.box("nose_plate", (1, 1, 1), (a + b) / 2, mat=STEEL, bev=0.008)
        K.align(bar, b - a)
        bar.scale = (0.05, 0.035, (b - a).length)
for k in range(9):
    x = -0.28 + 0.07 * k
    loc, n = onto((x, -3, -0.5), (0, 1, 0))
    if loc is not None:
        K.box("tooth_up", (0.05, 0.05, 0.12 + 0.025 * ((k + 1) % 2)), loc + Vector((0, -0.02, -0.08)), mat=BOLT, bev=0.008)
K.box("maw_glow", (0.56, 0.04, 0.1), (0, -0.88, -0.63), mat=MAW, bev=0.01)
weld_line([((x, -3, -0.44), (0, 1, 0)) for x in np.linspace(-0.3, 0.3, 6)], 0.02)


# ------------------------------------------------------------------ the jaw (mandible, its own part: it grinds in the game)
def mandible(P):
    d = np.full(P.shape[:-1], 1e9)
    for s in (-1, 1):
        d = np.minimum(d, sd_capsule(P, (s * 0.7, -0.28, -0.22), (s * 0.62, -0.42, -0.74), 0.1))  # ramus
        d = smin(d, sd_capsule(P, (s * 0.62, -0.42, -0.74), (s * 0.16, -0.9, -0.86), 0.1), 0.08)  # body
    d = smin(d, sd_box(P, (0, -0.95, -0.86), (0.2, 0.1, 0.12), 0.06), 0.1)  # chin
    d = smax(d, -sd_box(P, (0, -0.35, -0.6), (0.5, 0.42, 0.12), 0.05), 0.04)  # tongue space
    return d


jaw = K.sdf_mesh("jaw", mandible, (-0.9, -1.15, -1.05), (0.9, -0.1, -0.1), 0.014, JAW)
for k in range(8):
    x = -0.24 + 0.068 * k
    K.box("tooth_low", (0.05, 0.05, 0.1 + 0.02 * (k % 2)), (x, -0.92 + 0.12 * abs(x), -0.72), mat=JAW, bev=0.008)
for s in (-1, 1):
    K.bolt((s * 0.79, -0.28, -0.24), (s, 0, 0), 0.05, BOLT)  # hinge
    top = Vector((s * 0.86, -0.12, 0.2))
    bot = Vector((s * 0.72, -0.6, -0.64))
    d = bot - top
    body = K.cyl("piston", 0.07, d.length * 0.56, top + d * 0.28, mat=STEEL, verts=20, bev=0.01)
    K.align(body, d)
    rod = K.cyl("rod", 0.03, d.length * 0.5, top + d * 0.72, mat=BOLT, verts=14)
    K.align(rod, d)
    for e, r in ((top, 0.055), (bot, 0.05)):
        K.ball("pin", r, e, BOLT)
    K.box("bracket", (0.07, 0.16, 0.12), top + Vector((-s * 0.05, 0.02, 0.02)), mat=STEEL, bev=0.012)

# ------------------------------------------------------------------ back: bolted spine plate, cables, exhaust stacks
spine_pts = []
for z in np.linspace(0.95, -0.7, 14):
    loc, n = onto((0, 3, z), (0, -1, 0))
    if loc is not None:
        spine_pts.append(loc + n * 0.05)
if len(spine_pts) > 3:
    path = K.smooth_path(spine_pts, 60)
    K.loft("spine", K.path_fn(path), lambda t: 0.1 - 0.02 * t, 60, 8,
           profile=lambda th, t: (1.0, 0.45 + 0.4 * max(0.0, math.sin(th)) ** 4), mat=STEEL)
    for p in spine_pts[::2]:
        for s in (-1, 1):
            K.bolt(p + Vector((s * 0.085, 0.02, 0)), (s * 0.3, 1, 0), 0.024, BOLT)
for k, x0 in enumerate((-0.3, -0.15, 0.15, 0.3)):
    start, n = onto((x0, 3, -0.15 + 0.06 * k), (0, -1, 0))
    if start is None:
        continue
    mid = Vector((x0 * 1.35, start.y + 0.3, -0.55))
    end = Vector((x0 * 0.9, 0.55, -0.95))
    K.tube("cable", K.smooth_path([start, mid, end], 20), 0.034 - 0.005 * (k % 2), RUBBER)
    K.box("clamp", (0.1, 0.06, 0.06), start, mat=BOLT, bev=0.01)
for s in (-1, 1):
    base, n = onto((s * 0.34, 3, 0.62), (0, -1, -0.2))
    if base is None:
        continue
    tip = base + Vector((s * 0.16, 0.5, 0.5))
    st = K.loft("exhaust", lambda t, b=base, e=tip: b.lerp(e, t), lambda t: 0.085 + 0.04 * t ** 6, 30, 20, mat=HOT, cap=False)
    K.solidify(st, 0.016)
    K.box("exhaust_collar", (0.17, 0.17, 0.06), base + (tip - base) * 0.12, mat=STEEL, bev=0.015)
    K.weld("weld_ex", [base + Vector((-0.1, 0, 0.02)), base + Vector((0, -0.02, 0.08)), base + Vector((0.1, 0, 0.02))], 0.022, WELD)

# ------------------------------------------------------------------ gorget: segmented rings at the neck
for k in range(3):
    z1, z0 = -0.7 - 0.11 * k, -0.84 - 0.11 * k
    rad = lambda z, k=k: (0.62 + 0.04 * k, 0.74 + 0.04 * k)  # noqa: E731
    o = K.lathe("gorget", rad, z1, z0, 160, 8, 3.0, mat=PLATE, cap=False)
    o.location.y = 0.08
    K.solidify(o, 0.03)
    K.bevel(o, 0.01, 2)
    for a in range(0, 360, 40):
        th = math.radians(a + 20 * k)
        p, n = K.surface_point(rad, 3.0, th, (z0 + z1) / 2, 0.02)
        K.bolt(p + Vector((0, 0.08, 0)), n, 0.02, BOLT)

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

# ------------------------------------------------------------------ preview effects: sparks under the jaw
SPARK = K.glow("spark", (1.0, 0.55, 0.12), 30.0)
random.seed(3)
for i in range(18):
    p = Vector((random.uniform(-0.3, 0.3), random.uniform(-1.1, -0.8), random.uniform(-1.7, -0.95)))
    K.ball("spark", 0.008, p, SPARK, (1, 1, 2.5), 6)
K.stage(head=False)
K.shoot_views("iron_reaper")
print("ok")

# Cracked Mirror mask (elite / mob mask 18, diary/DECISIONS_SKINS.md B18, plan in diary/MASK_PLANS_DROPS.md): a blank
# mirror face (base 9) shattered from one blow, set in an antique mirror's ornate frame, over a black velvet hood.
# FRONT = shards stepped at slight angles round an impact point on the brow, dark cracks, a few shards missing, the
# oval frame with a scrollwork crest and side finials; SIDE = the frame proud of the face, the shard steps; BACK = the
# hood gathered into a knot with a tassel.
# Run: python3 tools/blender/mask_cracked_mirror.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py cracked_mirror
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(181)

MIRROR = K.steel("mirror", (0.82, 0.83, 0.85), heat=0.0, rust=0.0, rough=0.04)
GILT = K.steel("gilt", (0.62, 0.45, 0.18), heat=0.0, rust=0.35, rough=0.3)
VELVET = K.simple("velvet", (0.011, 0.008, 0.013), 0.95)
DARK = K.simple("under_glass", (0.015, 0.015, 0.018), 0.6)

IMPACT = np.array([0.16, 0.62])  # (x, z) of the blow on the brow
FACE_C, FACE_R = (0, -0.2, 0.25), (0.66, 0.8, 0.95)  # fills the frame's oval


def hsh(a, b):
    """A repeatable pseudo-random 0..1 per shard index."""
    return np.mod(np.sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


def shard_cells(P):
    """Shard index (angle bin, ring bin) round the impact, with crack distances (to the bin edges)."""
    q = np.stack([P[..., 0] - IMPACT[0], P[..., 2] - IMPACT[1]], -1)
    r = np.linalg.norm(q, axis=-1) + 1e-6
    ang = np.arctan2(q[..., 1], q[..., 0])
    nb = 9
    warp = 0.18 * np.sin(r * 9.0)  # cracks wander a little as they run out
    a = (ang + warp) / (2 * math.pi) * nb
    ab = np.floor(a)
    rings = np.array([0.0, 0.1, 0.32, 0.65, 9.0])  # big shards
    rb = np.searchsorted(rings, r) - 1
    rb = np.clip(rb, 0, len(rings) - 2)
    ring_r = rings[rb + 1] + 0.05 * np.sin(ab * 2.3)  # rings bend per shard
    d_ang = np.minimum(a - ab, ab + 1 - a) * (2 * math.pi / nb) * r
    d_ring = np.minimum(np.abs(r - rings[rb]), np.abs(r - ring_r))
    return ab, rb, np.minimum(d_ang, d_ring), r


def face(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    fo = sd_ellipsoid(P, FACE_C, FACE_R)
    fo = smax(fo, P @ np.array([0, -0.96, 0.28]) - 0.86, 0.2)  # a soft face plane
    fo = smin(fo, sd_capsule(P, (0, -0.96, 0.36), (0, -0.99, 0.16), 0.03), 0.14)  # only a faint nose ridge: a blank mannequin face
    ab, rb, crack, r = shard_cells(P)
    h = hsh(ab, rb)
    off = (h - 0.5) * 0.008 * np.clip(r * 3, 0, 1)  # each shard sits a little in or out
    tilt = (hsh(ab + 3.1, rb) - 0.5) * 0.018 * ((x - IMPACT[0]) * np.cos(ab) + (z - IMPACT[1]) * np.sin(ab))  # and tips
    missing = (h > 0.8) & (rb >= 1) & (rb <= 2)
    d = fo - off - tilt + missing * 0.05  # missing shards: pushed in, the dark beneath shows
    d = d + 0.01 * np.exp(-(crack / 0.004) ** 2) * (r > 0.03)  # crisp crack lines cut in
    d = d + 0.03 * np.exp(-(r / 0.05) ** 2)  # the pit where it was struck
    d = smax(d, y + 0.28, 0.04)  # a face plate, open behind
    d = smax(d, -(fo + 0.06), 0.02)
    return d


face_o = K.sdf_mesh("face", face, (-0.75, -1.15, -0.75), (0.75, -0.2, 1.25), 0.007, MIRROR)
K.ball("under_glass", 0.6, (0, -0.42, 0.25), DARK, (0.95, 0.6, 1.3), 24)  # dark behind the missing shards


def hood(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)
    head = sd_ellipsoid(P, (0, 0.08, 0.36), (0.74, 0.88, 0.84))
    knot = sd_ellipsoid(P, (0, 1.0, 0.36), (0.22, 0.2, 0.22))  # gathered behind into a big knot
    kq = np.arctan2(x, z - 0.36)  # angle round the knot, seen from behind
    pleat = 0.05 * np.abs(np.sin(kq * 6.0)) * np.clip((y - 0.1) / 0.8, 0, 1)  # pleats radiating from the knot
    folds = pleat + 0.02 * np.sin(th * 9.0 - z * 2.0)
    outer = smin(head - 0.07 - folds, knot, 0.2)
    neck = sd_capsule(P, (0, 0.08, -0.1), (0, 0.1, -0.9), 0.5)
    outer = smin(outer, neck - 0.02, 0.18)
    d = np.abs(outer) - 0.035
    d = smax(d, -(z + 0.96), 0.03)
    d = smax(d, -(y + 0.3), 0.05)  # open in front, behind the frame
    return d


hood_o = K.sdf_mesh("hood", hood, (-0.95, -0.5, -1.0), (0.95, 1.35, 1.35), 0.012, VELVET)

# the ornate oval frame round the face
RING = []
for a in np.linspace(0, 2 * math.pi, 73):
    px = 0.64 * math.sin(a); pz = 0.25 + 0.9 * math.cos(a)
    ok, loc, n, i = face_o.ray_cast(Vector((px * 0.97, -2.0, pz * 0.97 + 0.0075)), Vector((0, 1, 0)))
    yy = loc.y if ok else -0.45
    RING.append(Vector((px, yy + 0.02, pz)))
K.tube("frame_outer", RING, 0.068, GILT, res=3)
K.tube("frame_bead", [p + (p - Vector((0, p.y, 0.25))).normalized() * 0.09 for p in RING], 0.026, GILT, res=2)
twist = []  # a twisted rope of gilt wound round the frame
for k in range(len(RING) * 6):
    t = k / (len(RING) * 6 - 1)
    a = t * 2 * math.pi
    c = Vector((0.64 * math.sin(a), 0, 0.25 + 0.9 * math.cos(a)))
    idx = min(int(t * (len(RING) - 1)), len(RING) - 1)
    c.y = RING[idx].y
    out = (c - Vector((0, c.y, 0.25))).normalized()
    ph = t * 2 * math.pi * 60
    twist.append(c + out * 0.075 * math.cos(ph) + Vector((0, -0.075 * math.sin(ph), 0)))
K.tube("frame_twist", twist, 0.016, GILT, res=2)
for j in range(8):  # rosettes round the frame
    p = RING[int(j * 9 + 4.5) % len(RING)]
    out = (p - Vector((0, p.y, 0.25))).normalized()
    c = p + out * 0.02 + Vector((0, -0.07, 0))
    K.ball("rosette", 0.04, tuple(c), GILT, (1, 0.6, 1), 12)
    for q in range(5):
        a = q * 2 * math.pi / 5
        K.ball("rosette_petal", 0.026, tuple(c + Vector((0.045 * math.cos(a), 0.01, 0.045 * math.sin(a)))), GILT, (1, 0.5, 1), 8)
# the scrollwork crest on top: two curls rolling out from a central finial
top = RING[0]
for s in (-1, 1):
    pts = []
    for k in range(40):
        t = k / 39
        ang = t * 2.6 * math.pi
        rad = 0.22 * (1 - t) + 0.03
        pts.append(top + Vector((s * (0.1 + 0.26 * t + rad * math.sin(ang) * 0.55), 0.0, 0.16 + rad * math.cos(ang) * 0.65 - 0.06 * t)))
    K.tube("crest_scroll", pts, 0.04, GILT, res=2, taper=lambda u: 1.0 - 0.5 * u)
K.ball("crest_finial", 0.09, tuple(top + Vector((0, 0, 0.4))), GILT, (1, 1, 1.3), 16)
for q in range(7):  # a shell fan behind the finial
    a = math.radians(-60 + 20 * q)
    K.loft("crest_shell", lambda t, a=a: top + Vector((0, 0.03, 0.06)) + Vector((math.sin(a), 0, math.cos(a))) * (0.32 * t), lambda t: 0.035 * math.sin(math.pi * min(t * 1.1, 1)) + 0.008, 10, 8, mat=GILT,
           profile=lambda th, t: (1.0, 0.35))
K.loft("crest_stem", lambda t: top + Vector((0, 0, 0.05 + 0.28 * t)), lambda t: 0.045 * (1 - 0.4 * t), 6, 12, mat=GILT)
# side finials at the temples and a small drop at the chin
for s in (-1, 1):
    p = RING[18] if s > 0 else RING[54]
    K.ball("side_finial", 0.05, tuple(p + Vector((s * 0.06, 0, 0))), GILT, (1.3, 1, 1), 12)
    K.loft("side_scroll", lambda t, p=p, s=s: p + Vector((s * (0.04 + 0.08 * t), 0, 0.12 * math.sin(t * math.pi))), lambda t: 0.02, 10, 8, mat=GILT)
bot = RING[36]
K.ball("chin_drop", 0.045, tuple(bot + Vector((0, 0, -0.07))), GILT, (1, 1, 1.4), 12)

# the tassel hanging from the knot
ok, loc, n, i = hood_o.ray_cast(Vector((0, 3.0, 0.3)), Vector((0, -1, 0)))
if ok:
    k0 = loc + n * 0.02
    K.tube("tassel_cord", [k0, k0 + Vector((0, 0.05, -0.12)), k0 + Vector((0, 0.06, -0.3))], 0.015, GILT, res=2)
    K.loft("tassel", lambda t: k0 + Vector((0, 0.06, -0.3 - 0.24 * t)), lambda t: 0.05 + 0.04 * t, 8, 12, mat=GILT)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("cracked_mirror")
print("ok")

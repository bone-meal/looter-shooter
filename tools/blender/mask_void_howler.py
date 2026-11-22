# Void Howler mask (boss mask 8, diary/DECISIONS_SKINS.md A8 + diary/MASK_PROCESS.md section 5): an armoured wolf
# hybrid (base 8): a long snarling wolf head cased in dark segmented plates, bared metal teeth, ears swept back like
# blades, dark fur ruffs between the plates. Silhouette plan: FRONT = the muzzle with bared metal teeth + swept ears;
# SIDE = the long muzzle, ear spikes, plate segments; BACK = plate ridges down the skull (+ runes orbiting: game).
# Behaviour: dark metal with purple light in the plate seams (fxR_), pure black void eyes ringed with purple (fxG_),
# void fog from the mouth, runes orbiting slowly (game: a turning ring of glyphs).
# Run: python3 tools/blender/mask_void_howler.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py void_howler
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(83)

PLATE = K.steel("void_plate", base=(0.075, 0.072, 0.085), heat=0.0, rust=0.0, rough=0.34)
TEETH = K.steel("teeth_steel", base=(0.42, 0.43, 0.45), heat=0.0, rust=0.0, rough=0.25)
GUM = K.simple("gum", (0.05, 0.01, 0.025), 0.6)
VOID = K.simple("void_eye", (0.002, 0.002, 0.003), 0.04)
VOID.node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 1.0
PURPLE = K.glow("fxR_seam", (0.62, 0.15, 1.0), 10.0, base=(0.08, 0.0, 0.15))
RING = K.glow("fxG_voidring", (0.75, 0.3, 1.0), 9.0, base=(0.1, 0.0, 0.18))


def fur(name):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    w = N.new("ShaderNodeTexWave"); w.inputs["Scale"].default_value = 60.0; w.inputs["Distortion"].default_value = 6.0
    w.wave_type = "BANDS"; w.bands_direction = "Z"
    L.new(tc.outputs["Object"], w.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(w.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (0.02, 0.02, 0.025, 1); mx.inputs[7].default_value = (0.09, 0.085, 0.1, 1)
    L.new(mx.outputs[2], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6; bump.inputs["Distance"].default_value = 0.006
    L.new(w.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


FUR = fur("dark_fur")

# the muzzle (upper jaw) and the lower jaw: wedges along axes from the cheeks to the nose; the snarl = the gap between
M0 = np.array([0.0, -0.6, 0.22]); M1 = np.array([0.0, -1.6, -0.02])   # upper jaw axis
R0 = (0.32, 0.24); R1 = (0.15, 0.12)                                   # its half width / height at each end
L0 = np.array([0.0, -0.6, -0.16]); L1 = np.array([0.0, -1.42, -0.31])  # lower jaw axis
Q0 = (0.27, 0.12); Q1 = (0.11, 0.065)


def along(P, a, b):
    ax = b - a
    return np.clip(((P - a) @ ax) / (ax @ ax), 0.0, 1.0)


def wedge(P, a, b, r0, r1, p=2.6):
    """A tapering rounded-box tube from a to b (cross-section a superellipse), capped at b."""
    t = along(P, a, b)
    c = a + (b - a) * t[..., None]
    rx = r0[0] + (r1[0] - r0[0]) * t
    rz = r0[1] + (r1[1] - r0[1]) * t
    q = P - c
    se = (np.abs(q[..., 0] / rx) ** p + np.abs(q[..., 2] / rz) ** p) ** (1.0 / p)
    d = (se - 1.0) * np.minimum(rx, rz)
    ax = (b - a) / np.linalg.norm(b - a)
    d = np.maximum(d, -((P - a) @ ax) - 0.05)  # capped behind its start too (else the tube ran out of the back of the skull)
    return np.maximum(d, (P - b) @ ax - 0.02)


def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.0, 0.25), (0.76, 0.9, 0.84))  # skull
    d = smax(d, y - 0.85, 0.2)
    d = smin(d, wedge(P, M0, M1, R0, R1), 0.14)  # the upper jaw / muzzle: flat-topped, tapering
    d = smin(d, sd_ellipsoid(P, (0, -1.63, 0.07), (0.11, 0.085, 0.075)), 0.04)  # nose, a little over the tip
    for s in (-1, 1):
        d = smax(d, -sd_ellipsoid(P, (s * 0.05, -1.71, 0.05), (0.028, 0.035, 0.022)), 0.01)  # nostrils
        d = smin(d, sd_capsule(P, (s * 0.12, -0.8, 0.48), (s * 0.5, -0.64, 0.6), 0.085), 0.07)  # heavy brow plates
        d = smax(d, -sd_ellipsoid(P, (s * 0.32, -0.82, 0.37), (0.15, 0.1, 0.09)), 0.04)  # eye socket
        d = smin(d, sd_ellipsoid(P, (s * 0.44, -0.52, -0.02), (0.28, 0.3, 0.26)), 0.15)  # cheek / jaw muscle
    d = smin(d, wedge(P, L0, L1, Q0, Q1), 0.05)  # lower jaw, hanging open at the front
    # plate seams across the muzzle (overlapping toward the nose)
    ax = (M1 - M0) / np.linalg.norm(M1 - M0)
    for tt in (0.38, 0.6, 0.8):
        pd = (P - (M0 + (M1 - M0) * tt)) @ ax
        w = np.clip((z - (M0[2] + (M1[2] - M0[2]) * tt - 0.1)) / 0.06, 0.0, 1.0)  # upper jaw only
        d = d + 0.011 * w * np.exp(-(pd / 0.012) ** 2) - 0.014 * w * 0.5 * (1.0 + np.tanh(pd / 0.005))
    d = groove(d, np.where(y < 0.1, y + 0.5 - 0.15 * np.clip(0.5 - z, 0.0, 1.5), 9.0), 0.012, 0.012, -0.016)  # face plate's rim
    for zz in (0.75, 0.45, 0.1):  # plate bands round the back of the skull
        w = np.clip((y - 0.1) / 0.3, 0.0, 1.0)
        pd = z - zz
        d = d + 0.011 * w * np.exp(-(pd / 0.012) ** 2) - 0.014 * w * 0.5 * (1.0 + np.tanh(pd / 0.005))
    for k in range(5):  # a segmented crest of plates down the back of the skull (each overlapping the next)
        a0 = 0.55 + 0.34 * k
        a1 = a0 + 0.3
        p0 = (0.0, 0.02 + 0.93 * math.sin(a0), 0.25 + 0.87 * math.cos(a0))
        p1 = (0.0, 0.02 + 0.97 * math.sin(a1), 0.25 + 0.91 * math.cos(a1))
        d = smin(d, sd_capsule(P, p0, p1, 0.075 - 0.006 * k), 0.025)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.5), 0.2)  # neck to the collar
    d = smax(d, -(z + 0.97), 0.03)
    return d


def mouth_sd(P):
    return smax(sd_capsule(P, (0, -0.75, -0.05), (0, -1.45, -0.2), 0.11), -(P[..., 1] + 0.7), 0.02)


face = K.sdf_mesh("head", head, (-0.95, -1.85, -1.0), (0.95, 1.05, 1.2), 0.012, PLATE)
face.data.materials.append(GUM)
for poly in face.data.polygons:  # inside the snarl and the jaws' inner faces: dark gums
    c = poly.center
    if mouth_sd(np.array([[c.x, c.y, c.z]]))[0] < 0.0 and abs(poly.normal.z) > 0.4:
        poly.material_index = 1
K.ball("mouth_inside", 0.2, (0, -1.0, -0.12), GUM, (0.9, 2.4, 0.5), 16)


def on_face(o, dvec):
    return K.ray_onto(face, Vector(o), Vector(dvec))


# purple light in the muzzle seams: rings of points around the muzzle at each seam
ax = Vector(tuple(M1 - M0)).normalized()
for tt in (0.38, 0.6, 0.8):
    c = Vector(tuple(M0 + (M1 - M0) * tt))
    pts = []
    for a in np.linspace(-1.1, 1.1, 15):  # over the top of the muzzle, side to side
        dvec = Vector((math.sin(a), 0.0, math.cos(a)))
        dvec = (dvec - ax * dvec.dot(ax)).normalized()
        loc, n = on_face(c + dvec * 1.2, -dvec)
        if loc:
            pts.append(loc - n * 0.004 - ax * 0.002)
    if len(pts) > 3:
        K.tube("seam_glow", pts, 0.009, PURPLE, res=2)

# metal teeth: the upper row hangs from the muzzle's lower edge, the lower row stands on the jaw; big canines
def jaw_at(a, b, r0, r1, t):
    c = a + (b - a) * t
    return c, r0[0] + (r1[0] - r0[0]) * t, r0[1] + (r1[1] - r0[1]) * t


for s in (-1, 1):
    for k in range(8):
        t = 0.3 + 0.66 * k / 7
        c, rx, rz = jaw_at(M0, M1, R0, R1, t)
        canine = k == 6
        L = 0.18 if canine else 0.06 + 0.03 * t
        root = Vector((s * (rx * 0.82), float(c[1]), float(c[2] - rz * 0.8)))
        K.loft("tooth", lambda tt, r=root, L=L: r + Vector((0, 0, -L * tt)),
               lambda tt, cn=canine: (0.042 if cn else 0.026) * (1 - tt) ** 0.9 + 0.003, 8, 8, mat=TEETH)
        c2, rx2, rz2 = jaw_at(L0, L1, Q0, Q1, min(1.0, t * 1.02))
        if t < 0.95:
            root2 = Vector((s * (rx2 * 0.8), float(c2[1]), float(c2[2] + rz2 * 0.75)))
            L2 = 0.13 if k == 5 else 0.05 + 0.02 * t
            K.loft("tooth", lambda tt, r=root2, L=L2: r + Vector((0, 0, L * tt)),
                   lambda tt, cn=(k == 5): (0.036 if cn else 0.022) * (1 - tt) ** 0.9 + 0.003, 8, 8, mat=TEETH)

# void eyes: black glass with a thin purple ring
for s in (-1, 1):
    c = Vector((s * 0.32, -0.85, 0.37))
    eye = K.ball("void_eye", 0.085, c, VOID, (1.25, 0.8, 0.7), 20)
    n = Vector((s * 0.35, -1.0, 0.0)).normalized()
    ring = [c + n * 0.035 + Matrix.Rotation(a, 3, n) @ (Vector((0, 0, 1)) - n * n.z).normalized() * 0.075 for a in np.linspace(0, 2 * math.pi, 33)]
    K.tube("eye_ring", ring, 0.008, RING, res=2)

# ears: blades swept back, a purple line inside each
for s in (-1, 1):
    a0 = Vector((s * 0.42, -0.25, 0.8)); a1 = Vector((s * 0.6, 0.2, 1.25)); a2 = Vector((s * 0.66, 0.78, 1.5))

    def ep(t, a0=a0, a1=a1, a2=a2):
        return a0 * (1 - t) ** 2 + a1 * 2 * t * (1 - t) + a2 * t * t
    K.loft("ear", ep, lambda t: 0.2 * (1 - t) ** 0.9 + 0.008, 40, 10, profile=lambda th, t: (0.32, 1.0), mat=PLATE)
    K.tube("ear_line", [ep(t) + Vector((-s * 0.05, 0, 0)) for t in np.linspace(0.05, 0.7, 12)], 0.008, PURPLE, res=2,
           taper=lambda t: 1.0 - 0.6 * t)

# purple light along the back crest's seams
for k in range(5):
    a = 0.55 + 0.34 * k + 0.17
    p0 = Vector((0.0, 0.02 + 0.97 * math.sin(a), 0.25 + 0.91 * math.cos(a)))
    tang = Vector((0, math.cos(a), -math.sin(a)))
    K.tube("ridge_glow", [p0 + tang * 0.02 + Vector((sx, 0, 0)) for sx in (-0.07, 0.0, 0.07)], 0.006, PURPLE, res=2)

# dark fur ruffs at the cheeks and under the jaw, between the plates
random.seed(3)
for s in (-1, 1):
    for k in range(14):
        a = random.uniform(-0.6, 0.9)
        o = Vector((s * 1.2, -0.45 + random.uniform(-0.25, 0.3), -0.15 + random.uniform(-0.35, 0.2)))
        loc, n = on_face(o, (-s, 0, 0))
        if loc is None:
            continue
        dirv = (n * 0.7 + Vector((0, 0.15, -0.9))).normalized()  # hanging down (seen from behind, backward tufts showed their open ends)
        L = random.uniform(0.14, 0.24)
        K.loft("fur", lambda t, l=loc - n * 0.05, d=dirv, L=L: l + d * L * t + Vector((0, 0, -0.06 * t * t)),
               lambda t: 0.06 * (1 - t) ** 1.3 + 0.004, 10, 6, mat=FUR)

if K.GAME:
    raise SystemExit(0)

# preview only: a ring of runes floating round the head (the game's ring turns)
for k in range(10):
    a = k * 2 * math.pi / 10
    p = Vector((1.25 * math.sin(a), 0.1 + 1.25 * math.cos(a), 0.55 + 0.08 * math.sin(3 * a)))
    K.box("rune", (0.11, 0.008, 0.16), p, rot=(0, 0, -a), mat=PURPLE, bev=0.003)
K.stage(head=False)
K.shoot_views("void_howler")
print("ok")

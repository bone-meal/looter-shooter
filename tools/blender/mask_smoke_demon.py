# Smoke Demon mask (elite 24, diary/DECISIONS_SKINS.md B24, plan in diary/MASK_PLANS_DROPS.md): a blank face of black
# burnt stone with smoke pouring out of it (featureless, base 9). FRONT = soft planes, no nose or lips, only two deep
# tear-shaped eye hollows and a ragged mouth slit with an ember far inside each (fxR_), hairline ember cracks running
# out from them (fxG_). SIDE = two ridged HORNS sweeping back from the temples and curling up. BACK = FROZEN SMOKE:
# thick curling tendrils of smoke-stone rising off the back of the skull and pouring down to the collar in billows.
# Run: python3 tools/blender/mask_smoke_demon.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py smoke_demon
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(241)


def charcoal(name, base=(0.009, 0.0085, 0.009), sheen=0.32):  # very dark: the game sun lifts it to slate
    """Burnt black stone: matte, a faint glassy sheen on high points, soot in the hollows, fine pitting."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 9.0; nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (*base, 1); mx.inputs[7].default_value = (base[0] * 2.2, base[1] * 2.0, base[2] * 2.0, 1)
    c, ao = K._ao_mix(N, L, mx.outputs[2], (0.003, 0.003, 0.003), 0.08)
    L.new(c, b.inputs["Base Color"])
    geo = N.new("ShaderNodeNewGeometry")
    hi = N.new("ShaderNodeMapRange"); hi.inputs["From Min"].default_value = 0.5; hi.inputs["From Max"].default_value = 0.58
    hi.inputs["To Min"].default_value = 0.75; hi.inputs["To Max"].default_value = sheen
    L.new(geo.outputs["Pointiness"], hi.inputs["Value"]); L.new(hi.outputs["Result"], b.inputs["Roughness"])
    pits = N.new("ShaderNodeTexVoronoi"); pits.inputs["Scale"].default_value = 70.0
    L.new(tc.outputs["Object"], pits.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.3; bump.inputs["Distance"].default_value = 0.003
    L.new(pits.outputs["Distance"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


STONE = charcoal("charcoal")
SMOKE = charcoal("smoke_stone", (0.012, 0.012, 0.014), 0.45)
HORN = charcoal("horn", (0.02, 0.016, 0.013), 0.4)
EMBER = K.glow("fxR_ember", (1.0, 0.35, 0.08), 9.0, base=(0.3, 0.06, 0.0))
CRACK = K.glow("fxG_crack", (1.0, 0.3, 0.06), 6.0, base=(0.25, 0.05, 0.0))
DARK = K.simple("hollow", (0.002, 0.002, 0.002), 0.95)

EYES = [(s * 0.27, 0.26) for s in (-1, 1)]


def openings(P):
    """The three openings, seen from the front: tear-shaped eyes (the point down-out) and a ragged mouth slit."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = 9.0
    for s in (-1, 1):
        q0 = (x - s * 0.27) * math.cos(0.35 * s) + (z - 0.26) * math.sin(0.35 * s)
        q1 = -(x - s * 0.27) * math.sin(0.35 * s) + (z - 0.26) * math.cos(0.35 * s)
        tear = np.sqrt((q0 / 0.13) ** 2 + (np.maximum(q1, 0) / 0.1) ** 2 + (np.minimum(q1, 0) / 0.22) ** 2) - 1.0
        d = np.minimum(d, tear * 0.09)
    mouth = np.sqrt((x / 0.3) ** 2 + ((z + 0.22 + 0.03 * (x / 0.3) ** 2) / (0.05 + 0.012 * np.sin(x * 13.0 + 1.0))) ** 2) - 1.0  # a long ragged slit, drooping
    return np.minimum(d, mouth * 0.05)


def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.2), (0.78, 0.92, 0.84))  # cranium
    d = smax(d, y - 0.84, 0.2)
    d = smin(d, sd_ellipsoid(P, (0, -0.36, -0.28), (0.58, 0.64, 0.52)), 0.25)  # lower face and jaw
    d = smin(d, sd_ellipsoid(P, (0, -0.78, -0.5), (0.2, 0.17, 0.15)), 0.14)  # chin
    d = smax(d, -y - 0.98, 0.2)  # a broad soft front plane
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.04, -0.99, 0.36), (s * 0.34, -0.9, 0.48), 0.045), 0.08)  # a scowling V brow ridge (ends inside the face: at 0.44 it stuck out as a bar)
        d = smax(d, -sd_capsule(P, (s * 0.04, -1.05, 0.3), (s * 0.34, -0.96, 0.42), 0.05), 0.02)  # undercut under it
        d = smin(d, sd_ellipsoid(P, (s * 0.42, -0.76, 0.02), (0.2, 0.14, 0.12)), 0.08)  # cheekbone
        d = smax(d, (P @ (np.array([s * 0.55, -0.6, -0.3]) / np.linalg.norm([0.55, 0.6, 0.3]))) - 0.74, 0.03)  # a cheek facet planed off
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.42, 0.36), (0.12, 0.2, 0.16)), 0.12)  # temple
    d = smin(d, sd_capsule(P, (0, -0.97, 0.75), (0, -1.03, 0.4), 0.03), 0.04)  # a ridge down the forehead into the brow's V
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.5), 0.2)  # neck to the collar
    d = smax(d, -(z + 0.98), 0.03)
    # the openings: deep hollows cut straight back
    hollow = np.maximum(openings(P), y + 0.42)  # only at the front, deep
    d = smax(d, -hollow, 0.012)
    # hairline cracks running out from the openings (grooves; ember sheets in them)
    d = groove(d, crack_field(P), 0.014, 0.008, 0.0)
    return d


CRACKS = []  # polylines in the front (x, z) plane
random.seed(7)
for (sx, sz, ang) in ((0.34, 0.18, -0.9), (0.2, 0.36, 1.9), (-0.36, 0.2, -2.3), (-0.18, 0.37, 1.2), (0.2, -0.22, -0.6), (-0.22, -0.24, -2.5), (0.36, 0.3, 0.4)):
    pts = [(sx, sz)]
    a = ang
    for k in range(6):
        a += random.uniform(-0.6, 0.6)
        x0, z0 = pts[-1]
        pts.append((x0 + 0.06 * math.cos(a), z0 + 0.06 * math.sin(a)))
    CRACKS.append(pts)


def crack_field(P):
    x, z = P[..., 0], P[..., 2]
    d = np.full(x.shape, 9.0)
    for pts in CRACKS:
        for (a, b) in zip(pts, pts[1:]):
            ax, az = a; bx, bz = b
            ex, ez = bx - ax, bz - az
            t = np.clip(((x - ax) * ex + (z - az) * ez) / (ex * ex + ez * ez), 0, 1)
            d = np.minimum(d, np.hypot(x - ax - t * ex, z - az - t * ez))
    return np.where(P[..., 1] < -0.45, d, 9.0)


face = K.sdf_mesh("face", head, (-0.85, -1.1, -1.02), (0.85, 1.0, 1.1), 0.009, STONE)


def crack_glow(P):
    """Thin ember sheets at the bottom of the cracks."""
    sk = head_plain(P)
    return np.maximum(crack_field(P) - 0.004, np.abs(sk + 0.01) - 0.008)


def head_plain(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.2), (0.78, 0.92, 0.84))
    d = smax(d, y - 0.84, 0.2)
    d = smin(d, sd_ellipsoid(P, (0, -0.36, -0.28), (0.58, 0.64, 0.52)), 0.25)
    d = smin(d, sd_ellipsoid(P, (0, -0.78, -0.5), (0.2, 0.17, 0.15)), 0.14)
    d = smax(d, -y - 0.98, 0.2)
    for s in (-1, 1):
        d = smin(d, sd_ellipsoid(P, (s * 0.3, -0.86, 0.42), (0.26, 0.12, 0.08)), 0.12)
        d = smin(d, sd_ellipsoid(P, (s * 0.42, -0.76, 0.02), (0.2, 0.14, 0.12)), 0.12)
    return d


K.sdf_mesh("cracks", crack_glow, (-0.7, -1.1, -0.5), (0.7, -0.45, 0.8), 0.005, CRACK)

# deep inside each opening: darkness and an ember
for (ex, ez) in EYES:
    K.ball("hollow_dark", 0.17, (ex, -0.5, ez - 0.03), DARK, (1.0, 0.9, 1.4), 16)
    K.ball("ember", 0.042, (ex, -0.62, ez - 0.05), EMBER, (1.0, 0.8, 1.3), 14)  # inside the hollow, ringed by dark (bigger / nearer read as cartoon eyes)
K.ball("mouth_dark", 0.22, (0.0, -0.5, -0.22), DARK, (1.6, 0.8, 0.5), 16)
K.ball("mouth_ember", 0.04, (0.0, -0.62, -0.23), EMBER, (3.2, 0.8, 0.6), 14)

# ------------------------------------------------------------------ horns: ridged, sweeping back from the temples, curling up
for s in (-1, 1):
    root = Vector((s * 0.56, -0.38, 0.66))

    def horn_c(t, s=s, root=root):
        return root + Vector((s * (0.42 * t + 0.12 * math.sin(t * 2.2)), 1.4 * t, 0.25 * t - 0.4 * t * t + 1.2 * max(t - 0.5, 0) ** 1.5))
    K.loft("horn", horn_c, lambda t: 0.17 * (1 - t) ** 0.85 + 0.008, 90, 18, mat=HORN,
           profile=lambda th, t: (1.0 + 0.07 * math.sin(t * 60.0), 1.0 + 0.07 * math.sin(t * 60.0)))  # growth ridges


# ------------------------------------------------------------------ frozen smoke: curling tendrils pouring off the back
def billow(t, a, start, drop, curl, phase):
    """A plume's centre: rises a little off the skull, then pours down and out, curling at its end."""
    side = Vector((math.sin(a), math.cos(a), 0.0))
    p = start + side * (0.3 * t + 0.08 * math.sin(t * 4 + phase)) + Vector((0, 0, 0.18 * math.sin(t * math.pi) - drop * t * t))
    if t > 0.65:  # the end rolls over into a curl
        u = (t - 0.65) / 0.35
        p = p + side * (0.12 * math.sin(u * 3.5) * curl) + Vector((0, 0, 0.1 * (1 - math.cos(u * 3.5))))
    return p


random.seed(24)
SPHERES = []  # (centre, radius): the plumes as chains of billows merged into one mass
PLUMES = [(-0.55, 0.62, "down"), (-0.25, 0.72, "down"), (0.0, 0.8, "down"), (0.25, 0.72, "down"), (0.55, 0.62, "down"),
          (0.85, 0.35, "down"), (-0.85, 0.35, "down"), (-0.3, 0.98, "up"), (0.3, 0.98, "up"), (0.0, 1.02, "up")]
for k, (a, zs, kind) in enumerate(PLUMES):
    ok, loc, n, j = face.ray_cast(Vector((2.5 * math.sin(a), 2.5 * math.cos(a), zs)), Vector((-math.sin(a), -math.cos(a), 0)).normalized())
    if not ok:
        continue
    start = loc - n * 0.12  # rooted well inside the skull: no holes between the plumes
    r0 = 0.14 + 0.03 * random.random()
    curl = random.choice((-1, 1))
    side = Vector((math.sin(a), math.cos(a), 0.0))
    for i in range(34):
        t = 0.9 * i / 33  # stop before the curl's thin end (it left hanging beads)
        if kind == "down":
            c = billow(t, a, start, 1.05 + 0.25 * random.random(), curl, k * 1.3)
        else:  # rising off the crown, leaning back and rolling over at the top
            c = start + side * (0.45 * t * t) + Vector((0, 0, 0.55 * t - 0.25 * max(t - 0.6, 0) ** 1.4)) + side * (0.1 * math.sin(t * 6 + k))
        helix = Vector((math.cos(t * 9 + k), math.sin(t * 9 + k), 0.5 * math.sin(t * 7))) * (0.045 * t)  # twisting as it goes
        r = r0 * (1.0 - 0.5 * t) * (0.92 + 0.12 * math.sin(i * 1.7))
        SPHERES.append((np.array(c + helix), r))
print("SMOKE billows", len(SPHERES))


def smoke(P):
    d = np.full(P.shape[:-1], 9.0)
    for c, r in SPHERES:
        d = smin(d, np.linalg.norm(P - c, axis=-1) - r, 0.12)
    d = d + 0.025 * np.sin(P[..., 0] * 13 + P[..., 2] * 9 + np.sin(P[..., 1] * 7) * 2) * np.sin(P[..., 1] * 11 - P[..., 2] * 6)  # swirl ripples
    return smax(d, -(P[..., 2] + 0.98), 0.02)


K.sdf_mesh("smoke", smoke, (-1.1, -0.3, -1.02), (1.1, 1.6, 1.8), 0.014, SMOKE)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("smoke_demon")
print("ok")

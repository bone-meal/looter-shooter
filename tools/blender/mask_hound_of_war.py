# Hound of War mask (elite / mob mask 19, diary/DECISIONS_SKINS.md B19, plan in diary/MASK_PLANS_DROPS.md): a war
# dog's head (base 8) in short fur, a steel helmet strapped on, a bundle of military tags at its throat. FRONT = the
# long muzzle with a lip curled off the canines, tall ears (the left torn), goggles on the helmet brim, the tags;
# SIDE = the muzzle profile, the helmet and chin strap; BACK = the helmet's band, ears, a studded collar, scruff tufts.
# Run: python3 tools/blender/mask_hound_of_war.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py hound_of_war
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
SC = K.setup(191)
random.seed(19)


def dog_fur(name):
    """Short fur: tan with a darker saddle over the back of the head and a black muzzle; strands in the relief."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    geo = N.new("ShaderNodeNewGeometry")
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Position"], sep.inputs[0])
    # saddle: dark where y (back) is high and over the top; muzzle: dark where y < -1.15
    sd = N.new("ShaderNodeMapRange"); sd.inputs["From Min"].default_value = -0.1; sd.inputs["From Max"].default_value = 0.4
    L.new(sep.outputs[1], sd.inputs["Value"])
    mz = N.new("ShaderNodeMapRange"); mz.inputs["From Min"].default_value = -1.05; mz.inputs["From Max"].default_value = -1.3
    L.new(sep.outputs[1], mz.inputs["Value"])
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 4.0
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    dk = N.new("ShaderNodeMath"); dk.operation = "MAXIMUM"
    L.new(sd.outputs["Result"], dk.inputs[0]); L.new(mz.outputs["Result"], dk.inputs[1])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(dk.outputs[0], mx.inputs[0]); mx.inputs[6].default_value = (0.42, 0.25, 0.1, 1); mx.inputs[7].default_value = (0.025, 0.018, 0.014, 1)
    w = N.new("ShaderNodeTexWave"); w.inputs["Scale"].default_value = 70.0; w.inputs["Distortion"].default_value = 8.0
    w.wave_type = "BANDS"; w.bands_direction = "Z"
    L.new(tc.outputs["Object"], w.inputs["Vector"])
    c, ao = K._ao_mix(N, L, mx.outputs[2], (0.02, 0.012, 0.006), 0.07)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.5; bump.inputs["Distance"].default_value = 0.005
    L.new(w.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


FUR = dog_fur("dog_fur")
NOSE = K.simple("nose_leather", (0.015, 0.012, 0.012), 0.35)
GUM = K.simple("gums", (0.12, 0.03, 0.03), 0.5)
EAR_IN = K.simple("ear_inside", (0.26, 0.13, 0.1), 0.8)
TEETH = K.simple("teeth", (0.75, 0.7, 0.58), 0.4)
EYE = K.simple("eye_gloss", (0.06, 0.03, 0.01), 0.1)
HELM = K.steel("helmet_olive", (0.13, 0.14, 0.08), heat=0.0, rust=0.35, rough=0.6)
STEEL = K.steel("tag_steel", (0.7, 0.7, 0.66), heat=0.0, rust=0.15, rough=0.3)
STRAP = K.simple("webbing", (0.12, 0.11, 0.07), 0.9)
LEATHER = K.simple("collar_leather", (0.08, 0.045, 0.025), 0.6)
GLASS = K.simple("goggle_glass", (0.05, 0.07, 0.06), 0.1)

M0 = np.array([0.0, -0.55, 0.22]); M1 = np.array([0.0, -1.72, 0.0])  # long and narrow: a shepherd's muzzle
R0 = (0.28, 0.24); R1 = (0.1, 0.1)
L0 = np.array([0.0, -0.55, -0.12]); L1 = np.array([0.0, -1.6, -0.12])
Q0 = (0.22, 0.11); Q1 = (0.08, 0.05)


def along(P, a, b):
    ax = b - a
    return np.clip(((P - a) @ ax) / (ax @ ax), 0.0, 1.0)


def wedge(P, a, b, r0, r1, p=2.2):
    t = along(P, a, b)
    c = a + (b - a) * t[..., None]
    rx = r0[0] + (r1[0] - r0[0]) * t
    rz = r0[1] + (r1[1] - r0[1]) * t
    q = P - c
    se = (np.abs(q[..., 0] / rx) ** p + np.abs(q[..., 2] / rz) ** p) ** (1.0 / p)
    d = (se - 1.0) * np.minimum(rx, rz)
    ax = (b - a) / np.linalg.norm(b - a)
    d = np.maximum(d, -((P - a) @ ax) - 0.05)
    return np.maximum(d, (P - b) @ ax - 0.02)


def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.0, 0.25), (0.72, 0.86, 0.8))
    d = smax(d, y - 0.82, 0.2)
    d = smin(d, wedge(P, M0, M1, R0, R1), 0.16)  # the muzzle
    d = smin(d, wedge(P, L0, L1, Q0, Q1), 0.08)  # lower jaw, closed
    d = smin(d, sd_ellipsoid(P, (0, -1.74, 0.06), (0.085, 0.07, 0.06)), 0.04)  # nose pad
    for s in (-1, 1):
        d = smax(d, -sd_ellipsoid(P, (s * 0.04, -1.81, 0.05), (0.022, 0.03, 0.018)), 0.01)  # nostrils
        d = smin(d, sd_ellipsoid(P, (s * 0.3, -0.72, 0.42), (0.16, 0.12, 0.09)), 0.1)  # brow over each eye
        d = smax(d, -sd_ellipsoid(P, (s * 0.3, -0.8, 0.33), (0.1, 0.08, 0.065)), 0.03)  # eye socket
        d = smin(d, sd_ellipsoid(P, (s * 0.42, -0.5, 0.0), (0.26, 0.3, 0.24)), 0.16)  # cheek
        # the lip curled back off the canine: a notch in the upper lip at the side
        d = smax(d, -sd_ellipsoid(P, (s * 0.17, -1.22, -0.06), (0.06, 0.1, 0.06)), 0.03)
    d = d + 0.007 * np.sin(y * 45.0) * np.exp(-((y + 0.85) / 0.15) ** 2) * np.exp(-(x / 0.18) ** 2) * (z > 0.2)  # a few snarl wrinkles on the bridge only
    th = np.arctan2(x, y)
    tufts = 0.03 * np.maximum(np.sin(th * 14.0 + z * 6.0), 0) * np.clip((y - 0.3) / 0.4, 0, 1) * np.clip((0.3 - z) / 0.5, 0, 1)
    d = d - tufts  # fur tufts at the scruff
    shag = 0.035 * np.maximum(np.sin(th * 16.0 + z * 3.0), 0) * np.clip((-0.15 - z) / 0.3, 0, 1)  # shaggy fur down the neck
    shag_d = shag
    d = smin(d, sd_capsule(P, (0, 0.08, -0.5), (0, 0.1, -0.95), 0.5) - shag_d, 0.2)  # neck to the collar, shaggy
    d = smax(d, -(z + 0.97), 0.03)
    return d


face = K.sdf_mesh("head", head, (-0.95, -1.75, -1.0), (0.95, 1.05, 1.2), 0.012, FUR)
K.ball("mouth_line_dark", 0.12, (0, -1.08, -0.09), GUM, (1.5, 4.2, 0.22), 12)

# eyes
for s in (-1, 1):
    K.ball("eye", 0.07, (s * 0.3, -0.83, 0.33), EYE, (1.15, 0.8, 0.8), 16)

# the canines showing where the lip is curled back + a few front teeth
for s in (-1, 1):
    for k, (yy, L, w) in enumerate(((-1.22, 0.13, 0.03), (-1.3, 0.07, 0.022), (-1.14, 0.07, 0.022))):
        root = Vector((s * 0.17, yy, -0.03))
        K.loft("tooth", lambda t, r=root, L=L: r + Vector((0, -0.01 * t, -L * t)), lambda t, w=w: w * (1 - t) ** 0.9 + 0.003, 8, 8, mat=TEETH)

# ears: tall, the left torn with a notch
for s in (-1, 1):
    base = Vector((s * 0.4, 0.02, 0.85))
    tip = Vector((s * 0.7, 0.15, 1.85))
    notch = s < 0

    def ear_w(t, notch=notch):
        w = 0.33 * (1 - t) ** 0.7 + 0.012
        if notch and 0.45 < t < 0.6:
            w *= 0.45  # a torn notch
        return w
    K.loft("ear", lambda t, a=base, b=tip: a.lerp(b, t) + Vector((0, -0.05 * math.sin(math.pi * t), 0)), ear_w, 36, 18, mat=FUR,
           profile=lambda th, t: (1.0, 0.22 + 0.06 * math.cos(th)))  # smooth, a little cupped
    K.loft("ear_inside", lambda t, a=base, b=tip: a.lerp(b, t) + Vector((0, -0.075 * math.sin(math.pi * t) - 0.02, 0)),
           lambda t, notch=notch: (0.24 * (1 - t) ** 0.7) * (0.45 if notch and 0.45 < t < 0.6 else 1.0) + 0.005, 32, 16, mat=EAR_IN,
           profile=lambda th, t: (1.0, 0.15))


# the steel helmet over the skull with a chin strap; goggles pushed up on the brim
def helmet(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.05, 0.42), (0.76, 0.88, 0.8))
    d = smax(d, -(z - (0.42 - 0.22 * np.clip(y, -1, 1))), 0.03)  # rim: down over the brow, low behind
    shell = np.maximum(d, -(d + 0.05))
    lip = np.maximum(np.abs(z - (0.42 - 0.22 * np.clip(y, -1, 1))) - 0.025, d - 0.05)
    lip = np.maximum(lip, -(d + 0.05))
    d = smin(shell, lip, 0.02)
    for xs in (-1, 1):  # ear holes: the ears come through
        d = smax(d, -sd_capsule(P, (xs * 0.4, 0.02, 0.7), (xs * 0.55, 0.1, 1.3), 0.22), 0.02)
    return d


helm_o = K.sdf_mesh("helmet", helmet, (-0.95, -1.05, 0.05), (0.95, 1.05, 1.3), 0.01, HELM)
# goggles on the brim
for s in (-1, 1):
    ok, loc, n, i = helm_o.ray_cast(Vector((s * 0.24, -2.0, 0.82)), Vector((0, 1, 0)))
    if ok:
        K.loft("goggle", lambda t, a=loc, n=n: a + n * (-0.01 + 0.08 * t), lambda t: 0.09, 4, 20, mat=STEEL)
        K.loft("goggle_glass", lambda t, a=loc, n=n: a + n * (0.07 + 0.005 * t), lambda t: 0.075, 2, 20, mat=GLASS)
K.loft("goggle_strap", lambda t: Vector((0.76 * math.sin(math.pi * (t - 0.5) * 1.8), 0.76 * -math.cos(math.pi * (t - 0.5) * 1.8) + 0.05, 0.8)),
       lambda t: 0.03, 40, 6, mat=STRAP, profile=lambda th, t: (0.35, 1.0))
# the chin strap from the helmet's sides round under the jaw
for s in (-1, 1):
    pts = [Vector((s * 0.66, -0.05, 0.5)), Vector((s * 0.62, -0.35, 0.05)), Vector((s * 0.36, -0.75, -0.3)), Vector((0, -0.85, -0.36))]
    K.tube("chin_strap", K.smooth_path(pts, 16), 0.025, STRAP, res=2)

# the studded collar with a buckle at the back
ring = [Vector((0.53 * math.sin(a), 0.1 + 0.53 * math.cos(a), -0.6)) for a in np.linspace(0, 2 * math.pi, 49)]
K.loft("collar", K.path_fn(ring), lambda t: 0.06, 96, 8, mat=LEATHER, profile=lambda th, t: (0.5, 1.0))
for k in range(16):
    a = k * 2 * math.pi / 16
    p = Vector((0.57 * math.sin(a), 0.1 + 0.57 * math.cos(a), -0.6))
    K.bolt(p, (p - Vector((0, 0.1, -0.6))).normalized(), 0.022, STEEL)
K.box("buckle", (0.12, 0.03, 0.1), (0, 0.66, -0.6), (0, 0, 0), STEEL, 0.008, 1)

# the cluster of dog tags hanging on chains at the throat
ring_p = Vector((0, -0.6, -0.62))
K.loft("tag_ring", lambda t: ring_p + Vector((0.04 * math.cos(2 * math.pi * t), -0.01, 0.04 * math.sin(2 * math.pi * t))), lambda t: 0.008, 24, 6, mat=STEEL, cap=False)
for k in range(7):
    ang = -0.6 + 1.2 * k / 6
    ln = 0.22 + 0.1 * random.random()
    top = ring_p + Vector((0.02 * math.sin(ang), -0.01, -0.03))
    bot = top + Vector((math.sin(ang) * 0.2, -0.05 - 0.02 * (k % 3), -ln))
    K.tube("tag_chain", [top, (top + bot) * 0.5 + Vector((0, -0.01, 0)), bot], 0.006, STEEL, res=1)
    K.box("dog_tag", (0.12, 0.028, 0.18), tuple(bot + Vector((0, 0, -0.05))), (0, math.radians(8 * (k - 3)), math.radians(15 * (k - 3) + random.uniform(-10, 10))), STEEL, 0.02, 2)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("hound_of_war")
print("ok")

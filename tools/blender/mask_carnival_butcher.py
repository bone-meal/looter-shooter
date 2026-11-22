# Carnival Butcher mask (elite / mob mask 16, diary/DECISIONS_SKINS.md B16, plan in diary/MASK_PLANS_DROPS.md): an
# oversized worn felt carnival mascot head (base 4) with a grin far too wide and far too full of teeth. FRONT = the
# grin crammed with rows of teeth, round staring eyes, a red bulb nose, rosy cheeks, stains round the mouth; SIDE = the
# grin wrapping toward the ears, a small striped top hat tipped forward, wild hair clumps; BACK = the hair, the hat, the
# zipper seam, a ruffled collar. The lower jaw (fxB_) clacks in the game.
# Run: python3 tools/blender/mask_carnival_butcher.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py carnival_butcher
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
SC = K.setup(161)
random.seed(16)


def felt(name, col, stain=0.0):
    """Worn felt: pilled fuzz in the relief, faded patches, optional brown stains splashed round the mouth (low z, front)."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 4.0; nz.inputs["Detail"].default_value = 5
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0]); mx.inputs[6].default_value = (*col, 1)
    mx.inputs[7].default_value = (col[0] * 0.75, col[1] * 0.72, col[2] * 0.7, 1)
    out = mx.outputs[2]
    if stain > 0:
        sp = N.new("ShaderNodeTexVoronoi"); sp.inputs["Scale"].default_value = 4.5; sp.inputs["Randomness"].default_value = 1.0
        L.new(tc.outputs["Object"], sp.inputs["Vector"])
        sm = N.new("ShaderNodeMapRange"); sm.inputs["From Min"].default_value = 0.2; sm.inputs["From Max"].default_value = 0.08
        L.new(sp.outputs["Distance"], sm.inputs["Value"])
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
        low = N.new("ShaderNodeMapRange"); low.inputs["From Min"].default_value = 0.35; low.inputs["From Max"].default_value = -0.1
        L.new(sep.outputs[2], low.inputs["Value"])
        st = N.new("ShaderNodeMath"); st.operation = "MULTIPLY"
        L.new(sm.outputs["Result"], st.inputs[0]); L.new(low.outputs["Result"], st.inputs[1])
        fr = N.new("ShaderNodeMapRange"); fr.inputs["From Min"].default_value = -0.4; fr.inputs["From Max"].default_value = -0.75
        L.new(sep.outputs[1], fr.inputs["Value"])
        st2 = N.new("ShaderNodeMath"); st2.operation = "MULTIPLY"
        L.new(st.outputs[0], st2.inputs[0]); L.new(fr.outputs["Result"], st2.inputs[1])
        st = st2
        sv = N.new("ShaderNodeMath"); sv.operation = "MULTIPLY"; sv.inputs[1].default_value = stain
        L.new(st.outputs[0], sv.inputs[0])
        ms = N.new("ShaderNodeMix"); ms.data_type = "RGBA"
        L.new(sv.outputs[0], ms.inputs[0]); L.new(out, ms.inputs[6]); ms.inputs[7].default_value = (0.16, 0.035, 0.02, 1)
        out = ms.outputs[2]
    c, ao = K._ao_mix(N, L, out, (col[0] * 0.25, col[1] * 0.22, col[2] * 0.2), 0.08)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    fz = N.new("ShaderNodeTexNoise"); fz.inputs["Scale"].default_value = 140.0; fz.inputs["Detail"].default_value = 3
    L.new(tc.outputs["Object"], fz.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.3; bump.inputs["Distance"].default_value = 0.003
    L.new(fz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


FACE_M = felt("face_felt", (0.78, 0.66, 0.52), stain=0.85)
JAW_M = felt("fxB_jaw_felt", (0.78, 0.66, 0.52), stain=1.0)
CHEEK = felt("cheek_felt", (0.75, 0.3, 0.3))
NOSE = K.simple("nose", (0.6, 0.04, 0.03), 0.4)
HAIR = felt("hair_felt", (0.62, 0.22, 0.06))
TEETH = K.simple("teeth", (0.78, 0.74, 0.6), 0.5)
TEETH_LO = K.simple("fxB_teeth_lower", (0.78, 0.74, 0.6), 0.5)  # the lower rows move with the jaw
GUM = K.simple("mouth_dark", (0.12, 0.02, 0.02), 0.8)
EYE_W = K.simple("eye_paint", (0.82, 0.8, 0.72), 0.4)
LENS = K.simple("eye_lens", (0.01, 0.01, 0.012), 0.25)
HAT_R = felt("hat_red", (0.45, 0.04, 0.05))
HAT_W = felt("hat_cream", (0.78, 0.72, 0.6))
COLLAR = felt("collar", (0.7, 0.66, 0.6), stain=0.5)
NECK_M = felt("neck_felt", (0.4, 0.05, 0.06))
STEEL = K.steel("zip", (0.35, 0.34, 0.3), heat=0.0, rust=0.2)

MOUTH_Z = -0.02


def grin_line(x):
    """The grin's middle line: a wide crescent whose corners curl up toward the ears."""
    return MOUTH_Z + 0.32 * (np.abs(x) / 0.9) ** 2.2


def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.4), (0.98, 0.94, 1.0))  # the big head
    d = smax(d, -(z + 0.45), 0.1)  # flat-ish under the chin
    for s in (-1, 1):
        d = smin(d, sd_ellipsoid(P, (s * 0.46, -0.72, 0.18), (0.32, 0.28, 0.27)), 0.15)  # puffed cheeks
    d = smin(d, sd_ellipsoid(P, (0, -0.8, 0.62), (0.62, 0.22, 0.2)), 0.18)  # brow
    # the grin: a deep slot following the crescent, wrapping round toward the ears
    in_front = np.clip((-y - 0.1) / 0.4, 0, 1)
    mouth = np.abs(z - grin_line(x)) - (0.13 - 0.06 * (np.abs(x) / 0.9) ** 2) * in_front
    mouth = np.maximum(mouth, np.abs(x) - 0.92)
    mouth = np.maximum(mouth, y + 0.15)
    d = smax(d, -np.maximum(mouth, -(sd_ellipsoid(P, (0, 0.02, 0.4), (0.98, 0.94, 1.0)) + 0.25)), 0.03)
    # cut away the lower jaw (its own part) below the grin's middle in front
    jaw = np.maximum(z - grin_line(x), y + 0.05)
    d = smax(d, -jaw, 0.02)
    # stitched seams: a centre seam over the head, the zipper seam down the back
    d = groove(d, np.where(y > -0.3, x, 9.0), 0.008, 0.01, 0.003)
    return d


def jaw_part(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.4), (0.98, 0.94, 1.0))
    d = smax(d, -(z + 0.45), 0.1)
    for s in (-1, 1):
        d = smin(d, sd_ellipsoid(P, (s * 0.46, -0.72, 0.18), (0.32, 0.28, 0.27)), 0.15)
    d = smin(d, sd_ellipsoid(P, (0, -0.78, -0.3), (0.3, 0.2, 0.16)), 0.12)  # a heavy chin
    d = smax(d, z - grin_line(x) + 0.004, 0.02)  # below the grin
    d = smax(d, y + 0.05, 0.03)  # the front part only
    d = smax(d, -(sd_ellipsoid(P, (0, 0.02, 0.4), (0.98, 0.94, 1.0)) + 0.25), 0.03)  # a shell
    return d


head_o = K.sdf_mesh("head", head, (-1.15, -1.15, -0.6), (1.15, 1.1, 1.45), 0.012, FACE_M)
jaw_o = K.sdf_mesh("jaw", jaw_part, (-1.1, -1.15, -0.6), (1.1, 0.0, 0.35), 0.011, JAW_M)

# the mouth's dark inside, then the teeth: three rows on top, two below, far too many
K.ball("mouth_inside", 0.75, (0, -0.35, 0.02), GUM, (1.15, 0.7, 0.32), 24)
for row, (dz, scale, count, depth) in enumerate(((0.07, 1.0, 26, 0.0), (0.11, 0.8, 22, 0.06), (0.145, 0.62, 18, 0.12))):
    for sgn in (1, -1):  # top rows hang down, bottom rows stand up
        if sgn < 0 and row == 2:
            continue
        for k in range(count):
            xx = -0.86 + 1.72 * (k + 0.5) / count
            zc = grin_line(xx) + sgn * (0.12 - 0.06 * (abs(xx) / 0.9) ** 2) * (1.0 - 0.25 * row)
            ok, loc, n, i = head_o.ray_cast(Vector((xx, -2.0, zc + sgn * 0.04)), Vector((0, 1, 0))) if sgn > 0 else jaw_o.ray_cast(Vector((xx, -2.0, zc - 0.04)), Vector((0, 1, 0)))
            if not ok:
                continue
            base = loc + Vector((0, 0.02 + depth, 0))
            h = (0.075 + 0.02 * random.random()) * scale * (1.0 - 0.3 * (abs(xx) / 0.9))
            tip = base + Vector((0, -0.01, -sgn * h))
            K.loft("tooth", lambda t, a=base, b=tip: a.lerp(b, t), lambda t, w=0.03 * scale: w * (1 - 0.65 * t ** 1.5) + 0.004, 6, 8, mat=TEETH if sgn > 0 else TEETH_LO)

# eyes: painted whites round dark mesh lenses with a painted pupil shine
for s in (-1, 1):
    ok, loc, n, i = head_o.ray_cast(Vector((s * 0.3, -2.0, 0.42)), Vector((0, 1, 0)))
    if ok:
        w = K.ball("eye_white", 0.2, tuple(loc + n * -0.04), EYE_W, (1.0, 1.15, 0.4), 24)
        K.align(w, n)
        l = K.ball("eye_lens", 0.11, tuple(loc + n * 0.035), LENS, (1.0, 1.0, 0.35), 20)  # a dark mesh lens: the pupil
        K.align(l, n)
        K.ball("eye_shine", 0.028, tuple(loc + n * 0.07 + Vector((s * -0.035, 0, 0.045))), EYE_W, (1, 1, 1), 10)
# the nose and the rosy cheeks
ok, loc, n, i = head_o.ray_cast(Vector((0, -2.0, 0.24)), Vector((0, 1, 0)))
if ok:
    K.ball("nose", 0.13, tuple(loc + n * 0.06), NOSE, (1.0, 0.95, 0.9), 24)
for s in (-1, 1):
    ok, loc, n, i = head_o.ray_cast(Vector((s * 0.55, -2.0, 0.24)), Vector((0, 1, 0)))
    if ok:
        c = K.ball("cheek_blush", 0.13, tuple(loc + n * -0.05), CHEEK, (1.0, 0.8, 0.4), 20)
        K.align(c, n)

# wild hair: one bushy mass of curls round the back and sides (bald on top), biggest over the ears


def hair(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)  # 0 = straight back
    base = sd_ellipsoid(P, (0, 0.05, 0.4), (0.98, 0.94, 1.0))
    ear = np.exp(-((np.abs(th) - 1.75) / 0.45) ** 2)  # fullest over the ears
    curls = 0.08 * np.sin(th * 8.0 + z * 6.0) * np.sin(z * 9.0 - th * 3.0) + 0.035 * np.sin(th * 19.0 + z * 13.0)  # big round tufts
    puff = 0.17 + 0.16 * ear + curls
    d = base - puff
    d = smax(d, -(base - 0.02), 0.03)  # sits on the head
    band_lo = -0.02 - 0.2 * ear + 0.11 * np.sin(th * 6.0) + 0.05 * np.sin(th * 13.0)
    band_hi = 0.86 - 0.1 * ear + 0.11 * np.sin(th * 4.0 + 1.0) + 0.06 * np.sin(th * 11.0)
    d = smax(d, band_lo - z, 0.16)  # ragged, rounded edges (no cut band)
    d = smax(d, z - band_hi, 0.18)
    d = smax(d, np.abs(th) - 2.2, 0.1)  # round the back, stopping behind the cheeks
    return d


K.sdf_mesh("hair", hair, (-1.4, -0.9, -0.3), (1.4, 1.35, 1.1), 0.012, HAIR)
for s_ in (-1, 1):  # low poufs over the jaw's seam
    K.ball("hair_pouf", 0.19, (s_ * 0.98, -0.06, 0.12), HAIR, (1.0, 1.0, 1.0), 16)
# the small striped top hat, tipped forward on the right
ok, loc, n, i = head_o.ray_cast(Vector((0.32, 0.0, 3.0)), Vector((0, 0, -1)))
if ok:
    tilt = Vector((0.32, -0.42, 1.0)).normalized()
    hb = loc - tilt * 0.02
    K.loft("hat_brim", lambda t: hb + tilt * (0.045 * t), lambda t: 0.46, 3, 32, mat=HAT_R, profile=lambda th, t: (1.0 + 0.06 * math.sin(th * 2 + 0.5), 1.0 + 0.06 * math.sin(th * 2 + 0.5)))
    for j in range(6):  # crown in red / cream bands
        K.loft("hat_band", lambda t, j=j: hb + tilt * (0.045 + 0.095 * j + 0.095 * t) + Vector((0.012 * j * j * 0.2, 0, 0)), lambda t, j=j: 0.3 - 0.008 * j, 3, 28, mat=HAT_R if j % 2 == 0 else HAT_W,
               profile=lambda th, t, j=j: (1.0 + 0.05 * math.sin(th * 3 + j), 1.0 + 0.05 * math.sin(th * 3 + j)))  # soft, crumpled felt
    K.loft("hat_top", lambda t: hb + tilt * (0.615 - 0.05 * t) + Vector((0.035, 0, 0)), lambda t: 0.255 * (1 - t ** 2), 4, 28, mat=HAT_R)  # a crushed, dented top

# the zipper seam down the back of the head
pts = []
for zz in np.linspace(1.1, -0.35, 22):
    ok, loc, n, i = head_o.ray_cast(Vector((0, 2.0, zz)), Vector((0, -1, 0)))
    if ok:
        pts.append(loc + n * 0.006)
if len(pts) > 3:
    K.tube("zip", pts, 0.018, STEEL, res=2)
    K.box("zip_pull", (0.05, 0.02, 0.09), tuple(pts[len(pts) // 3] + Vector((0, 0.03, 0))), (0, 0, 0), STEEL, 0.006, 1)


# the ruffled collar at the neck
def collar(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)
    r = np.sqrt(x ** 2 + (y - 0.02) ** 2)
    d = 9.0
    for zc, r0, n in ((-0.5, 0.66, 22), (-0.62, 0.6, 18)):  # two tiers of round flutes
        flute = r0 + 0.07 * np.sin(th * n)
        d = np.minimum(d, np.sqrt(((r - flute) / 1.6) ** 2 + (z - zc - 0.03 * np.cos(th * n)) ** 2) - 0.05)
    return d


K.sdf_mesh("collar", collar, (-0.9, -0.9, -0.75), (0.9, 0.95, -0.35), 0.012, COLLAR)


def neck(P):
    """The costume's felt neck under the head, down to the collar line (the body's neck is cut away under full masks)."""
    d = sd_capsule(P, (0, 0.04, -0.3), (0, 0.08, -0.95), 0.44 + 0.015 * np.sin(np.arctan2(P[..., 0], P[..., 1]) * 8))
    return smax(d, -(P[..., 2] + 0.97), 0.03)


K.sdf_mesh("neck", neck, (-0.6, -0.5, -1.0), (0.6, 0.6, -0.2), 0.014, NECK_M)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("carnival_butcher")
print("ok")

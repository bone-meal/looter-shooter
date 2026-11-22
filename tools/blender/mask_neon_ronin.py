# Neon Ronin mask (elite 22, diary/DECISIONS_SKINS.md B22, plan in diary/MASK_PLANS_DROPS.md): a masterless
# swordsman of a neon city (Payday face, base 2): a smooth gunmetal face under a tattered conical straw hat, glowing
# characters written down both cheeks. FRONT = calm stern face, narrow eye slits with cyan light (fxR_), NEON
# CHARACTERS in grooves down the cheeks (left 浪人, right 夜行; fxG_, their hue from the colour map in the game), a
# thin neon line down the nose, a chin cord from the hat. SIDE = the wide hat tipped forward, torn notches and loose
# straws at its rim, the face plate's edge, the cloth wrap. BACK = the hat's woven rings, a dark cloth wrap over the
# head and neck to the collar with a knot and two tails at the nape and a neon stitch line down its seam.
# Run: python3 tools/blender/mask_neon_ronin.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py neon_ronin
# Dependencies: tools/blender/mask_kit.py, Pillow + scipy (the characters' distance field), the Noto Sans CJK font.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from scipy import ndimage  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(221)
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc"


# ------------------------------------------------------------------ materials
def gunmetal(name, base=(0.05, 0.055, 0.062)):
    """Brushed gunmetal: fine streaks, soft polished wear on the high points (pointiness), grime in the grooves."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1.0, 1.0, 40.0)
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    br = N.new("ShaderNodeTexNoise"); br.inputs["Scale"].default_value = 30.0; br.inputs["Detail"].default_value = 3
    L.new(mp.outputs["Vector"], br.inputs["Vector"])
    geo = N.new("ShaderNodeNewGeometry")
    wear = N.new("ShaderNodeMapRange"); wear.inputs["From Min"].default_value = 0.52; wear.inputs["From Max"].default_value = 0.6
    L.new(geo.outputs["Pointiness"], wear.inputs["Value"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(wear.outputs["Result"], mx.inputs[0])
    mx.inputs[6].default_value = (*base, 1); mx.inputs[7].default_value = (base[0] * 3.2, base[1] * 3.1, base[2] * 3.0, 1)
    col, ao = K._ao_mix(N, L, mx.outputs[2], (0.008, 0.008, 0.009), 0.05)
    L.new(col, b.inputs["Base Color"])
    rr = N.new("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.32; rr.inputs["To Max"].default_value = 0.5
    L.new(br.outputs["Fac"], rr.inputs["Value"]); L.new(rr.outputs["Result"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.85
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.08; bump.inputs["Distance"].default_value = 0.002
    L.new(br.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def straw(name):
    """Woven straw: concentric rings of plait with spokes, sun-faded tan, darker in the weave."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    rings = N.new("ShaderNodeTexWave"); rings.wave_type = "RINGS"; rings.inputs["Scale"].default_value = 45.0; rings.inputs["Distortion"].default_value = 0.3
    rings.inputs["Distortion"].default_value = 1.5; rings.inputs["Detail"].default_value = 2
    L.new(tc.outputs["Object"], rings.inputs["Vector"])
    weave = N.new("ShaderNodeTexWave"); weave.inputs["Scale"].default_value = 70.0; weave.inputs["Distortion"].default_value = 3.0
    L.new(tc.outputs["Object"], weave.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 6.0; nz.inputs["Detail"].default_value = 5
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (0.42, 0.31, 0.15, 1); mx.inputs[7].default_value = (0.26, 0.18, 0.08, 1)
    grad = N.new("ShaderNodeTexGradient"); grad.gradient_type = "RADIAL"
    L.new(tc.outputs["Object"], grad.inputs["Vector"])
    sp = N.new("ShaderNodeMath"); sp.operation = "MULTIPLY"; sp.inputs[1].default_value = 900.0
    L.new(grad.outputs["Fac"], sp.inputs[0])
    sn = N.new("ShaderNodeMath"); sn.operation = "SINE"; L.new(sp.outputs[0], sn.inputs[0])
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    L.new(rings.outputs["Fac"], mul.inputs[0]); L.new(sn.outputs[0], mul.inputs[1])  # plait: rings crossed by spokes
    md = N.new("ShaderNodeMix"); md.data_type = "RGBA"
    L.new(rings.outputs["Fac"], md.inputs[0])
    md.inputs[6].default_value = (0.08, 0.05, 0.02, 1); L.new(mx.outputs[2], md.inputs[7])
    col, ao = K._ao_mix(N, L, md.outputs[2], (0.05, 0.035, 0.015), 0.05)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6; bump.inputs["Distance"].default_value = 0.006
    L.new(mul.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def cloth(name, col=(0.01, 0.01, 0.014)):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    wv = N.new("ShaderNodeTexNoise"); wv.inputs["Scale"].default_value = 160.0; wv.inputs["Detail"].default_value = 2
    L.new(tc.outputs["Object"], wv.inputs["Vector"])
    rgb = N.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*col, 1)
    col_s, ao = K._ao_mix(N, L, rgb.outputs[0], (0.004, 0.004, 0.006), 0.07)
    L.new(col_s, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.9
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.003
    L.new(wv.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


METAL = gunmetal("gunmetal")
STRAW = straw("straw")
WRAP = cloth("wrap", (0.03, 0.036, 0.07))  # indigo: apart from the gunmetal from behind
CORD = K.simple("cord", (0.32, 0.03, 0.025), 0.7)
EYE = K.glow("fxR_eye_cyan", (0.2, 0.95, 1.0), 9.0, base=(0.0, 0.2, 0.25))
NEON_M = K.glow("fxG_neon_magenta", (1.0, 0.1, 0.65), 9.0, base=(0.6, 0.05, 0.4))
NEON_C = K.glow("fxG_neon_cyan", (0.15, 0.9, 1.0), 9.0, base=(0.05, 0.5, 0.6))
HOLE = K.simple("eye_hole", (0.004, 0.004, 0.005), 0.9)


# ------------------------------------------------------------------ the characters: a distance field from the font
def column_field(text, px=220):
    """Two characters stacked vertically -> a signed distance field in pixels (negative inside the strokes)."""
    font = ImageFont.truetype(FONT, int(px * 0.92), index=0)
    W, H = px, px * len(text)
    im = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(im)
    for i, ch in enumerate(text):
        bb = dr.textbbox((0, 0), ch, font=font)
        dr.text(((W - (bb[2] - bb[0])) / 2 - bb[0], i * px + (px - (bb[3] - bb[1])) / 2 - bb[1]), ch, fill=255, font=font)
    a = np.array(im) > 127
    return ndimage.distance_transform_edt(~a) - ndimage.distance_transform_edt(a), W, H


COLUMNS = []  # (field, W, H, centre x, top z, width, height, material)
for text, cx, mat in (("浪人", 0.36, NEON_M), ("夜行", -0.36, NEON_C)):
    f, W, H = column_field(text)
    COLUMNS.append((f, W, H, cx, 0.12, 0.2, 0.4, mat))


def glyph_sd(P, col):
    """The column's strokes extruded along y (front view), in sculpt units; far away outside its frame."""
    f, W, H, cx, zt, w, h, _ = col
    x, z = P[..., 0], P[..., 2]
    u = (x - (cx - w / 2)) / w * (W - 1)
    v = (zt - z) / h * (H - 1)
    inside = (u >= 0) & (u <= W - 1) & (v >= 0) & (v <= H - 1) & (P[..., 1] < -0.62)  # front only (at -0.3 they cut through to the sides)
    val = ndimage.map_coordinates(f, [np.clip(v, 0, H - 1).ravel(), np.clip(u, 0, W - 1).ravel()], order=1).reshape(x.shape)
    return np.where(inside, val * (w / W), 1.0)


# ------------------------------------------------------------------ the face
def face_base(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.2), (0.8, 0.94, 0.84))  # cranium
    d = smax(d, y - 0.86, 0.2)
    d = smin(d, sd_ellipsoid(P, (0, -0.36, -0.28), (0.6, 0.64, 0.52)), 0.25)  # lower face and jaw
    d = smin(d, sd_ellipsoid(P, (0, -0.8, -0.5), (0.22, 0.17, 0.16)), 0.14)  # chin
    d = smax(d, -y - 1.0, 0.18)  # the soft front plane
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.05, -0.97, 0.38), (s * 0.42, -0.86, 0.4), 0.035), 0.1)  # a straight calm brow
        d = smin(d, sd_ellipsoid(P, (s * 0.44, -0.76, 0.04), (0.2, 0.15, 0.12)), 0.12)  # cheekbone
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.42, 0.36), (0.12, 0.2, 0.16)), 0.12)  # temple
        # the narrow eye slit, nearly level
        q = P - np.array([s * 0.28, -0.97, 0.27])
        rot = np.stack([q[..., 0] * math.cos(0.1) - s * q[..., 2] * math.sin(0.1), q[..., 1],
                        s * q[..., 0] * math.sin(0.1) + q[..., 2] * math.cos(0.1)], axis=-1)
        d = smax(d, -sd_ellipsoid(rot, (0, 0, 0), (0.12, 0.3, 0.022)), 0.01)
    d = smin(d, sd_capsule(P, (0, -0.98, 0.33), (0, -1.1, 0.07), 0.042), 0.05)  # straight nose
    d = smin(d, sd_ellipsoid(P, (0, -1.09, 0.04), (0.07, 0.06, 0.05)), 0.04)
    d = smin(d, sd_ellipsoid(P, (0, -0.9, -0.2), (0.27, 0.13, 0.17)), 0.12)  # muzzle
    mouth = np.where((np.abs(x) < 0.15) & (y < -0.85), z + 0.205, 9.0)  # a closed straight mouth line
    d = groove(d, mouth, 0.01, 0.006, 0.0)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.5), 0.2)  # neck down to the collar
    d = smax(d, -(z + 0.98), 0.03)
    return d


def plate_edge(P):
    """Where the face plate stops and the wrap begins (negative = on the plate, in front)."""
    y, z = P[..., 1], P[..., 2]
    return y - (-0.44 + 0.2 * np.clip((0.55 - z) / 1.3, 0.0, 1.0))


def face(P):
    d0 = face_base(P)
    d = groove(d0, np.where(P[..., 1] < 0.2, plate_edge(P), 9.0), 0.014, 0.014, -0.02)  # the plate's rim step
    for col in COLUMNS:  # the characters' grooves
        g = glyph_sd(P, col)
        d = np.maximum(d, -np.maximum(g, -d0 - 0.02))
    return d


head = K.sdf_mesh("face", face, (-0.9, -1.2, -1.02), (0.9, 1.0, 1.1), 0.009, METAL)

# the characters' neon: thin glowing sheets at the bottom of the grooves (slightly thinner than the grooves)
for col in COLUMNS:
    K.sdf_mesh("neon", lambda P, col=col: np.maximum(glyph_sd(P, col) + 0.003, np.abs(face_base(P) + 0.016) - 0.008),
               (col[3] - 0.13, -1.1, col[4] - col[6] - 0.05), (col[3] + 0.13, -0.5, col[4] + 0.05), 0.004, col[7])

# eyes: dark behind the slits, a cyan light deep in each
for s in (-1, 1):
    K.ball("eye_dark", 0.13, (s * 0.28, -0.8, 0.27), HOLE, (1.0, 0.8, 0.45), 16)
    K.ball("eye_light", 0.05, (s * 0.28, -0.9, 0.27), EYE, (1.6, 0.6, 0.5), 16)
# a neon line down the bridge of the nose
nose = [Vector((0, -0.995 - 0.115 * t, 0.36 - 0.27 * t)) for t in np.linspace(0, 1, 8)]
K.tube("nose_neon", nose, 0.013, NEON_C, res=3)


# ------------------------------------------------------------------ the cloth wrap behind the plate (head and neck)
def wrap(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d0 = face_base(P)
    folds = 0.012 * np.sin(z * 14.0 + x * 3.0) + 0.008 * np.sin(np.arctan2(x, y) * 9.0 + z * 4.0)
    shell = np.maximum(d0 - 0.036 - folds, -(d0 + 0.006))  # never thinner than ~0.02 (no holes)
    shell = smax(shell, -(plate_edge(P) + 0.01), 0.02)  # only behind the plate's rim
    band = np.sin((z + 0.35 * np.arctan2(x, y + 0.2)) * 13.0)  # wound strips spiralling round the head
    shell = shell + 0.008 * np.clip(band * 3.0, -1.0, 1.0)
    # the knot at the nape and two short tails
    shell = smin(shell, sd_ellipsoid(P, (0, 0.74, -0.08), (0.14, 0.1, 0.1)), 0.05)
    return smax(shell, -(z + 0.98), 0.02)


K.sdf_mesh("wrap", wrap, (-0.9, -0.7, -1.02), (0.9, 1.0, 1.1), 0.011, WRAP)
for s in (-1, 1):
    K.loft("wrap_tail", lambda t, s=s: Vector((s * (0.06 + 0.16 * t), 0.8 + 0.12 * t - 0.08 * t * t, -0.12 - 0.72 * t)),
           lambda t: 0.11 * (1 - 0.35 * t) + 0.01, 28, 10, mat=WRAP, profile=lambda th, t: (1.0, 0.32))
# the neon stitch line down the wrap's centre seam at the back
seam = []
for zz in np.linspace(0.95, -0.05, 12):
    loc, n = K.ray_onto(K.bpy.data.objects["wrap"], Vector((0, 2.5, zz)), Vector((0, -1, 0)))
    if loc:
        seam.append(loc + n * 0.006)
if len(seam) > 2:
    K.tube("seam_neon", seam, 0.012, NEON_C, res=3)


# ------------------------------------------------------------------ the straw hat: a wide cone tipped forward
HAT_C = np.array([0.0, -0.12, 1.02])
TILT = math.radians(10.0)
APEX, RIM_R = 0.45, 1.6  # in hat space: apex height, rim radius (director: much larger, hiding the face)


def prof(r):
    """The hat's height at radius r (hat space): high over the crown, the brim drooping hard toward its edge."""
    return APEX - 0.25 * r - 0.38 * r * r


def dprof(r):
    return -0.25 - 0.76 * r


def to_sculpt(p):
    c, s = math.cos(TILT), math.sin(TILT)
    y = p[1] * c + p[2] * s
    z = -p[1] * s + p[2] * c
    return Vector((p[0] + HAT_C[0], y + HAT_C[1], z + HAT_C[2]))


def hat_space(P):
    q = P - HAT_C
    c, s = math.cos(TILT), math.sin(TILT)
    return np.stack([q[..., 0], q[..., 1] * c - q[..., 2] * s, q[..., 1] * s + q[..., 2] * c], axis=-1)  # front tips down


def hat(P):
    q = hat_space(P)
    r = np.sqrt(q[..., 0] ** 2 + q[..., 1] ** 2)
    h = q[..., 2]
    surf = (h - prof(r)) / np.sqrt(1.0 + dprof(r) ** 2)  # distance to the drooping cone (+ above / outside)
    shell = np.abs(surf) - 0.028
    th = np.arctan2(q[..., 1], q[..., 0])  # -pi/2 = the front
    # torn notches in the rim (none at the back, where they showed a hole) + a ragged edge
    rim = RIM_R - 0.006 * np.sin(th * 23.0) - 0.004 * np.sin(th * 41.0)  # bigger read as a pie crust
    for a, w, dpt in ((-2.2, 0.12, 0.17), (0.3, 0.09, 0.12), (-1.0, 0.07, 0.1)):
        rim = rim - dpt * np.exp(-((np.angle(np.exp(1j * (th - a)))) / w) ** 2)
    d = smax(shell, r - rim, 0.01)
    d = smin(d, np.sqrt((r - rim + 0.02) ** 2 + surf ** 2) - 0.034, 0.01)  # a bound rolled edge
    d = d - 0.004 * np.sign(np.sin(r * 55.0))  # the woven rings as shallow steps
    # a dark ribbon band round the crown and a small knob at the top (own material below)
    return d


K.sdf_mesh("hat", hat, (-1.75, -1.95, -0.35), (1.75, 1.6, 1.55), 0.012, STRAW)
BAND = cloth("hat_band", (0.05, 0.012, 0.012))
K.sdf_mesh("hat_band", lambda P: (lambda q, r: smax(np.abs((q[..., 2] - prof(r)) / np.sqrt(1 + dprof(r) ** 2)) - 0.045, np.abs(r - 0.42) - 0.05, 0.01))(
    hat_space(P), np.sqrt(hat_space(P)[..., 0] ** 2 + hat_space(P)[..., 1] ** 2)), (-0.6, -0.8, 0.9), (0.6, 0.5, 1.6), 0.008, BAND)
K.ball("hat_knob", 0.06, tuple(to_sculpt((0, 0, APEX + 0.03))), STRAW, (1.0, 1.0, 0.8), 14)

# loose straws at the notches
for a in (-2.2, 0.3, -1.0):
    for k in range(3):
        aa = a + random.uniform(-0.08, 0.08)
        base_r = RIM_R - 0.16
        p0 = np.array([base_r * math.cos(aa), base_r * math.sin(aa), prof(base_r)])
        a2 = aa + random.uniform(-0.25, 0.25)
        p1 = p0 + np.array([0.24 * math.cos(a2), 0.24 * math.sin(a2), -0.2 - 0.06 * random.random()])
        K.tube("straw_loose", [to_sculpt(p) for p in (p0, (p0 + p1) / 2, p1)], 0.013, STRAW, res=2)

# the chin cord: from inside the hat at both sides down along the jaw and under the chin
for s in (-1, 1):
    pts = [Vector((s * 0.6, -0.15, 0.95))]
    for (yy, zz) in ((-0.25, 0.3), (-0.38, -0.1), (-0.5, -0.4)):
        loc, n = K.ray_onto(head, Vector((s * 2.0, yy, zz)), Vector((-s, 0, 0)))
        if loc:
            pts.append(loc + n * 0.015)
    pts.append(Vector((s * 0.12, -0.78, -0.66)))
    pts.append(Vector((0.0, -0.8, -0.68)))
    K.tube("chin_cord", K.smooth_path(pts, 24), 0.022, CORD, res=3)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("neon_ronin")
print("ok")

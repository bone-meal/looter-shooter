# Silent Judge mask (boss mask 12, diary/DECISIONS_SKINS.md A12 + diary/MASK_PROCESS.md section 5): a half-mask
# hybrid (base 10). Silhouette plan: FRONT = a tall vertical blade CREST + a heavy squared JAW; SIDE = the crest sweeping
# back from the brow to the nape + the jaw's hinge PISTONS at the temples; BACK = the crest's bolted base flange running
# down the back. Behaviour: brushed steel, light in the crest's grooves (fxG_: brightens in combat in the game), a cold
# visor slit (fxR_), the jaw a separate darker iron part (fxB_: opens a little on a slow breath in the game), the step
# between the helm's rim and the jaw a dark recess with cables.
# Run: python3 tools/blender/mask_silent_judge.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py silent_judge
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(121)

HELM = K.steel("helm_steel", (0.34, 0.345, 0.36), heat=0.15, rust=0.0, rough=0.32)
JAW = K.steel("fxB_jaw_iron", (0.1, 0.1, 0.105), heat=0.35, rust=0.25, rough=0.45)
IRON = K.steel("iron", (0.12, 0.12, 0.125), heat=0.3, rust=0.2)
RUB = K.rubber("cable")
DARK = K.simple("recess", (0.01, 0.01, 0.012), 0.8)
CLOTH = K.simple("gorget_cloth", (0.03, 0.028, 0.03), 0.85)
SLIT = K.glow("fxR_visor", (0.8, 0.9, 1.0), 9.0, base=(0.1, 0.12, 0.15))
LINES = K.glow("fxG_crest_lines", (0.8, 0.9, 1.0), 7.0, base=(0.1, 0.12, 0.15))

CREST_T = 0.04  # crest half thickness at its base


def crest_top(y):
    """Height of the crest's edge over y: a steep rise from the brow to the tip, then a long concave sweep to the nape."""
    y = np.asarray(y, dtype=float)
    u1 = np.clip((y + 0.52) / 0.47, 0, 1)
    rise = 0.9 + 1.2 * (1 - (1 - u1) ** 2.6)  # steep, the tip a little forward of the crown
    u2 = np.clip((y + 0.05) / 1.03, 0, 1)
    sweep = 0.2 + 1.9 * (1 - u2) ** 0.75
    sweep = sweep - 0.06 * np.abs(np.sin(u2 * math.pi * 3.0)) * np.clip(u2 * 6, 0, 1)  # three scallops: plates stepping back
    return np.where(y < -0.05, rise, sweep)


def crest(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    h = crest_top(y)
    eps = 0.01
    slope = (crest_top(y + eps) - crest_top(y - eps)) / (2 * eps)
    edge = (z - h) / np.sqrt(1 + slope ** 2)  # distance-ish below the edge line
    edge = np.maximum(edge, -(y + 0.56))
    edge = np.maximum(edge, y - 0.98)
    t = CREST_T * (0.3 + 0.7 * np.clip(-edge / 0.25, 0, 1))  # thins toward the edge: a blade
    d = np.maximum(edge, np.abs(x) - t)
    for off in (0.07, 0.15, 0.23):  # grooves parallel to the edge, both faces, the light lines sit in them
        d = groove(d, edge + off, 0.014, 0.02, 0.0)
    return d


def helm(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.04, 0.38), (0.7, 0.86, 0.78))
    d = smax(d, np.abs(x) - 0.64, 0.12)  # squared sides
    d = smax(d, y - 0.84, 0.15)
    d = smax(d, P @ np.array([0, -0.94, 0.34]) - 0.82, 0.08)  # the flat face plane (a judge's stern front)
    d = smin(d, sd_box(P, (0, -0.8, 0.47), (0.34, 0.08, 0.05), 0.04), 0.12)  # heavy brow shelf, ends inside the face
    # the visor slit: a narrow V across the face under the brow
    for s in (-1, 1):
        q = P - np.array([s * 0.2, -0.86, 0.34])
        ca, sa = math.cos(s * 0.12), math.sin(s * 0.12)
        qx = q[..., 0] * ca + q[..., 2] * sa; qz = -q[..., 0] * sa + q[..., 2] * ca
        slit = np.maximum(np.maximum(np.abs(qx) - 0.21, np.abs(qz) - 0.028), np.abs(q[..., 1]) - 0.2)
        d = smax(d, -slit, 0.01)
    d = smin(d, sd_box(P, (0, -0.9, 0.2), (0.025, 0.06, 0.12), 0.01), 0.03)  # nose ridge under the slit
    # the helm's lower rim: cut at the cheekbones in front, lower at the back (the half-mask's step)
    rim = 0.06 - 0.32 * np.clip((y + 0.1) / 0.9, 0, 1)
    d = smax(d, rim - z, 0.03)
    d = groove(d, z - rim - 0.07, 0.01, 0.014, 0.004)  # a rolled band along the rim
    # crest base flange and the crest
    flange = np.maximum(np.abs(x) - 0.09, d - 0.05)  # a raised band 0.05 proud along the middle line
    flange = np.maximum(flange, np.minimum(0.62 - z, 0.3 - y))  # only over the top and down the back
    flange = np.maximum(flange, -(z + 0.12))  # ending above the rim at the nape
    d = smin(d, flange, 0.02)
    d = smin(d, crest(P), 0.03)
    # plate seams over the crown
    for s in (-1, 1):
        d = groove(d, s * x - 0.36 - 0.05 * z, 0.016, 0.014, 0.006)
        # a raised ear plate on each side (the pistons' anchor), a stepped edge
        ear = np.sqrt(((y - 0.12) / 1.0) ** 2 + ((z - 0.3) / 1.15) ** 2) - 0.27
        plate = np.maximum(np.maximum(ear, d - 0.035), 0.4 - s * x)
        d = smin(d, plate, 0.008)
        d = groove(d, np.sqrt((y - 0.12) ** 2 + ((z - 0.3) / 1.15) ** 2) - 0.16 + 9.0 * (s * x < 0.4), 0.01, 0.012, 0.0)
    return d


def jaw(P):
    """The heavy jaw: a squared iron cowl over mouth and chin, vent slots at the mouth, arms up to the temple hinges."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_box(P, (0, -0.55, -0.2), (0.48, 0.32, 0.3), 0.12)
    d = smax(d, np.abs(x) - (0.5 - 0.3 * np.clip(-(z + 0.05) / 0.45, 0, 1)), 0.04)  # sides narrowing to the chin
    d = smax(d, P @ np.array([0, -0.9, -0.44]) - 0.86, 0.05)  # a raked chin plane
    keel = np.abs(x) * 0.35 + (P @ np.array([0, -0.94, -0.34])) - 0.9  # a ridge down the front to a heavy chin point
    d = smax(d, keel, 0.05)
    d = smin(d, sd_box(P, (0, -0.82, -0.47), (0.12, 0.08, 0.06), 0.04), 0.06)  # the chin block
    d = smax(d, -sd_box(P, (0, -0.4, -0.12), (0.36, 0.32, 0.32), 0.1), 0.03)  # hollow behind
    for s in (-1, 1):
        d = smin(d, sd_box(P, (s * 0.52, -0.3, -0.02), (0.05, 0.18, 0.2), 0.03), 0.06)  # arms back to the hinges
        d = smin(d, sd_capsule(P, (s * 0.52, -0.18, 0.12), (s * 0.6, -0.18, 0.12), 0.1), 0.03)  # hinge discs
    d = groove(d, np.where(y < -0.6, z + 0.1 + 0.05 * np.abs(x), 9.0), 0.016, 0.02, 0.006)  # a stern closed mouth line
    d = groove(d, np.where(y < -0.6, z + 0.2 + 0.03 * np.abs(x), 9.0), 0.008, 0.012, 0.004)
    d = groove(d, z + 0.36, 0.008, 0.012, 0.004)  # a seam across the chin
    return d


def gorget(P):
    d = sd_capsule(P, (0, 0.05, -0.3), (0, 0.08, -0.95), 0.5)
    return smax(d, -(P[..., 2] + 0.97), 0.03)


head = K.sdf_mesh("helm", helm, (-0.85, -1.1, -0.45), (0.85, 1.05, 1.95), 0.011, HELM)
jaw_o = K.sdf_mesh("jaw", jaw, (-0.75, -1.05, -0.65), (0.75, 0.0, 0.3), 0.01, JAW)
K.sdf_mesh("gorget", gorget, (-0.65, -0.5, -1.0), (0.65, 0.65, -0.2), 0.016, CLOTH)

# the dark recess behind the slit with the cold light deep inside
K.box("slit_dark", (0.66, 0.08, 0.12), (0, -0.74, 0.34), (0, 0, 0), DARK, 0.02, 2)
K.box("slit_light", (0.6, 0.03, 0.03), (0, -0.78, 0.34), (0, 0, 0), SLIT, 0.01, 1)
# the step between helm and jaw: a dark recess and cables
K.ball("face_recess", 0.4, (0, -0.55, -0.0), DARK, (1.1, 0.6, 0.35), 16)
for s in (-1, 1):
    K.tube("cable", K.smooth_path([(s * 0.3, -0.55, 0.08), (s * 0.36, -0.6, -0.02), (s * 0.42, -0.5, -0.1)], 12), 0.022, RUB, res=3)

# hinge pistons: from the helm's temple down to the jaw arm, each a sleeve + a polished rod
for s in (-1, 1):
    top = Vector((s * 0.7, 0.02, 0.44))
    bot = Vector((s * 0.6, -0.3, -0.12))
    mid = top.lerp(bot, 0.5)
    K.loft("piston_sleeve", lambda t, a=top, b=mid: a.lerp(b, t), lambda t: 0.06, 6, 16, mat=IRON)
    K.loft("piston_collar", lambda t, a=mid: a + (bot - top).normalized() * (0.025 * t), lambda t: 0.068, 3, 16, mat=IRON)
    K.loft("piston_rod", lambda t, a=mid, b=bot: a.lerp(b, t), lambda t: 0.034, 6, 12, mat=HELM)
    K.box("piston_bracket", (0.06, 0.12, 0.1), (s * 0.69, 0.04, 0.47), (0, 0, 0), IRON, 0.012, 2)
    K.box("piston_bracket", (0.06, 0.12, 0.1), (s * 0.58, -0.31, -0.15), (0, 0, 0), IRON, 0.012, 2)
    K.loft("hinge_cap", lambda t: Vector((s * (0.62 + 0.03 * t), -0.18, 0.12)), lambda t: 0.075 - 0.01 * t, 3, 16, mat=IRON)

# light lines in the crest grooves: thin glowing sheets inside the blade showing at the bottom of each groove


def crest_lines(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    h = crest_top(y)
    slope = (crest_top(y + 0.01) - crest_top(y - 0.01)) / 0.02
    edge = (z - h) / np.sqrt(1 + slope ** 2)
    t = CREST_T * (0.3 + 0.7 * np.clip(-edge / 0.25, 0, 1))
    d = 9.0
    for off in (0.07, 0.15, 0.23):
        d = np.minimum(d, np.abs(edge + off) - 0.007)
    d = np.maximum(d, np.abs(x) - (t - 0.007))
    d = np.maximum(d, -(y + 0.52))
    return np.maximum(d, 0.62 - z + 0.0 * y)


K.sdf_mesh("crest_lines", crest_lines, (-0.06, -0.6, 0.55), (0.06, 1.0, 2.15), 0.005, LINES)
for k, y in enumerate(np.linspace(-0.5, 0.86, 10)):
    for s in (-1, 1):
        ok, loc, nn, i = head.ray_cast(Vector((s * 0.115, y, 2.5)), Vector((0, 0, -1)))
        if ok:
            K.bolt(loc, nn, 0.026, IRON)
for zz in (0.3, 0.12, -0.02):  # down the back below the crest
    ok, loc, nn, i = head.ray_cast(Vector((0, 2.0, zz)), Vector((0, -1, 0)))
    if ok:
        for s in (-1, 1):
            K.bolt(loc + Vector((s * 0.1, 0, 0)), nn, 0.026, IRON)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("silent_judge")
print("ok")

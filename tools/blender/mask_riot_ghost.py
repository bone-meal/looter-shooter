# Riot Ghost mask (elite / mob mask 14, diary/DECISIONS_SKINS.md B14, plan in diary/MASK_PLANS_DROPS.md): a smooth
# heister face (base 2) of milky white "glass" (FAKED translucency, director 2026-11-22: a rim glow in the game) with
# a ghost's veil covering the head and streaming back in tapering tails. FRONT = the face, a blank stare from deep dark
# hollows, four faint faces under the skin (fxG_: they surface and sink in the game, fx drift); SIDE = the veil tearing
# off the face's edge and streaming back; BACK = the tails at different lengths, a ragged hem, folds from the crown.
# Run: python3 tools/blender/mask_riot_ghost.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py riot_ghost
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(141)


def milk(name, col=(0.82, 0.86, 0.9)):
    """Milky white glass: a faint frosty grain under a gloss coat, a cool tint deepening in the hollows."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3.0; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0]); mx.inputs[6].default_value = (*col, 1)
    mx.inputs[7].default_value = (col[0] * 0.8, col[1] * 0.86, col[2] * 0.95, 1)
    c, ao = K._ao_mix(N, L, mx.outputs[2], (0.28, 0.34, 0.42), 0.08)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.22
    gr = N.new("ShaderNodeTexNoise"); gr.inputs["Scale"].default_value = 90.0; gr.inputs["Detail"].default_value = 3
    L.new(tc.outputs["Object"], gr.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.08; bump.inputs["Distance"].default_value = 0.002
    L.new(gr.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


FACE_M = milk("face_milk")
VEIL_M = milk("veil_milk", (0.62, 0.71, 0.83))  # cooler and darker than the face: reads as thinner stuff
FACES = K.glow("fxG_inner_faces", (0.7, 0.85, 1.0), 7.0, base=(0.36, 0.44, 0.58))
EYES = K.glow("fxR_eye_light", (0.7, 0.85, 1.0), 6.0, base=(0.05, 0.06, 0.08))
DARK = K.simple("hollow", (0.01, 0.012, 0.016), 0.9)


def face_solid(P):
    """The heister face as a solid: soft exaggerated planes, deep eye hollows, a flat closed mouth."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, -0.25, 0.28), (0.6, 0.72, 0.86))
    d = smax(d, P @ np.array([0, -0.95, 0.3]) - 0.86, 0.28)  # the face plane, eased (no block edge)
    d = smin(d, sd_capsule(P, (-0.22, -0.86, 0.46), (0.22, -0.86, 0.46), 0.03), 0.16)  # a soft brow
    for s in (-1, 1):
        q = P - np.array([s * 0.22, -0.98, 0.33]); c_, s_ = math.cos(0.25 * s), math.sin(0.25 * s)
        qr = np.stack([q[..., 0] * c_ + q[..., 2] * s_, q[..., 1], -q[..., 0] * s_ + q[..., 2] * c_], -1)
        d = smax(d, -sd_ellipsoid(qr, (0, 0, 0), (0.13, 0.2, 0.065)), 0.05)  # deep almond eye hollows, drooping out
        d = smin(d, sd_ellipsoid(P, (s * 0.3, -0.8, 0.12), (0.16, 0.12, 0.1)), 0.1)  # cheekbones
        d = smax(d, -sd_ellipsoid(P, (s * 0.33, -0.86, -0.08), (0.1, 0.1, 0.1)), 0.1)  # hollow cheeks
    d = smin(d, sd_capsule(P, (0, -0.95, 0.34), (0, -0.99, 0.2), 0.035), 0.08)  # nose bridge, short
    d = smin(d, sd_ellipsoid(P, (0, -0.99, 0.18), (0.055, 0.05, 0.045)), 0.06)  # nose tip
    d = groove(d, np.where(y < -0.7, z + 0.13 + 0.02 * np.abs(x) ** 2, 9.0), 0.012, 0.012, 0.004)  # a flat closed mouth
    return d


def face(P):
    """The plate: the face solid hollowed to 0.07 thick (the hollow follows every feature), open behind."""
    d = face_solid(P)
    d = smax(d, -(d + 0.07), 0.01)
    return smax(d, P[..., 1] + 0.3, 0.05)


face_o = K.sdf_mesh("face", face, (-0.7, -1.2, -0.65), (0.7, -0.15, 1.2), 0.009, FACE_M)

# the veil: covers the head behind the face and streams back into tails
TAILS = [(-0.62, -0.55, 0.1), (0.6, -0.6, 0.1), (-0.42, -0.82, 0.1), (0.4, -0.78, 0.1), (-0.18, -0.95, 0.09),
         (0.2, -0.9, 0.09), (0.0, -1.0, 0.08)]  # torn strips hanging behind, kept above the shoulders


def veil(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)
    head = sd_ellipsoid(P, (0, 0.22, 0.42), (0.72, 0.98, 0.84))  # drawn back, as if streaming away
    sweep = sd_capsule(P, (0, 0.3, 0.75), (0, 1.15, 0.55), 0.22)  # the veil's crown swept back to a trailing point
    folds = 0.055 * (np.abs(np.sin(th * 5.0 + y * 2.5)) - 0.5) * np.clip(1.3 - z, 0, 1)  # creased folds running back
    neck = sd_capsule(P, (0, 0.05, -0.1), (0, 0.1, -0.9), 0.5)  # down round the neck under the face
    outer = smin(smin(head, sweep, 0.25), neck, 0.2) - (0.06 + folds)
    for tx, tz, r in TAILS:  # tails streaming back and down, curling at their ends
        a = np.array([tx, 0.7 - 0.25 * abs(tx), 0.3])
        b = np.array([tx * 1.2, 1.15 - 0.25 * abs(tx), tz])
        flat = P.copy(); flat[..., 1] = a[1] + (P[..., 1] - a[1]) * 2.4  # squashed front-to-back: flat ribbons, not tubes
        tail = sd_capsule(flat, tuple(a), (b[0], a[1] + (b[1] - a[1]) * 2.4, b[2]), r * 1.5) / 2.4 + 0.03 * np.clip((0.1 - z) / 1.0, 0, 1)
        outer = smin(outer, tail, 0.12)  # joined into one sheet at the top, splitting lower
    d = np.abs(outer) - 0.04  # a sheet 0.08 thick (thinner: its two sides cross once decimated and flicker)
    d = smax(d, -(z + 0.85) + 0.08 * np.sin(th * 9.0) + 0.05 * np.sin(th * 23.0), 0.03)  # a ragged hem
    d = smax(d, -(y + 0.5 + 0.2 * np.clip((-0.3 - z) / 0.25, 0, 1)), 0.05)  # tucked behind the plate's edge; under the chin it comes forward
    return d


veil_o = K.sdf_mesh("veil", veil, (-1.0, -0.62, -1.5), (1.0, 1.6, 1.55), 0.011, VEIL_M)

# eye hollows: darkness with a faint cold light deep inside
for s in (-1, 1):
    K.ball("eye_dark", 0.16, (s * 0.22, -0.84, 0.33), DARK, (1.0, 0.35, 0.8), 16)  # a backing behind the hole
    K.ball("eye_light", 0.045, (s * 0.22, -0.9, 0.31), EYES, (1.0, 0.5, 0.9), 12)


# ------------------------------------------------------------------ four faint faces just under the skin
def ghost_face(c, n, size):
    """A small open-mouthed face drawn in thin raised glowing lines on the surface at c (normal n)."""
    n = np.array(n) / np.linalg.norm(n)
    u = np.cross(n, [0.0, 0.0, 1.0]); u /= np.linalg.norm(u)
    v = np.cross(u, n)
    c = np.array(c)

    def fn(P):
        q = P - c
        along = q @ n
        a = (q @ u) / size; b = (q @ v) / size
        d = 9.0  # no outline: only drawn-out eye hollows and a long wailing mouth, faint under the skin
        for s in (-1, 1):
            ea = (a - s * 0.3) * math.cos(0.35 * s) + (b - 0.25) * math.sin(0.35 * s)
            eb = -(a - s * 0.3) * math.sin(0.35 * s) + (b - 0.25) * math.cos(0.35 * s)
            d = np.minimum(d, np.sqrt((ea / 0.13) ** 2 + (eb / 0.24) ** 2) - 1.0)
        d = np.minimum(d, np.sqrt(((a + 0.03 * np.sin(b * 6)) / 0.12) ** 2 + ((b + 0.45) / 0.38) ** 2) - 1.0)
        return np.maximum(d * size * 0.3, np.abs(face_solid(P) - 0.003) - 0.003)  # a thin skin just over the surface
    lo = tuple(c - size * 1.3); hi = tuple(c + size * 1.3)
    K.sdf_mesh("inner_face", fn, lo, hi, 0.0035, FACES)


for (px, pz, size) in ((0.02, 0.78, 0.24), (-0.36, 0.02, 0.2), (0.38, 0.05, 0.19)):
    ok, loc, nrm, i = face_o.ray_cast(Vector((px, -2.0, pz)), Vector((0, 1, 0)))
    if ok:
        ghost_face(tuple(loc), tuple(nrm), size)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("riot_ghost")
print("ok")

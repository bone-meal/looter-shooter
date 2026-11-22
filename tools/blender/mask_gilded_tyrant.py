# Gilded Tyrant mask (boss mask 7, diary/DECISIONS_SKINS.md A7 + diary/MASK_PROCESS.md section 5): an oversized
# mascot head (base 4) - a grinning lion king - in tarnished gold. Silhouette plan: FRONT = a huge crown + jewelled eye
# sockets (rubies in raised settings) + a wide toothy grin; SIDE = the oversized snout and the crown's points; BACK =
# the crown + a sunburst mane of jewel-set gold plates.
# Behaviour: tarnish in the recesses, polished high points, jewel settings with prongs; rubies fxR_, the plate and
# crown jewels fxG_ (they pulse in the game), gold dust falling and the mane plates "breathing" (game).
# Run: python3 tools/blender/mask_gilded_tyrant.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py gilded_tyrant
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(71)


# ------------------------------------------------------------------ materials
def gold(name, polish=0.22, tarnish=0.55):
    """Gold leaf over a cast: polished high points, a mottle of dull wear, dark tarnish (brown-green) in recesses."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Metallic"].default_value = 1.0
    tc = N.new("ShaderNodeTexCoord")
    mot = N.new("ShaderNodeTexNoise"); mot.inputs["Scale"].default_value = 9.0; mot.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    base = N.new("ShaderNodeMix"); base.data_type = "RGBA"
    L.new(mot.outputs["Fac"], base.inputs[0])
    base.inputs[6].default_value = (1.0, 0.64, 0.14, 1); base.inputs[7].default_value = (0.82, 0.48, 0.08, 1)  # saturated: the game's metal reflections wash it pale
    col, ao = K._ao_mix(N, L, base.outputs[2], (0.09 * tarnish, 0.07 * tarnish, 0.03 * tarnish), 0.09)
    L.new(col, b.inputs["Base Color"])
    rg = N.new("ShaderNodeMapRange"); rg.inputs["To Min"].default_value = polish; rg.inputs["To Max"].default_value = polish + 0.3
    L.new(mot.outputs["Fac"], rg.inputs["Value"]); L.new(rg.outputs["Result"], b.inputs["Roughness"])
    pit = N.new("ShaderNodeTexNoise"); pit.inputs["Scale"].default_value = 70.0; pit.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], pit.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.15; bump.inputs["Distance"].default_value = 0.003
    L.new(pit.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


GOLD = gold("tarnished_gold")
BRIGHT = gold("polished_gold", 0.2, 0.25)  # teeth, crown points, settings
MOUTH = K.simple("velvet_mouth", (0.09, 0.012, 0.015), 0.85)
RUBY = K.glow("fxR_ruby", (1.0, 0.05, 0.08), 8.0, base=(0.35, 0.0, 0.02))
EMERALD = K.glow("fxG_emerald", (0.1, 1.0, 0.45), 5.0, base=(0.0, 0.2, 0.08))
SAPPHIRE = K.glow("fxG_sapphire", (0.15, 0.35, 1.0), 5.0, base=(0.0, 0.03, 0.2))


def bent(P, k):
    """Bends space so a mouth cut along x curls up at its ends (a grin)."""
    Q = P.copy()
    Q[..., 2] = P[..., 2] - k * P[..., 0] ** 2
    return Q


MOUTH_C = (0.0, -1.18, -0.34)


def mouth_sd(P):
    return sd_ellipsoid(bent(P, 0.42), MOUTH_C, (0.66, 0.5, 0.16))


# ------------------------------------------------------------------ the head
def head(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, -0.1, 0.25), (1.02, 1.02, 0.98))  # the big round head
    for s in (-1, 1):
        d = smin(d, sd_ellipsoid(P, (s * 0.5, -0.72, -0.08), (0.44, 0.42, 0.4)), 0.18)  # puffed cheeks
        d = smin(d, sd_capsule(P, (s * 0.12, -0.98, 0.5), (s * 0.6, -0.8, 0.62), 0.11), 0.12)  # heavy scowling brow
        d = smax(d, -sd_ellipsoid(P, (s * 0.37, -0.95, 0.4), (0.21, 0.2, 0.17)), 0.05)  # the eye socket
        d = smin(d, sd_ellipsoid(P, (s * 0.86, -0.15, 0.78), (0.22, 0.12, 0.24)), 0.08)  # ear
        d = smax(d, -sd_ellipsoid(P, (s * 0.88, -0.22, 0.78), (0.14, 0.08, 0.16)), 0.03)  # inside of the ear
        d = smax(d, -sd_ellipsoid(P, (s * 0.09, -1.56, 0.13), (0.045, 0.05, 0.035)), 0.012)  # nostril
    d = smin(d, sd_ellipsoid(P, (0, -1.08, -0.1), (0.56, 0.46, 0.4)), 0.16)  # the oversized muzzle
    d = smin(d, sd_capsule(P, (0, -0.95, 0.45), (0, -1.38, 0.2), 0.12), 0.1)  # bridge of the nose
    d = smin(d, sd_ellipsoid(P, (0, -1.47, 0.15), (0.23, 0.15, 0.14)), 0.08)  # the big nose
    d = smin(d, sd_ellipsoid(P, (0, -0.95, -0.55), (0.42, 0.3, 0.2)), 0.12)  # heavy chin under the grin
    d = smax(d, -mouth_sd(P), 0.02)  # the grin, wide, its corners curling up
    furrow = np.where((z > 0.45) & (z < 0.7) & (y < -0.85), np.abs(x) - 0.06, 9.0)
    d = groove(d, furrow, 0.012, 0.014, 0.0)
    d = smin(d, sd_capsule(P, (0, 0.05, -0.5), (0, 0.1, -0.95), 0.52), 0.2)  # neck down to the collar
    d = smax(d, -(z + 0.97), 0.03)
    return d


face = K.sdf_mesh("head", head, (-1.15, -1.75, -1.0), (1.15, 1.0, 1.3), 0.013, GOLD)
face.data.materials.append(MOUTH)
for poly in face.data.polygons:  # inside the grin: dark velvet
    c = poly.center
    if mouth_sd(np.array([[c.x, c.y, c.z]]))[0] < 0.015:
        poly.material_index = 1


def on_face(origin, direction):
    return K.ray_onto(face, Vector(origin), Vector(direction))


# teeth: big rounded cartoon teeth along both lips of the grin, polished gold, fangs at the corners
cx, cy, cz = MOUTH_C
for row, sgn in (("upper", 1), ("lower", -1)):
    n = 7 if sgn > 0 else 6
    for k in range(n):
        xx = -0.5 + 1.0 * (k + 0.5) / n
        zz = cz + sgn * 0.16 * math.sqrt(max(0.0, 1 - (xx / 0.66) ** 2)) + 0.42 * xx * xx
        loc, nrm = on_face((xx, -2.2, zz + sgn * 0.02), (0, 1, 0))
        if loc is None:
            continue
        fang = k in (0, n - 1) and sgn > 0
        L = 0.24 if fang else (0.17 if abs(xx) < 0.3 else 0.14)
        w = 0.075 if fang else 0.1
        root = loc + Vector((0, 0.08, sgn * 0.03))
        K.loft("tooth", lambda t, r=root, s=sgn, L=L: r + Vector((0, -0.012 * t, -s * L * t)),
               lambda t, w=w, f=fang: w * (math.sqrt(max(0.0, 1 - t ** 4)) if not f else (1 - t) ** 0.8) + 0.006,
               12, 14, profile=lambda th, t: (1.0, 0.62), mat=BRIGHT)

# jewelled eye sockets: a raised setting ring, a big cut ruby, prongs
for s in (-1, 1):
    c = Vector((s * 0.37, -1.0, 0.4))
    n = Vector((s * 0.25, -1.0, 0.08)).normalized()
    ring = [c + (Matrix.Rotation(a, 3, n) @ (n.orthogonal().normalized() * 0.17)) for a in np.linspace(0, 2 * math.pi, 41)]
    K.tube("setting", ring, 0.03, BRIGHT, res=3)
    gem = K.ball("ruby", 0.14, c - n * 0.02, RUBY, (1.0, 1.0, 1.0), 8)  # low segments: facets
    gem.data.polygons.foreach_set("use_smooth", [False] * len(gem.data.polygons))
    for k in range(6):
        a = k * math.pi / 3
        p = c + (Matrix.Rotation(a, 3, n) @ (n.orthogonal().normalized() * 0.13)) + n * 0.06
        K.ball("prong", 0.026, p, BRIGHT, (1, 1, 1), 8)


# ------------------------------------------------------------------ the crown
CROWN_Z = 0.98


def crown_band(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    q = np.sqrt((x / 0.74) ** 2 + ((y + 0.1) / 0.74) ** 2)
    rad = (q - 1.0) * 0.74
    d = smax(np.abs(rad) - 0.06, np.abs(z - CROWN_Z) - 0.13, 0.02)
    for zz in (CROWN_Z - 0.1, CROWN_Z + 0.1):  # beaded rims
        d = smin(d, smax(np.abs(rad - 0.05) - 0.03, np.abs(z - zz) - 0.025, 0.012), 0.012)
    return d


band = K.sdf_mesh("crown_band", crown_band, (-0.9, -0.95, CROWN_Z - 0.2), (0.9, 0.75, CROWN_Z + 0.2), 0.011, BRIGHT)
random.seed(4)
for k in range(9):
    a = (k / 9.0) * 2 * math.pi
    out = Vector((math.sin(a), -math.cos(a), 0.0))
    base = Vector((0.8 * math.sin(a), -0.1 - 0.8 * math.cos(a), CROWN_Z + 0.1))
    front = 0.5 + 0.5 * math.cos(a)
    h = 0.42 + 0.38 * front
    pt = K.loft("crown_point", lambda t, b=base, h=h, o=out: b + Vector((0, 0, h * t)) + o * 0.08 * t,
                lambda t: 0.27 * (1 - t) ** 1.05 + 0.014, 16, 8,
                profile=lambda th, t, a=a: (max(0.2, abs(math.cos(a))), max(0.2, abs(math.sin(a)))), mat=BRIGHT)  # flat plates facing out
    pt.data.polygons.foreach_set("use_smooth", [False] * len(pt.data.polygons))
    gem_mat = EMERALD if k % 2 == 0 else SAPPHIRE
    K.ball("crown_tip", 0.055, base + Vector((0, 0, h + 0.03)) + out * 0.08, BRIGHT, (1, 1, 1), 12)  # a gold ball on each point
    loc_gem = base + out * 0.075 + Vector((0, 0, -0.1))
    g = K.ball("band_gem", 0.06, loc_gem, gem_mat, (1.0, 0.6, 1.0), 8)
    g.data.polygons.foreach_set("use_smooth", [False] * len(g.data.polygons))
    K.align(g, out)
# a cap of gold cloth inside the crown would be hidden: the head's own top shows (gold)


# ------------------------------------------------------------------ the mane: a sunburst of jewel-set gold plates
MANE_C = Vector((0.0, 0.42, 0.22))
# three tiers of broad overlapping plates with round ends, swept back and curling outward: a mane, not spikes
for tier, (r0, length, count, width, back) in enumerate(((0.84, 0.58, 21, 0.33, 0.0), (0.8, 0.46, 19, 0.3, 0.12), (0.74, 0.34, 17, 0.26, 0.24))):
    for k in range(count):
        a = math.radians(-112 + 224 * (k + 0.5 * (tier % 2)) / (count - 1))
        if abs(a) > math.radians(115):
            continue
        radial = Vector((math.sin(a), 0.0, math.cos(a)))
        root = MANE_C + radial * r0 + Vector((0, back, 0))
        tip = root + radial * length + Vector((0, 0.16 + back * 0.6, 0))
        curl = radial * 0.08

        def path(t, r=root, tp=tip, c=curl):
            return r.lerp(tp, t) + c * math.sin(math.pi * t) * 0.6
        K.loft("mane_plate", path,
               lambda t, w=width: w * math.sqrt(max(0.0, 1.0 - t ** 3)) * (0.75 + 0.25 * math.sin(math.pi * min(1.0, t * 1.6))) + 0.01,
               16, 12, profile=lambda th, t: (0.15, 1.0), mat=GOLD)
        if tier < 2:
            mid = root.lerp(tip, 0.62)
            gm = EMERALD if (k + tier) % 2 == 0 else SAPPHIRE
            for side in (-1, 1):  # a jewel on both faces of each outer plate
                g = K.ball("mane_gem", 0.042 - tier * 0.006, mid + Vector((0, side * 0.04, 0)), gm, (1.0, 0.6, 1.0), 8)
                g.data.polygons.foreach_set("use_smooth", [False] * len(g.data.polygons))
                K.align(g, Vector((0, side, 0)))

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

K.stage(head=False)
K.shoot_views("gilded_tyrant")
print("ok")

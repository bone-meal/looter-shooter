# Ashen King mask (boss mask 4, diary/DECISIONS_SKINS.md A4 + diary/MASK_PROCESS.md section 5): a smooth, slightly
# exaggerated full face (the base-2 "heister" face: soft planes, a scowl) in porcelain charred black from the crown
# down. Silhouette plan: FRONT = a cracked crown of charred ceramic spikes + a chunk broken out of one cheek with fire
# inside; SIDE = the face profile under the crown spikes; BACK = the crown ring + glowing crack lines down the skull.
# Behaviour: crackle glaze, soot gradient, ember-filled cracks (two groups: fxR_ always lit, fxG_ the cracks that
# open and heal in the game), coal eyes in deep almond holes.
# Run: python3 tools/blender/mask_ashen_king.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py ashen_king
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
SC = K.setup(41)
CHUNK = (0.52, -0.72, -0.03)  # the piece broken out of the (sculpt +x) cheek
CHUNK2 = (-0.5, 0.62, 0.22)  # a smaller break at the back


# ------------------------------------------------------------------ materials
def ceramic(name, char_lo, char_hi, crackle=18.0):
    """Glazed porcelain charred to black: soot rises from `char_lo` to fully black at `char_hi` (object z), warped by
    noise; ash-grey blooms in between; a crackle-glaze network shows in the white; soot gathers in cavities."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
    warp = N.new("ShaderNodeTexNoise"); warp.inputs["Scale"].default_value = 2.4; warp.inputs["Detail"].default_value = 8
    warp.inputs["Roughness"].default_value = 0.62
    L.new(tc.outputs["Object"], warp.inputs["Vector"])
    wz = N.new("ShaderNodeMath"); wz.operation = "MULTIPLY_ADD"; wz.inputs[1].default_value = 0.55; wz.inputs[2].default_value = -0.27
    L.new(warp.outputs["Fac"], wz.inputs[0])
    zz = N.new("ShaderNodeMath"); zz.operation = "ADD"
    L.new(sep.outputs["Z"], zz.inputs[0]); L.new(wz.outputs[0], zz.inputs[1])
    char = N.new("ShaderNodeMapRange"); char.inputs["From Min"].default_value = char_lo; char.inputs["From Max"].default_value = char_hi
    L.new(zz.outputs[0], char.inputs["Value"])
    # crackle glaze: thin dark lines (Voronoi cell edges), finer cells inside bigger ones
    cr = N.new("ShaderNodeTexVoronoi"); cr.feature = "DISTANCE_TO_EDGE"; cr.inputs["Scale"].default_value = crackle
    cr.inputs["Randomness"].default_value = 0.9
    L.new(tc.outputs["Object"], cr.inputs["Vector"])
    cr2 = N.new("ShaderNodeTexVoronoi"); cr2.feature = "DISTANCE_TO_EDGE"; cr2.inputs["Scale"].default_value = crackle * 2.7
    L.new(tc.outputs["Object"], cr2.inputs["Vector"])
    l1 = N.new("ShaderNodeMapRange"); l1.inputs["From Min"].default_value = 0.0; l1.inputs["From Max"].default_value = 0.035
    L.new(cr.outputs["Distance"], l1.inputs["Value"])
    l2 = N.new("ShaderNodeMapRange"); l2.inputs["From Min"].default_value = 0.0; l2.inputs["From Max"].default_value = 0.05
    L.new(cr2.outputs["Distance"], l2.inputs["Value"])
    lines = N.new("ShaderNodeMath"); lines.operation = "MINIMUM"
    L.new(l1.outputs["Result"], lines.inputs[0]); L.new(l2.outputs["Result"], lines.inputs[1])
    # porcelain with its crackle lines stained by soot
    pm = N.new("ShaderNodeMix"); pm.data_type = "RGBA"
    L.new(lines.outputs[0], pm.inputs[0])
    pm.inputs[6].default_value = (0.16, 0.13, 0.1, 1); pm.inputs[7].default_value = (0.8, 0.77, 0.7, 1)
    # ash: grey blooms where the noise is high in the half-burnt band
    ash_n = N.new("ShaderNodeTexNoise"); ash_n.inputs["Scale"].default_value = 9.0; ash_n.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], ash_n.inputs["Vector"])
    ash = N.new("ShaderNodeMix"); ash.data_type = "RGBA"
    am = N.new("ShaderNodeMapRange"); am.inputs["From Min"].default_value = 0.5; am.inputs["From Max"].default_value = 0.68
    L.new(ash_n.outputs["Fac"], am.inputs["Value"])
    L.new(am.outputs["Result"], ash.inputs[0])
    ash.inputs[6].default_value = (0.008, 0.007, 0.0065, 1); ash.inputs[7].default_value = (0.075, 0.07, 0.066, 1)
    cm = N.new("ShaderNodeMix"); cm.data_type = "RGBA"
    L.new(char.outputs["Result"], cm.inputs[0]); L.new(pm.outputs[2], cm.inputs[6]); L.new(ash.outputs[2], cm.inputs[7])
    col, ao = K._ao_mix(N, L, cm.outputs[2], (0.01, 0.009, 0.008), 0.08)
    L.new(col, b.inputs["Base Color"])
    # glazed where white, dry and dull where burnt
    rg = N.new("ShaderNodeMapRange"); rg.inputs["To Min"].default_value = 0.16; rg.inputs["To Max"].default_value = 0.86
    L.new(char.outputs["Result"], rg.inputs["Value"])
    L.new(rg.outputs["Result"], b.inputs["Roughness"])
    cw = N.new("ShaderNodeMapRange"); cw.inputs["To Min"].default_value = 0.6; cw.inputs["To Max"].default_value = 0.0
    L.new(char.outputs["Result"], cw.inputs["Value"])
    L.new(cw.outputs["Result"], b.inputs["Coat Weight"])
    b.inputs["Coat Roughness"].default_value = 0.08
    # relief: crackle lines sunk a hair, blistered char
    blis = N.new("ShaderNodeTexNoise"); blis.inputs["Scale"].default_value = 40.0; blis.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], blis.inputs["Vector"])
    bh = N.new("ShaderNodeMath"); bh.operation = "MULTIPLY"
    L.new(blis.outputs["Fac"], bh.inputs[0]); L.new(char.outputs["Result"], bh.inputs[1])
    hh = N.new("ShaderNodeMath"); hh.operation = "ADD"
    L.new(bh.outputs[0], hh.inputs[0]); L.new(lines.outputs[0], hh.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = 0.004
    L.new(hh.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


FACE = ceramic("porcelain", -0.55, 0.32)
CROWN = ceramic("crown_ceramic", 0.2, 0.7, crackle=12.0)
BISQUE = K.simple("bisque_broken", (0.22, 0.12, 0.07), 0.9)  # the raw, scorched body where the chunk broke away
EMBER = K.glow("fxR_ember", (1.0, 0.34, 0.05), 14.0, base=(0.25, 0.03, 0.0))
REFORM = K.glow("fxG_reform", (1.0, 0.5, 0.12), 10.0, base=(0.2, 0.04, 0.0))
HOLE = K.simple("eye_hole", (0.004, 0.003, 0.003), 0.9)


# ------------------------------------------------------------------ the face
def jag(P, f):
    return (np.sin(P[..., 0] * f + P[..., 2] * f * 0.37) * np.sin(P[..., 1] * f * 0.9 + P[..., 2] * f * 0.71)
            + 0.5 * np.sin(P[..., 0] * f * 2.3 - P[..., 1] * f * 1.7 + P[..., 2] * f * 1.3))


def chunk_sd(P):
    return np.minimum(sd_ellipsoid(P, CHUNK, (0.21, 0.2, 0.17)), sd_ellipsoid(P, CHUNK2, (0.17, 0.17, 0.15))) + 0.035 * jag(P, 34.0)


def face(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.2), (0.8, 0.94, 0.82))  # cranium (its dome sits inside the crown)
    d = smax(d, y - 0.86, 0.2)  # a flatter back
    d = smin(d, sd_ellipsoid(P, (0, -0.36, -0.28), (0.62, 0.64, 0.52)), 0.25)  # lower face and jaw
    d = smin(d, sd_ellipsoid(P, (0, -0.8, -0.5), (0.24, 0.17, 0.17)), 0.16)  # chin
    d = smax(d, -y - 1.0, 0.18)  # the face's soft front plane
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.05, -0.99, 0.35), (s * 0.5, -0.84, 0.47), 0.075), 0.08)  # brow: a scowl, low at the middle
        d = smin(d, sd_ellipsoid(P, (s * 0.46, -0.75, 0.07), (0.21, 0.16, 0.13)), 0.12)  # cheekbone
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.42, 0.36), (0.12, 0.2, 0.16)), 0.12)  # temple
        d = smax(d, -sd_ellipsoid(P, (s * 0.3, -0.98, 0.25), (0.17, 0.12, 0.095)), 0.05)  # eye socket
        d = smax(d, -sd_ellipsoid(P, (s * 0.3, -0.93, 0.245), (0.11, 0.3, 0.04)), 0.015)  # the almond eye hole
        d = smin(d, sd_ellipsoid(P, (s * 0.075, -1.05, 0.02), (0.05, 0.05, 0.04)), 0.03)  # nostril wing
        d = smax(d, -sd_ellipsoid(P, (s * 0.045, -1.12, 0.0), (0.02, 0.02, 0.014)), 0.008)  # nostril
    d = smin(d, sd_capsule(P, (0, -0.98, 0.33), (0, -1.1, 0.07), 0.052), 0.06)  # nose bridge
    d = smin(d, sd_ellipsoid(P, (0, -1.1, 0.04), (0.09, 0.07, 0.065)), 0.05)  # nose tip
    d = smin(d, sd_ellipsoid(P, (0, -0.9, -0.2), (0.3, 0.14, 0.18)), 0.12)  # muzzle
    d = smin(d, sd_ellipsoid(P, (0, -1.02, -0.165), (0.17, 0.05, 0.035)), 0.03)  # upper lip
    d = smin(d, sd_ellipsoid(P, (0, -1.0, -0.25), (0.15, 0.05, 0.04)), 0.03)  # lower lip
    mouth = np.where((np.abs(x) < 0.19) & (y < -0.85), z + 0.207 + 0.05 * (x / 0.18) ** 2, 9.0)  # corners turned down
    d = groove(d, mouth, 0.014, 0.008, 0.0)
    furrow = np.where((z > 0.3) & (z < 0.47) & (y < -0.8), np.abs(x) - 0.035, 9.0)  # the scowl's furrows
    d = groove(d, furrow, 0.007, 0.01, 0.0)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.5), 0.2)  # neck down to the collar
    for s in (-1, 1):  # occipital ridge across the back
        d = smin(d, sd_capsule(P, (s * 0.55, 0.62, 0.0), (0, 0.84, -0.08), 0.06), 0.08)
    # the face is a plate on the ceramic helm: a stepped rim from the temples past the ears to the jaw
    edge = np.where(y < 0.2, y - (-0.42 + 0.22 * np.clip((0.55 - z) / 1.3, 0.0, 1.0)), 9.0)
    d = groove(d, edge, 0.012, 0.012, -0.022)
    d = smax(d, -(z + 0.97), 0.03)
    d = smax(d, -chunk_sd(P), 0.012)  # the broken cheek
    return d


# first pass, coarse, only to walk the cracks over
rough = K.sdf_mesh("rough_face", face, (-0.95, -1.25, -1.0), (0.95, 1.1, 1.2), 0.028, None, relax=0)


def walk(start, heading, steps, step=0.032, wobble=0.45, branch=0.08, depth=0, max_depth=2):
    """A crack over `rough` from near `start`: a jittery walk in the surface, now and then forking. Returns a list of
    point lists (each with its normals)."""
    loc, n = K.ray_onto(rough, Vector(start) * 3.0, -Vector(start))
    if loc is None:
        return []
    paths, pts, h = [], [(loc, n)], Vector(heading)
    for i in range(steps):
        p, n = pts[-1]
        t = (h - n * h.dot(n)).normalized()
        t = Matrix.Rotation(random.uniform(-wobble, wobble), 3, n) @ t
        q = p + t * step
        nl, nn = K.ray_onto(rough, q + n * 0.25, -n)
        if nl is None or (nl - p).length > step * 2.5:
            break
        h = (nl - p).normalized()
        pts.append((nl, nn))
        if depth < max_depth and random.random() < branch and i > 2:
            side = Matrix.Rotation(random.choice((-1, 1)) * random.uniform(0.5, 0.9), 3, nn) @ h
            paths += walk(nl / 3.0 * 3.0 + nn * 0.0, side, int(steps * 0.45), step, wobble, branch * 0.5, depth + 1, max_depth)
    paths.insert(0, pts)
    return paths


EMBER_CRACKS, REFORM_CRACKS = [], []
cx, cy, cz = CHUNK
for k in range(5):  # out from the broken cheek
    a = k * 2 * math.pi / 5 + 0.3
    dirv = Vector((0.0, math.cos(a), math.sin(a)))
    start = Vector((cx + 0.03, cy, cz)) + dirv * 0.2
    EMBER_CRACKS += walk(start, Vector((-0.4, dirv.y, dirv.z)), 9 + k % 3 * 3)
for k in range(4):  # out from the break at the back
    a = k * 2 * math.pi / 4 + 0.5
    dirv = Vector((0.0, math.cos(a), math.sin(a)))
    EMBER_CRACKS += walk(Vector(CHUNK2) + Vector((0.6 * dirv.y * 0.3, 0.0, 0.0)) + dirv * 0.17, Vector((0.5, dirv.y, dirv.z)), 8)
for s in (-1, 1):  # down the forehead from the crown
    EMBER_CRACKS += walk((s * 0.18, -0.75, 0.62), (s * 0.2, -0.3, -1), 12)
for k in range(6):  # down the back of the skull from the crown ring
    a = math.pi + (k - 2.5) * 0.36
    EMBER_CRACKS += walk((0.75 * math.sin(a), -0.82 * math.cos(a), 0.5), (0, 0, -1), 16, branch=0.14)
for start, head_to in (((-0.45, -0.75, 0.0), (0, -0.2, -1)), ((-0.3, -0.7, -0.45), (1, -0.2, -0.3)),
                       ((0.55, -0.2, 0.3), (0.2, 0.6, -1)), ((-0.6, 0.3, 0.1), (0, 1, -0.6)),
                       ((0.3, 0.6, -0.2), (-1, 0.2, -0.3))):  # the cracks that open and heal (fxG_)
    REFORM_CRACKS += walk(start, head_to, 11)
cracks = [(p, EMBER) for p in EMBER_CRACKS] + [(p, REFORM) for p in REFORM_CRACKS]
K.bpy.data.objects.remove(rough, do_unlink=True)

SEG_A, SEG_B, SEG_W = [], [], []
for pts, _m in cracks:
    for i in range(len(pts) - 1):
        f = 1.0 - i / max(len(pts) - 1, 1)
        SEG_A.append(tuple(pts[i][0])); SEG_B.append(tuple(pts[i + 1][0])); SEG_W.append(0.6 + 0.4 * f)
SEG_A, SEG_B, SEG_W = np.array(SEG_A), np.array(SEG_B), np.array(SEG_W)


def cracked_face(P):
    d = face(P)
    band = np.abs(d) < 0.05
    Q = P[band]
    best = np.full(len(Q), 9.0); wbest = np.ones(len(Q))
    for a, b, w in zip(SEG_A, SEG_B, SEG_W):
        ba = b - a; pa = Q - a
        h = np.clip((pa @ ba) / max(ba @ ba, 1e-9), 0.0, 1.0)
        dist = np.linalg.norm(pa - h[:, None] * ba, axis=1)
        closer = dist < best
        best = np.where(closer, dist, best); wbest = np.where(closer, w, wbest)
    d2 = d.copy()
    d2[band] = d[band] + 0.022 * wbest * np.exp(-(best / (0.013 * wbest)) ** 2)
    return d2


head = K.sdf_mesh("face", cracked_face, (-0.95, -1.25, -1.0), (0.95, 1.1, 1.2), 0.012, FACE)
head.data.materials.append(BISQUE)
for poly in head.data.polygons:  # the broken edge: raw scorched body inside the chunk
    c = poly.center
    if chunk_sd(np.array([[c.x, c.y, c.z]]))[0] < 0.03:
        poly.material_index = 1

# ember lines lying in the crack grooves (fine detail: baked into the maps, glowing in the game)
for pts, mat in cracks:
    if len(pts) < 3:
        continue
    line = [p - n * 0.012 for p, n in pts]
    K.tube("crack", line, 0.009, mat, res=2, taper=lambda t: 1.0 - 0.5 * t)
# fire inside the broken cheek and coals in the eyes
K.ball("cheek_fire", 0.13, Vector(CHUNK) + Vector((-0.08, 0.02, 0.0)), EMBER, (0.9, 1.0, 0.9), 20)
K.ball("back_fire", 0.08, Vector(CHUNK2) + Vector((0.13, -0.11, 0.0)), EMBER, (0.9, 0.9, 0.9), 20)
for s in (-1, 1):
    K.ball("eye_dark", 0.1, (s * 0.3, -0.77, 0.245), HOLE, (1.0, 1.0, 0.45), 16)
    K.ball("eye_coal", 0.05, (s * 0.3, -0.89, 0.24), EMBER, (1.1, 0.5, 0.42), 16)


# ------------------------------------------------------------------ the crown: a ring of charred ceramic, spikes, some broken
def crown_ring(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    q = np.sqrt((x / 0.8) ** 2 + ((y - 0.04) / 0.9) ** 2)
    rad = (q - 1.0) * 0.78
    d = smax(np.abs(rad) - 0.05, np.abs(z - 0.66) - 0.1, 0.02)
    d = d + 0.012 * jag(P, 22.0) * (z > 0.72)  # a chipped top edge
    for zz in (0.6, 0.72):  # two raised bands round it
        d = smin(d, smax(np.abs(rad - 0.03) - 0.025, np.abs(z - zz) - 0.012, 0.01), 0.01)
    return d


crown = K.sdf_mesh("crown_ring", crown_ring, (-0.92, -0.98, 0.5), (0.92, 1.02, 0.84), 0.012, CROWN)
random.seed(9)
broken = {2, 6, 9}
for k in range(12):
    a = (k / 12.0) * 2 * math.pi
    base = Vector((0.82 * math.sin(a), 0.04 - 0.92 * math.cos(a), 0.74))
    out = Vector((math.sin(a), -math.cos(a), 0.0))
    front = 0.5 + 0.5 * math.cos(a)  # 1 at the front, 0 at the back
    h = 0.42 + 0.42 * front + random.uniform(-0.05, 0.06)
    tip_r = 0.004
    if k in broken:
        h *= random.uniform(0.38, 0.5); tip_r = 0.035
    lean = out * (0.18 + 0.1 * front)
    twist = random.uniform(-0.6, 0.6)
    K.loft("spike", lambda t, b=base, h=h, l=lean: b + Vector((0, 0, h * t)) + l * h * t ** 1.5,
           lambda t, tr=tip_r: 0.1 * (1 - t) ** 0.9 + tr, 14, 5,
           profile=lambda th, t, tw=twist: (1.0 + 0.25 * math.cos(3 * th + tw), 0.8), mat=CROWN)
    # a small spike between each pair
    a2 = a + math.pi / 12
    b2 = Vector((0.82 * math.sin(a2), 0.04 - 0.92 * math.cos(a2), 0.74))
    o2 = Vector((math.sin(a2), -math.cos(a2), 0.0))
    h2 = 0.16 + 0.1 * front
    K.loft("spikelet", lambda t, b=b2, h=h2, o=o2: b + Vector((0, 0, h * t)) + o * 0.04 * t,
           lambda t: 0.045 * (1 - t) + 0.003, 8, 5, mat=CROWN)

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

# preview only: ash flakes and embers rising off the crown (the game's are particles)
ASH = K.simple("ash", (0.25, 0.24, 0.23), 0.9)
for i in range(26):
    a = random.uniform(0, 2 * math.pi); r = random.uniform(0.2, 0.9)
    p = Vector((r * math.sin(a), -r * math.cos(a) * 0.9, random.uniform(1.1, 2.1)))
    if i % 3 == 0:
        K.ball("ember_spark", 0.012, p, EMBER, (1, 1, 1), 6)
    else:
        f = K.box("ash_flake", (0.035, 0.03, 0.004), p, rot=(random.uniform(0, 3), random.uniform(0, 3), 0), mat=ASH, bev=0.002)
K.stage(head=False)
K.shoot_views("ashen_king")
print("ok")

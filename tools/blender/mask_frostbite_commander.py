# Frostbite Commander mask (boss mask 6, diary/DECISIONS_SKINS.md A6 + diary/MASK_PROCESS.md section 5): a ballistic
# (base 3) armour helm of overlapping plates - crown, brow bar over a visor slit, cheek plates with vent slats, jaw
# plate, ear hinges - in arctic-painted steel with rime in every seam, and LIVING ICE growing out of it.
# Silhouette plan: FRONT = ice crystal clusters out of the visor edge + the jaw vents; SIDE = the plates + crystal
# spikes breaking the outline; BACK = frost-crusted bolts + icicles hanging off the rim.
# Behaviour: visor glow fxR_ (icy blue), the ice fxG_ (a faint inner light: the game lets it crack and re-form), mist
# from the vents and frost drifting off on quick turns (game particles).
# Run: python3 tools/blender/mask_frostbite_commander.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py frostbite_commander
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
SC = K.setup(61)


# ------------------------------------------------------------------ materials
def armour(name):
    """Arctic paint on steel: blue-grey with a mottle, rime (white frost) gathered in seams and on upward faces."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mot = N.new("ShaderNodeTexNoise"); mot.inputs["Scale"].default_value = 7.0; mot.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    paint = N.new("ShaderNodeMix"); paint.data_type = "RGBA"
    L.new(mot.outputs["Fac"], paint.inputs[0])
    paint.inputs[6].default_value = (0.05, 0.07, 0.09, 1); paint.inputs[7].default_value = (0.11, 0.14, 0.18, 1)
    # frost on upward faces, broken up by noise
    geo = N.new("ShaderNodeNewGeometry")
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Normal"], sep.inputs[0])
    fn = N.new("ShaderNodeTexNoise"); fn.inputs["Scale"].default_value = 4.0; fn.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], fn.inputs["Vector"])
    up = N.new("ShaderNodeMath"); up.operation = "MULTIPLY_ADD"; up.inputs[2].default_value = -0.35
    L.new(sep.outputs["Z"], up.inputs[0]); L.new(fn.outputs["Fac"], up.inputs[1])
    fr = N.new("ShaderNodeMapRange"); fr.inputs["From Min"].default_value = 0.15; fr.inputs["From Max"].default_value = 0.6
    L.new(up.outputs[0], fr.inputs["Value"])
    fm = N.new("ShaderNodeMix"); fm.data_type = "RGBA"
    L.new(fr.outputs["Result"], fm.inputs[0]); L.new(paint.outputs[2], fm.inputs[6])
    fm.inputs[7].default_value = (0.72, 0.8, 0.86, 1)
    col, ao = K._ao_mix(N, L, fm.outputs[2], (0.78, 0.86, 0.92), 0.05)  # rime packed into the seams
    L.new(col, b.inputs["Base Color"])
    rg = N.new("ShaderNodeMapRange"); rg.inputs["To Min"].default_value = 0.42; rg.inputs["To Max"].default_value = 0.85
    L.new(fr.outputs["Result"], rg.inputs["Value"]); L.new(rg.outputs["Result"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.25
    sp = N.new("ShaderNodeTexNoise"); sp.inputs["Scale"].default_value = 90.0; sp.inputs["Detail"].default_value = 3
    L.new(tc.outputs["Object"], sp.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.003
    L.new(sp.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


PLATE = armour("arctic_plate")
DARK = K.simple("vent_dark", (0.02, 0.025, 0.03), 0.7, metal=0.6)
VISOR = K.glow("fxR_visor", (0.35, 0.8, 1.0), 9.0, base=(0.05, 0.12, 0.16))
ICE = K.simple("fxG_ice", (0.42, 0.66, 0.84), 0.07, emit=(0.4, 0.75, 1.0), es=0.6)
ICE.node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 1.0
RIME = K.simple("rime", (0.8, 0.86, 0.9), 0.85)
BOLT = K.steel("bolt_steel", base=(0.16, 0.17, 0.18), heat=0.0, rust=0.2)


# ------------------------------------------------------------------ the helm
def plane(P, n, k):
    n = np.array(n, dtype=float); n = n / np.linalg.norm(n)
    return P @ n - k


def helm(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_box(P, (0, -0.02, 0.16), (0.8, 0.9, 0.9), 0.34)  # a boxy shell
    d = smax(d, sd_ellipsoid(P, (0, 0.0, 0.12), (0.98, 1.08, 1.08)), 0.1)  # its top rounded off
    d = smax(d, plane(P, (0, -0.55, 0.84), 0.78), 0.04)  # a chamfered brow-to-crown facet
    for s in (-1, 1):
        d = smax(d, plane(P, (s * 0.62, -0.78, 0.0), 0.9), 0.04)  # the face as a shallow prow
        d = smax(d, plane(P, (s * 0.5, 0.0, 0.86), 0.96), 0.05)  # crown side facets
        d = smax(d, plane(P, (s * 0.55, 0.62, 0.0), 0.98), 0.05)  # back corners
    d = smin(d, sd_box(P, (0, -0.94, 0.42), (0.6, 0.1, 0.075), 0.03), 0.05)  # the brow bar over the visor
    jaw = sd_box(P, (0, -0.6, -0.34), (0.6, 0.44, 0.32), 0.1)
    for s in (-1, 1):
        jaw = smax(jaw, plane(P, (s * 0.66, -0.74, -0.12), 0.84), 0.02)  # the jaw plate's prow: a sharp keel down the middle
    jaw = smax(jaw, plane(P, (0, -0.5, -0.87), 0.88), 0.03)  # its underside raked back to the chin's point
    d = smin(d, jaw, 0.05)
    d = smax(d, np.abs(x) - 0.84, 0.05)  # nothing sticks out past the sides (the brow bar's ends)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.52), 0.18)  # neck guard down to the collar
    d = smax(d, -(z + 0.97), 0.03)
    for s in (-1, 1):  # ear hinge plates: flat round bosses
        d = smin(d, smax(np.sqrt((y + 0.12) ** 2 + (z - 0.02) ** 2) - 0.2, np.abs(x - s * 0.84) - 0.07, 0.03), 0.03)
    d = smax(d, -sd_box(P, (0, -1.05, 0.27), (0.62, 0.35, 0.055), 0.02), 0.012)  # the visor slit
    for k in range(3):  # vent slats raked down toward the keel, on both sides of the jaw (a snarl, not a grille)
        zz = -0.06 - k * 0.1
        vent = np.where((np.abs(x) > 0.12) & (np.abs(x) < 0.52) & (y < -0.5), z - (zz - 0.45 * (0.52 - np.abs(x))), 9.0)
        d = groove(d, vent, 0.026, 0.013, 0.0)
    w_top = np.clip((z - 0.3) / 0.2, 0.0, 1.0)
    for s in (-1, 1):  # crown plate over the side plates
        pd = s * x - 0.46
        d = d + 0.012 * w_top * np.exp(-(pd / 0.014) ** 2) - 0.016 * w_top * 0.5 * (1.0 - np.tanh(pd / 0.005))
    face = np.where(z < 0.5, y - (-0.5 + 0.2 * np.clip((0.1 - z) / 1.0, 0.0, 1.0)), 9.0)  # face plates over the sides
    d = groove(d, face, 0.012, 0.014, -0.02)
    d = groove(d, z + 0.48, 0.01, 0.012, 0.012)  # the neck guard's lip
    back = np.where(y > 0.2, z - 0.05, 9.0)  # a band round the back of the skull
    d = groove(d, back, 0.012, 0.014, -0.014)
    return d


head = K.sdf_mesh("helm", helm, (-1.05, -1.25, -1.0), (1.05, 1.1, 1.2), 0.012, PLATE)
# the visor's glowing strip deep in the slit
K.box("visor_glow", (1.12, 0.03, 0.06), (0, -0.9, 0.27), mat=VISOR, bev=0.015)
K.box("visor_back", (1.2, 0.04, 0.12), (0, -0.84, 0.27), mat=DARK, bev=0.01)


def on_helm(origin, direction):
    return K.ray_onto(head, Vector(origin), Vector(direction))


# bolts: round the ear hinges, along the brow bar, on the back band (frost-crusted)
for s in (-1, 1):
    for k in range(6):
        a = k * math.pi / 3
        loc, n = on_helm((s * 1.6, -0.12 + 0.14 * math.cos(a), 0.02 + 0.14 * math.sin(a)), (-s, 0, 0))
        if loc:
            K.bolt(loc, n, 0.022, BOLT)
    for xx in (0.2, 0.45):
        loc, n = on_helm((s * xx, -1.6, 0.47), (0, 1, 0))
        if loc:
            K.bolt(loc, n, 0.025, BOLT)
frosted = []
for k in range(9):
    a = math.pi * (0.12 + 0.76 * k / 8)
    loc, n = on_helm((1.6 * math.cos(a), 1.6 * math.sin(a), 0.1), (-math.cos(a), -math.sin(a), 0))
    if loc:
        K.bolt(loc, n, 0.026, BOLT)
        frosted.append((loc, n))
random.seed(5)
for loc, n in frosted:  # rime crusted over the back bolts
    for j in range(5):
        off = Vector((random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), random.uniform(-0.01, 0.035)))
        K.ball("rime", random.uniform(0.012, 0.022), loc + n * 0.02 + off, RIME, (1.0, 1.0, 0.7), 8)


# ------------------------------------------------------------------ living ice
def crystal(base, direction, length, r):
    """A hexagonal ice prism with a point, rooted a little into the plate."""
    dvec = Vector(direction).normalized()
    start = Vector(base) - dvec * 0.03
    twist = random.uniform(0, 1)
    K.loft("ice", lambda t: start + dvec * (length * t),
           lambda t: r * (1.0 if t < 0.72 else max(0.0, (1.0 - t) / 0.28)) + 0.002, 8, 6,
           profile=lambda th, t, tw=twist: (1.0 + 0.0 * tw, 1.0), mat=ICE)


def cluster(origin, ray, out, n, size, spread=0.6):
    loc, nrm = on_helm(origin, ray)
    if loc is None:
        return
    axis = (Vector(out).normalized() + nrm * 0.6).normalized()
    for k in range(n):
        tilt = Matrix.Rotation(random.uniform(-spread, spread), 3, axis.orthogonal().normalized())
        spin = Matrix.Rotation(random.uniform(0, 2 * math.pi), 3, axis)
        d = spin @ tilt @ axis
        big = 1.0 if k == 0 else random.uniform(0.35, 0.8)
        crystal(loc + Vector((random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03))),
                d, size * big, size * big * random.uniform(0.17, 0.24))


random.seed(11)
# out of the visor's top edge (biggest at the left corner) and hanging off its lower edge
cluster((0.52, -2.0, 0.35), (0, 1, 0), (0.5, -1.0, 0.6), 9, 0.58)
cluster((-0.4, -2.0, 0.35), (0, 1, 0), (-0.3, -1.0, 0.5), 6, 0.38)
# out of the right cheek's vents
cluster((-0.36, -2.0, -0.2), (0, 1, 0), (-0.6, -1.0, -0.3), 7, 0.42)
cluster((0.38, -2.0, -0.3), (0, 1, 0), (0.6, -1.0, -0.5), 4, 0.26)
# spikes breaking the side outline (big on the left, smaller right), on the crown, one at the back
cluster((2.0, -0.45, 0.45), (-1, 0, 0), (1.0, -0.1, 0.8), 8, 0.62)
cluster((2.0, 0.35, 0.15), (-1, 0, 0), (1.0, 0.4, 0.2), 5, 0.36)
cluster((-2.0, -0.2, 0.55), (1, 0, 0), (-1.0, 0.0, 0.9), 5, 0.4)
cluster((0.3, 0.1, 2.0), (0, 0, -1), (0.3, 0.2, 1.0), 6, 0.45)
cluster((0.55, -0.35, 2.0), (0, 0, -1), (0.7, -0.3, 1.0), 10, 0.55, 0.75)  # the ice taking over the crown's left side
cluster((0.62, 0.5, 2.0), (0, 0, -1), (0.8, 0.4, 0.8), 7, 0.4, 0.7)
cluster((-0.45, 2.0, 0.55), (0, -1, 0), (-0.4, 1.0, 0.6), 5, 0.36)
# icicles hanging off the back rim (the neck guard's lip and the back band)
for k in range(15):
    a = math.pi * (0.08 + 0.84 * k / 14)
    for zz, scale in ((-0.47, 1.0), (0.04, 0.55)):
        loc, nrm = on_helm((1.6 * math.cos(a), 1.6 * math.sin(a), zz), (-math.cos(a), -math.sin(a), 0))
        if loc and random.random() < 0.8:
            L = random.uniform(0.1, 0.32) * scale
            crystal(loc + nrm * 0.015, (nrm.x * 0.15, nrm.y * 0.15, -1.0), L, L * 0.16)

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

K.stage(head=False)
K.shoot_views("frostbite_commander")
print("ok")

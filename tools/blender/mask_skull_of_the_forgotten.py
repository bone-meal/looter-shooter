# Skull of the Forgotten mask (elite 21, diary/DECISIONS_SKINS.md B21, plan in diary/MASK_PLANS_DROPS.md): an old
# human skull long buried in a forest floor, dug up with the forest still growing through it (full skull, base 10).
# FRONT = a crack across the brow, a chunk of the left brow gone, a ROOT bursting out of the left orbit and curling
# up over the brow, MOSS packed in the right orbit and the nose, teeth with gaps, the lower jaw HELD ON BY ROOTS, a
# small SAPLING sprouting from the crown. SIDE = roots gripping the cheekbone and temple like fingers, BRACKET FUNGI
# stepping out of the right temple, a broken hole in the parietal filled with moss. BACK = a ROOT BEARD hanging from
# the base of the skull over a dark earth-and-moss mass round the neck (to the collar line), moss on the crown.
# Glow: small pale mushroom caps (fxG_) in the moss. Kept apart from the Bone Cathedral (no spires, no light through
# bone, no vertebrae).
# Run: python3 tools/blender/mask_skull_of_the_forgotten.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py skull_of_the_forgotten
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
SC = K.setup(211)


def weathered_bone(name):
    """Bone long in the soil: brown-green stains, lichen rosettes, soil in cracks and pits, chipped and porous."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mot = N.new("ShaderNodeTexNoise"); mot.inputs["Scale"].default_value = 6.0; mot.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(mot.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (0.46, 0.39, 0.26, 1)  # darker than it looks right in the preview: the game sun washes bone out
    mx.inputs[7].default_value = (0.25, 0.2, 0.12, 1)
    # broad soil stains, greener toward the bottom
    st = N.new("ShaderNodeTexNoise"); st.inputs["Scale"].default_value = 2.4; st.inputs["Detail"].default_value = 5
    L.new(tc.outputs["Object"], st.inputs["Vector"])
    sr = N.new("ShaderNodeMapRange"); sr.inputs["From Min"].default_value = 0.42; sr.inputs["From Max"].default_value = 0.62
    sr.inputs["To Max"].default_value = 0.92
    L.new(st.outputs["Fac"], sr.inputs["Value"])
    ms = N.new("ShaderNodeMix"); ms.data_type = "RGBA"
    L.new(sr.outputs["Result"], ms.inputs[0]); L.new(mx.outputs[2], ms.inputs[6])
    ms.inputs[7].default_value = (0.16, 0.14, 0.06, 1)
    # lichen rosettes: small round patches (Voronoi F1 under a radius), grey-green and a few orange
    li = N.new("ShaderNodeTexVoronoi"); li.inputs["Scale"].default_value = 9.0; li.inputs["Randomness"].default_value = 1.0
    L.new(tc.outputs["Object"], li.inputs["Vector"])
    lr = N.new("ShaderNodeMapRange"); lr.inputs["From Min"].default_value = 0.12; lr.inputs["From Max"].default_value = 0.2
    lr.inputs["To Min"].default_value = 1.0; lr.inputs["To Max"].default_value = 0.0
    L.new(li.outputs["Distance"], lr.inputs["Value"])
    lc = N.new("ShaderNodeMapRange"); lc.inputs["From Min"].default_value = 0.0; lc.inputs["From Max"].default_value = 1.0
    lc.inputs["To Min"].default_value = 0.0; lc.inputs["To Max"].default_value = 1.0
    L.new(li.outputs["Color"], lc.inputs["Value"])
    ml = N.new("ShaderNodeMix"); ml.data_type = "RGBA"
    L.new(lr.outputs["Result"], ml.inputs[0]); L.new(ms.outputs[2], ml.inputs[6])
    lic = N.new("ShaderNodeMix"); lic.data_type = "RGBA"
    L.new(lc.outputs["Result"], lic.inputs[0])
    lic.inputs[6].default_value = (0.36, 0.42, 0.28, 1)
    lic.inputs[7].default_value = (0.62, 0.36, 0.1, 1)
    L.new(lic.outputs[2], ml.inputs[7])
    # hairline cracks with soil in them
    cr = N.new("ShaderNodeTexVoronoi"); cr.feature = "DISTANCE_TO_EDGE"; cr.inputs["Scale"].default_value = 3.6
    L.new(tc.outputs["Object"], cr.inputs["Vector"])
    crm = N.new("ShaderNodeMapRange"); crm.inputs["From Min"].default_value = 0.0; crm.inputs["From Max"].default_value = 0.014
    crm.inputs["To Min"].default_value = 1.0; crm.inputs["To Max"].default_value = 0.0
    L.new(cr.outputs["Distance"], crm.inputs["Value"])
    mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
    L.new(crm.outputs["Result"], mc.inputs[0]); L.new(ml.outputs[2], mc.inputs[6])
    mc.inputs[7].default_value = (0.05, 0.035, 0.02, 1)
    col, ao = K._ao_mix(N, L, mc.outputs[2], (0.05, 0.04, 0.02), 0.1)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.82
    pores = N.new("ShaderNodeTexVoronoi"); pores.inputs["Scale"].default_value = 55.0
    L.new(tc.outputs["Object"], pores.inputs["Vector"])
    pr = N.new("ShaderNodeMapRange"); pr.inputs["From Min"].default_value = 0.0; pr.inputs["From Max"].default_value = 0.18
    L.new(pores.outputs["Distance"], pr.inputs["Value"])
    h = N.new("ShaderNodeMath"); h.operation = "SUBTRACT"
    L.new(pr.outputs["Result"], h.inputs[0]); L.new(crm.outputs["Result"], h.inputs[1])
    h2 = N.new("ShaderNodeMath"); h2.operation = "ADD"
    L.new(h.outputs[0], h2.inputs[0]); L.new(lr.outputs["Result"], h2.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6; bump.inputs["Distance"].default_value = 0.005
    L.new(h2.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def moss(name, base=(0.045, 0.08, 0.014), tip=(0.16, 0.24, 0.04)):
    """Cushion moss: fuzzy fine relief, brighter tips, darker in the hollows."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    fz = N.new("ShaderNodeTexNoise"); fz.inputs["Scale"].default_value = 120.0; fz.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], fz.inputs["Vector"])
    big = N.new("ShaderNodeTexNoise"); big.inputs["Scale"].default_value = 9.0; big.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], big.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(big.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (*base, 1); mx.inputs[7].default_value = (*tip, 1)
    col, ao = K._ao_mix(N, L, mx.outputs[2], (0.02, 0.03, 0.01), 0.08)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    add = N.new("ShaderNodeMath"); add.operation = "ADD"
    L.new(fz.outputs["Fac"], add.inputs[0]); L.new(big.outputs["Fac"], add.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.9; bump.inputs["Distance"].default_value = 0.01
    L.new(add.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def bark(name):
    """Root bark: dark brown, long ridges along the root (wave bands on a warped noise), paler worn bumps."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    wv = N.new("ShaderNodeTexWave"); wv.inputs["Scale"].default_value = 26.0; wv.inputs["Distortion"].default_value = 9.0
    wv.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], wv.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 14.0; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (0.09, 0.055, 0.03, 1); mx.inputs[7].default_value = (0.25, 0.17, 0.1, 1)
    md = N.new("ShaderNodeMix"); md.data_type = "RGBA"
    L.new(wv.outputs["Fac"], md.inputs[0]); L.new(mx.outputs[2], md.inputs[6])
    md.inputs[7].default_value = (0.04, 0.025, 0.015, 1)
    col, ao = K._ao_mix(N, L, md.outputs[2], (0.02, 0.012, 0.006), 0.05)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.8; bump.inputs["Distance"].default_value = 0.008
    L.new(wv.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def earth(name):
    """Packed forest soil with moss patches growing over it."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 5.0; nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = N.new("ShaderNodeMapRange"); ramp.inputs["From Min"].default_value = 0.58; ramp.inputs["From Max"].default_value = 0.66
    L.new(nz.outputs["Fac"], ramp.inputs["Value"])
    grit = N.new("ShaderNodeTexNoise"); grit.inputs["Scale"].default_value = 70.0
    L.new(tc.outputs["Object"], grit.inputs["Vector"])
    soil = N.new("ShaderNodeMix"); soil.data_type = "RGBA"
    L.new(grit.outputs["Fac"], soil.inputs[0])
    soil.inputs[6].default_value = (0.045, 0.032, 0.02, 1); soil.inputs[7].default_value = (0.1, 0.075, 0.05, 1)
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(ramp.outputs["Result"], mx.inputs[0]); L.new(soil.outputs[2], mx.inputs[6])
    mx.inputs[7].default_value = (0.06, 0.1, 0.02, 1)
    col, ao = K._ao_mix(N, L, mx.outputs[2], (0.015, 0.012, 0.008), 0.08)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.97
    add = N.new("ShaderNodeMath"); add.operation = "ADD"
    L.new(grit.outputs["Fac"], add.inputs[0]); L.new(ramp.outputs["Result"], add.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.7; bump.inputs["Distance"].default_value = 0.01
    L.new(add.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


BONE = weathered_bone("bone")
MOSS = moss("moss")
BARK = bark("bark")
EARTH = earth("earth")
FUNGUS = K.simple("fungus", (0.3, 0.19, 0.09), 0.75)
FUNGUS_RIM = K.simple("fungus_rim", (0.55, 0.45, 0.3), 0.7)
LEAF = K.simple("leaf", (0.16, 0.38, 0.05), 0.55)
STEM = K.simple("stem", (0.2, 0.22, 0.08), 0.7)
CAP_GLOW = K.glow("fxG_glowcap", (0.55, 1.0, 0.7), 4.0, base=(0.5, 0.62, 0.5))
CAP_STEM = K.simple("cap_stem", (0.62, 0.64, 0.55), 0.6)
DARK = K.simple("cavity", (0.008, 0.006, 0.004), 0.95)


def wave(P, f, a):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    return a * (np.sin(x * f + 1.3) * np.sin(y * f * 1.1 + 0.4) * np.sin(z * f * 0.9 + 2.1))


def teeth_arc(P, cy, cz, rx, ry, n, lost, h, tilt=None):
    """Separate rounded teeth along a U arc (centre (0, cy), radii rx / ry at height cz), skipping the `lost` ones;
    each a little narrower at the root, worn and uneven in height; `tilt` = {index: z offset} for loose teeth."""
    d = np.full(P.shape[:-1], 9.0)
    for i in range(n):
        if i in lost:
            continue
        a = -1.15 + 2.3 * i / (n - 1)
        c = np.array([rx * math.sin(a), cy - ry * math.cos(a), cz + (tilt or {}).get(i, 0.0)])
        w = 0.034 if abs(a) < 0.5 else 0.03
        hh = h * (0.85 + 0.3 * ((i * 37) % 7) / 7.0)
        d = smin(d, sd_ellipsoid(P, c, (w, 0.03, hh)), 0.006)
    return d


def skull(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.05, 0.35), (0.74, 0.9, 0.8))  # cranium
    d = smax(d, y - 0.88, 0.2)
    d = smin(d, sd_capsule(P, (-0.38, -0.78, 0.44), (0.38, -0.78, 0.44), 0.055), 0.12)  # brow ridge
    for s in (-1, 1):
        d = smax(d, -sd_ellipsoid(P, (s * 0.3, -0.92, 0.26), (0.17, 0.32, 0.15)), 0.04)  # orbits
        d = smin(d, sd_capsule(P, (s * 0.42, -0.78, 0.12), (s * 0.62, -0.38, 0.16), 0.045), 0.06)  # cheekbone / arch
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.3, 0.36), (0.12, 0.32, 0.26)), 0.08)  # temporal hollow
    d = smin(d, sd_ellipsoid(P, (0, -0.74, -0.1), (0.3, 0.24, 0.16)), 0.1)  # maxilla
    for s in (-1, 1):  # nasal aperture: an upside-down heart
        d = smax(d, -sd_capsule(P, (s * 0.06, -1.05, -0.04), (s * 0.015, -1.05, 0.14), 0.045), 0.015)
    # A CHUNK BROKEN OUT of the left brow (+x): a jagged bite, its edge rough
    bite = sd_ellipsoid(P, (0.36, -0.86, 0.52), (0.19, 0.17, 0.13)) + 0.025 * np.sin(x * 47) * np.sin(z * 41) + 0.015 * np.sin(y * 63)
    d = np.maximum(d, -bite)
    # the CRACK across the brow from the bite toward the right temple (a wide jagged cut)
    crack = np.where((y < -0.35) & (x < 0.4), z - (0.6 + 0.07 * np.sin(x * 9.0) + 0.025 * np.sin(x * 31.0)) + 0.18 * (x - 0.4) * 0.3, 9.0)
    d = groove(d, crack, 0.04, 0.022, 0.012)
    # a crack up over the crown toward the back (shallower)
    crack2 = np.where((z > 0.55) & (y > -0.55), x - 0.06 - 0.05 * np.sin(y * 11.0) - 0.02 * np.sin(y * 37.0), 9.0)
    d = groove(d, crack2, 0.022, 0.014, 0.006)
    # a broken HOLE in the right parietal (-x, back, top), filled with moss later
    hole = sd_ellipsoid(P, (-0.48, 0.3, 0.72), (0.2, 0.24, 0.17)) + 0.02 * np.sin(y * 40) * np.sin(z * 37)
    d = np.maximum(d, -hole)
    # sutures (jagged, shallow)
    sag = np.where((z > 0.4) & (y > -0.45) & (np.abs(x) < 0.3), x + 0.03 * np.sin(y * 32.0) + 0.012 * np.sin(y * 77.0), 9.0)
    d = groove(d, sag, 0.01, 0.009, 0.0)
    # the upper teeth: separate rounded teeth, three lost, one loose and hanging lower
    d = smin(d, teeth_arc(P, -0.6, -0.29, 0.25, 0.23, 14, (3, 9, 11), 0.05, {6: -0.03}), 0.012)
    # weathering: a slight lumpy erosion over everything
    return d + wave(P, 13.0, 0.006)


head = K.sdf_mesh("skull", skull, (-0.85, -1.15, -0.5), (0.85, 1.0, 1.2), 0.011, BONE)


def mandible(P):
    """The lower jaw, sagging a little open and askew (held on by the roots)."""
    q = P.copy()
    q[..., 2] = q[..., 2] + 0.05 + 0.03 * q[..., 0]  # dropped and tilted
    body = smax(sd_ellipsoid(q, (0, -0.62, -0.42), (0.36, 0.34, 0.12)), -sd_ellipsoid(q, (0, -0.55, -0.36), (0.27, 0.27, 0.2)), 0.03)
    for s in (-1, 1):
        body = smin(body, sd_ellipsoid(q, (s * 0.31, -0.36, -0.24), (0.05, 0.12, 0.24)), 0.06)
    body = smin(body, sd_ellipsoid(q, (0, -0.88, -0.47), (0.09, 0.05, 0.05)), 0.04)
    teeth = teeth_arc(q, -0.58, -0.33, 0.24, 0.22, 12, (2, 8), 0.045)
    return smin(body, teeth, 0.01) + wave(P, 15.0, 0.005)


jaw = K.sdf_mesh("mandible", mandible, (-0.6, -1.1, -0.7), (0.6, -0.1, 0.05), 0.011, BONE)


def neck_mass(P):
    """Dark packed earth and moss round the neck, down to the collar line (under the root beard)."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_capsule(P, (0, 0.14, -0.35), (0, 0.16, -0.94), 0.44)
    for (c, r) in (((0.25, 0.4, -0.25), 0.26), ((-0.3, 0.38, -0.32), 0.24), ((0.36, 0.1, -0.55), 0.22), ((-0.38, 0.12, -0.62), 0.23),
                   ((0.0, 0.5, -0.5), 0.27), ((0.2, 0.42, -0.8), 0.22), ((-0.22, 0.4, -0.86), 0.21), ((0.0, -0.18, -0.7), 0.24)):
        d = smin(d, sd_ellipsoid(P, c, (r, r * 0.9, r * 0.8)), 0.12)  # clods of earth
    d = d + wave(P, 9.0, 0.035) + wave(P, 23.0, 0.014)
    return smax(d, -(z + 0.98), 0.03)


earth_mesh = K.sdf_mesh("earth", neck_mass, (-0.7, -0.5, -1.02), (0.7, 0.8, -0.1), 0.016, EARTH)

# darkness in the orbits and the hole
for s in (-1, 1):
    K.ball("orbit_dark", 0.15, (s * 0.3, -0.66, 0.26), DARK, (1.0, 1.0, 0.85), 16)
K.ball("nose_dark", 0.08, (0.0, -0.9, 0.04), DARK, (1.0, 0.8, 1.2), 12)


# ------------------------------------------------------------------ moss: right orbit, the nose, the parietal hole, the crown
def moss_sdf(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    lump = wave(P, 23.0, 0.018) + wave(P, 53.0, 0.008)
    d = sd_ellipsoid(P, (-0.3, -0.82, 0.17), (0.16, 0.12, 0.08)) + lump  # cushion in the bottom of the right orbit (the top stays dark)
    d = smin(d, sd_ellipsoid(P, (0.0, -0.92, 0.04), (0.06, 0.05, 0.07)) + lump, 0.02)  # deep in the nose
    d = smin(d, sd_ellipsoid(P, (-0.46, 0.28, 0.7), (0.19, 0.22, 0.16)) + lump, 0.02)  # filling the broken hole
    # a carpet over the crown and down the back: a skin over the skull where a noise allows
    sk = skull(P)
    carpet = np.maximum(sk - 0.035, -(sk + 0.004))
    patch = (z - 0.58) + 0.16 * np.sin(x * 5.0 + 0.7) * np.sin(y * 4.0 + 1.1) + 0.07 * np.sin(x * 13.0 + y * 9.0) + 0.04 * np.sin(y * 23.0 - x * 17.0)
    holes = 0.1 + 0.5 * (np.sin(x * 9.0 + 1.0) * np.sin(y * 8.0) * np.sin(z * 7.0 + 0.5)) + 0.25 * np.sin(x * 19.0 - y * 15.0 + z * 11.0)
    carpet = np.maximum(carpet, -patch)
    carpet = np.maximum(carpet, -holes)  # bone showing through in islands
    carpet = np.maximum(carpet, -(y + 0.45))  # not over the brow at the front
    d = smin(d, carpet + lump, 0.015)
    # a patch on the left cheekbone
    cheek = np.maximum(sk - 0.03, -(sk + 0.004))
    cheek = np.maximum(cheek, sd_ellipsoid(P, (0.5, -0.62, 0.12), (0.15, 0.2, 0.12)))
    return smin(d, cheek + lump, 0.01)


K.sdf_mesh("moss", moss_sdf, (-0.8, -1.1, -0.1), (0.8, 0.95, 1.2), 0.011, MOSS)


# ------------------------------------------------------------------ roots
CENTRE = Vector((0.0, 0.05, 0.3))


def on(obj, p, lift, centre=CENTRE):
    """p pushed onto obj's surface along the line from `centre`, lifted `lift` off it (None if missed)."""
    p = Vector(p)
    d = (p - centre).normalized()
    loc, n = K.ray_onto(obj, centre + d * 3.0, -d)
    return (loc + n * lift) if loc else None


def root(name, ctrl, r0, r1=0.006, objs=None, lift=0.6, n=40, twigs=0):
    """A tapering root through control points; points given as (x, y, z, 'on') are pressed onto the skull / earth."""
    pts = []
    for c in ctrl:
        if len(c) == 4:
            o = objs.get(c[3], head) if objs else head
            hit = on(o, c[:3], r0 * lift)
            pts.append(hit if hit else Vector(c[:3]))
        else:
            pts.append(Vector(c))
    path = K.smooth_path(pts, n)
    # a little wander so it does not look drawn with a ruler
    path = [p + Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * r0 * 0.12 for p in path]
    f = K.path_fn(path)
    K.loft(name, f, lambda t: r0 * (1 - t) ** 0.8 + r1, 60, 10, mat=BARK,
           profile=lambda th, t: (1.0 + 0.12 * math.sin(th * 3 + t * 9), 1.0 + 0.1 * math.cos(th * 2 + t * 7)))
    for k in range(twigs):  # side rootlets
        t0 = 0.25 + 0.6 * random.random()
        a = f(t0); dirv = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 0.2))).normalized()
        rr = (r0 * (1 - t0) ** 0.8 + r1) * 0.55
        K.loft(name + "_twig", lambda t, a=a, dv=dirv: a + dv * (0.16 * t) + Vector((0, 0, -0.05 * t * t)),
               lambda t, rr=rr: rr * (1 - t) + 0.004, 12, 6, mat=BARK)
    return f


OBJS = {"on": head, "jaw": jaw, "earth": earth_mesh}

# THE ROOT OUT OF THE LEFT ORBIT: from deep inside, out past the rim, curling up over the brow into the crack and the
# bite, over the crown to the back
root("orbit_root", [(0.3, -0.62, 0.24), (0.31, -0.9, 0.26), (0.4, -1.04, 0.33), (0.46, -0.96, 0.46, "on"),
                    (0.42, -0.82, 0.62, "on"), (0.32, -0.62, 0.82, "on"), (0.16, -0.4, 0.97, "on"), (0.1, 0.0, 1.06, "on"), (0.16, 0.4, 0.95, "on"),
                    (0.2, 0.7, 0.6, "on"), (0.18, 0.8, 0.3, "on")], 0.1, objs=OBJS, lift=0.45, twigs=4)
# its branches spreading over the brow like fingers: into the crack, over to the temple
root("orbit_branch", [(0.44, -0.9, 0.52, "on"), (0.25, -0.86, 0.6, "on"), (0.05, -0.84, 0.6, "on"), (-0.2, -0.8, 0.6, "on"),
                      (-0.42, -0.68, 0.58, "on"), (-0.6, -0.45, 0.6, "on")], 0.045, objs=OBJS, lift=0.4, twigs=2)
root("orbit_branch", [(0.42, -0.82, 0.62, "on"), (0.56, -0.62, 0.68, "on"), (0.68, -0.32, 0.62, "on"), (0.74, -0.05, 0.5, "on")],
     0.04, objs=OBJS, lift=0.4, twigs=1)
root("orbit_root_b", [(0.36, -1.04, 0.36), (0.46, -1.0, 0.28), (0.56, -0.86, 0.2, "on"), (0.66, -0.6, 0.18, "on"), (0.72, -0.3, 0.1, "on"),
                      (0.68, 0.0, -0.05, "on"), (0.55, 0.3, -0.2, "earth")], 0.035, objs=OBJS, twigs=1)

# roots GRIPPING both sides like fingers: from the back of the skull over the temples to the cheekbones
for s in (-1, 1):
    for k, (zt, yt) in enumerate(((0.48, -0.3), (0.2, -0.55))):  # diagonal: from low behind the ear up and forward
        root("grip", [(s * 0.45, 0.7, -0.08 + 0.06 * k, "on"), (s * 0.68, 0.38, 0.05 + 0.12 * k, "on"), (s * 0.77, 0.05, zt - 0.1, "on"),
                      (s * 0.75, yt + 0.15, zt, "on"), (s * 0.62, yt - 0.15, zt - 0.08, "on")], 0.065 - 0.012 * k, objs=OBJS, lift=0.4, twigs=2)

# roots holding the jaw on: from the temples down round the ramus to the jaw corners and under the chin
for s in (-1, 1):
    root("jaw_tie", [(s * 0.7, -0.15, 0.25, "on"), (s * 0.5, -0.3, -0.12, "jaw"), (s * 0.38, -0.42, -0.42, "jaw"),
                     (s * 0.26, -0.68, -0.56, "jaw"), (s * 0.05, -0.82, -0.58, "jaw")], 0.04, objs=OBJS)
    root("jaw_wrap", [(s * 0.62, -0.05, 0.0, "on"), (s * 0.36, -0.36, -0.3, "jaw"), (s * 0.4, -0.5, -0.48, "jaw"),
                      (s * 0.42, -0.25, -0.7), (s * 0.4, 0.0, -0.85, "earth")], 0.03, objs=OBJS)

# THE ROOT BEARD: a tangle out of the base of the skull hanging over the earth to the collar line
for k in range(9):  # fewer, thicker roots that cross over each other as they hang
    a = -1.2 + 2.4 * k / 8
    a2 = a + random.choice((-1, 1)) * random.uniform(0.25, 0.5)  # each drifts sideways across its neighbours
    sx, sy = math.sin(a), math.cos(a)
    ex, ey = math.sin(a2), math.cos(a2)
    top = (sx * 0.4, 0.55 + 0.2 * sy, 0.08 + 0.06 * random.random(), "on")
    mid = (0.5 * (sx + ex) * 0.5, 0.15 + 0.5 * 0.5 * (sy + ey), -0.42, "earth")
    low = (ex * 0.5, 0.18 + 0.5 * ey, -0.72 - 0.12 * random.random(), "earth")
    end = (ex * 0.52, 0.2 + 0.55 * ey, -0.95)
    root("beard", [top, mid, low, end], 0.05 + 0.02 * random.random(), objs=OBJS, lift=0.45, twigs=1 if k % 2 == 0 else 0)


# ------------------------------------------------------------------ bracket fungi stepping out of the right temple
def brackets(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = np.full(P.shape[:-1], 9.0)
    for (yy, zz, w) in ((-0.15, 0.62, 0.17), (0.08, 0.46, 0.21), (-0.05, 0.28, 0.15)):
        c = np.array([-0.74, yy, zz])
        shelf = sd_ellipsoid(P, c + np.array([-0.08, 0, 0]), (w * 0.9, w, 0.065))
        shelf = shelf - 0.03 * np.clip(1.0 - np.abs(x - c[0]) / (w * 0.9), 0, 1) * (z > zz)  # domed top
        shelf = smax(shelf, (x - (c[0] + 0.06)), 0.02)  # flat against the skull
        shelf = shelf + 0.006 * np.sin(np.arctan2(y - yy, -(x - c[0])) * 14.0)  # growth ridges at the rim
        d = smin(d, shelf, 0.02)
    return d


K.sdf_mesh("brackets", brackets, (-1.05, -0.45, 0.15), (-0.6, 0.35, 0.75), 0.008, FUNGUS)
for (yy, zz, w) in ((-0.15, 0.62, 0.17), (0.08, 0.46, 0.21), (-0.05, 0.28, 0.15)):  # pale growing rims
    K.tube("bracket_rim", [Vector((-0.82 - w * 0.88 * math.cos(a), yy + w * 0.98 * math.sin(a), zz + 0.01))
                           for a in np.linspace(-1.35, 1.35, 15)], 0.026, FUNGUS_RIM, res=2)


# ------------------------------------------------------------------ small glowing mushrooms in the moss
def mushroom(base, up, h, cap_r):
    up = Vector(up).normalized()
    top = Vector(base) + up * h
    K.tube("cap_stem", [Vector(base), Vector(base).lerp(top, 0.5) + Vector((0.01, 0, 0)), top], 0.018, CAP_STEM, res=2)
    cap = K.ball("glow_cap", cap_r, tuple(top), CAP_GLOW, (1.0, 1.0, 0.55), 12)
    K.align(cap, up)


for p, h, r in (((-0.42, 0.18, 0.86), 0.12, 0.07), ((-0.52, 0.32, 0.84), 0.09, 0.055), ((-0.34, 0.36, 0.86), 0.1, 0.06),
                ((-0.46, 0.06, 0.84), 0.07, 0.045), ((0.05, 0.42, 0.98), 0.1, 0.06), ((0.14, 0.5, 0.92), 0.07, 0.045),
                ((0.52, -0.66, 0.14), 0.07, 0.045), ((-0.12, 0.62, 0.7), 0.09, 0.055)):
    loc = on(head, p, 0.03)
    if loc:
        mushroom(loc, (loc - CENTRE).normalized() + Vector((0, 0, 0.6)), h, r)

# ------------------------------------------------------------------ the sapling sprouting from the crack on the crown
sp = on(head, (-0.05, -0.32, 1.1), 0.0)
if sp:
    stem = K.smooth_path([sp, sp + Vector((0.0, -0.06, 0.18)), sp + Vector((0.09, -0.03, 0.36)), sp + Vector((0.06, 0.07, 0.52))], 18)
    K.tube("sapling", stem, 0.026, STEM, res=3, taper=lambda t: 1.0 - 0.5 * t)
    for k, (t, ang, ln) in enumerate(((0.4, 0.4, 0.3), (0.62, 2.6, 0.32), (0.82, 4.4, 0.3), (0.95, 1.3, 0.28))):
        a = stem[min(int(t * (len(stem) - 1)), len(stem) - 1)]
        dv = Vector((math.cos(ang), math.sin(ang), 0.35)).normalized()
        K.loft("leaf", lambda u, a=a, dv=dv, ln=ln: a + dv * (ln * u) + Vector((0, 0, -0.04 * u * u)),
               lambda u: 0.12 * math.sin(math.pi * min(max(u, 0.02), 0.98)) ** 0.7 + 0.004, 20, 10, mat=LEAF,
               profile=lambda th, u: (1.0, 0.16))
    K.loft("leaf_tip", lambda u: stem[-1] + Vector((0.0, -0.08, 0.16)) * u, lambda u: 0.07 * math.sin(math.pi * min(max(u, 0.02), 0.98)) ** 0.7 + 0.004, 16, 10, mat=LEAF, profile=lambda th, u: (1.0, 0.28))

# ivy leaves along the left grip roots (flat little hearts)
for k in range(9):
    p = on(head, (0.7 + 0.03 * math.sin(k), 0.45 - 0.12 * k, 0.4 - 0.03 * k), 0.05)
    if p:
        n = (p - CENTRE).normalized()
        lf = K.ball("ivy", 0.05, tuple(p), LEAF, (1.0, 0.85, 0.3), 10)
        K.align(lf, n)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("skull_of_the_forgotten")
print("ok")

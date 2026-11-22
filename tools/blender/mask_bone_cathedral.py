# Bone Cathedral mask (boss mask 10, diary/DECISIONS_SKINS.md A10 + diary/MASK_PROCESS.md section 5): a full skull
# (base 6) grown into a cathedral of bone. Silhouette plan: FRONT = a crown of bone SPIRES (crockets, bands) + the
# jaw; SIDE = flying BUTTRESSES of bone stepping back along the skull; BACK = a spine of VERTEBRAE down the back.
# Behaviour: sutures, porous bone, holy light through thin bone: a rose window of petal holes in the forehead (fxG_)
# and deep amber light in the orbits (fxR_); the mandible is the moving part (fxB_: a slow chatter in the game).
# Run: python3 tools/blender/mask_bone_cathedral.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py bone_cathedral
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(101)


def bone(name, base=(0.72, 0.64, 0.5)):
    """Old bone: yellowed ivory with a mottle, brown stains, a network of hairline cracks, pores, dirt in cavities."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    mot = N.new("ShaderNodeTexNoise"); mot.inputs["Scale"].default_value = 7.0; mot.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(mot.outputs["Fac"], mx.inputs[0])
    mx.inputs[6].default_value = (base[0] * 1.08, base[1] * 1.06, base[2] * 1.02, 1)
    mx.inputs[7].default_value = (base[0] * 0.7, base[1] * 0.6, base[2] * 0.45, 1)
    # broad brown stains
    st = N.new("ShaderNodeTexNoise"); st.inputs["Scale"].default_value = 2.2; st.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], st.inputs["Vector"])
    sr = N.new("ShaderNodeMapRange"); sr.inputs["From Min"].default_value = 0.52; sr.inputs["From Max"].default_value = 0.68
    sr.inputs["To Max"].default_value = 0.75
    L.new(st.outputs["Fac"], sr.inputs["Value"])
    ms = N.new("ShaderNodeMix"); ms.data_type = "RGBA"
    L.new(sr.outputs["Result"], ms.inputs[0]); L.new(mx.outputs[2], ms.inputs[6])
    ms.inputs[7].default_value = (0.3, 0.19, 0.08, 1)
    # hairline cracks: Voronoi cell edges, shown only where a noise allows
    cr = N.new("ShaderNodeTexVoronoi"); cr.feature = "DISTANCE_TO_EDGE"; cr.inputs["Scale"].default_value = 3.2
    L.new(tc.outputs["Object"], cr.inputs["Vector"])
    crm = N.new("ShaderNodeMapRange"); crm.inputs["From Min"].default_value = 0.0; crm.inputs["From Max"].default_value = 0.012
    crm.inputs["To Min"].default_value = 1.0; crm.inputs["To Max"].default_value = 0.0
    L.new(cr.outputs["Distance"], crm.inputs["Value"])
    cn = N.new("ShaderNodeTexNoise"); cn.inputs["Scale"].default_value = 3.0
    L.new(tc.outputs["Object"], cn.inputs["Vector"])
    cnm = N.new("ShaderNodeMapRange"); cnm.inputs["From Min"].default_value = 0.48; cnm.inputs["From Max"].default_value = 0.56
    L.new(cn.outputs["Fac"], cnm.inputs["Value"])
    crk = N.new("ShaderNodeMath"); crk.operation = "MULTIPLY"
    L.new(crm.outputs["Result"], crk.inputs[0]); L.new(cnm.outputs["Result"], crk.inputs[1])
    mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
    L.new(crk.outputs[0], mc.inputs[0]); L.new(ms.outputs[2], mc.inputs[6])
    mc.inputs[7].default_value = (0.08, 0.05, 0.025, 1)
    col, ao = K._ao_mix(N, L, mc.outputs[2], (0.12, 0.07, 0.03), 0.09)
    L.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.68
    # pores + cracks as relief
    pores = N.new("ShaderNodeTexVoronoi"); pores.inputs["Scale"].default_value = 60.0
    L.new(tc.outputs["Object"], pores.inputs["Vector"])
    pr = N.new("ShaderNodeMapRange"); pr.inputs["From Min"].default_value = 0.0; pr.inputs["From Max"].default_value = 0.15
    L.new(pores.outputs["Distance"], pr.inputs["Value"])
    h = N.new("ShaderNodeMath"); h.operation = "SUBTRACT"
    L.new(pr.outputs["Result"], h.inputs[0]); L.new(crk.outputs[0], h.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.55; bump.inputs["Distance"].default_value = 0.004
    L.new(h.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


BONE = bone("bone")
JAW = bone("fxB_jaw_bone")
CLOTH = K.simple("shroud", (0.02, 0.018, 0.02), 0.85)
AMBER = K.glow("fxR_amber", (1.0, 0.62, 0.22), 10.0, base=(0.3, 0.15, 0.04))
HOLY = K.glow("fxG_holy", (1.0, 0.85, 0.5), 5.0, base=(0.3, 0.25, 0.12))
DARK = K.simple("cavity", (0.01, 0.008, 0.006), 0.9)

ROSE_C = np.array([0.0, -0.84, 0.74])
ROSE_N = np.array([0.0, -0.8, 0.6]) / np.linalg.norm([0.0, -0.8, 0.6])
ROSE_U = np.cross(ROSE_N, [1.0, 0.0, 0.0]); ROSE_U /= np.linalg.norm(ROSE_U)


def rose_frame(P):
    """Returns (a, b, along) coordinates in the rose window's plane."""
    q = P - ROSE_C
    along = q @ ROSE_N
    flat = q - along[..., None] * ROSE_N
    return flat[..., 0], flat @ ROSE_U, along


def rose_holes(P):
    """The rose window: a round centre hole and 10 petal holes round it (tracery bars between them)."""
    a, bq, along = rose_frame(P)
    r = np.sqrt(a ** 2 + bq ** 2)
    d = r - 0.04
    th = np.arctan2(bq, a)
    sector = (np.mod(th + math.pi / 10, math.pi / 5) - math.pi / 10) * r  # arc distance to the petal's centre line
    petal = np.maximum(np.abs(sector) - (0.012 + 0.11 * (r - 0.065)), np.abs(r - 0.115) - 0.05)
    d = np.minimum(d, petal)
    return np.maximum(d, np.abs(along) - 0.22)


def rose_ring(P):
    a, bq, along = rose_frame(P)
    r = np.sqrt(a ** 2 + bq ** 2)
    return np.sqrt((r - 0.19) ** 2 + (along + 0.02) ** 2) - 0.024


def skull(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.05, 0.35), (0.74, 0.9, 0.8))  # cranium
    d = smax(d, y - 0.88, 0.2)
    d = smin(d, sd_capsule(P, (-0.4, -0.77, 0.43), (0.4, -0.77, 0.43), 0.05), 0.12)  # brow ridge, low and blended
    for s in (-1, 1):
        d = smax(d, -sd_ellipsoid(P, (s * 0.3, -0.92, 0.26), (0.17, 0.32, 0.15)), 0.04)  # deep orbits
        d = smin(d, sd_capsule(P, (s * 0.42, -0.78, 0.12), (s * 0.62, -0.38, 0.16), 0.045), 0.06)  # cheekbone / arch
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.3, 0.36), (0.12, 0.32, 0.26)), 0.08)  # temporal hollow
    d = smin(d, sd_ellipsoid(P, (0, -0.74, -0.1), (0.3, 0.24, 0.16)), 0.1)  # maxilla, flatter
    # nasal aperture: an upside-down heart (two tilted lobes meeting at a point at the top)
    for s in (-1, 1):
        d = smax(d, -sd_capsule(P, (s * 0.06, -1.05, -0.04), (s * 0.015, -1.05, 0.14), 0.045), 0.015)
    d = smax(d, -rose_holes(P), 0.006)  # the rose window
    d = smin(d, rose_ring(P), 0.02)  # its raised round frame
    # sutures: the sagittal down the middle, the coronal across the top, both jagged
    sag = np.where((z > 0.4) & (y > -0.45), x + 0.03 * np.sin(y * 32.0) + 0.012 * np.sin(y * 77.0), 9.0)
    d = groove(d, sag, 0.013, 0.011, 0.0)
    cor = np.where((z > 0.45), y + 0.25 - 0.08 * np.abs(x) + 0.03 * np.sin(x * 32.0) + 0.012 * np.sin(x * 71.0), 9.0)
    d = groove(d, cor, 0.013, 0.011, 0.0)
    # the upper teeth row: a band of blocks under the maxilla
    tz = np.abs(z + 0.29) - 0.06
    trow = np.maximum(np.maximum(tz, sd_ellipsoid(P, (0, -0.7, -0.29), (0.28, 0.28, 0.2))), -sd_ellipsoid(P, (0, -0.6, -0.29), (0.2, 0.22, 0.3)))
    gaps = np.abs(np.sin(np.arctan2(x, -(y + 0.6)) * 9.0)) - 0.25  # gaps between the teeth
    d = smin(d, np.maximum(trow, -gaps * 0.03), 0.01)
    # the stringcourse: a bone ledge along each side the buttress piers stand on
    for s in (-1, 1):
        d = smin(d, sd_capsule(P, (s * 0.7, -0.25, 0.02), (s * 0.66, 0.62, 0.02), 0.05), 0.05)
    return d


def shroud(P):
    """A black shroud round the neck down to the collar (under the vertebrae)."""
    d = sd_capsule(P, (0, 0.1, -0.35), (0, 0.12, -0.95), 0.52)
    return smax(d, -(P[..., 2] + 0.97), 0.03)


head = K.sdf_mesh("skull", skull, (-0.85, -1.15, -0.5), (0.85, 1.0, 1.2), 0.011, BONE)
K.sdf_mesh("shroud", shroud, (-0.65, -0.5, -1.0), (0.65, 0.7, -0.2), 0.016, CLOTH)


def mandible(P):
    body = smax(sd_ellipsoid(P, (0, -0.62, -0.42), (0.36, 0.34, 0.12)), -sd_ellipsoid(P, (0, -0.55, -0.36), (0.27, 0.27, 0.2)), 0.03)
    for s in (-1, 1):
        body = smin(body, sd_ellipsoid(P, (s * 0.31, -0.36, -0.24), (0.05, 0.12, 0.24)), 0.06)  # ramus: a flat plate up to the hinge
    body = smin(body, sd_ellipsoid(P, (0, -0.88, -0.47), (0.09, 0.05, 0.05)), 0.04)  # chin point
    # lower teeth
    tz = np.abs(P[..., 2] + 0.33) - 0.05
    trow = np.maximum(np.maximum(tz, sd_ellipsoid(P, (0, -0.66, -0.33), (0.27, 0.27, 0.2))), -sd_ellipsoid(P, (0, -0.58, -0.33), (0.19, 0.21, 0.3)))
    gaps = np.abs(np.sin(np.arctan2(P[..., 0], -(P[..., 1] + 0.58)) * 8.0)) - 0.25
    return smin(body, np.maximum(trow, -gaps * 0.03), 0.01)


K.sdf_mesh("mandible", mandible, (-0.6, -1.1, -0.65), (0.6, -0.1, 0.05), 0.011, JAW)

# light deep in the orbits and behind the rose window
for s in (-1, 1):
    K.ball("orbit_dark", 0.15, (s * 0.3, -0.66, 0.26), DARK, (1.0, 1.0, 0.85), 16)
    K.ball("orbit_light", 0.055, (s * 0.3, -0.84, 0.25), AMBER, (1.0, 0.6, 0.8), 16)
K.ball("rose_light", 0.12, tuple(ROSE_C - ROSE_N * 0.17), HOLY, (1.0, 0.45, 0.85), 16)  # behind the holes, inside the skull


# ------------------------------------------------------------------ the spires
def spire(base, height, r, lean=Vector((0, 0.05, 0)), crockets=5):
    top = base + Vector((0, 0, height)) + lean
    K.loft("spire", lambda t, b=base, tp=top: b.lerp(tp, t), lambda t: r * (1 - t) ** 1.25 + 0.006, 24, 6, mat=BONE)
    for f in (0.32, 0.55):  # a band round it
        c = base.lerp(top, f)
        rr = r * (1 - f) ** 1.25 + 0.012
        K.tube("spire_band", [c + Vector((rr * math.cos(a), rr * math.sin(a), 0)) for a in np.linspace(0, 2 * math.pi, 13)], 0.012, BONE, res=2)
    for k in range(crockets):  # crockets: little hooked spikes climbing the spire
        f = 0.2 + 0.65 * k / max(crockets, 1)
        c = base.lerp(top, f)
        ang = k * 2.4
        out = Vector((math.cos(ang), math.sin(ang), 0.0))
        rr = r * (1 - f) ** 1.25
        K.loft("crocket", lambda t, c=c, o=out, rr=rr: c + o * (rr + 0.07 * t) + Vector((0, 0, 0.05 * t * t)),
               lambda t: 0.022 * (1 - t) + 0.003, 8, 5, mat=BONE)


for xx, h, r in ((0.0, 1.0, 0.11), (0.26, 0.72, 0.085), (-0.26, 0.72, 0.085), (0.48, 0.45, 0.07), (-0.48, 0.45, 0.07)):
    loc, n = K.ray_onto(head, Vector((xx, -0.1, 2.5)), Vector((0, 0, -1)))
    if loc:
        spire(loc - Vector((0, 0, 0.05)), h, r)

# ------------------------------------------------------------------ flying buttresses: piers standing off the sides
# on the stringcourse, stepping back and down, each with a pinnacle and a flying arch leaning into the skull wall
PIERS = ((-0.12, 0.78), (0.2, 0.66), (0.5, 0.54))


def pointed_arch(a, b, rise, n=9):
    """Points of a pointed (two-centred) arch from a to b, its apex `rise` above the line between them."""
    pts = []
    for i in range(n):
        u = i / (n - 1)
        w = 1.0 - abs(2 * u - 1)  # 0 at the springs, 1 at the apex
        pts.append(a.lerp(b, u) + Vector((0, 0, rise * (1 - (1 - w) ** 1.6))))
    return pts


for s in (-1, 1):
    tops = []
    for k, (yy, top) in enumerate(PIERS):
        px = s * 0.9
        K.loft("pier_foot", lambda t, a=Vector((s * 0.68, yy, 0.02)), f=Vector((px, yy, 0.0)): a.lerp(f, t), lambda t: 0.055, 6, 6, mat=BONE)
        K.box("pier", (0.09, 0.09, top + 0.04), (px, yy, top * 0.5 - 0.02), (0, 0, 0), BONE, 0.012, 2)
        K.box("pier_cap", (0.12, 0.12, 0.03), (px, yy, top), (0, 0, 0), BONE, 0.008, 2)
        spire(Vector((px, yy, top + 0.01)), 0.26, 0.05, lean=Vector((0, 0, 0)), crockets=2)
        tops.append(Vector((px, yy, top - 0.1)))
        wall, wn = K.ray_onto(head, Vector((s * 2.0, yy + 0.07, top + 0.05)), Vector((-s, 0, 0)))
        if not wall:
            print("BUTTRESS: no wall", s, k)
            continue
        a0 = Vector((px - s * 0.02, yy, top - 0.1))
        mid = (a0 + wall) * 0.5 + Vector((0, 0, 0.07))

        def arc(t, a=a0, p=mid, f=wall):
            return a * (1 - t) ** 2 + p * 2 * t * (1 - t) + f * t * t
        K.loft("flyer", arc, lambda t: 0.035, 20, 8, mat=BONE, profile=lambda th, t: (0.6, 1.3))  # thin across, tall
    for a, b in zip(tops, tops[1:]):  # the arcade: pointed arches from pier to pier along the side
        K.tube("arcade", pointed_arch(a, b, 0.13), 0.022, BONE, res=3)

# ------------------------------------------------------------------ vertebrae down the back of the skull and neck
spots = []
for zz in (0.78, 0.6, 0.42, 0.24, 0.06):
    loc, n = K.ray_onto(head, Vector((0, 2.0, zz)), Vector((0, -1, 0)))
    if loc:
        spots.append((loc + n * 0.045, n))
for zz in (-0.16, -0.38, -0.6):
    spots.append((Vector((0.0, 0.64, zz)), Vector((0, 1, 0.0))))
for k, (c, n) in enumerate(spots):
    sz = 0.1 - 0.004 * k
    K.ball("vertebra", sz, c, BONE, (1.5, 0.75, 0.7), 16)
    out = (n + Vector((0, 0, -0.9))).normalized()  # spinous process: points down-back like a roof tile
    K.loft("spinous", lambda t, c=c, o=out: c + o * (0.04 + 0.09 * t), lambda t: 0.04 * (1 - 0.45 * t), 8, 8, mat=BONE,
           profile=lambda th, t: (0.55, 1.0))
    for s in (-1, 1):  # transverse processes: short blunt wings
        K.loft("transverse", lambda t, c=c, s=s: c + Vector((s * (0.08 + 0.07 * t), 0.0, -0.01 * t)), lambda t: 0.026 * (1 - 0.35 * t), 6, 6, mat=BONE)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("bone_cathedral")
print("ok")

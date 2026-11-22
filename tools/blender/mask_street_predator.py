# Street Predator mask (elite / mob mask 13, diary/DECISIONS_SKINS.md B13, plan in diary/MASK_PLANS_DROPS.md): an
# old yellowed fibreglass goalie mask (base 1) worn over a dark street hoodie. FRONT = three deep claw gouges raking
# across the face, the lowest tearing a notch out of the rim at the jaw + vent holes + forehead ridge; SIDE = the
# shell's thickness and rolled rim, strap studs, the hood standing round it; BACK = the hood with the mask's two
# elastic straps buckled over it, biting into the cloth, and drawstring cords. Dried blood dark in the gouges.
# Run: python3 tools/blender/mask_street_predator.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py street_predator
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(131)


def fibreglass(name, col=(0.6, 0.57, 0.47)):
    """Old fibreglass: a yellowed gloss gone dull, scuffs, edge chips to the grey resin, dirt in the cavities."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 4.0; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0]); mx.inputs[6].default_value = (*col, 1)
    mx.inputs[7].default_value = (col[0] * 0.78, col[1] * 0.72, col[2] * 0.58, 1)
    sc = N.new("ShaderNodeTexNoise"); sc.inputs["Scale"].default_value = 40.0; sc.inputs["Detail"].default_value = 12
    mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1, 1, 6)
    L.new(tc.outputs["Object"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], sc.inputs["Vector"])
    scm = N.new("ShaderNodeMapRange"); scm.inputs["From Min"].default_value = 0.66; scm.inputs["From Max"].default_value = 0.72
    L.new(sc.outputs["Fac"], scm.inputs["Value"])
    ms = N.new("ShaderNodeMix"); ms.data_type = "RGBA"
    L.new(scm.outputs["Result"], ms.inputs[0]); L.new(mx.outputs[2], ms.inputs[6]); ms.inputs[7].default_value = (0.28, 0.27, 0.24, 1)
    c, ao = K._ao_mix(N, L, ms.outputs[2], (0.07, 0.055, 0.035), 0.06)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.42
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.2; bump.inputs["Distance"].default_value = 0.002
    L.new(scm.outputs["Result"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def fleece(name, col=(0.035, 0.035, 0.04)):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 160.0; nz.inputs["Detail"].default_value = 4
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    c, ao = K._ao_mix(N, L, K._const(N, col), (0.008, 0.008, 0.01), 0.08)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.002
    L.new(nz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


SHELL_M = fibreglass("fibreglass")
HOOD_M = fleece("hoodie")
BLOOD = K.simple("dried_blood", (0.12, 0.02, 0.012), 0.75)
RESIN = K.simple("resin_fibre", (0.42, 0.4, 0.33), 0.8)
STRAP = K.rubber("elastic", (0.22, 0.22, 0.24))
STEEL = K.steel("steel", (0.25, 0.25, 0.25), heat=0.0, rust=0.35)
CORD = K.simple("cord", (0.5, 0.5, 0.48), 0.8)
DARK = K.simple("hood_inside", (0.008, 0.008, 0.009), 0.95)

FACE_C, FACE_R = (0, -0.18, 0.28), (0.62, 0.82, 0.86)
GOUGES = [((0.5, 0.78), (-0.3, -0.25), 0.042), ((0.58, 0.6), (-0.2, -0.42), 0.04), ((0.62, 0.4), (-0.12, -0.6), 0.038)]


def face_out(P):
    return sd_ellipsoid(P, FACE_C, FACE_R)


def outline(P):
    """The mask's outline seen from the front (positive outside): an oval tapering to the chin."""
    x, z = P[..., 0], P[..., 2]
    w = 0.56 - 0.16 * np.clip(-(z - 0.05) / 0.55, 0, 1)
    return (np.sqrt((x / w) ** 2 + ((z - 0.24) / 0.8) ** 2) - 1.0) * 0.5


def gouge2d(P, a, b, w):
    """Distance in the front (x, z) plane to a gouge line from a to b, tapering at both ends."""
    q = np.stack([P[..., 0], P[..., 2]], -1)
    a = np.array(a); b = np.array(b)
    ab = b - a
    t = np.clip(((q - a) @ ab) / (ab @ ab), 0, 1)
    dist = np.linalg.norm(q - (a + t[..., None] * ab), axis=-1)
    return dist - w * np.sin(np.pi * np.clip(t, 0.03, 0.97)) ** 0.5, t


def shell_uncut(P):
    fo = face_out(P)
    d = np.maximum(fo, -(fo + 0.06))  # 0.06 thick
    d = np.maximum(d, outline(P))
    d = np.maximum(d, P[..., 1] + 0.12)
    rim = np.sqrt(np.maximum(outline(P), -0.5) ** 2 * 0 + outline(P) ** 2 + (fo + 0.03) ** 2) - 0.035
    d = smin(d, np.maximum(rim, P[..., 1] + 0.1), 0.02)  # the rolled rim
    d = smin(d, sd_capsule(P, (0, -0.99, 0.62), (0, -0.82, 1.0), 0.04), 0.06)  # forehead ridge
    for s in (-1, 1):
        d = smin(d, np.maximum(sd_ellipsoid(P, (s * 0.21, -0.92, 0.42), (0.17, 0.2, 0.1)), fo - 0.03), 0.04)  # brows
    d = smin(d, sd_ellipsoid(P, (0, -1.0, 0.2), (0.07, 0.1, 0.13)), 0.05)  # nose
    d = smin(d, sd_ellipsoid(P, (0, -0.84, -0.4), (0.1, 0.05, 0.06)), 0.05)  # chin
    return d


def holes(P):
    """Eye holes + vent holes (through the shell)."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    h = 9.0
    for s in (-1, 1):
        q = np.stack([(x - s * 0.21) * math.cos(0.15 * s) - (z - 0.36) * math.sin(0.15 * s), (x - s * 0.21) * math.sin(0.15 * s) + (z - 0.36) * math.cos(0.15 * s)], -1)
        h = np.minimum(h, np.sqrt((q[..., 0] / 0.12) ** 2 + (q[..., 1] / 0.06) ** 2) * 0.06 - 0.06 + 0.0 * y)  # almond eyes
    vents = [(xx, zz) for xx in (-0.15, -0.05, 0.05, 0.15) for zz in (0.72, 0.84)]  # forehead
    vents += [(s * (0.2 + 0.06 * k), 0.1 - 0.08 * k) for s in (-1, 1) for k in range(4)]  # cheeks
    vents += [(xx, zz) for xx in (-0.09, 0.0, 0.09) for zz in (-0.12, -0.22)] + [(-0.045, -0.31), (0.045, -0.31)]  # mouth
    for vx, vz in vents:
        h = np.minimum(h, np.sqrt((x - vx) ** 2 + (z - vz) ** 2) - 0.022)
    return np.maximum(h, np.abs(y + 0.8) - 0.5)


def gouges(P):
    """The claw gouges: stepped grooves raked in from the outer surface, the third one tearing through at its end."""
    fo = face_out(P)
    d = 9.0
    for k, (a, b, w) in enumerate(GOUGES):
        g, t = gouge2d(P, a, b, w)
        depth = 0.03 + 0.025 * np.sin(np.pi * t) + (0.06 * np.clip((t - 0.7) / 0.2, 0, 1) if k == 2 else 0.0)
        wide = np.maximum(g, -(fo + depth * 0.45))  # a wide shallow scrape
        narrow = np.maximum(g + w * 0.5, -(fo + depth))  # a narrow deep cut in its middle
        d = np.minimum(d, np.minimum(wide, narrow))
    return d


def mask(P):
    d = shell_uncut(P)
    d = smax(d, -holes(P), 0.006)
    d = smax(d, -gouges(P), 0.004)
    # the notch: the third gouge carries a chunk out of the rim at the jaw
    d = smax(d, -(np.sqrt((P[..., 0] + 0.14) ** 2 + (P[..., 2] + 0.56) ** 2) - 0.07), 0.01)
    return d


def blood(P):
    """Dried blood lying in the gouges' floors (a thin fill just above each floor)."""
    fo = face_out(P)
    d = 9.0
    for k, (a, b, w) in enumerate(GOUGES):
        g, t = gouge2d(P, a, b, w * 0.8)
        d = np.minimum(d, g + 0.002 + 0.01 * (np.sin(t * 23.0 + k) > 0.3))
    inside = np.maximum(-(fo + 0.065), fo + 0.022)  # a layer from deep in the shell up to 0.022 below its surface
    return np.maximum(np.maximum(d, inside), P[..., 1] + 0.3)


def hood(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)
    head = sd_ellipsoid(P, (0, 0.08, 0.36), (0.76, 0.9, 0.84))
    peak = np.exp(-(((y - 0.5) / 0.3) ** 2 + ((z - 1.0) / 0.3) ** 2 + (x / 0.16) ** 2))  # the hood's point, up and back
    folds = 0.035 * np.sin(th * 7.0 + z * 3.0) * np.clip(1.1 - z, 0, 1) + 0.02 * np.sin(th * 13.0 - z * 5.0)  # creases
    outer = head - (0.09 + 0.16 * peak + folds)
    bag = sd_ellipsoid(P, (0, 0.72, -0.02), (0.5, 0.32, 0.42))  # the loose cloth slumped at the back of the neck
    outer = smin(outer, bag + 0.6 * folds, 0.22)
    d = np.abs(outer) - 0.03
    neck = np.abs(sd_capsule(P, (0, 0.1, -0.1), (0, 0.1, -0.9), 0.55 + 0.015 * np.sin(th * 9)) ) - 0.03
    d = smin(d, neck, 0.15)
    d = smax(d, -(z + 0.95), 0.03)
    # the face opening: an oval round the mask, a little bigger
    w = 0.68 - 0.12 * np.clip(-(z - 0.05) / 0.55, 0, 1)  # its edge lies behind the mask's outline (no frame round it)
    open_ = (np.sqrt((x / w) ** 2 + ((z - 0.24) / 0.95) ** 2) - 1.0) * 0.5
    open_ = np.maximum(open_, -(z + 0.4))  # closed under the chin (the neck is covered behind the mask's chin)
    d = smax(d, -np.maximum(-open_, y + 0.2), 0.03)
    roll = np.sqrt(np.maximum(open_, -0.2) ** 2 + outer ** 2) - 0.04  # the rolled hem round the opening, part of the hood
    d = smin(d, np.maximum(roll, y + 0.2), 0.02)

    for s in (-1, 1):  # the hood's centre panel: two seams over the top and down the back
        d = groove(d, np.where(y > -0.45, s * x - 0.17, 9.0), 0.014, 0.016, 0.005)
    return d


m_obj = K.sdf_mesh("mask", mask, (-0.72, -1.15, -0.62), (0.72, 0.0, 1.1), 0.009, SHELL_M)
K.sdf_mesh("gouge_blood", blood, (-0.72, -1.15, -0.62), (0.72, -0.3, 1.1), 0.007, BLOOD)
hood_o = K.sdf_mesh("hood", hood, (-1.0, -0.85, -1.0), (1.0, 1.45, 1.4), 0.012, HOOD_M)
K.ball("hood_inside", 0.62, (0, -0.1, 0.25), DARK, (1.0, 0.9, 1.25), 24)  # darkness round the mask's edge

# blood drips run down from the gouges' lower ends
for k, (a, b, w) in enumerate(GOUGES):
    for f in (0.55, 0.85):
        x0 = a[0] + (b[0] - a[0]) * f; z0 = a[1] + (b[1] - a[1]) * f
        pts = []
        for i in range(8):
            zz = z0 - 0.025 * i * (1.6 if k == 1 else 1.0)
            ok, loc, n, j = m_obj.ray_cast(Vector((x0 + 0.004 * math.sin(i), -2.0, zz)), Vector((0, 1, 0)))
            if ok:
                pts.append(loc + n * 0.004)
        if len(pts) > 3:
            K.tube("drip", pts, 0.008, BLOOD, res=2, taper=lambda u: 1.0 - 0.5 * u)

# straps: studs on the mask's sides, two elastic straps round the hood's back with buckles
STUDS = {}
for s in (-1, 1):
    for zz in (0.62, 0.05):
        ok, loc, n, j = m_obj.ray_cast(Vector((s * 2.0, -0.45, zz)), Vector((-s, 0, 0)))
        if ok:
            K.bolt(loc, n, 0.03, STEEL)
            STUDS[(s, zz)] = loc + n * 0.01
for zz, tilt in ((0.62, 0.32), (0.05, -0.12)):
    pts = []
    for a in np.linspace(-1.0, 1.0, 41):
        ang = a * 1.95
        dirn = Vector((math.sin(ang), math.cos(ang), tilt * math.cos(ang) * 0.6)).normalized()
        c = Vector((0, 0.05, zz))
        ok, loc, n, j = hood_o.ray_cast(c + dirn * 3.0, -dirn)
        if ok and loc.y > -0.4:
            pts.append(loc - n * 0.006)  # biting into the cloth
    if (-1, zz) in STUDS and (1, zz) in STUDS:
        sa, sb = (STUDS[(-1, zz)], STUDS[(1, zz)]) if pts and pts[0].x < 0 else (STUDS[(1, zz)], STUDS[(-1, zz)])
        pts = [sa] + pts + [sb]
    if len(pts) > 5:
        K.loft("strap", K.path_fn(pts), lambda t: 0.075, 80, 8, mat=STRAP, profile=lambda th, t: (0.35, 1.0))
        mid = pts[len(pts) // 2]
        K.box("buckle", (0.1, 0.03, 0.07), tuple(mid + Vector((0, 0.02, 0))), (0, 0, 0), STEEL, 0.008, 1)
# hood drawstrings hanging from the opening at the jaw
for s in (-1, 1):
    top = Vector((s * 0.5, -0.52, -0.36))
    K.tube("cord", K.smooth_path([top, top + Vector((s * 0.03, -0.08, -0.15)), top + Vector((s * 0.01, -0.1, -0.35))], 12), 0.016, CORD, res=3)
    K.loft("aglet", lambda t, p=top + Vector((s * 0.01, -0.1, -0.35)): p + Vector((0, 0, -0.06 * t)), lambda t: 0.02, 3, 8, mat=STEEL)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("street_predator")
print("ok")

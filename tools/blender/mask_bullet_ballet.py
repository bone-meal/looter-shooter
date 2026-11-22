# Bullet Ballet mask (elite 23, diary/DECISIONS_SKINS.md B23, plan in diary/MASK_PLANS_DROPS.md): a goalie mask that
# took a whole firefight and kept every round, worn by a dancer (hockey, base 1). Kept apart from the Street Predator
# and from any film mask: a BLACK painted shell with no markings, covered in brass, ballet satin and tulle.
# FRONT = spent casings driven into the shell base-out in rough scale rows, denser round the eyes, a few stuck in at
# an angle; bullet strikes where the shell shows. SIDE = casings bristling off the cheeks and brow, the rolled rim,
# pale pink satin ribbons from the temples and jaw over a black hood. BACK = the ribbons crossing in an X, tied in a
# big bow at the nape with long tails, a layered stiff tulle ruffle round the neck at the collar.
# Run: python3 tools/blender/mask_bullet_ballet.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py bullet_ballet
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
SC = K.setup(231)


def paint(name, col=(0.012, 0.012, 0.014)):
    """Black paint on fibreglass, chipped to grey at edges and in patches, scuffed."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    ch = N.new("ShaderNodeTexNoise"); ch.inputs["Scale"].default_value = 14.0; ch.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], ch.inputs["Vector"])
    geo = N.new("ShaderNodeNewGeometry")
    edge = N.new("ShaderNodeMapRange"); edge.inputs["From Min"].default_value = 0.53; edge.inputs["From Max"].default_value = 0.62
    L.new(geo.outputs["Pointiness"], edge.inputs["Value"])
    chip = N.new("ShaderNodeMapRange"); chip.inputs["From Min"].default_value = 0.66; chip.inputs["From Max"].default_value = 0.7
    L.new(ch.outputs["Fac"], chip.inputs["Value"])
    mx = N.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
    L.new(edge.outputs["Result"], mx.inputs[0]); L.new(chip.outputs["Result"], mx.inputs[1])
    mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
    L.new(mx.outputs[0], mc.inputs[0]); mc.inputs[6].default_value = (*col, 1); mc.inputs[7].default_value = (0.3, 0.29, 0.26, 1)
    c, ao = K._ao_mix(N, L, mc.outputs[2], (0.004, 0.004, 0.004), 0.05)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.38
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.002
    L.new(chip.outputs["Result"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def brass(name, col=(0.55, 0.38, 0.13), tarnish=(0.2, 0.13, 0.05)):
    """Spent brass: tarnished brown in a mottle, bright where rubbed (edges), slight powder burn."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 22.0; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    geo = N.new("ShaderNodeNewGeometry")
    rub = N.new("ShaderNodeMapRange"); rub.inputs["From Min"].default_value = 0.5; rub.inputs["From Max"].default_value = 0.58
    L.new(geo.outputs["Pointiness"], rub.inputs["Value"])
    mt = N.new("ShaderNodeMix"); mt.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mt.inputs[0]); mt.inputs[6].default_value = (*col, 1); mt.inputs[7].default_value = (*tarnish, 1)
    mr = N.new("ShaderNodeMix"); mr.data_type = "RGBA"
    L.new(rub.outputs["Result"], mr.inputs[0]); L.new(mt.outputs[2], mr.inputs[6])
    mr.inputs[7].default_value = (col[0] * 1.4, col[1] * 1.35, col[2] * 1.2, 1)
    c, ao = K._ao_mix(N, L, mr.outputs[2], (0.03, 0.02, 0.01), 0.03)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.9
    b.inputs["Roughness"].default_value = 0.35
    return m


def satin(name, col=(0.85, 0.55, 0.6)):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = 0.3
    b.inputs["Sheen Weight"].default_value = 0.6
    b.inputs["Sheen Tint"].default_value = (1.0, 0.9, 0.92, 1)
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexWave"); nz.inputs["Scale"].default_value = 120.0
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.05; bump.inputs["Distance"].default_value = 0.001
    L.new(nz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def tulle(name, col=(0.05, 0.045, 0.055)):
    """Stiff black tulle: a fine net (Voronoi-free: crossed waves) catching a soft sheen."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    w1 = N.new("ShaderNodeTexWave"); w1.inputs["Scale"].default_value = 220.0
    L.new(tc.outputs["Object"], w1.inputs["Vector"])
    c, ao = K._ao_mix(N, L, K._const(N, col), (0.005, 0.004, 0.005), 0.05)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    b.inputs["Sheen Weight"].default_value = 0.5
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.2; bump.inputs["Distance"].default_value = 0.002
    L.new(w1.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


SHELL_M = paint("black_paint")
BRASS = brass("brass")
COPPER = brass("copper", (0.6, 0.27, 0.15), (0.2, 0.08, 0.04))
NICKEL = brass("nickel", (0.55, 0.55, 0.52), (0.22, 0.22, 0.2))
PRIMER = K.simple("primer", (0.35, 0.3, 0.25), 0.4, metal=0.8)
SATIN = satin("satin")
TULLE = tulle("tulle")
HOOD_M = K.simple("hood_black", (0.012, 0.012, 0.014), 0.9)
STEEL = K.steel("steel", (0.25, 0.25, 0.25), heat=0.0, rust=0.2)
DARK = K.simple("inside", (0.006, 0.006, 0.007), 0.95)

FACE_C, FACE_R = (0, -0.18, 0.28), (0.62, 0.82, 0.86)


def face_out(P):
    return sd_ellipsoid(P, FACE_C, FACE_R)


def outline(P):
    x, z = P[..., 0], P[..., 2]
    w = 0.56 - 0.16 * np.clip(-(z - 0.05) / 0.55, 0, 1)
    return (np.sqrt((x / w) ** 2 + ((z - 0.24) / 0.8) ** 2) - 1.0) * 0.5


EYES = [(s * 0.21, 0.36, 0.15 * s) for s in (-1, 1)]


def eye_holes(P):
    x, z = P[..., 0], P[..., 2]
    h = 9.0
    for ex, ez, a in EYES:
        q0 = (x - ex) * math.cos(a) - (z - ez) * math.sin(a)
        q1 = (x - ex) * math.sin(a) + (z - ez) * math.cos(a)
        h = np.minimum(h, np.sqrt((q0 / 0.12) ** 2 + (q1 / 0.06) ** 2) * 0.06 - 0.06)
    return h


STRIKES = [(0.32, -0.2), (-0.36, 0.0), (0.05, -0.42), (-0.12, 0.7), (0.4, 0.62)]


def mask(P):
    fo = face_out(P)
    d = np.maximum(fo, -(fo + 0.06))
    d = np.maximum(d, outline(P))
    d = np.maximum(d, P[..., 1] + 0.12)
    rim = np.sqrt(outline(P) ** 2 + (fo + 0.03) ** 2) - 0.035
    d = smin(d, np.maximum(rim, P[..., 1] + 0.1), 0.02)
    d = smin(d, sd_capsule(P, (0, -0.99, 0.62), (0, -0.82, 1.0), 0.04), 0.06)  # forehead ridge
    for s in (-1, 1):
        d = smin(d, np.maximum(sd_ellipsoid(P, (s * 0.21, -0.92, 0.42), (0.17, 0.2, 0.1)), fo - 0.03), 0.04)  # brows
    d = smin(d, sd_ellipsoid(P, (0, -1.0, 0.2), (0.07, 0.1, 0.13)), 0.05)  # nose
    d = smin(d, sd_ellipsoid(P, (0, -0.84, -0.4), (0.1, 0.05, 0.06)), 0.05)  # chin
    d = smax(d, -np.maximum(eye_holes(P), np.abs(P[..., 1] + 0.8) - 0.5), 0.006)
    for (sx, sz) in STRIKES:  # bullet strikes: craters with a raised lip
        r = np.sqrt((P[..., 0] - sx) ** 2 + (P[..., 2] - sz) ** 2)
        d = d + 0.018 * np.exp(-(r / 0.03) ** 2) * (P[..., 1] < -0.3) - 0.006 * np.exp(-((r - 0.045) / 0.012) ** 2) * (P[..., 1] < -0.3)
    return d


def hood(P):
    """A tight black hood behind the mask over the head and neck down to the collar."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    head = sd_ellipsoid(P, (0, 0.06, 0.34), (0.74, 0.88, 0.82))
    d = smin(head, sd_capsule(P, (0, 0.1, -0.1), (0, 0.12, -0.96), 0.5), 0.15)
    d = d - 0.01 * np.sin(np.arctan2(x, y) * 9.0 + z * 4.0)
    d = smin(d, sd_ellipsoid(P, (0, 0.78, 0.42), (0.24, 0.2, 0.22)), 0.1)  # a dancer's bun under the hood, high at the back
    for sx in (-1, 1):  # the hood's centre panel seams
        d = groove(d, np.where(y > -0.3, sx * x - 0.16, 9.0), 0.012, 0.014, 0.004)
    d = smax(d, -(z + 0.98), 0.03)
    w = 0.66 - 0.12 * np.clip(-(z - 0.05) / 0.55, 0, 1)  # the opening behind the mask's outline
    open_ = np.maximum((np.sqrt((x / w) ** 2 + ((z - 0.24) / 0.82) ** 2) - 1.0) * 0.5, -(z + 0.4))  # not up over the crown
    return smax(d, -np.maximum(-open_, y + 0.25), 0.03)


m_obj = K.sdf_mesh("mask", mask, (-0.72, -1.15, -0.62), (0.72, 0.0, 1.1), 0.009, SHELL_M)
hood_o = K.sdf_mesh("hood", hood, (-0.9, -0.7, -1.02), (0.9, 1.05, 1.25), 0.012, HOOD_M)
K.ball("inside", 0.6, (0, -0.15, 0.25), DARK, (1.0, 0.9, 1.25), 24)


# ------------------------------------------------------------------ the casings: one mesh (kept by the baker as a whole)
def casing_geo(verts, faces, base, n, length, r, seg=8, crimp=True):
    """A spent casing standing out of the surface at `base` along `n`: rim, body, a slight neck, open mouth."""
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((0, 1, 0))
    a = n.cross(up).normalized(); bvec = n.cross(a).normalized()
    rings = [(0.0, r * 1.08), (0.012, r * 1.08), (0.016, r * 0.92), (0.02, r), (length * 0.75, r), (length * 0.85, r * 0.86),
             (length, r * 0.84), (length, r * 0.66), (length - 0.02, r * 0.66)]  # rim, extractor groove, body, neck, mouth lip, inside
    i0 = len(verts)
    for (t, rr) in rings:
        c = base + n * (length - t)  # base-out: the head (rim + primer) faces OUT, the mouth goes in
        for j in range(seg):
            th = 2 * math.pi * j / seg
            verts.append(tuple(c + a * (math.cos(th) * rr) + bvec * (math.sin(th) * rr)))
    for k in range(len(rings) - 1):
        for j in range(seg):
            p0 = i0 + k * seg + j; p1 = i0 + k * seg + (j + 1) % seg
            faces.append((p0, p1, p1 + seg, p0 + seg))
    ci = len(verts); verts.append(tuple(base + n * length))  # the head's face (cap)
    for j in range(seg):
        faces.append((i0 + (j + 1) % seg, i0 + j, ci))


groups = {"brass": ([], []), "copper": ([], []), "nickel": ([], [])}
primers = []
centre = Vector((0.0, -0.2, 0.25))
count = 0
for zz in np.arange(-0.5, 1.02, 0.085):
    row_off = 0.0425 if int(round(zz / 0.085)) % 2 else 0.0
    for xx in np.arange(-0.6 + row_off, 0.61, 0.085):
        p = Vector((xx + random.uniform(-0.012, 0.012), -2.0, zz + random.uniform(-0.012, 0.012)))
        ok, loc, n, j = m_obj.ray_cast(p, Vector((0, 1, 0)))
        if not ok or n.y > -0.05:
            continue
        # leave the eye holes clear (a ring of casings round them, denser) and thin out toward the chin
        ex = min(math.hypot((loc.x - e[0]) / 0.12, (loc.z - e[1]) / 0.06) for e in EYES)
        if ex < 1.35:
            continue
        if loc.z < -0.25 and random.random() < 0.45:
            continue
        if random.random() < 0.08:
            continue  # a few gaps where the shell shows
        if (abs(loc.x) < 0.09 and loc.z > 0.5) or min(math.hypot(loc.x - a, loc.z - b) for (a, b) in STRIKES) < 0.09:
            continue  # the forehead ridge and the strikes stay bare
        tilt = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * (0.6 if random.random() < 0.12 else 0.18)
        nn = (n + tilt + Vector((0, 0, -0.75))).normalized()  # laid downward like scales, overlapping (not a pincushion)
        length = random.uniform(0.1, 0.13) if ex > 2.2 else random.uniform(0.07, 0.1)
        r = random.choice((0.028, 0.03, 0.032, 0.036))
        kind = random.choices(("brass", "copper", "nickel"), (0.8, 0.1, 0.1))[0]
        base = loc - nn * (length * 0.3)  # driven in a third of its length: the bodies stand out
        casing_geo(*groups[kind], base, nn, length, r)
        primers.append((base + nn * (length + 0.002), nn, r * 0.42))
        count += 1
print("CASINGS", count)
for kind, mat in (("brass", BRASS), ("copper", COPPER), ("nickel", NICKEL)):
    v, f = groups[kind]
    if v:
        K.mesh_obj("casings_" + kind, v, f, mat, smooth_it=False)
# primers: little dimpled discs in one mesh
pv, pf = [], []
for (c, n, r) in primers:
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((0, 1, 0))
    a = n.cross(up).normalized(); b = n.cross(a).normalized()
    i0 = len(pv)
    for j in range(8):
        th = 2 * math.pi * j / 8
        pv.append(tuple(c + a * (math.cos(th) * r) + b * (math.sin(th) * r)))
    pv.append(tuple(c - n * 0.004))  # the firing pin dimple
    for j in range(8):
        pf.append((i0 + j, i0 + (j + 1) % 8, i0 + 8))
K.mesh_obj("primers", pv, pf, PRIMER, smooth_it=False)


# ------------------------------------------------------------------ satin ribbons: temples and jaw, crossing behind in an X, a bow
HC = Vector((0.0, 0.1, 0.3))


def on_hood_dir(th, z):
    """The point on the hood in the direction th (0 = straight back, + toward +x) at height z, lifted off it."""
    dirn = Vector((math.sin(th), math.cos(th), 0.0))
    o = Vector((HC.x, HC.y, z)) + dirn * 3.0
    ok, loc, n, j = hood_o.ray_cast(o, -dirn)
    return (loc + n * 0.012) if ok else None


def ribbon(pts, w=0.08, twists=1.0):
    """A satin ribbon along pts that turns over on itself as it goes (a flat band would read as tape)."""
    f = K.path_fn(K.smooth_path(pts, 60))
    rings, segs = 120, 8
    verts, faces = [], []
    for i in range(rings):
        t = i / (rings - 1)
        c = f(t)
        T = (f(min(1, t + 1e-3)) - f(max(0, t - 1e-3))).normalized()
        up = Vector((0, 0, 1)) if abs(T.z) < 0.95 else Vector((0, 1, 0))
        B = T.cross(up).normalized(); U = B.cross(T).normalized()
        a = math.pi * 0.45 * math.sin(t * math.pi * 2 * twists)
        Bt = B * math.cos(a) + U * math.sin(a); Ut = U * math.cos(a) - B * math.sin(a)
        for j in range(segs):
            th = 2 * math.pi * j / segs
            verts.append(tuple(c + Bt * (math.cos(th) * w * 0.36) + Ut * (math.sin(th) * w)))  # thick enough to survive decimation (0.2 tore)
    for i in range(rings - 1):
        for j in range(segs):
            p0 = i * segs + j; p1 = i * segs + (j + 1) % segs
            faces.append((p0, p0 + segs, p1 + segs, p1))
    K.mesh_obj("ribbon", verts, faces, SATIN)


NAPE = Vector((0.0, 0.84, -0.12))
for s in (-1, 1):
    for (zs, zend, th_end) in ((0.6, -0.1, s * 0.12), (0.02, 0.62, -s * 0.5)):  # temple ribbon down to the nape, jaw ribbon up across: an X
        ok, loc, n, j = m_obj.ray_cast(Vector((s * 2.0, -0.45, zs)), Vector((-s, 0, 0)))
        if not ok:
            continue
        K.bolt(loc, n, 0.03, STEEL)
        pts = [loc + n * 0.01]
        for f in np.linspace(0.12, 1.0, 9):
            th = s * 1.75 + (th_end - s * 1.75) * f
            hit = on_hood_dir(th, zs + (zend - zs) * f)
            if hit is not None:
                pts.append(hit)
        if zend < 0:
            pts.append(NAPE + Vector((s * 0.04, 0.02, 0.0)))
        if len(pts) > 3:
            ribbon(pts)

# the bow at the nape: two loops and two long tails
for s in (-1, 1):
    loop = [NAPE + Vector((0, 0.02, 0)), NAPE + Vector((s * 0.12, 0.1, 0.1)), NAPE + Vector((s * 0.26, 0.1, 0.04)),
            NAPE + Vector((s * 0.24, 0.07, -0.08)), NAPE + Vector((s * 0.1, 0.06, -0.04)), NAPE + Vector((0, 0.03, 0))]
    ribbon(loop, 0.08)
    ribbon([NAPE + Vector((0, 0.04, -0.02)), NAPE + Vector((s * 0.08, 0.12, -0.2)), NAPE + Vector((s * 0.12, 0.1, -0.45)),
            NAPE + Vector((s * 0.18, 0.08, -0.7))], 0.07)
K.ball("bow_knot", 0.06, tuple(NAPE + Vector((0, 0.05, 0))), SATIN, (1.2, 0.8, 1.0), 14)


# ------------------------------------------------------------------ the tulle ruffle round the neck at the collar
def ruffle(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y - 0.1)
    r = np.sqrt(x ** 2 + (y - 0.1) ** 2)
    d = 9.0
    for k, (zc, R, amp) in enumerate(((-0.66, 0.64, 0.035), (-0.73, 0.7, 0.04), (-0.8, 0.76, 0.045), (-0.88, 0.82, 0.05))):
        flute = 0.4 * amp * np.sin(th * (9 + k) + k * 1.7)  # soft waves in the frill (big pleats read as a paper zig-zag)
        layer = np.sqrt((r - R - flute * 0.4) ** 2 * 0 + 0.0) + 0.0
        sheet = np.abs((z - zc) + (r - 0.5) * 0.35 + flute) - 0.016  # a cone-like frill flaring down and out
        sheet = np.maximum(sheet, r - R - 0.035 * np.abs(np.sin(th * (8 + k))))  # a scalloped round edge
        sheet = np.maximum(sheet, 0.48 - r)
        d = np.minimum(d, sheet)
    return smax(d, -(z + 0.99), 0.01)


K.sdf_mesh("ruffle", ruffle, (-0.95, -0.8, -1.02), (0.95, 1.0, -0.55), 0.008, TULLE)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("bullet_ballet")
print("ok")

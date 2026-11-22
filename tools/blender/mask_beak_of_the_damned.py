# Beak of the Damned mask (elite / mob mask 20, diary/DECISIONS_SKINS.md B20, plan in diary/MASK_PLANS_DROPS.md): the
# Plague Doctor (base 7) rebuilt by a machinist: no hat, a short segmented steel beak, iris lenses, a pump on the back.
# FRONT = riveted overlapping beak segments with a hinged tip and a slotted grille under it, brass lens cups with iris
# blades round dark glass (fxR_ faint green), a riveted brow band; SIDE = the stepped segments, a hose from under the
# beak back to the pump, the cowl's seams; BACK = a brass bellows pump with a turning gear (fxB_: spin), lacing below.
# Run: python3 tools/blender/mask_beak_of_the_damned.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py beak_of_the_damned
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(201)


def leather(name, col=(0.045, 0.03, 0.022)):
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 6.0; nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0]); mx.inputs[6].default_value = (*col, 1)
    mx.inputs[7].default_value = (col[0] * 1.8, col[1] * 1.7, col[2] * 1.5, 1)
    c, ao = K._ao_mix(N, L, mx.outputs[2], (0.008, 0.006, 0.004), 0.06)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.55
    vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 70.0
    L.new(tc.outputs["Object"], vo.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.003
    L.new(vo.outputs["Distance"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


LEATHER = leather("leather", (0.028, 0.018, 0.012))
STEEL = K.steel("blued_steel", (0.12, 0.13, 0.16), heat=0.5, rust=0.4)
BRASS = K.steel("brass", (0.5, 0.36, 0.14), heat=0.0, rust=0.3, rough=0.35)
GEAR = K.steel("fxB_gear_brass", (0.5, 0.36, 0.14), heat=0.0, rust=0.3, rough=0.35)
GLASS = K.glow("fxR_lens_green", (0.35, 1.0, 0.3), 2.5, base=(0.01, 0.03, 0.01))
DARK = K.simple("dark", (0.008, 0.008, 0.008), 0.9)
RUB = K.rubber("hose")
CORD = K.simple("lace", (0.25, 0.2, 0.14), 0.9)


def cowl(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.03, 0.36), (0.72, 0.86, 0.82))
    d = smax(d, np.abs(x) - 0.66, 0.12)
    d = smax(d, P @ np.array([0, -0.95, 0.3]) - 0.84, 0.15)  # a flat face
    d = smin(d, sd_capsule(P, (0, 0.08, -0.1), (0, 0.1, -0.92), 0.5), 0.18)
    d = smax(d, -(z + 0.98), 0.03)  # down to the collar line (z -0.97)
    for s in (-1, 1):  # welted seams over the head
        d = groove(d, s * x - 0.3 - 0.0 * z, 0.01, 0.012, 0.004)
    d = groove(d, np.where(y > 0.0, np.abs(x) - 0.0, 9.0) * 0 + np.where(y > 0.0, x, 9.0), 0.01, 0.01, 0.0)
    d = d + 0.06 * np.exp(-((z + 0.62) / 0.06) ** 2)  # a rolled collar at the neck (pushed out)
    d = d - 0.06 * np.exp(-((z + 0.62) / 0.06) ** 2) * 2
    return d


head = K.sdf_mesh("cowl", cowl, (-0.85, -1.0, -1.0), (0.85, 1.0, 1.25), 0.012, LEATHER)


def cap(P):
    """A riveted steel skull cap of five overlapping bands from brow to nape (a lobster-tail) + hinged cheek guards."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    c = cowl(P)
    shell = np.maximum(c - 0.06, -(c - 0.005))
    phi = np.arctan2(y - 0.03, z - 0.36)  # 0 = straight up, + toward the back
    d = np.maximum(shell, np.abs(x) - 0.52 + 0.1 * np.clip(phi - 1.2, 0, 1))
    d = np.maximum(d, -0.75 - phi)  # starts at the brow
    d = np.maximum(d, phi - 2.15)  # ends at the nape
    for k in range(4):  # overlapping band edges, each band stepping over the next
        pk = -0.45 + 0.6 * (k + 1)
        d = groove(d, (phi - pk) * 0.8, 0.012, 0.014, -0.014)
    d = smin(d, np.maximum(np.maximum(c - 0.1, -(c - 0.005)), np.maximum(np.abs(x) - 0.05, np.maximum(-0.7 - phi, phi - 2.1))), 0.02)  # a centre ridge
    for s in (-1, 1):  # cheek guards: plates hinged at the temples, flaring out a little
        g = sd_box(P, (s * 0.7, -0.42, 0.08), (0.05, 0.28, 0.32), 0.04)
        d = smin(d, g, 0.01)
    return d


cap_o = K.sdf_mesh("cap", cap, (-0.9, -0.95, -0.35), (0.9, 1.0, 1.3), 0.011, STEEL)
for s in (-1, 1):
    for zz in (0.3, -0.12):
        K.bolt(Vector((s * 0.76, -0.42, zz)), Vector((s, 0, 0)), 0.02, BRASS)

# the short segmented beak: four overlapping steel bands, curving down to a hinged tip
BASE = Vector((0, -0.84, 0.12))
TIP = Vector((0, -1.72, -0.22))


def beak_c(t):
    return BASE.lerp(TIP, t) + Vector((0, 0, 0.12 * math.sin(math.pi * t * 0.9)))


def beak_r(t):
    return 0.33 * (1 - t) ** 0.85 + 0.035


segs = [(0.0, 0.3), (0.26, 0.52), (0.48, 0.74), (0.7, 0.92)]
for k, (t0, t1) in enumerate(segs):
    K.loft("beak_seg", lambda u, t0=t0, t1=t1: beak_c(t0 + (t1 - t0) * u), lambda u, t0=t0, t1=t1: beak_r(t0 + (t1 - t0) * u) * (1.06 - 0.06 * u) + 0.012,
           10, 28, mat=STEEL, profile=lambda th, t: (1.0, 0.9))
    for j in range(7):  # rivets along each band's back edge
        a = -1.25 + 2.5 * j / 6
        c = beak_c(t0 + 0.02); r = beak_r(t0) * 1.06 + 0.014
        T = (beak_c(t0 + 0.03) - beak_c(t0)).normalized()
        B = T.cross(Vector((0, 0, 1))).normalized(); U = B.cross(T)
        p = c + (B * math.sin(a) * 1.0 + U * math.cos(a) * 0.9) * r
        K.bolt(p, (p - c).normalized(), 0.016, BRASS)
K.loft("beak_tip", lambda u: beak_c(0.9 + 0.12 * u), lambda u: beak_r(0.9) * (1 - u) ** 0.6 + 0.008, 8, 20, mat=BRASS)
hinge = beak_c(0.9)
for s in (-1, 1):
    K.ball("tip_hinge", 0.025, tuple(hinge + Vector((s * beak_r(0.9) * 1.05, 0, 0))), BRASS, (1, 1, 1), 10)
for j in range(5):  # the slotted grille under the beak
    t = 0.15 + 0.12 * j
    c = beak_c(t)
    K.box("grille_slot", (beak_r(t) * 1.1, 0.025, 0.02), tuple(c + Vector((0, 0, -beak_r(t) * 0.86))), (0.3, 0, 0), DARK, 0.004, 1)

# brass lens cups with iris blades round dark green glass
for s in (-1, 1):
    ok, loc, n, i = head.ray_cast(Vector((s * 0.26, -2.0, 0.38)), Vector((0, 1, 0)))
    if not ok:
        continue
    nn = (n + Vector((s * 0.2, 0, 0))).normalized()
    K.loft("lens_cup", lambda u, a=loc: a + nn * (-0.03 + 0.19 * u), lambda u: 0.17 - 0.015 * u, 8, 28, mat=BRASS)
    K.loft("lens_rim", lambda u, a=loc: a + nn * (0.16 + 0.03 * u), lambda u: 0.19, 3, 28, mat=BRASS)
    K.ball("lens_glass", 0.13, tuple(loc + nn * 0.15), GLASS, (1, 1, 0.3), 20)
    u_ = nn.cross(Vector((0, 0, 1))).normalized(); v_ = nn.cross(u_)
    for q in range(6):  # iris blades half closed round the glass
        a = q * math.pi / 3
        c = loc + nn * 0.175 + (u_ * math.cos(a) + v_ * math.sin(a)) * 0.12
        bl = K.box("iris_blade", (0.09, 0.028, 0.012), tuple(c), (0, 0, 0), STEEL, 0.004, 1)
        K.align(bl, nn)
        bl.rotation_mode = "QUATERNION"
    for q in range(8):
        a = q * math.pi / 4
        K.bolt(loc + nn * 0.19 + (u_ * math.cos(a) + v_ * math.sin(a)) * 0.19, nn, 0.012, STEEL)

# the riveted brow band round the head
band = []
for a in np.linspace(0, 2 * math.pi, 49):
    d_ = Vector((math.sin(a), -math.cos(a), 0.0))
    ok, loc, n, i = head.ray_cast(Vector((0, 0.03, 0.62)) + d_ * 3.0, -d_)
    if ok:
        band.append(loc + n * 0.015)
if len(band) > 10:
    K.loft("brow_band", K.path_fn(band), lambda t: 0.06, 96, 8, mat=STEEL, profile=lambda th, t: (0.45, 1.0))
    for j in range(0, len(band), 3):
        K.bolt(band[j], (band[j] - Vector((0, 0.03, 0.62))).normalized(), 0.016, BRASS)

# the bellows pump on the back of the head, with a gear that turns
ok, loc, n, i = head.ray_cast(Vector((0, 2.0, 0.2)), Vector((0, -1, 0)))
PUMP = None
if ok:
    PUMP = loc
    K.box("pump_plate", (0.52, 0.05, 0.5), tuple(loc + n * 0.025), (math.radians(-10), 0, 0), BRASS, 0.02, 2)
    K.loft("bellows", lambda u: loc + n * (0.05 + 0.3 * u), lambda u: 0.17 + 0.045 * abs(math.sin(u * math.pi * 6)), 48, 4, mat=LEATHER,
           profile=lambda th, t: (1.15, 1.0))
    K.box("bellows_end", (0.4, 0.05, 0.36), tuple(loc + n * 0.37), (math.radians(-10), 0, 0), BRASS, 0.015, 2)
    gc = loc + n * 0.06 + Vector((0.3, 0, 0.16))
    K.loft("gear", lambda u: gc + n * (0.03 * u), lambda u: 0.13, 3, 48, mat=GEAR, profile=lambda th, t: (1.0 + 0.16 * (math.cos(th * 12) > 0), 1.0 + 0.16 * (math.cos(th * 12) > 0)))
    print("GEAR_CENTRE", tuple(round(v, 4) for v in gc), "AXIS", tuple(round(v, 4) for v in n))
    g2 = loc + n * 0.06 + Vector((-0.3, 0, -0.14))
    K.loft("gear_small", lambda u: g2 + n * (0.03 * u), lambda u: 0.085, 3, 32, mat=BRASS, profile=lambda th, t: (1.0 + 0.2 * (math.cos(th * 8) > 0), 1.0 + 0.2 * (math.cos(th * 8) > 0)))

# the hose from under the beak back to the pump
if PUMP is not None:
    st = beak_c(0.2) + Vector((0, 0, -0.2))
    ctrl = [st, Vector((0.35, -0.75, -0.4)), Vector((0.72, -0.1, -0.35)), Vector((0.6, 0.6, -0.15)), PUMP + Vector((0.15, 0.1, -0.15))]
    f = K.path_fn(K.smooth_path(ctrl, 60))
    K.loft("hose", f, lambda t: 0.045 * (1 + 0.15 * math.sin(t * 2 * math.pi * 24)), 220, 12, mat=RUB)

# lacing down the back of the neck below the pump
for k in range(5):
    zz = -0.15 - 0.12 * k
    for s in (-1, 1):
        ok, loc, n, i = head.ray_cast(Vector((s * 0.07, 2.0, zz)), Vector((0, -1, 0)))
        if ok:
            K.ball("eyelet", 0.018, tuple(loc + n * 0.005), BRASS, (1, 1, 1), 8)
    a = Vector((-0.07, 0.62, zz)); b = Vector((0.07, 0.62, zz - 0.12))
    K.tube("lace", [a + Vector((0, 0.03, 0)), b + Vector((0, 0.03, 0))], 0.01, CORD, res=1)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("beak_of_the_damned")
print("ok")

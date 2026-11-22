# Filter Fiend mask (elite / mob mask 17, diary/DECISIONS_SKINS.md B17, plan in diary/MASK_PLANS_DROPS.md): a
# respirator taken to excess (base 5), its face crowded with filters like an insect's. FRONT = a snout of three
# stacked pancake filters, four canisters fanning out from the cheeks like mandibles, four round lenses set high;
# SIDE = corrugated tubes looping over the head into a crest of small filters; BACK = the tubes plunging into a back
# plate with gauges, a strap harness. Dim amber lenses (fxR_).
# Run: python3 tools/blender/mask_filter_fiend.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py filter_fiend
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(171)


def painted(name, col, chip=(0.32, 0.3, 0.27), stripes=False, scorch=0.0):
    """Painted metal: the paint chipped to bare metal on edges by noise; optional hazard stripes; optional scorch."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    base = K._const(N, col)
    if stripes:
        w = N.new("ShaderNodeTexWave"); w.wave_type = "BANDS"; w.bands_direction = "DIAGONAL"
        w.inputs["Scale"].default_value = 4.5; w.inputs["Distortion"].default_value = 0.0
        L.new(tc.outputs["Object"], w.inputs["Vector"])
        st = N.new("ShaderNodeMath"); st.operation = "GREATER_THAN"; st.inputs[1].default_value = 0.5
        L.new(w.outputs["Fac"], st.inputs[0])
        mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
        L.new(st.outputs[0], mx.inputs[0]); mx.inputs[6].default_value = (*col, 1); mx.inputs[7].default_value = (0.012, 0.012, 0.01, 1)
        base = mx.outputs[2]
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 14.0; nz.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ch = N.new("ShaderNodeMapRange"); ch.inputs["From Min"].default_value = 0.62; ch.inputs["From Max"].default_value = 0.66
    L.new(nz.outputs["Fac"], ch.inputs["Value"])
    mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
    L.new(ch.outputs["Result"], mc.inputs[0]); L.new(base, mc.inputs[6]); mc.inputs[7].default_value = (*chip, 1)
    out = mc.outputs[2]
    if scorch > 0:
        sn = N.new("ShaderNodeTexNoise"); sn.inputs["Scale"].default_value = 3.0; sn.inputs["Detail"].default_value = 6
        L.new(tc.outputs["Object"], sn.inputs["Vector"])
        sr = N.new("ShaderNodeMapRange"); sr.inputs["From Min"].default_value = 0.45; sr.inputs["From Max"].default_value = 0.62
        sr.inputs["To Max"].default_value = scorch
        L.new(sn.outputs["Fac"], sr.inputs["Value"])
        ms = N.new("ShaderNodeMix"); ms.data_type = "RGBA"
        L.new(sr.outputs["Result"], ms.inputs[0]); L.new(out, ms.inputs[6]); ms.inputs[7].default_value = (0.02, 0.012, 0.006, 1)
        out = ms.outputs[2]
    col_o, ao = K._ao_mix(N, L, out, (0.02, 0.018, 0.012), 0.06)
    L.new(col_o, b.inputs["Base Color"])
    L.new(ch.outputs["Result"], b.inputs["Metallic"])
    b.inputs["Roughness"].default_value = 0.5
    return m


RUBBER = K.rubber("rubber", (0.02, 0.02, 0.02))
YEL = painted("yellow_paint", (0.62, 0.45, 0.04), chip=(0.2, 0.19, 0.17))
HAZ = painted("hazard", (0.7, 0.5, 0.04), stripes=True)
STEEL = K.steel("steel", (0.22, 0.22, 0.21), heat=0.1, rust=0.4)
LENS = K.glow("fxR_lens", (1.0, 0.6, 0.15), 1.6, base=(0.06, 0.04, 0.015))
DARK = K.simple("holes", (0.008, 0.008, 0.008), 0.9)
STRAP = K.rubber("strap", (0.06, 0.06, 0.055))
GAUGE = K.simple("gauge_face", (0.75, 0.72, 0.62), 0.4)


def hood(P):
    """A tight rubber hood: squared skull, a ribbed neck down to the collar."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.04, 0.36), (0.7, 0.85, 0.8))
    d = smax(d, np.abs(x) - 0.64, 0.12)
    neck = sd_capsule(P, (0, 0.05, -0.1), (0, 0.08, -0.92), 0.48)
    d = smin(d, neck, 0.16)
    d = smax(d, -(z + 0.95), 0.03)
    d = d - 0.035 * (np.abs(np.sin(z * 22.0)) - 0.6) * np.clip(-(z + 0.15) * 3, 0, 1) - 0.06 * np.clip(-(z + 0.6) * 3, 0, 1)  # bellows ribs, flaring at the bottom
    return d


def face(P):
    """The yellow face plate: a forward wedge from brow to chin, sockets for four lenses, the snout's seat."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = hood(P) - 0.05
    fy = np.maximum(-(y - 0.15), 0.05)  # an oval round the face, seen from behind the head
    region = (np.sqrt((x / fy / 0.86) ** 2 + ((z - 0.16) / fy / 1.0) ** 2) - 1.0) * 0.55
    seal = d
    d = smax(d, region, 0.03)
    d = smin(d, np.sqrt(region ** 2 + seal ** 2) - 0.03, 0.02)  # a rolled rubber-edged rim
    d = smin(d, sd_ellipsoid(P, (0, -0.8, -0.1), (0.36, 0.3, 0.34)), 0.1)  # the muzzle mount
    for c, r in LENSES:
        d = smin(d, sd_ellipsoid(P, (c[0], c[1] + 0.06, c[2]), (r * 1.25, 0.1, r * 1.25)), 0.03)  # raised lens sockets
        d = smax(d, -sd_ellipsoid(P, c, (r, 0.3, r)), 0.01)
    return d


LENSES = [((-0.2, -0.84, 0.46), 0.11), ((0.2, -0.84, 0.46), 0.11), ((-0.42, -0.7, 0.3), 0.07), ((0.42, -0.7, 0.3), 0.07)]

head = K.sdf_mesh("hood", hood, (-0.8, -1.0, -1.0), (0.8, 1.0, 1.2), 0.012, RUBBER)
face_o = K.sdf_mesh("face", face, (-0.85, -1.2, -0.6), (0.85, 0.0, 0.85), 0.01, YEL)

for c, r in LENSES:  # lenses: glass with a dim amber glow, steel rings
    ctr = Vector(c) + Vector((0, -0.02, 0))
    K.ball("lens", r, tuple(ctr), LENS, (1.0, 0.3, 1.0), 20)
    K.tube("lens_ring", [ctr + Vector(((r + 0.012) * math.cos(a), -0.03, (r + 0.012) * math.sin(a))) for a in np.linspace(0, 2 * math.pi, 25)], 0.016, STEEL, res=2)


def pancake(base, axis, r, h):
    """A flat pancake filter: a ribbed steel rim round a perforated face."""
    axis = axis.normalized()
    K.loft("pancake", lambda t: base + axis * (h * t), lambda t: r + 0.01 * math.sin(t * math.pi), 5, 32, mat=YEL)
    K.loft("pancake_rim", lambda t: base + axis * (h * (0.45 + 0.1 * t)), lambda t: r + 0.014, 2, 32, mat=STEEL, cap=False)
    u = axis.cross(Vector((0, 0, 1))).normalized(); v = axis.cross(u)
    for ring, cnt in ((0.35, 6), (0.68, 12)):
        for k in range(cnt):
            a = k * 2 * math.pi / cnt + ring
            K.ball("pc_hole", 0.014, base + axis * (h + 0.002) + (u * math.cos(a) + v * math.sin(a)) * r * ring, DARK, (1, 1, 1), 6)
    return base + axis * h


def canister(base, axis, length, r):
    axis = axis.normalized()
    K.loft("can_neck", lambda t: base + axis * (0.05 * t), lambda t: r * 0.6 + 0.01 * math.sin(t * 40), 10, 20, mat=STEEL)
    b0 = base + axis * 0.04

    def rr(t):
        return r + (0.01 if (t * 7) % 1 < 0.2 else 0.0)
    K.loft("can_body", lambda t: b0 + axis * (length * t), rr, 40, 24, mat=YEL)
    K.loft("can_band", lambda t: b0 + axis * (length * (0.3 + 0.2 * t)), lambda t: r + 0.014, 3, 24, mat=HAZ, cap=False)
    end = b0 + axis * length
    K.loft("can_cap", lambda t: end + axis * (0.02 * t), lambda t: r * (0.95 - 0.2 * t), 3, 24, mat=STEEL)
    return end


# the snout: three stacked pancake filters
ok, loc, n, i = face_o.ray_cast(Vector((0, -2.0, -0.12)), Vector((0, 1, 0)))
SNOUT = []
if ok:
    ax = Vector((0, -1, -0.3)).normalized()
    p = loc - ax * 0.02
    for j, (r, h) in enumerate(((0.28, 0.07), (0.22, 0.065), (0.16, 0.06))):  # stepping down: a stack that reads
        K.loft("snout_spacer", lambda t, p=p: p + ax * (0.055 * t), lambda t, r=r: r * 0.42, 3, 20, mat=STEEL)
        p = pancake(p + ax * 0.05, ax, r, h)
    SNOUT.append(p)
# four mandible canisters fanning out from the cheeks
MANDIBLES = []
for s in (-1, 1):
    for zz, ax in ((0.08, Vector((s * 0.8, -0.65, 0.05))), (-0.24, Vector((s * 0.85, -0.5, -0.55)))):
        ok, loc, n, i = face_o.ray_cast(Vector((s * 0.4, -2.0, zz)), Vector((0, 1, 0)))
        if ok:
            MANDIBLES.append((s, loc, canister(loc - ax.normalized() * 0.02, ax, 0.32, 0.115)))

# the crest of small filters along the top of the head
CREST = []
for k, yy in enumerate((-0.45, -0.18, 0.1, 0.38, 0.62)):
    ok, loc, n, i = head.ray_cast(Vector((0, yy, 3.0)), Vector((0, 0, -1)))
    if ok:
        ax = (n + Vector((0, 0.25 * (k - 1), 0))).normalized()
        CREST.append(canister(loc - ax * 0.03, ax, 0.18 + 0.05 * (2 - abs(k - 2)), 0.1))
# the back plate with two gauges
ok, loc, n, i = head.ray_cast(Vector((0, 2.0, 0.25)), Vector((0, -1, 0)))
BACKP = None
if ok:
    BACKP = loc
    K.box("back_plate", (0.56, 0.07, 0.56), tuple(loc + n * 0.035), (math.radians(-12), 0, 0), YEL, 0.03, 2)
    drum = pancake(loc + n * 0.07 + Vector((0, 0, -0.04)), n, 0.24, 0.13)  # a big filter drum on the back
    pancake(drum + n * 0.01, n, 0.17, 0.06)
    for gx in (-0.2, 0.2):
        g = loc + n * 0.075 + Vector((gx, 0, 0.22))
        K.loft("gauge", lambda t, g=g: g + n * (0.03 * t), lambda t: 0.07, 3, 20, mat=STEEL)
        K.loft("gauge_face", lambda t, g=g: g + n * (0.031 + 0.002 * t), lambda t: 0.058, 2, 20, mat=GAUGE)

# corrugated tubes: snout -> over the head -> back plate; each mandible pair -> the crest's sides
def hose(ctrl, r):
    f = K.path_fn(K.smooth_path(ctrl, 60))
    K.loft("hose", f, lambda t: r * (1.0 + 0.14 * math.sin(t * 2 * math.pi * 26)), 260, 12, mat=RUBBER)


if SNOUT and BACKP is not None:
    for s in (-1, 1):
        sp = SNOUT[0]
        hose([sp + Vector((s * 0.12, 0.05, 0.08)), Vector((s * 0.55, -0.8, 0.35)), Vector((s * 0.55, -0.5, 1.0)),
              Vector((s * 0.4, 0.3, 1.15)), Vector((s * 0.25, 0.85, 0.6)), BACKP + Vector((s * 0.15, 0.06, 0.1))], 0.045)
for s, loc, end in MANDIBLES:
    if s > 0 and end.z > -0.2 or s < 0 and end.z > -0.2:
        hose([loc + Vector((s * 0.1, 0.06, 0.0)), Vector((s * 0.78, -0.25, 0.2)), Vector((s * 0.72, 0.35, 0.3)),
              Vector((s * 0.35, 0.82, 0.1)), (BACKP or Vector((0, 0.9, 0.2))) + Vector((s * 0.2, 0.05, -0.08))], 0.035)
# straps: two round the back of the hood from the face plate's edge
for zz in (0.55, -0.05):
    pts = []
    for a in np.linspace(-1.0, 1.0, 31):
        ang = a * 1.7
        dirn = Vector((math.sin(ang), math.cos(ang), 0.1 if zz > 0.3 else -0.05)).normalized()
        ok, loc, n, i = head.ray_cast(Vector((0, 0.04, zz)) + dirn * 3.0, -dirn)
        if ok:
            pts.append(loc + n * 0.015)
    if len(pts) > 5:
        K.loft("strap", K.path_fn(pts), lambda t: 0.05, 60, 8, mat=STRAP, profile=lambda th, t: (0.3, 1.0))

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("filter_fiend")
print("ok")

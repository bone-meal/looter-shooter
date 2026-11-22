# Nuclear Prophet mask (boss mask 11, diary/DECISIONS_SKINS.md A11 + diary/MASK_PROCESS.md section 5): a gas-mask
# hybrid (base 5). Silhouette plan: FRONT = twin filter canisters on the cheeks + a radiation-symbol plate raised on
# the forehead; SIDE = corrugated hoses looping from the canisters under the ears to a back canister; BACK = the
# canister pack on the back of the head + the strap harness. Behaviour: rubber sag (folds under the chin and down the
# neck bib, pulled in under a cinch), scorched labels on the canisters, green fog glowing in the lenses (fxR_); the trefoil turns and pulses
# green in the game (fxBG_ = glow group G + the moving part). The PROPHET: a ragged cloth cowl over the crown.
# Run: python3 tools/blender/mask_nuclear_prophet.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py nuclear_prophet
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(111)


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


RUBBER = K.rubber("face_rubber", (0.022, 0.022, 0.022))
HOOD = K.rubber("hood_rubber", (0.06, 0.068, 0.045))
CAN = painted("canister", (0.12, 0.14, 0.07))
HAZ = painted("hazard", (0.75, 0.55, 0.04), stripes=True)
LABEL = painted("label", (0.72, 0.62, 0.36), chip=(0.4, 0.33, 0.2), scorch=0.9)
PLATE = painted("fxB_rad_plate", (0.78, 0.6, 0.05), scorch=0.6)  # the plate turns with its trefoil (moving part)
STEEL = K.steel("steel", (0.2, 0.2, 0.19), heat=0.2, rust=0.3)
STRAP = K.rubber("strap", (0.34, 0.27, 0.15))
LENS = K.glow("fxR_lens_fog", (0.35, 1.0, 0.25), 6.0, base=(0.04, 0.1, 0.03))
TREFOIL = K.glow("fxBG_trefoil", (0.4, 1.0, 0.2), 7.0, base=(0.05, 0.12, 0.03))
DARK = K.simple("grille_dark", (0.008, 0.008, 0.008), 0.9)


def cloth(name, col=(0.11, 0.095, 0.07)):
    """Old sackcloth: a coarse weave in the relief, stains and ash darkening the folds."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 5.0; nz.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    L.new(nz.outputs["Fac"], mx.inputs[0]); mx.inputs[6].default_value = (col[0] * 1.3, col[1] * 1.3, col[2] * 1.25, 1)
    mx.inputs[7].default_value = (col[0] * 0.45, col[1] * 0.45, col[2] * 0.4, 1)
    c, ao = K._ao_mix(N, L, mx.outputs[2], (0.012, 0.01, 0.008), 0.08)
    L.new(c, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    wv = N.new("ShaderNodeTexWave"); wv.inputs["Scale"].default_value = 90.0; wv.wave_type = "BANDS"
    L.new(tc.outputs["Object"], wv.inputs["Vector"])
    wv2 = N.new("ShaderNodeTexWave"); wv2.inputs["Scale"].default_value = 90.0; wv2.bands_direction = "Y"
    L.new(tc.outputs["Object"], wv2.inputs["Vector"])
    h = N.new("ShaderNodeMath"); h.operation = "MULTIPLY"
    L.new(wv.outputs["Fac"], h.inputs[0]); L.new(wv2.outputs["Fac"], h.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = 0.003
    L.new(h.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


CLOTH = cloth("cowl_cloth")

LENS_C = [(s * 0.27, -0.8, 0.3) for s in (-1, 1)]


def hit(o, origin, direction):
    """(location, normal) where a ray meets object `o` alone (other parts in the way are ignored), or (None, None)."""
    ok, loc, n, i = o.ray_cast(Vector(origin), Vector(direction).normalized())
    return (loc, n) if ok else (None, None)


def hood(P):
    """The rubber hood: a squared skull with a bib down the neck, folds sagging round the neck and under the chin."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.05, 0.36), (0.72, 0.86, 0.8))
    d = smax(d, np.abs(x) - 0.66, 0.12)  # squarer sides
    d = smax(d, y - 0.86, 0.15)
    neck = sd_capsule(P, (0, 0.05, -0.1), (0, 0.1, -0.92), 0.5 + 0.03 * (-(z + 0.1)))
    th = np.arctan2(x, y)
    neck = neck + 0.035 * np.sin(th * 11.0) * np.clip(-(z + 0.15) * 1.5, 0, 1)  # bib folds
    neck = neck + 0.05 * np.exp(-((z + 0.5) / 0.05) ** 2) - 0.02 * np.exp(-((z + 0.5) / 0.12) ** 2)  # pulled in by the cinch, bulging either side
    d = smin(d, neck, 0.18)
    d = smax(d, -(z + 0.95), 0.03)
    sag = np.exp(-((z + 0.28) / 0.1) ** 2) * 0.013 * np.sin(z * 45.0)  # rings sagging round the neck
    return d + sag


def facepiece(P):
    """The black rubber face piece pressed over the hood: proud by 0.045 with a stepped rim, lenses cut in."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = hood(P) - 0.045
    fy = np.maximum(-(y - 0.15), 0.05)  # an oval cone round the face, seen from behind the head
    u = x / fy; v = (z - 0.18) / fy
    region = (np.sqrt((u / 0.78) ** 2 + (v / 0.95) ** 2) - 1.0) * 0.55
    seal = d
    d = smax(d, region, 0.03)
    d = smin(d, np.sqrt(region ** 2 + seal ** 2) - 0.03, 0.02)  # the rolled sealing lip round the edge
    muz = smax(sd_ellipsoid(P, (0, -0.83, -0.12), (0.25, 0.26, 0.24)), P @ np.array([0, -0.8, -0.6]) - 0.86, 0.03)
    d = smin(d, muz, 0.1)  # the muzzle, its front cut flat for the voicemitter
    for c in LENS_C:
        d = smax(d, -sd_ellipsoid(P, c, (0.15, 0.3, 0.14)), 0.015)  # lens holes
        d = smin(d, sd_ellipsoid(P, (c[0], c[1] + 0.04, c[2]), (0.2, 0.08, 0.19)) + 0.0, 0.05)  # the moulded lens rims
        d = smax(d, -sd_ellipsoid(P, c, (0.145, 0.4, 0.135)), 0.01)
    # rubber folds under the chin
    d = d + np.exp(-((z + 0.32) / 0.1) ** 2) * (y < -0.4) * 0.01 * np.sin(x * 40.0)
    return d


head = K.sdf_mesh("hood", hood, (-0.8, -1.0, -1.0), (0.8, 1.0, 1.2), 0.012, HOOD)
face = K.sdf_mesh("facepiece", facepiece, (-0.8, -1.25, -0.65), (0.8, 0.1, 0.9), 0.01, RUBBER)


def cowl_front(z):
    return -0.44 - 0.12 * np.clip((z - 0.85) / 0.3, 0, 1) + 0.3 * np.clip((0.75 - z) / 0.6, 0, 1)


def cowl(P):
    """The prophet's ragged cowl: a cloth shell over the crown rising to a slumped point behind, falling in folds to a
    torn hem (high at the back over the pack, low at the sides), opening round the face behind the forehead plate."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)  # 0 = straight back
    tip = np.exp(-(((y - 0.35) / 0.35) ** 2 + ((z - 1.1) / 0.3) ** 2 + (x / 0.3) ** 2))
    off = 0.07 + 0.16 * tip + 0.025 * np.sin(th * 9.0) * np.clip(0.9 - z, 0, 1)  # the slumped point + drapery folds
    shell = np.abs(hood(P) - off) - 0.022
    hem = 0.48 - 0.36 * np.clip(np.abs(th) / 2.0, 0, 1) + 0.05 * np.sin(th * 7.0) + 0.035 * np.sin(th * 19.0 + 1.0)
    d = smax(shell, hem - z, 0.02)
    rag = 0.025 * np.sin(z * 31.0) + 0.015 * np.sin(z * 67.0)
    return smax(d, cowl_front(z) + rag - y, 0.02)


hood_cowl = K.sdf_mesh("cowl", cowl, (-0.95, -0.75, -0.2), (0.95, 1.1, 1.45), 0.011, CLOTH)
edge = []  # a rolled hem along the cowl's face opening (found by rays from the side)
for zz in np.linspace(1.2, 0.15, 16):
    loc, n = K.ray_onto(hood_cowl, Vector((1.6, float(cowl_front(zz)) + 0.035, zz)), Vector((-1, 0, 0)))
    if loc:
        edge.append(loc)
if len(edge) > 3:
    top = Vector((0, edge[0].y - 0.03, edge[0].z + 0.08))
    for sgn in (-1, 1):
        pts = [top] + [Vector((sgn * abs(p.x), p.y, p.z)) for p in edge]
        K.tube("cowl_hem", K.smooth_path(pts, 40), 0.03, CLOTH, res=3)
else:
    print("COWL: hem rays missed", len(edge))

# ------------------------------------------------------------------ lenses: glass full of green fog in steel rings
for c in LENS_C:
    loc, n = K.ray_onto(face, Vector((c[0], -2.0, c[2])), Vector((0, 1, 0)))
    ctr = Vector((c[0], -0.84, c[2]))
    g = K.ball("lens", 0.15, ctr, LENS, (1.0, 0.25, 0.94), 24)
    K.tube("lens_ring", [ctr + Vector((0.155 * math.cos(a), -0.03, 0.145 * math.sin(a))) for a in np.linspace(0, 2 * math.pi, 33)], 0.022, STEEL, res=3)
    for a in np.linspace(0, 2 * math.pi, 7)[:-1]:
        K.bolt(ctr + Vector((0.155 * math.cos(a), -0.05, 0.145 * math.sin(a))), Vector((0, -1, 0)), 0.012, STEEL)

# ------------------------------------------------------------------ the voicemitter at the mouth
vloc, vn = K.ray_onto(face, Vector((0, -2.0, -0.15)), Vector((0, 1, 0)))
if vloc:
    out = Vector((0, -1, -0.25)).normalized()
    K.loft("voicemitter", lambda t, a=vloc: a + out * (-0.02 + 0.12 * t), lambda t: 0.12 - 0.01 * t, 8, 28, mat=STEEL)
    K.loft("vm_grille", lambda t, a=vloc: a + out * (0.1 + 0.01 * t), lambda t: 0.095, 2, 28, mat=DARK)
    for k in range(5):
        zz = -0.06 + 0.03 * k
        K.box("vm_slat", (0.17 - 0.04 * abs(k - 2), 0.012, 0.01), tuple(vloc + out * 0.115 + Vector((0, 0, zz))), (math.radians(-14), 0, 0), STEEL, 0.003, 1)


# ------------------------------------------------------------------ twin filter canisters on the cheeks
def canister(base, axis, length, r, label=True):
    """A ribbed filter canister: threaded neck, ribbed body, a hazard band, a scorched label, a perforated end cap."""
    axis = axis.normalized()
    K.loft("can_neck", lambda t: base + axis * (0.07 * t), lambda t: r * 0.6 + 0.012 * math.sin(t * 40), 12, 24, mat=STEEL)
    b0 = base + axis * 0.06

    def rr(t):
        rib = 0.012 * (1 if (t * 9) % 1 < 0.18 else 0) if t > 0.72 else 0.0
        return r * (0.92 + 0.08 * min(t / 0.06, 1)) + rib
    K.loft("can_body", lambda t: b0 + axis * (length * t), rr, 60, 32, mat=CAN)
    K.loft("can_band", lambda t: b0 + axis * (length * (0.08 + 0.12 * t)), lambda t: r + 0.006, 3, 32, mat=HAZ, cap=False)
    if label:
        K.loft("can_label", lambda t: b0 + axis * (length * (0.28 + 0.36 * t)), lambda t: r + 0.004, 3, 32, mat=LABEL, cap=False)
    end = b0 + axis * length
    K.loft("can_cap", lambda t: end + axis * (0.025 * t), lambda t: r * (0.98 - 0.15 * t), 4, 32, mat=STEEL)
    for k in range(7):  # perforations
        a = k * 2 * math.pi / 7
        u = axis.cross(Vector((0, 0, 1))).normalized(); v = axis.cross(u)
        K.ball("can_hole", 0.018, end + axis * 0.026 + (u * math.cos(a) + v * math.sin(a)) * r * 0.5, DARK, (1, 1, 1), 8)
    K.ball("can_hole", 0.022, end + axis * 0.027, DARK, (1, 1, 1), 8)
    return end


CAN_ENDS = []
for s in (-1, 1):
    loc, n = hit(face, Vector((s * 0.4, -2.0, -0.08)), Vector((0, 1.0, 0.0)))
    if not loc:
        print("CANISTER: no face", s); continue
    axis = Vector((s * 0.55, -0.75, -0.3))
    CAN_ENDS.append((s, loc, canister(loc - axis.normalized() * 0.03, axis, 0.38, 0.19)))

# ------------------------------------------------------------------ the back canister pack + mount
BACK_BASE = Vector((0.0, 0.84, -0.08))
PACK_AXIS = Vector((0, 0.16, 1)).normalized()
K.box("pack_mount", (0.3, 0.05, 0.5), (0, 0.79, 0.16), (math.radians(-9), 0, 0), STEEL, 0.02, 2)
PACK_TOPS = []
for px in (-0.15, 0.15):  # a pack of two canisters side by side
    base = BACK_BASE + Vector((px, 0.03, 0))
    top = canister(base, PACK_AXIS, 0.52, 0.16)
    PACK_TOPS.append(top)
    for f in (0.3, 0.72):  # steel clamp rings holding it to the mount
        c = base + PACK_AXIS * (0.06 + 0.52 * f)
        K.loft("pack_clamp", lambda t, c=c: c + PACK_AXIS * (0.03 * t), lambda t: 0.178, 3, 32, mat=STEEL)
    K.loft("pack_valve", lambda t, tp=top: tp + PACK_AXIS * (0.025 + 0.04 * t), lambda t: 0.06 - 0.02 * t, 6, 16, mat=STEEL)

# ------------------------------------------------------------------ hoses looping from the canisters to the pack
for s, loc, end in CAN_ENDS:
    start = loc + Vector((s * 0.14, 0.06, -0.02))
    ctrl = [start, Vector((s * 0.8, -0.32, -0.08)), Vector((s * 0.9, 0.12, -0.04)), Vector((s * 0.7, 0.58, -0.02)),
            Vector((s * 0.36, 0.92, 0.02)), BACK_BASE + Vector((s * 0.15, 0.2, 0.08))]
    pts = K.smooth_path(ctrl, 80)
    f = K.path_fn(pts)
    K.loft("hose", f, lambda t: 0.055 * (1.0 + 0.12 * math.sin(t * 2 * math.pi * 30)), 360, 14, mat=RUBBER)
    for t in (0.0, 1.0):
        K.loft("hose_collar", lambda u, t=t: f(abs(t - 0.04 * u)), lambda u: 0.066, 4, 16, mat=STEEL)


# ------------------------------------------------------------------ strap harness over the hood
def strap(a_pt, b_pt, w=0.07, lift=0.024, n=26):
    """A flat strap along the hood's surface from a to b (points projected by rays toward the head's middle)."""
    mid = Vector((0, 0.05, 0.3))
    pts = []
    for i in range(n):
        p = a_pt.lerp(b_pt, i / (n - 1))
        dirn = (p - mid).normalized()
        loc, nn = K.ray_onto(hood_cowl, mid + dirn * 3.0, -dirn)
        if not loc:
            loc, nn = K.ray_onto(head, mid + dirn * 3.0, -dirn)
        if loc:
            pts.append(loc + nn * lift)
    if len(pts) > 2:
        K.loft("strap", K.path_fn(pts), lambda t: w, len(pts) * 2, 8, mat=STRAP, profile=lambda th, t: (1.0, 0.18))
    return pts


for s in (-1, 1):
    pts = strap(Vector((s * 0.55, -0.3, 0.6)), Vector((s * 0.16, 0.8, 0.52)))
    if pts:
        K.box("buckle", (0.03, 0.075, 0.06), tuple(pts[3]), (0, 0, 0), STEEL, 0.006, 1)
    pts = strap(Vector((s * 0.62, -0.32, 0.05)), Vector((s * 0.16, 0.8, 0.12)))
    if pts:
        K.box("buckle", (0.03, 0.075, 0.06), tuple(pts[3]), (0, 0, 0), STEEL, 0.006, 1)

K.loft("cinch", lambda t: Vector((0, 0.075, -0.5)) + Vector((0.53 * math.sin(2 * math.pi * t), 0.53 * math.cos(2 * math.pi * t), 0)),
       lambda t: 0.035, 64, 8, mat=STRAP, profile=lambda th, t: (0.35, 1.0), cap=False)
K.box("cinch_buckle", (0.1, 0.03, 0.08), (0.0, -0.47, -0.5), (0, 0, 0), STEEL, 0.008, 1)

# ------------------------------------------------------------------ the radiation plate raised on the forehead
ploc, pn = hit(head, Vector((0, -2.0, 1.3)), Vector((0, 1.0, -0.42)))
PC = ploc + pn * 0.005
PN = pn.normalized()
K.loft("rad_boss", lambda t: PC + PN * (-0.03 + 0.07 * t), lambda t: 0.2 + 0.02 * (1 - t), 6, 40, mat=STEEL)
K.loft("rad_plate", lambda t: PC + PN * (0.04 + 0.012 * t), lambda t: 0.19, 3, 40, mat=PLATE)
for a in np.linspace(0, 2 * math.pi, 9)[:-1]:
    u = PN.cross(Vector((1, 0, 0))).normalized(); v = Vector((1, 0, 0))
    K.bolt(PC + PN * 0.07 + (u * math.cos(a) + v * math.sin(a)) * 0.205, PN, 0.012, STEEL)
TC = np.array(PC + PN * 0.052); TN = np.array(PN); TU = np.cross(TN, [1.0, 0.0, 0.0]); TU /= np.linalg.norm(TU)
print("TREFOIL_CENTRE", tuple(round(v, 4) for v in TC), "AXIS", tuple(round(v, 4) for v in TN))


def trefoil(P):
    q = P - TC
    along = q @ TN
    a = q[..., 0]; b = q @ TU
    r = np.sqrt(a ** 2 + b ** 2)
    th = np.arctan2(b, a) + math.pi / 2
    sec = np.mod(th, 2 * math.pi / 3) - math.pi / 3  # each blade spans 60 deg, gaps between
    blade = np.maximum(np.maximum(r - 0.16, 0.055 - r), (np.abs(sec) - math.pi / 6) * r)
    d = np.minimum(blade, r - 0.035)
    return np.maximum(d, np.abs(along) - 0.017)  # 0.034 thick: the baker keeps parts at least 0.025 thick


K.sdf_mesh("trefoil", trefoil, tuple(TC - 0.2), tuple(TC + 0.2), 0.005, TREFOIL)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("nuclear_prophet")
print("ok")

# Trench Rat mask (elite / mob mask 15, diary/DECISIONS_SKINS.md B15, plan in diary/MASK_PLANS_DROPS.md): a battered
# steel helmet (base 3) with a bolted face plate painted with a crude rat's grin, dented by gunfire, caked in mud.
# FRONT = eye slits, breathing holes, the painted grin, bullet dents (one round lodged), mud on the jaw; SIDE = the
# flared steel brim, hinge bolts, hessian scrim strips; BACK = the scrim's knot and strips, a leather neck flap.
# Run: python3 tools/blender/mask_trench_rat.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py trench_rat
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, sd_box, smin, smax, groove  # noqa: E402
from mathutils import Vector  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(151)
random.seed(15)


def army_paint(name, col=(0.11, 0.12, 0.07), rat=False):
    """Olive paint chipped to rust and steel; mud caked low and splashed higher; optionally the white rat grin."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
    base = K._const(N, col)
    if rat:  # the grin: white paint in a band of buck teeth + whisker strokes, drawn from object coordinates
        img = N.new("ShaderNodeTexImage"); img.image = RAT_IMG; img.extension = "CLIP"
        mp = N.new("ShaderNodeMapping"); mp.inputs["Location"].default_value = (0.5, 0.0, 0.0)
        mp.inputs["Scale"].default_value = (0.9, 0.0, 0.9)
        # project onto x / z: u = x * 0.9 + 0.5, v = z * 0.9 + 0.5 - 0.0
        comb = N.new("ShaderNodeCombineXYZ")
        mx_ = N.new("ShaderNodeMath"); mx_.operation = "MULTIPLY_ADD"; mx_.inputs[1].default_value = 0.85; mx_.inputs[2].default_value = 0.5
        mz_ = N.new("ShaderNodeMath"); mz_.operation = "MULTIPLY_ADD"; mz_.inputs[1].default_value = 0.85; mz_.inputs[2].default_value = 0.73
        L.new(sep.outputs[0], mx_.inputs[0]); L.new(sep.outputs[2], mz_.inputs[0])
        L.new(mx_.outputs[0], comb.inputs[0]); L.new(mz_.outputs[0], comb.inputs[1])
        L.new(comb.outputs[0], img.inputs[0])
        front = N.new("ShaderNodeMath"); front.operation = "LESS_THAN"; front.inputs[1].default_value = -0.6
        L.new(sep.outputs[1], front.inputs[0])
        msk = N.new("ShaderNodeMath"); msk.operation = "MULTIPLY"
        L.new(img.outputs["Color"], msk.inputs[0]); L.new(front.outputs[0], msk.inputs[1])
        mw = N.new("ShaderNodeMix"); mw.data_type = "RGBA"
        L.new(msk.outputs[0], mw.inputs[0]); L.new(base, mw.inputs[6]); mw.inputs[7].default_value = (0.82, 0.8, 0.7, 1)
        base = mw.outputs[2]
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 12.0; nz.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ch = N.new("ShaderNodeMapRange"); ch.inputs["From Min"].default_value = 0.67; ch.inputs["From Max"].default_value = 0.7
    L.new(nz.outputs["Fac"], ch.inputs["Value"])
    mc = N.new("ShaderNodeMix"); mc.data_type = "RGBA"
    L.new(ch.outputs["Result"], mc.inputs[0]); L.new(base, mc.inputs[6]); mc.inputs[7].default_value = (0.13, 0.075, 0.04, 1)
    # mud: thick below z 0, splashes fading out higher
    mn = N.new("ShaderNodeTexNoise"); mn.inputs["Scale"].default_value = 5.0; mn.inputs["Detail"].default_value = 8
    L.new(tc.outputs["Object"], mn.inputs["Vector"])
    hz = N.new("ShaderNodeMath"); hz.operation = "MULTIPLY_ADD"; hz.inputs[1].default_value = -0.9; hz.inputs[2].default_value = 0.0
    L.new(sep.outputs[2], hz.inputs[0])
    mm = N.new("ShaderNodeMath"); mm.operation = "ADD"
    L.new(hz.outputs[0], mm.inputs[0]); L.new(mn.outputs["Fac"], mm.inputs[1])
    mud = N.new("ShaderNodeMapRange"); mud.inputs["From Min"].default_value = 0.95; mud.inputs["From Max"].default_value = 1.05
    L.new(mm.outputs[0], mud.inputs["Value"])
    md = N.new("ShaderNodeMix"); md.data_type = "RGBA"
    L.new(mud.outputs["Result"], md.inputs[0]); L.new(mc.outputs[2], md.inputs[6]); md.inputs[7].default_value = (0.09, 0.065, 0.04, 1)
    c, ao = K._ao_mix(N, L, md.outputs[2], (0.03, 0.022, 0.012), 0.06)
    L.new(c, b.inputs["Base Color"])
    L.new(ch.outputs["Result"], b.inputs["Metallic"])
    b.inputs["Roughness"].default_value = 0.72
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.4; bump.inputs["Distance"].default_value = 0.004
    hh = N.new("ShaderNodeMath"); hh.operation = "MULTIPLY"
    L.new(mud.outputs["Result"], hh.inputs[0]); L.new(mn.outputs["Fac"], hh.inputs[1])
    L.new(hh.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def make_rat_image():
    """The crude grin, hand-painted look: two buck teeth under a curled lip line, whisker strokes, a nose blob."""
    from PIL import Image, ImageDraw, ImageFilter
    W = 512
    im = Image.new("L", (W, W), 0)
    dr = ImageDraw.Draw(im)
    cx = W // 2
    # lip line: a wide wavy grin
    pts = [(cx + int(190 * t), int(200 - 55 * (1 - t * t))) for t in np.linspace(-1, 1, 30)]
    dr.line(pts, fill=255, width=20)
    # two big buck teeth hanging from the middle of the lip, filled, a dark gap between
    for s in (-1, 1):
        x0 = cx + (6 if s > 0 else -62)
        dr.rounded_rectangle([x0, 150, x0 + 56, 262], radius=10, fill=255)
    # whisker strokes from the cheeks
    for s in (-1, 1):
        for k, ang in enumerate((-0.25, 0.0, 0.25)):
            x0 = cx + s * 120; y0 = 175 + k * 12
            x1 = x0 + s * int(150 * math.cos(ang)); y1 = y0 - int(150 * math.sin(ang)) + 10
            dr.line([(x0, y0), ((x0 + x1) // 2, (y0 + y1) // 2 - 6), (x1, y1)], fill=255, width=11)
    dr.ellipse([cx - 34, 92, cx + 34, 136], fill=255)  # the nose
    im = im.filter(ImageFilter.GaussianBlur(1.6))
    # wear: knock holes out of the paint
    arr = np.array(im).astype(float) / 255.0
    rng = np.random.default_rng(3)
    noise = rng.random((W // 8, W // 8))
    noise = np.array(Image.fromarray((noise * 255).astype(np.uint8)).resize((W, W), Image.BILINEAR)).astype(float) / 255.0
    arr *= (noise > 0.18)
    img = K.bpy.data.images.new("rat_grin", W, W, alpha=False)
    flat = np.repeat(arr[::-1, :, None], 4, axis=2); flat[..., 3] = 1.0
    img.pixels = flat.ravel().tolist()
    return img


RAT_IMG = make_rat_image()
HELM_M = army_paint("helm_paint")
PLATE_M = army_paint("plate_paint", (0.1, 0.11, 0.065), rat=True)
STEEL = K.steel("steel", (0.25, 0.24, 0.22), heat=0.0, rust=0.6)
BRASS = K.steel("copper_round", (0.55, 0.32, 0.15), heat=0.1, rust=0.0, rough=0.35)
HESSIAN = K.simple("hessian", (0.24, 0.18, 0.1), 0.95)
LEATHER = K.simple("neck_leather", (0.09, 0.055, 0.03), 0.7)
DARK = K.simple("slit_dark", (0.01, 0.01, 0.008), 0.9)

DENTS = [((0.32, -0.86, 0.66), 0.075), ((-0.5, -0.5, 0.82), 0.06), ((0.62, 0.15, 0.62), 0.07), ((-0.2, -0.95, 0.05), 0.06),
         ((0.26, -0.93, -0.2), 0.055), ((-0.62, 0.35, 0.4), 0.065)]
LODGED = 0


def dent(d, P, c, r):
    """A bullet dent: pushed in at the middle, a raised stretched rim."""
    q = np.linalg.norm(P - np.array(c), axis=-1)
    return d + 0.035 * np.exp(-(q / r) ** 2) - 0.012 * np.exp(-((q - r * 1.15) / (r * 0.35)) ** 2)


def helmet(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    dome = sd_box(P, (0, 0.04, 0.3), (0.7, 0.82, 0.72), 0.45)  # a squared deep dome
    dome = smax(dome, sd_ellipsoid(P, (0, 0.04, 0.25), (0.86, 0.98, 1.0)), 0.1)
    rim = 0.2 - 0.27 * y  # the rim line: at the brow in front, down to the nape behind
    d = smax(dome, -(z - rim), 0.03)
    # the flared brim: a lip turned out along the rim, wider at the sides and back
    reach = 0.06 + 0.07 * np.clip((y + 0.4) / 1.0, 0, 1)
    lip = np.maximum(np.abs(z - rim + 0.02) - 0.022, dome - reach)
    lip = np.maximum(lip, -(dome + 0.03))
    d = smin(d, lip, 0.03)
    d = groove(d, z - (rim + 0.32), 0.01, 0.014, 0.004)  # a pressed rib round the dome
    for c, r in DENTS:
        if c[2] > 0.2:
            d = dent(d, P, c, r)
    return d


def faceplate(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    fo = sd_ellipsoid(P, (0, -0.12, 0.0), (0.68, 0.9, 0.78))
    fo = smax(fo, -P[..., 1] - 0.93, 0.08)  # a flat front
    fo = smin(fo, sd_ellipsoid(P, (0, -0.93, -0.16), (0.27, 0.22, 0.2)), 0.12)  # the plate pressed out into a rat's short snout
    for s in (-1, 1):
        fo = smax(fo, P @ np.array([s * 0.55, -0.6, -0.58]) - 0.78, 0.06)  # a V jaw: two planes meeting at the chin
    d = np.maximum(fo, -(fo + 0.05))  # a plate 0.05 thick
    d = np.maximum(d, y + 0.3)
    d = np.maximum(d, z - 0.5)  # up under the brim
    d = np.maximum(d, -(z + 0.64))
    d = smin(d, np.maximum(np.maximum(sd_capsule(P, (-0.34, -0.9, 0.25), (0.34, -0.9, 0.25), 0.045), fo - 0.04), -(fo + 0.03)), 0.02)  # a riveted brow strip on the plate, not past it
    d = smax(d, -sd_box(P, (0.22, -0.9, 0.1), (0.14, 0.3, 0.022), 0.01), 0.008)  # eye slits
    d = smax(d, -sd_box(P, (-0.22, -0.9, 0.1), (0.14, 0.3, 0.022), 0.01), 0.008)
    for xx in (-0.16, 0.16):  # nostril holes either side of the snout
        for zz in (-0.06,):
            d = smax(d, -(np.sqrt((x - xx) ** 2 + (z - zz) ** 2) - 0.018 + 0 * y), 0.004)
    for c, r in DENTS:
        if c[2] <= 0.2:
            d = dent(d, P, c, r)
    return d


def mud(P):
    """Mud caked on the jaw: a lumpy crust over the plate's lower part with a ragged top edge and drips."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    fo = sd_ellipsoid(P, (0, -0.12, 0.0), (0.68, 0.9, 0.78))
    lump = 0.018 * np.sin(x * 23.0 + z * 11.0) * np.sin(z * 17.0 - x * 9.0)
    d = np.maximum(fo - 0.028 - lump, -(fo + 0.01))
    edge = -0.42 + 0.07 * np.sin(x * 9.0) + 0.04 * np.sin(x * 23.0 + 1.0)
    patch = np.sin(x * 7.0 + z * 5.0) * np.sin(z * 9.0 - x * 4.0) + 0.35 * np.sin(x * 19.0)
    for k, xx in enumerate((-0.32, -0.1, 0.14, 0.36)):  # drips running down from the edge
        edge = edge + (0.0 if True else 0.0)
    d = np.maximum(d, z - edge)
    d = np.maximum(d, (-0.15 - patch) * 0.05)  # in patches, not a band
    d = np.maximum(d, y + 0.3)
    d = np.maximum(d, -(z + 0.7))
    for k, xx in enumerate((-0.3, -0.08, 0.17, 0.38)):
        drip = sd_capsule(P, (xx, -0.8, -0.44), (xx, -0.78, -0.44 - 0.12 - 0.05 * (k % 2)), 0.022)
        d = smin(d, np.maximum(drip, -(fo + 0.0)), 0.02)
    return d


def flap(P):
    """A leather neck flap hanging behind under the brim."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    th = np.arctan2(x, y)
    sh = np.abs(sd_capsule(P, (0, 0.05, 0.1), (0, 0.08, -0.8), 0.56 + 0.06 * np.clip(-z, 0, 1) + 0.04 * np.sin(th * 6))) - 0.025
    sh = smax(sh, -(y + 0.32), 0.05)  # behind and wrapping round the sides to the jaw
    return smax(sh, -(z + 0.72 + 0.05 * np.sin(th * 9)), 0.03)  # a wavy hem, flared


helm_o = K.sdf_mesh("helmet", helmet, (-1.1, -1.2, 0.0), (1.1, 1.2, 1.15), 0.011, HELM_M)
plate_o = K.sdf_mesh("faceplate", faceplate, (-0.75, -1.15, -0.75), (0.75, -0.1, 0.6), 0.009, PLATE_M)
MUD = K.simple("caked_mud", (0.075, 0.055, 0.035), 0.95)
K.sdf_mesh("mud", mud, (-0.75, -1.15, -0.8), (0.75, -0.1, -0.1), 0.009, MUD)
K.sdf_mesh("neck_flap", flap, (-0.8, -0.2, -0.95), (0.8, 0.85, 0.3), 0.013, LEATHER)
K.ball("inside_dark", 0.55, (0, -0.25, 0.1), DARK, (1.0, 0.8, 0.9), 20)

# the lodged round in the brow dent
c, r = DENTS[LODGED]
ok, loc, n, i = helm_o.ray_cast(Vector((c[0], -2.0, c[2])), Vector((0, 1, 0)))
if ok:
    K.loft("round", lambda t, a=loc: a + n * (-0.01 + 0.05 * t), lambda t: 0.022 * (1 - 0.6 * max(t - 0.5, 0) * 2) + 0.004, 8, 12, mat=BRASS)

# hinge bolts where the face plate hangs from the helmet
for s in (-1, 1):
    ok, loc, n, i = plate_o.ray_cast(Vector((s * 2.0, -0.45, 0.12)), Vector((-s, 0, 0)))
    if ok:
        K.bolt(loc, n, 0.045, STEEL)
        K.loft("hinge", lambda t, a=loc, s=s: a + Vector((0, 0, 0.12 * t)), lambda t: 0.03, 4, 10, mat=STEEL)

# the scrim band round the dome and hessian strips hanging from it
band = []
for a in np.linspace(0, 2 * math.pi, 49):
    ok, loc, n, i = helm_o.ray_cast(Vector((2.0 * math.sin(a), 2.0 * math.cos(a), 0.5)), Vector((-math.sin(a), -math.cos(a), 0)))
    if ok:
        band.append(loc + n * 0.01)
if len(band) > 10:
    K.tube("scrim_band", band, 0.03, HESSIAN, res=3)
def ribbon(name, centre, width, side, n=14, thick=0.03):
    """A closed flat strip along centre(t): `width` across `side`(t), `thick` through it (kept by the baker)."""
    verts, faces = [], []
    for i in range(n):
        t = i / (n - 1)
        c = centre(t); w = side(t)
        nrm = (centre(min(t + 0.02, 1)) - centre(max(t - 0.02, 0))).cross(w).normalized()
        ww = width * (1 - 0.35 * t)
        for sw, sn in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(c + w * (sw * ww * 0.5) + nrm * (sn * thick * 0.5))
    for i in range(n - 1):
        for j in range(4):
            a0 = i * 4 + j; a1 = i * 4 + (j + 1) % 4
            faces.append((a0, a1, a1 + 4, a0 + 4))
    faces.append((3, 2, 1, 0)); last = (n - 1) * 4; faces.append((last, last + 1, last + 2, last + 3))
    return K.mesh_obj(name, verts, faces, HESSIAN, smooth_it=False)  # flat shaded: reads as flat cloth, not a cord


for k in range(17):
    a = math.pi * (-0.72 + 1.44 * k / 16)  # round the sides and back (a = 0 straight back; none over the face)
    ok, loc, n, i = helm_o.ray_cast(Vector((2.0 * math.sin(a), 2.0 * math.cos(a), 0.5)), Vector((-math.sin(a), -math.cos(a), 0)))
    if not ok:
        continue
    out = Vector((math.sin(a), math.cos(a), 0.0))
    tang = out.cross(Vector((0, 0, 1))).normalized()
    ln = 0.42 + 0.3 * random.random()
    top = loc + n * 0.03
    clear = 0.1 + 0.05 * math.cos(a)

    def centre(t, top=top, out=out, tang=tang, ln=ln, clear=clear, k=k):
        bulge = clear * math.sin(min(t * 3.0, 1.0) * math.pi / 2)  # over the brim, then hanging
        return top + out * (bulge + 0.015 * math.sin(t * 3 + k)) + Vector((0, 0, -ln * t)) + tang * 0.012 * math.sin(t * 3 + k * 1.7)

    ribbon("scrim_strip", centre, 0.095, lambda t, tang=tang: tang)  # flat to the helmet, hanging straight
# the knot at the back
ok, loc, n, i = helm_o.ray_cast(Vector((0, 2.0, 0.5)), Vector((0, -1, 0)))
if ok:
    K.ball("scrim_knot", 0.07, tuple(loc + n * 0.04), HESSIAN, (1.2, 0.8, 0.9), 12)

if K.GAME:
    raise SystemExit(0)

K.stage(head=False)
K.shoot_views("trench_rat")
print("ok")

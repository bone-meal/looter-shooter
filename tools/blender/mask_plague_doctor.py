# Plague Doctor mask v4 (the approved bar): scripted sculpt (Blender bpy 5.x, Cycles CPU).
# Reconstructed 2026-11-21 from the planning session's v1 script + its v2 / v3 / v4 patches (chat "TCG card game design").
# Helmet: superellipse cranium, V jaw, welted seams, rolled collar, tie cord biting in at the back with the leather
# scrunched to a knot + gathered ruffle, laced closure, brow plate, cheek guards with studs, leather eye cups with
# glass + glow (Morse), hooked lofted beak with bands / ties / stitching / breathing holes, drawstring herb pouch,
# 17th c. hat, toxic mist + flies. Output dir = argv[1]; views "three" / "front" / "both" / "back" / "side" / "all".
# Env RES / SPP set the render size / samples. Env MASK_GAME=1 builds only the mask (no stand, mist, flies, lights,
# camera, renders) for tools/blender/mask_bake.py, which turns it into the game model + baked textures.
import sys, os, math, random
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix

GAME = os.environ.get("MASK_GAME") == "1"
GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}  # sculpt units -> metres in the head anchor's space (mask_bake.py)
OUT = sys.argv[1]
VIEWS = sys.argv[2] if len(sys.argv) > 2 else "both"
RES = int(os.environ.get("RES", 1100))
os.makedirs(OUT, exist_ok=True)
random.seed(4)

bpy.ops.wm.read_factory_settings(use_empty=True)
SC = bpy.context.scene
SC.render.engine = "CYCLES"
SC.cycles.device = "CPU"
SC.cycles.samples = int(os.environ.get("SPP", 56))
SC.cycles.use_denoising = True
SC.render.resolution_x = SC.render.resolution_y = RES
SC.view_settings.view_transform = "AgX"
SC.view_settings.look = "AgX - Medium High Contrast"
SC.view_settings.exposure = -0.5


# ------------------------------------------------------------------ helpers
def link(o):
    SC.collection.objects.link(o)
    return o


def mesh_obj(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    return link(bpy.data.objects.new(name, me))


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def mod_subsurf(o, lv=2, rlv=3):
    m = o.modifiers.new("sub", "SUBSURF")
    m.levels, m.render_levels = lv, rlv
    return m


def mod_displace(o, tex_type, size, strength, mid=0.5, detail=None):
    t = bpy.data.textures.new(o.name + tex_type, tex_type)
    if hasattr(t, "noise_scale"):
        t.noise_scale = size
    if detail is not None and hasattr(t, "noise_depth"):
        t.noise_depth = detail
    m = o.modifiers.new("disp" + tex_type, "DISPLACE")
    m.texture = t
    m.texture_coords = "LOCAL"
    m.strength = strength
    m.mid_level = mid
    return m


def look(o, target):
    o.rotation_euler = (Vector(target) - o.location).to_track_quat("-Z", "Y").to_euler()


def light(name, loc, power, size, col, target=(0, -0.6, 0.1)):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy, ld.size, ld.color = power, size, col
    o = link(bpy.data.objects.new(name, ld))
    o.location = loc
    look(o, target)


def nodes(mat):
    mat.use_nodes = True
    return mat.node_tree.nodes, mat.node_tree.links


# ------------------------------------------------------------------ materials
def leather_mat(name, base=(0.045, 0.032, 0.026), wear=(0.16, 0.11, 0.075), scale=1.0):
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    # pores
    vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 140 * scale
    L.new(tc.outputs["Object"], vo.inputs["Vector"])
    # crease network
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 9 * scale
    nz.inputs["Detail"].default_value = 12; nz.inputs["Roughness"].default_value = 0.65
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    vc = N.new("ShaderNodeTexVoronoi"); vc.feature = "DISTANCE_TO_EDGE"
    vc.inputs["Scale"].default_value = 11 * scale
    L.new(nz.outputs["Color"], vc.inputs["Vector"])
    crease = N.new("ShaderNodeMapRange")
    crease.inputs["From Max"].default_value = 0.05
    crease.inputs["To Min"].default_value = 0.0; crease.inputs["To Max"].default_value = 1.0
    L.new(vc.outputs["Distance"], crease.inputs["Value"])
    # height = pores + creases
    h = N.new("ShaderNodeMath"); h.operation = "ADD"
    L.new(vo.outputs["Distance"], h.inputs[0])
    hc = N.new("ShaderNodeMath"); hc.operation = "MULTIPLY"; hc.inputs[1].default_value = 1.6
    L.new(crease.outputs["Result"], hc.inputs[0]); L.new(hc.outputs[0], h.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.004
    L.new(h.outputs[0], bump.inputs["Height"])
    # colour: base, worn edges (pointiness), dirt in cavities (AO)
    geo = N.new("ShaderNodeNewGeometry")
    pt = N.new("ShaderNodeMapRange")
    pt.inputs["From Min"].default_value = 0.57; pt.inputs["From Max"].default_value = 0.66
    L.new(geo.outputs["Pointiness"], pt.inputs["Value"])
    nz2 = N.new("ShaderNodeTexNoise"); nz2.inputs["Scale"].default_value = 3
    nz2.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz2.inputs["Vector"])
    var = N.new("ShaderNodeMix"); var.data_type = "RGBA"
    var.inputs[6].default_value = (*base, 1)
    var.inputs[7].default_value = (base[0] * 1.9, base[1] * 1.6, base[2] * 1.4, 1)
    L.new(nz2.outputs["Fac"], var.inputs[0])
    w = N.new("ShaderNodeMix"); w.data_type = "RGBA"
    L.new(pt.outputs["Result"], w.inputs[0]); L.new(var.outputs[2], w.inputs[6])
    w.inputs[7].default_value = (*wear, 1)
    crease_dark = N.new("ShaderNodeMix"); crease_dark.data_type = "RGBA"; crease_dark.blend_type = "MULTIPLY"
    inv = N.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    L.new(crease.outputs["Result"], inv.inputs[1])
    cf = N.new("ShaderNodeMath"); cf.operation = "MULTIPLY"; cf.inputs[1].default_value = 0.7
    L.new(inv.outputs[0], cf.inputs[0]); L.new(cf.outputs[0], crease_dark.inputs[0])
    L.new(w.outputs[2], crease_dark.inputs[6]); crease_dark.inputs[7].default_value = (0.25, 0.2, 0.17, 1)
    ao = N.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.08
    aom = N.new("ShaderNodeMix"); aom.data_type = "RGBA"; aom.blend_type = "MULTIPLY"
    aoi = N.new("ShaderNodeMath"); aoi.operation = "SUBTRACT"; aoi.inputs[0].default_value = 1.0
    L.new(ao.outputs["AO"], aoi.inputs[1]); L.new(aoi.outputs[0], aom.inputs[0])
    L.new(crease_dark.outputs[2], aom.inputs[6]); aom.inputs[7].default_value = (0.15, 0.12, 0.1, 1)
    L.new(aom.outputs[2], b.inputs["Base Color"])
    # roughness: worn = shinier
    rr = N.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.62; rr.inputs["To Max"].default_value = 0.35
    L.new(pt.outputs["Result"], rr.inputs["Value"])
    L.new(rr.outputs["Result"], b.inputs["Roughness"])
    b.inputs["Coat Weight"].default_value = 0.12
    b.inputs["Coat Roughness"].default_value = 0.3
    b.inputs["Specular IOR Level"].default_value = 0.35
    L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def brass_mat():
    m = bpy.data.materials.new("brass")
    N, L = nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Metallic"].default_value = 1.0
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 18; nz.inputs["Detail"].default_value = 10
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ao = N.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.05
    cr = N.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].color = (0.12, 0.13, 0.07, 1)  # tarnish in cavities
    cr.color_ramp.elements[1].color = (0.8, 0.56, 0.24, 1)
    mix = N.new("ShaderNodeMath"); mix.operation = "MULTIPLY"
    L.new(ao.outputs["AO"], mix.inputs[0]); L.new(nz.outputs["Fac"], mix.inputs[1])
    mm = N.new("ShaderNodeMath"); mm.operation = "MULTIPLY"; mm.inputs[1].default_value = 1.9
    L.new(mix.outputs[0], mm.inputs[0]); L.new(mm.outputs[0], cr.inputs["Fac"])
    L.new(cr.outputs["Color"], b.inputs["Base Color"])
    r = N.new("ShaderNodeMapRange"); r.inputs["To Min"].default_value = 0.45; r.inputs["To Max"].default_value = 0.18
    L.new(mm.outputs[0], r.inputs["Value"]); L.new(r.outputs["Result"], b.inputs["Roughness"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.15
    L.new(nz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def simple_mat(name, col, rough, metal=0.0, emit=None, es=0.0, trans=0.0, ior=1.45, alpha=1.0):
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Transmission Weight"].default_value = trans
    b.inputs["IOR"].default_value = ior
    b.inputs["Alpha"].default_value = alpha
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = es
    return m


def lens_glow_mat(strength):
    """Glowing green behind the glass: bright core, scanline flicker texture (Morse LED array)."""
    m = bpy.data.materials.new("lensglow%.0f" % strength)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    gr = N.new("ShaderNodeTexGradient"); gr.gradient_type = "SPHERICAL"
    mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (7, 7, 7)
    L.new(tc.outputs["Object"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], gr.inputs["Vector"])
    wav = N.new("ShaderNodeTexWave"); wav.inputs["Scale"].default_value = 40
    L.new(tc.outputs["Object"], wav.inputs["Vector"])
    mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    L.new(gr.outputs["Fac"], mul.inputs[0])
    wv = N.new("ShaderNodeMapRange"); wv.inputs["To Min"].default_value = 0.6
    L.new(wav.outputs["Fac"], wv.inputs["Value"]); L.new(wv.outputs["Result"], mul.inputs[1])
    es = N.new("ShaderNodeMath"); es.operation = "MULTIPLY"; es.inputs[1].default_value = strength
    L.new(mul.outputs[0], es.inputs[0])
    b.inputs["Base Color"].default_value = (0.02, 0.06, 0.02, 1)
    b.inputs["Emission Color"].default_value = (0.35, 1.0, 0.3, 1)
    L.new(es.outputs[0], b.inputs["Emission Strength"])
    return m


def toxic_mat():
    m = bpy.data.materials.new("toxic")
    N, L = nodes(m)
    N.remove(N["Principled BSDF"])
    out = N["Material Output"]
    v = N.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = (0.4, 0.95, 0.3, 1)
    v.inputs["Emission Color"].default_value = (0.3, 1.0, 0.2, 1)
    v.inputs["Anisotropy"].default_value = 0.3
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.2; nz.inputs["Detail"].default_value = 8
    nz.inputs["Roughness"].default_value = 0.6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ln = N.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"
    L.new(tc.outputs["Object"], ln.inputs[0])
    fall = N.new("ShaderNodeMapRange")
    fall.inputs["From Min"].default_value = 0.2; fall.inputs["From Max"].default_value = 1.0
    fall.inputs["To Min"].default_value = 1.0; fall.inputs["To Max"].default_value = 0.0
    L.new(ln.outputs["Value"], fall.inputs["Value"])
    sh = N.new("ShaderNodeMapRange")  # sharpen noise into wisps
    sh.inputs["From Min"].default_value = 0.48; sh.inputs["From Max"].default_value = 0.75
    L.new(nz.outputs["Fac"], sh.inputs["Value"])
    d = N.new("ShaderNodeMath"); d.operation = "MULTIPLY"
    L.new(sh.outputs["Result"], d.inputs[0]); L.new(fall.outputs["Result"], d.inputs[1])
    d2 = N.new("ShaderNodeMath"); d2.operation = "MULTIPLY"; d2.inputs[1].default_value = 3.0
    L.new(d.outputs[0], d2.inputs[0]); L.new(d2.outputs[0], v.inputs["Density"])
    e2 = N.new("ShaderNodeMath"); e2.operation = "MULTIPLY"; e2.inputs[1].default_value = 1.2
    L.new(d.outputs[0], e2.inputs[0]); L.new(e2.outputs[0], v.inputs["Emission Strength"])
    L.new(v.outputs[0], out.inputs["Volume"])
    return m


LEATHER = leather_mat("leather", (0.03, 0.022, 0.018), (0.12, 0.085, 0.06))
LEATHER_BEAK = leather_mat("leather_beak", (0.05, 0.035, 0.028), (0.2, 0.14, 0.09), 1.3)
STRAP = leather_mat("strap", (0.11, 0.06, 0.035), (0.3, 0.19, 0.11), 1.6)
HAT = leather_mat("hat", (0.012, 0.011, 0.011), (0.05, 0.045, 0.042), 0.8)
BRASS = brass_mat()
THREAD = simple_mat("thread", (0.32, 0.26, 0.18), 0.8)
GLASS = simple_mat("glass", (0.85, 1.0, 0.85), 0.02, trans=1.0, ior=1.5)
IRON = simple_mat("iron", (0.05, 0.05, 0.055), 0.35, 1.0)
SKIN = simple_mat("mannequin", (0.015, 0.015, 0.017), 0.8)


# ------------------------------------------------------------------ head (reference, mostly hidden; not in the game build)
if not GAME:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1)
    hd = bpy.context.object; hd.scale = (0.78, 0.95, 1.0); smooth(hd); hd.data.materials.append(SKIN)
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.42, depth=1.2, location=(0, 0.1, -1.15))
    nk = bpy.context.object; smooth(nk); nk.data.materials.append(SKIN)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=1, location=(0, 0.2, -2.05))
    sh = bpy.context.object; sh.scale = (1.6, 0.85, 0.45); sh.location.z = -1.85; smooth(sh); sh.data.materials.append(SKIN)


# ------------------------------------------------------------------ helmet (head + neck only: angular cranium, V jaw, welted panels)
BEAK_BASE = Vector((0, -0.93, -0.13))
NA, NZ = 200, 170
Z_TOP, Z_CHIN, Z_BOT = 1.1, -0.82, -1.04
TIE_Z = -0.02
SE = 2.7  # superellipse exponent: squarer cross-section than an oval
SEAMS = [math.radians(a) for a in (-90 + 38, -90 - 38, -90 + 100, -90 - 100, 90)]


def helm_radii(z):
    if z >= -0.15:
        f = math.sqrt(max(0.0, 1 - (abs(z) / Z_TOP) ** 2.4))
        temple = 1 + 0.06 * math.exp(-((z - 0.25) / 0.25) ** 2)
        return 0.86 * f * temple, 1.04 * f
    if z >= Z_CHIN:  # jaw narrows into a V
        t = (-0.15 - z) / (-0.15 - Z_CHIN)
        f0 = math.sqrt(1 - (0.15 / Z_TOP) ** 2.4)
        return 0.86 * f0 * (1 - 0.48 * t ** 1.3), 1.04 * f0 * (1 - 0.3 * t ** 1.5)
    t = (Z_CHIN - z) / (Z_CHIN - Z_BOT)  # short neck with a flared, rolled collar edge
    f0 = math.sqrt(1 - (0.15 / Z_TOP) ** 2.4)
    rx0, ry0 = 0.86 * f0 * 0.52, 1.04 * f0 * 0.7
    fl = 1 + 0.22 * t ** 3
    return rx0 * fl, ry0 * fl


def se(c, n=SE):
    return math.copysign(abs(c) ** (2 / n), c)


verts, faces = [], []
zs = [Z_TOP - (Z_TOP - Z_BOT) * k / (NZ - 1) for k in range(NZ)]
for k, z in enumerate(zs):
    rx, ry = helm_radii(z)
    for a in range(NA):
        th = 2 * math.pi * a / NA
        cx, cy = math.cos(th), math.sin(th)
        x, y = rx * se(cx), ry * se(cy)
        if cy < 0 and Z_CHIN < z < 0.7:  # flat face plane
            y *= 1 - 0.08 * (-cy) ** 4
        off = 0.0
        for sth in SEAMS:  # raised welted seams running over the head
            dth = math.atan2(math.sin(th - sth), math.cos(th - sth))
            off += 0.022 * math.exp(-(dth / 0.035) ** 2) * (1 if z > Z_CHIN else 0.4)
        if z < Z_BOT + 0.06:  # rolled collar lip
            off += 0.03 * math.exp(-((z - Z_BOT - 0.03) / 0.025) ** 2)
        if z < 0.0 and cy > 0:  # loose wrinkles at the nape
            off += 0.01 * math.sin(th * 14 + z * 20) * min(1, -z)
        # tie cord groove: runs round the back half, the leather bites in under the cord
        if cy > -0.35:
            k_ = min(1.0, (cy + 0.35) / 0.5)
            off -= 0.045 * k_ * math.exp(-((z - TIE_Z) / 0.035) ** 2)
            off += 0.018 * k_ * math.exp(-((z - TIE_Z - 0.07) / 0.03) ** 2)  # bulge above the cord
            off += 0.018 * k_ * math.exp(-((z - TIE_Z + 0.07) / 0.03) ** 2)  # bulge below the cord
        # leather scrunched toward the knot at the back: pleats radiating from it, pulled in at the centre
        if cy > 0.2:
            dx, dz = x, z - TIE_Z
            d = math.hypot(dx, dz)
            phi = math.atan2(dz, dx)
            ring = (1 - math.exp(-(d / 0.07) ** 2)) * math.exp(-(d / 0.5) ** 2)
            off += 0.04 * math.sin(phi * 13 + d * 10) * ring * (cy - 0.2) / 0.8
            off -= 0.07 * math.exp(-(d / 0.13) ** 2) * (cy - 0.2) / 0.8
        n = Vector((x / max(rx, 1e-3) ** 2, y / max(ry, 1e-3) ** 2, 0)).normalized()
        verts.append((x + n.x * off, y + n.y * off, z))
for k in range(NZ - 1):
    for a in range(NA):
        i0 = k * NA + a; i1 = k * NA + (a + 1) % NA
        faces.append((i0, i0 + NA, i1 + NA, i1))
top = len(verts); verts.append((0, 0, Z_TOP + 0.002))
for a in range(NA):
    faces.append((top, a, (a + 1) % NA))
hood = mesh_obj("hood", verts, faces)
bm = bmesh.new(); bm.from_mesh(hood.data); bm.normal_update()
for v in bm.verts:
    p = v.co.copy(); n = v.normal.copy(); off = 0.0
    d = (p - BEAK_BASE).length
    if d < 0.62 and p.y < -0.3:  # leather gathered into the beak
        rel = p - BEAK_BASE
        ang = math.atan2(rel.z, rel.x)
        off += 0.026 * math.sin(ang * 11 + d * 9) * math.exp(-((d - 0.34) / 0.15) ** 2)
    v.co += n * off
bm.to_mesh(hood.data); bm.free()
smooth(hood)
md = hood.modifiers.new("solid", "SOLIDIFY"); md.thickness = 0.03; md.offset = -1
mod_subsurf(hood, 1, 2)
mod_displace(hood, "CLOUDS", 0.25, 0.006, detail=4)
mod_displace(hood, "VORONOI", 0.12, -0.0025)
hood.data.materials.append(LEATHER)


def surf(o_xyz, direction):
    """Ray-cast onto the helmet: returns (location, normal)."""
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, n, i, ob, mw = SC.ray_cast(dg, Vector(o_xyz), Vector(direction).normalized())
    return (loc, n) if hit else (None, None)


# heavy brow plate: a thick curved leather band that juts out over the eye cups
bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.06, major_segments=96, minor_segments=16,
                                 location=(0, -0.06, 0.4))
brow = bpy.context.object
brow.scale = (0.84, 0.98, 0.9)
bm = bmesh.new(); bm.from_mesh(brow.data)
kill = [v for v in bm.verts if v.co.y > -0.25]
bmesh.ops.delete(bm, geom=kill, context="VERTS")
for v in bm.verts:  # dips to a point in the middle, flicks up at the temples
    v.co.z -= 0.12 * math.exp(-(v.co.x / 0.18) ** 2) - 0.08 * abs(v.co.x) ** 2
    v.co.y -= 0.05 * math.exp(-(v.co.x / 0.4) ** 2)
bm.to_mesh(brow.data); bm.free()
smooth(brow); mod_subsurf(brow, 1, 2); brow.data.materials.append(STRAP)

# cheek guards: angled leather plates that stick out past the jaw line
for s_ in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(s_ * 0.6, -0.55, -0.42))
    cg = bpy.context.object
    cg.scale = (0.05, 0.42, 0.5)
    cg.rotation_euler = (math.radians(12), math.radians(s_ * 10), math.radians(s_ * -32))
    bv = cg.modifiers.new("bv", "BEVEL"); bv.width = 0.035; bv.segments = 4
    mod_subsurf(cg, 1, 2)
    cg.modifiers.new("sb", "SIMPLE_DEFORM").deform_method = "BEND"
    cg.data.materials.append(LEATHER)
    for k in range(5):  # brass studs along the guard's edge
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.02)
        st = bpy.context.object
        st.parent = cg; st.location = (0.9 * -s_ * -1 * 0.0 + 0.0, -0.4 + k * 0.2, 0.42)
        st.location.x = 0.6 * (-1)  # outer face of the plate (local, before scale)
        st.scale = (1 / 0.05 * 0.05, 1 / 0.42 * 0.05, 1 / 0.5 * 0.05)
        st.data.materials.append(BRASS)

# tie cord round the back half + knot + gathered leather ruffle at the back
bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.02, major_segments=160, minor_segments=10,
                                 location=(0, 0, TIE_Z))
tcord = bpy.context.object; smooth(tcord)
sw = tcord.modifiers.new("sw", "SHRINKWRAP"); sw.target = hood; sw.wrap_method = "NEAREST_SURFACEPOINT"
sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.012
bm = bmesh.new(); bm.from_mesh(tcord.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.35], context="VERTS")
bm.to_mesh(tcord.data); bm.free()
tcord.data.materials.append(STRAP)
kloc, kn = surf((0, 3, TIE_Z), (0, -1, 0))
if kloc is not None:
    # ruffle: lathe along +y with deep folds, drooping slightly
    NA2, NL = 72, 40
    rv, rf = [], []
    for i in range(NL):
        u = i / (NL - 1)
        rad = 0.08 + 0.27 * u ** 0.7
        for j in range(NA2):
            th = 2 * math.pi * j / NA2
            fold = 1 + 0.28 * u * math.sin(th * 9 + u * 3) + 0.08 * math.sin(th * 23)
            px = math.cos(th) * rad * fold * 1.15
            pz = math.sin(th) * rad * fold * 0.8 - 0.14 * u ** 2
            py = u * 0.26 + 0.04 * math.sin(th * 9) * u
            rv.append((kloc.x + px, kloc.y - 0.05 + py, kloc.z + pz))
    for i in range(NL - 1):
        for j in range(NA2):
            a = i * NA2 + j; b = i * NA2 + (j + 1) % NA2
            rf.append((a, a + NA2, b + NA2, b))
    ruf = mesh_obj("ruffle", rv, rf); smooth(ruf)
    sm = ruf.modifiers.new("so", "SOLIDIFY"); sm.thickness = 0.02
    mod_subsurf(ruf, 1, 2); ruf.data.materials.append(LEATHER)
    # knot binding the gather
    bpy.ops.mesh.primitive_torus_add(major_radius=0.08, minor_radius=0.03, location=kloc + Vector((0, 0.03, 0)),
                                     rotation=(math.radians(90), 0, 0))
    kn_o = bpy.context.object; kn_o.scale = (1.1, 1, 0.8); smooth(kn_o); kn_o.data.materials.append(STRAP)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.05, location=kloc + Vector((0, 0.07, 0.0)))
    kb = bpy.context.object; kb.scale = (1.2, 0.8, 0.9); smooth(kb); kb.data.materials.append(STRAP)
    # cord tails hanging from the knot
    for s_, sway in ((-1, 0.12), (1, -0.05)):
        pts_ = [kloc + Vector((s_ * 0.05 + sway * (q / 8) ** 2, 0.08 + 0.02 * q, -0.07 * q)) for q in range(9)]
        cu = bpy.data.curves.new("tail", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = 0.014; cu.bevel_resolution = 3
        sp = cu.splines.new("POLY"); sp.points.add(len(pts_) - 1)
        for q, pp in enumerate(pts_):
            sp.points[q].co = (pp.x, pp.y, pp.z, 1)
        to = link(bpy.data.objects.new("tail", cu)); to.data.materials.append(STRAP)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.022, location=pts_[-1])
        en = bpy.context.object; en.data.materials.append(BRASS)  # brass aglet at the cord end


# laced closure down the back of the head (below the knot): eyelets + criss-cross cord
eye_pts = []
for k in range(5):
    z = -0.26 - k * 0.15
    for s_ in (-1, 1):
        loc, n = surf((s_ * 0.06, 3, z), (0, -1, 0))
        if loc is not None:
            bpy.ops.mesh.primitive_torus_add(major_radius=0.018, minor_radius=0.006, location=loc)
            ey = bpy.context.object; ey.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
            ey.data.materials.append(BRASS)
            eye_pts.append((k, s_, loc + n * 0.008))
by = {(k, s_): p for k, s_, p in eye_pts}
for k in range(4):
    for s_ in (-1, 1):
        a, b = by.get((k, s_)), by.get((k + 1, -s_))
        if a and b:
            mid = (a + b) / 2
            bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.008, depth=(b - a).length, location=mid)
            lc = bpy.context.object
            lc.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
            lc.data.materials.append(THREAD)


# ------------------------------------------------------------------ beak (lofted along a curve)
def beak_center(t):
    return Vector((0.0, -0.9 - 1.45 * t, -0.13 - 0.06 * t - 0.62 * t ** 2.6))


def beak_radius(t):
    r = 0.31 * (1 - t) ** 0.85 + 0.01
    for tk, a in ((0.1, 0.07), (0.27, 0.05), (0.46, 0.04), (0.64, 0.03)):  # leather bands / folds
        r *= 1 + a * math.exp(-((t - tk) / 0.018) ** 2)
    r *= 1 + 0.015 * math.sin(t * 90)  # small ripples from the gathered leather
    return r


RINGS, SEGS = 260, 72
verts, faces = [], []
for i in range(RINGS):
    t = i / (RINGS - 1)
    c = beak_center(t)
    dt = 1e-3
    T = (beak_center(min(1, t + dt)) - beak_center(max(0, t - dt))).normalized()
    up = Vector((0, 0, 1))
    B = T.cross(up).normalized()
    U = B.cross(T).normalized()
    r = beak_radius(t)
    for j in range(SEGS):
        th = 2 * math.pi * j / SEGS
        cx, cz = math.cos(th), math.sin(th)
        rx = r * 0.88
        rz = r * (1.05 + 0.18 * max(0.0, cz) ** 6)  # keel along the top
        if cz < 0:
            rz *= 0.9  # flatter underside
        p = c + B * (cx * rx) + U * (cz * rz)
        verts.append(tuple(p))
for i in range(RINGS - 1):
    for j in range(SEGS):
        a = i * SEGS + j; b = i * SEGS + (j + 1) % SEGS
        faces.append((a, b, b + SEGS, a + SEGS))
tip = len(verts); verts.append(tuple(beak_center(1.0) + (beak_center(1) - beak_center(0.99)).normalized() * 0.01))
for j in range(SEGS):
    a = (RINGS - 1) * SEGS + j; b = (RINGS - 1) * SEGS + (j + 1) % SEGS
    faces.append((a, b, tip))
beak = mesh_obj("beak", verts, faces)
smooth(beak)
mod_subsurf(beak, 1, 2)
mod_displace(beak, "CLOUDS", 0.2, 0.008, detail=4)
beak.data.materials.append(LEATHER_BEAK)

# breathing holes (nostrils) near the base: dark sunken ovals + brass grommets
for s in (-1, 1):
    t = 0.2
    c = beak_center(t)
    p = c + Vector((s * beak_radius(t) * 0.8, 0, beak_radius(t) * 0.25))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.028, minor_radius=0.009, location=p)
    g = bpy.context.object; g.rotation_euler = (0, math.radians(90 * s), 0)
    g.rotation_euler.rotate_axis("X", math.radians(20)); smooth(g); g.data.materials.append(BRASS)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.024, location=p)
    h = bpy.context.object; h.scale = (0.4, 1, 1); h.data.materials.append(simple_mat("hole", (0, 0, 0), 1))


# herb pouch: drawstring sack hanging from the first beak tie, frilled mouth, herbs poking out
PC = beak_center(0.3) + Vector((0.16, 0.0, -0.36))
NA3, NL3 = 64, 48
pv, pf = [], []
for i in range(NL3):
    h = i / (NL3 - 1)  # 0 bottom .. 1 mouth
    if h < 0.62:
        r = 0.115 * math.sin(min(1.0, h / 0.62) * math.pi / 2) ** 0.55
    elif h < 0.78:
        q = (h - 0.62) / 0.16
        r = 0.115 * (1 - q) + 0.032 * q
    else:
        q = (h - 0.78) / 0.22
        r = 0.032 + 0.06 * q ** 0.8
    for j in range(NA3):
        th = 2 * math.pi * j / NA3
        g = math.exp(-((h - 0.78) / 0.12) ** 2)  # gathered pleats round the drawstring
        fold = 1 + 0.22 * g * math.sin(th * 12) + 0.05 * math.sin(th * 5 + h * 7) + 0.3 * max(0, h - 0.85) * math.sin(th * 7)
        sag = 0.02 * math.sin(th) * (1 - h)  # contents settle to one side
        pv.append((PC.x + math.cos(th) * r * fold, PC.y + math.sin(th) * r * fold * 0.9 + sag, PC.z - 0.3 + h * 0.3))
for i in range(NL3 - 1):
    for j in range(NA3):
        a = i * NA3 + j; b = i * NA3 + (j + 1) % NA3
        pf.append((a, a + NA3, b + NA3, b))
bot = len(pv); pv.append((PC.x, PC.y, PC.z - 0.302))
for j in range(NA3):
    pf.append((bot, (j + 1) % NA3, j))
pouch = mesh_obj("pouch", pv, pf); smooth(pouch)
sp_ = pouch.modifiers.new("so", "SOLIDIFY"); sp_.thickness = 0.008
mod_subsurf(pouch, 1, 2)
pouch.data.materials.append(leather_mat("pouch", (0.13, 0.09, 0.055), (0.28, 0.2, 0.12), 3))
bpy.ops.mesh.primitive_torus_add(major_radius=0.036, minor_radius=0.009, location=PC + Vector((0, 0, -0.066)))
dr = bpy.context.object; smooth(dr); dr.data.materials.append(THREAD)
HERB = simple_mat("herb", (0.09, 0.14, 0.04), 0.7)
STEM = simple_mat("stem", (0.12, 0.1, 0.05), 0.8)
for k in range(7):
    ang = k * 0.9
    base_ = PC + Vector((math.cos(ang) * 0.015, math.sin(ang) * 0.015, -0.04))
    tip_ = base_ + Vector((math.cos(ang) * 0.06, math.sin(ang) * 0.05, 0.1 + 0.03 * (k % 3)))
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.004, depth=(tip_ - base_).length, location=(base_ + tip_) / 2)
    st_ = bpy.context.object; st_.rotation_euler = (tip_ - base_).to_track_quat("Z", "Y").to_euler(); st_.data.materials.append(STEM)
    for l in range(3):
        lp = base_ + (tip_ - base_) * (0.45 + 0.25 * l)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.016, location=lp)
        lf = bpy.context.object; lf.scale = (1.0, 0.35, 0.12)
        lf.rotation_euler = (random.uniform(0, 1), random.uniform(0, 1), ang + l); lf.data.materials.append(HERB)
# hanging cord from the beak tie to the pouch
tie_pt = beak_center(0.36) + Vector((0.1, 0, -0.12))
cu = bpy.data.curves.new("pcord", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = 0.007
spl = cu.splines.new("POLY"); spl.points.add(1)
spl.points[0].co = (*tie_pt, 1); spl.points[1].co = (*(PC + Vector((0, 0, -0.066))), 1)
pc_o = link(bpy.data.objects.new("pcord", cu)); pc_o.data.materials.append(THREAD)
for t_ in (0.36, 0.56):
    c_ = beak_center(t_)
    T_ = (beak_center(t_ + 1e-3) - beak_center(t_ - 1e-3)).normalized()
    bpy.ops.mesh.primitive_torus_add(major_radius=beak_radius(t_) * 1.04, minor_radius=0.012, location=c_)
    tr = bpy.context.object; tr.rotation_euler = T_.to_track_quat("Z", "Y").to_euler(); tr.scale = (0.9, 1.08, 1)
    smooth(tr); tr.data.materials.append(THREAD)


# ------------------------------------------------------------------ stitching
def stitches(points, normals, step_dir, size=0.018, mat=THREAD):
    """Cross stitches along a seam: points on the surface, normals out, step_dir across the seam."""
    bm = bmesh.new()
    for p, n, d in zip(points, normals, step_dir):
        for tilt in (-1, 1):
            m = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.0035, radius2=0.0035, depth=size)
            vs = m["verts"]
            rot = Vector((0, 0, 1)).rotation_difference(d.normalized())
            rot2 = Matrix.Rotation(math.radians(28 * tilt), 4, n.normalized())
            mat4 = Matrix.Translation(p + n * 0.003) @ rot2 @ rot.to_matrix().to_4x4()
            bmesh.ops.transform(bm, matrix=mat4, verts=vs)
    me = bpy.data.meshes.new("stitch"); bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new("stitch", me)); smooth(o); o.data.materials.append(mat)
    return o


# along the top keel of the beak
pts, nrm, drs = [], [], []
for k in range(34):
    t = 0.05 + k * 0.026
    c = beak_center(t)
    T = (beak_center(t + 1e-3) - beak_center(t - 1e-3)).normalized()
    B = T.cross(Vector((0, 0, 1))).normalized(); U = B.cross(T).normalized()
    r = beak_radius(t)
    pts.append(c + U * r * 1.23); nrm.append(U); drs.append(B)
stitches(pts, nrm, drs, 0.026 * 1.0)
# along a side welt over the head (sample the helmet surface by ray cast)
deps = bpy.context.evaluated_depsgraph_get()
pts, nrm, drs = [], [], []
for k in range(26):
    a = math.radians(-60 + k * 5.5)
    o = Vector((math.cos(math.radians(-52)) * 3 * math.sin(a + 1.2), math.sin(math.radians(-52)) * 3 * math.sin(a + 1.2), math.cos(a + 1.2) * 3))
    hit, loc, n, idx, obj, mw = SC.ray_cast(deps, o, -o.normalized())
    if hit and obj.name == "hood":
        pts.append(loc); nrm.append(n); drs.append(Vector((1, 0, 0)))
stitches(pts, nrm, drs, 0.03)


# ------------------------------------------------------------------ eye cups (leather cones, glass, glow)
for s in (-1, 1):
    base = Vector((s * 0.31, -0.97, 0.2))
    rot = (math.radians(90 - 6), 0, math.radians(-s * 14))
    bpy.ops.mesh.primitive_cone_add(vertices=64, radius1=0.2, radius2=0.165, depth=0.2, location=base, rotation=rot)
    tube = bpy.context.object; smooth(tube)
    if GAME:  # open the cup's caps so the baked lens sees the glow disc (the game draws the glass and glow itself)
        bm = bmesh.new(); bm.from_mesh(tube.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if len(f.verts) > 4], context="FACES")
        bm.to_mesh(tube.data); bm.free()
    bv = tube.modifiers.new("bv", "BEVEL"); bv.width = 0.012; bv.segments = 3
    tube.data.materials.append(STRAP)
    fwd = Vector((math.sin(math.radians(s * 14)) * -1, -1, 0.1)).normalized()
    front = base + fwd * 0.1
    bpy.ops.mesh.primitive_torus_add(major_radius=0.172, minor_radius=0.02, location=front, rotation=rot)
    rim = bpy.context.object; smooth(rim); rim.data.materials.append(BRASS)
    # glass dome + glowing interior (left eye mid-flash, right dimmer: Morse)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.155, location=front - fwd * 0.03)
    dome = bpy.context.object; dome.name = "glass"; dome.scale = (1, 1, 0.35); dome.rotation_euler = rot; smooth(dome)
    dome.data.materials.append(GLASS)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.165 if GAME else 0.15, depth=0.01,
                                        location=front - fwd * (0.0 if GAME else 0.05), rotation=rot)
    glow = bpy.context.object; glow.name = "glow_L" if s < 0 else "glow_R"
    glow.data.materials.append(lens_glow_mat(28 if s < 0 else 5))
    # leather gasket where the cup meets the helmet
    bpy.ops.mesh.primitive_torus_add(major_radius=0.19, minor_radius=0.03, location=base - fwd * 0.05, rotation=rot)
    gk = bpy.context.object; smooth(gk); gk.data.materials.append(STRAP)

if not GAME:  # light from the left lens spilling on the beak
    pl = bpy.data.lights.new("lensspill", "POINT"); pl.energy = 6; pl.color = (0.4, 1.0, 0.3); pl.shadow_soft_size = 0.05
    po = link(bpy.data.objects.new("lensspill", pl)); po.location = (-0.31, -1.12, 0.17)


# ------------------------------------------------------------------ hat (17th c.: broad flat brim, low flat-topped crown)
HAT_Z = 0.66
bpy.ops.mesh.primitive_circle_add(vertices=192, radius=1.0, fill_type="TRIFAN", location=(0, 0, 0))
brim = bpy.context.object
bm = bmesh.new(); bm.from_mesh(brim.data)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=4, use_grid_fill=True)
for v in bm.verts:
    v.co.x *= 1.55; v.co.y *= 1.62
    r = math.hypot(v.co.x / 1.55, v.co.y / 1.62)
    ang = math.atan2(v.co.y, v.co.x)
    if r > 0.5:
        k = (r - 0.5) / 0.5
        v.co.z -= 0.09 * k ** 2 * (0.6 + 0.4 * abs(math.sin(ang)))  # soft droop of heavy felt / leather
        v.co.z += 0.015 * math.sin(ang * 7 + 1.0) * k ** 2  # uneven, hand-made
bm.to_mesh(brim.data); bm.free()
brim.location = (0, 0.02, HAT_Z)
md = brim.modifiers.new("solid", "SOLIDIFY"); md.thickness = 0.03
mod_subsurf(brim, 1, 2); smooth(brim); brim.data.materials.append(HAT)
# crown: low, slightly tapered, flat top with soft edge; its opening fits the helmet
bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=1.0, depth=0.5, location=(0, 0.02, HAT_Z + 0.25))
crown = bpy.context.object
bm = bmesh.new(); bm.from_mesh(crown.data)
for v in bm.verts:
    t = (v.co.z + 0.25) / 0.5
    sx, sy = 0.68 - 0.04 * t, 0.83 - 0.05 * t
    v.co.x *= sx; v.co.y *= sy
bm.to_mesh(crown.data); bm.free()
bv = crown.modifiers.new("bv", "BEVEL"); bv.width = 0.05; bv.segments = 6; bv.limit_method = "ANGLE"
mod_subsurf(crown, 1, 2); smooth(crown); crown.data.materials.append(HAT)
bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=1.0, depth=0.09, location=(0, 0.02, HAT_Z + 0.06))
band = bpy.context.object; band.scale = (0.685, 0.835, 1); smooth(band)
band.data.materials.append(leather_mat("band", (0.03, 0.022, 0.018), (0.09, 0.07, 0.05), 2))
for o in (brim, crown, band):  # whole hat tipped slightly forward
    o.rotation_euler = (math.radians(-4), 0, 0)


if GAME:  # the mist, flies and lights are the game's own effects (game/mask_model.gd)
    raise SystemExit(0)  # (tools/blender/mask_bake.py catches it and goes on with the scene as it is)

# ------------------------------------------------------------------ toxic mist + flies
bpy.ops.mesh.primitive_cube_add(size=2, location=(0.0, -2.25, -1.1))
mist = bpy.context.object; mist.scale = (0.55, 0.5, 0.5); mist.data.materials.append(toxic_mat())
FLY = simple_mat("fly", (0.005, 0.005, 0.006), 0.25, 0.3)
WING = simple_mat("wing", (0.7, 0.75, 0.7), 0.05, trans=0.8, alpha=0.5)
for i in range(22):
    p = Vector((random.uniform(-0.5, 0.5), random.uniform(-2.6, -1.9), random.uniform(-1.5, -0.7)))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.018, location=p)
    f = bpy.context.object; f.scale = (1, 1.7, 0.9); f.rotation_euler = (0, 0, random.uniform(0, 6.3))
    f.data.materials.append(FLY)
    for s in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.02,
                                             location=p + Vector((s * 0.025, 0.005, 0.014)))
        wg = bpy.context.object; wg.scale = (1.3, 0.7, 0.12); wg.data.materials.append(WING)


# ------------------------------------------------------------------ backdrop + lights + camera
w = bpy.data.worlds.new("w"); SC.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.006, 0.007, 0.01, 1)
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 6, 0))
bd = bpy.context.object; bd.rotation_euler = (math.radians(90), 0, 0)
m = bpy.data.materials.new("smoke_bd"); N, L = nodes(m)
b = N["Principled BSDF"]; tc = N.new("ShaderNodeTexCoord")
nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.25; nz.inputs["Detail"].default_value = 10
nz.inputs["Distortion"].default_value = 1.5
L.new(tc.outputs["Object"], nz.inputs["Vector"])
cr = N.new("ShaderNodeValToRGB")
cr.color_ramp.elements[0].color = (0.01, 0.012, 0.016, 1); cr.color_ramp.elements[1].color = (0.12, 0.13, 0.16, 1)
cr.color_ramp.elements[0].position = 0.4
L.new(nz.outputs["Fac"], cr.inputs["Fac"]); L.new(cr.outputs["Color"], b.inputs["Base Color"])
b.inputs["Roughness"].default_value = 1
bd.data.materials.append(m)

light("key", (3.2, -4.0, 3.6), 300, 2.5, (1.0, 0.9, 0.78))
light("fill", (-4.2, -3.0, 0.2), 90, 4.0, (0.6, 0.72, 1.0))
light("rim_l", (-2.8, 2.5, 2.4), 420, 1.5, (0.75, 0.85, 1.0))
light("rim_r", (2.8, 2.2, 1.8), 300, 1.5, (1.0, 0.85, 0.7))
light("toxic_up", (0.2, -2.6, -2.6), 50, 2.0, (0.35, 1.0, 0.3), target=(0, -1.2, 0))
light("back_key", (-3.0, 4.5, 2.2), 260, 2.5, (0.95, 0.9, 0.85), target=(0, 0.6, 0))
light("bd_glow", (0, 3.0, 0.5), 900, 6.0, (0.55, 0.62, 0.8), target=(0, 6, 0))

cd = bpy.data.cameras.new("cam"); cam = link(bpy.data.objects.new("cam", cd)); SC.camera = cam
cd.dof.use_dof = True; cd.dof.aperture_fstop = 6.0


def shoot(name, loc, target, lens):
    cam.location = loc; look(cam, target); cd.lens = lens
    cd.dof.focus_distance = (Vector(loc) - Vector((0, -1.0, 0.1))).length
    SC.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


if VIEWS in ("both", "three", "all"):
    shoot("plague_doctor_sculpt_34", (3.6, -6.4, 0.9), (0.05, -0.9, 0.1), 62)
if VIEWS in ("both", "front", "all"):
    shoot("plague_doctor_sculpt_front", (0.0, -7.6, 0.55), (0, -0.8, 0.12), 62)
if VIEWS in ("both", "back", "all"):
    shoot("plague_doctor_sculpt_back", (-4.6, 5.2, 1.3), (0, 0.1, 0.05), 62)
if VIEWS in ("side", "all"):
    shoot("plague_doctor_sculpt_side", (-7.2, -0.6, 0.6), (0, -0.6, 0.05), 55)
print("ok")

# Purpose: developer-time. Shared helpers for the scripted mask sculpts (diary/MASK_PROCESS.md) after the Plague Doctor
# (tools/blender/mask_plague_doctor.py, the bar, keeps its own copy): scene set-up (Cycles CPU, AgX), mesh helpers
# (lathe with a superellipse cross-section, loft along a curve, shell patches cut from a lathed head, plates, bolts,
# weld beads, teeth rows, tubes), procedural materials (leather, steel with heat colours and rust, brass, rubber, bone,
# glow), and the render stage (smoky backdrop, warm key, cool fill, two rims, back key, 3/4 / front / side / back
# views). Head space: x across, -y forward, z up; the head is ~0.8 wide, ~1.0 deep, top at ~1.1 (sculpt units; the game
# fit is the mask's GAME_FIT). GAME=1 (env MASK_GAME) builds only the mask for tools/blender/mask_bake.py.
# Material names starting fxR_ / fxG_ glow in the game (two glow groups), fxB_ marks the part that moves (a jaw).
# Dependencies: pip bpy (5.x), numpy.
import os
import sys
import math
import random

import bpy
import bmesh
from mathutils import Vector, Matrix

GAME = os.environ.get("MASK_GAME") == "1"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mask"
VIEWS = sys.argv[2] if len(sys.argv) > 2 else "all"
SC = None


def setup(seed=7):
    global SC
    random.seed(seed)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SC = bpy.context.scene
    SC.render.engine = "CYCLES"
    SC.cycles.device = "CPU"
    SC.cycles.samples = int(os.environ.get("SPP", 56))
    SC.cycles.use_denoising = True
    SC.render.resolution_x = SC.render.resolution_y = int(os.environ.get("RES", 1100))
    SC.view_settings.view_transform = "AgX"
    SC.view_settings.look = "AgX - Medium High Contrast"
    SC.view_settings.exposure = -0.5
    return SC


# ------------------------------------------------------------------ mesh helpers
def link(o):
    SC.collection.objects.link(o)
    return o


def mesh_obj(name, verts, faces, mat=None, smooth_it=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = link(bpy.data.objects.new(name, me))
    if smooth_it:
        smooth(o)
    if mat is not None:
        o.data.materials.append(mat)
    return o


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def subsurf(o, lv=1, rlv=2):
    m = o.modifiers.new("sub", "SUBSURF")
    m.levels, m.render_levels = lv, rlv
    return m


def solidify(o, t, offset=-1.0):
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness, m.offset = t, offset
    return m


def bevel(o, w, seg=2, angle=None):
    m = o.modifiers.new("bv", "BEVEL")
    m.width, m.segments = w, seg
    if angle is not None:
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(angle)
    return m


def displace(o, tex_type, size, strength, detail=None):
    t = bpy.data.textures.new(o.name + tex_type, tex_type)
    if hasattr(t, "noise_scale"):
        t.noise_scale = size
    if detail is not None and hasattr(t, "noise_depth"):
        t.noise_depth = detail
    m = o.modifiers.new("disp" + tex_type, "DISPLACE")
    m.texture, m.texture_coords, m.strength = t, "LOCAL", strength
    return m


def se(c, n):
    return math.copysign(abs(c) ** (2.0 / n), c)


def lathe(name, radii, z_top, z_bot, na=160, nz=120, exp=2.7, offset=None, mat=None, cap=True):
    """A head-like shell: radii(z) -> (rx, ry); superellipse cross-section `exp`; offset(x, y, z, th) -> push along the
    outward normal (sculpt moves). Rings from the top down; a fan closes the top."""
    verts, faces = [], []
    for k in range(nz):
        z = z_top - (z_top - z_bot) * k / (nz - 1)
        rx, ry = radii(z)
        for a in range(na):
            th = 2 * math.pi * a / na
            cx, cy = math.cos(th), math.sin(th)
            x, y = rx * se(cx, exp), ry * se(cy, exp)
            off = offset(x, y, z, th) if offset else 0.0
            n = Vector((x / max(rx, 1e-3) ** 2, y / max(ry, 1e-3) ** 2, 0)).normalized()
            verts.append((x + n.x * off, y + n.y * off, z))
    for k in range(nz - 1):
        for a in range(na):
            i0 = k * na + a; i1 = k * na + (a + 1) % na
            faces.append((i0, i0 + na, i1 + na, i1))
    if cap:
        top = len(verts); verts.append((0, 0, z_top + 0.002))
        for a in range(na):
            faces.append((top, a, (a + 1) % na))
    return mesh_obj(name, verts, faces, mat)


def surface_point(radii, exp, th, z, out=0.0):
    rx, ry = radii(z)
    cx, cy = math.cos(th), math.sin(th)
    x, y = rx * se(cx, exp), ry * se(cy, exp)
    n = Vector((x / max(rx, 1e-3) ** 2, y / max(ry, 1e-3) ** 2, 0.0)).normalized()
    return Vector((x, y, z)) + n * out, n


def patch(name, radii, exp, th0, th1, z0, z1, out, thick, mat, nt=40, nzz=30, bulge=None, edge_round=0.0):
    """A plate that follows the shell between angles th0..th1 and heights z0..z1, `out` off the surface, `thick`
    deep (solidify inward). bulge(u, v) adds a push (u, v in 0..1). edge_round rounds the outline's corners."""
    verts, faces = [], []
    for j in range(nzz):
        v = j / (nzz - 1)
        z = z1 - (z1 - z0) * v
        for i in range(nt):
            u = i / (nt - 1)
            th = th0 + (th1 - th0) * u
            p, n = surface_point(radii, exp, th, z, out + (bulge(u, v) if bulge else 0.0))
            verts.append(tuple(p))
    for j in range(nzz - 1):
        for i in range(nt - 1):
            a = j * nt + i
            faces.append((a, a + nt, a + nt + 1, a + 1))
    o = mesh_obj(name, verts, faces, mat)
    solidify(o, thick)
    bevel(o, min(thick * 0.45, 0.02), 2)
    return o


def box(name, size, loc, rot=(0, 0, 0), mat=None, bev=0.01, seg=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; o.scale = size
    if bev > 0:
        bevel(o, bev, seg)
    if mat is not None:
        o.data.materials.append(mat)
    return o


def cyl(name, r, depth, loc, rot=(0, 0, 0), mat=None, verts=24, bev=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; smooth(o)
    if bev > 0:
        bevel(o, bev, 2, 40)
    if mat is not None:
        o.data.materials.append(mat)
    return o


def ball(name, r, loc, mat=None, scale=(1, 1, 1), seg=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(seg // 2, 4), radius=r, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale; smooth(o)
    if mat is not None:
        o.data.materials.append(mat)
    return o


def align(o, direction, up=(0, 0, 1)):
    """Turns `o` so its local +Z points along `direction`."""
    o.rotation_euler = Vector(direction).normalized().to_track_quat("Z", "Y").to_euler()


def bolt(loc, normal, r, mat, head=0.6):
    """A hex bolt head standing on a surface."""
    o = cyl("bolt", r, r * head, Vector(loc) + Vector(normal).normalized() * r * head * 0.4, mat=mat, verts=6)
    align(o, normal)
    bevel(o, r * 0.12, 1)
    return o


def tube(name, pts, r, mat, res=6, taper=None):
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = r; cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY"); sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p[0], p[1], p[2], 1)
        if taper:
            sp.points[i].radius = taper(i / max(len(pts) - 1, 1))
    o = link(bpy.data.objects.new(name, cu))
    o.data.materials.append(mat)
    return o


def smooth_path(ctrl, n=24):
    """Catmull-Rom through control points -> n points."""
    c = [Vector(p) for p in ctrl]
    c = [c[0]] + c + [c[-1]]
    out = []
    segs = len(c) - 3
    for s in range(segs):
        p0, p1, p2, p3 = c[s], c[s + 1], c[s + 2], c[s + 3]
        steps = max(n // segs, 2)
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(c[-2])
    return out


def path_fn(pts):
    """t (0..1) -> a point along the polyline `pts`, evenly by length."""
    pts = [Vector(p) for p in pts]
    lens = [0.0]
    for i in range(len(pts) - 1):
        lens.append(lens[-1] + (pts[i + 1] - pts[i]).length)
    total = max(lens[-1], 1e-6)

    def at(t):
        d = min(max(t, 0.0), 1.0) * total
        for i in range(len(pts) - 1):
            if d <= lens[i + 1] or i == len(pts) - 2:
                f = (d - lens[i]) / max(lens[i + 1] - lens[i], 1e-6)
                return pts[i].lerp(pts[i + 1], min(max(f, 0.0), 1.0))
        return pts[-1]
    return at


def weld(name, pts, r, mat, beads_per=None):
    """A weld seam: overlapping squashed beads along a path (pts on the surface)."""
    bm = bmesh.new()
    path = smooth_path(pts, max(len(pts) * 8, 12))
    total = sum((path[i + 1] - path[i]).length for i in range(len(path) - 1))
    count = int(total / (r * 1.1)) if beads_per is None else beads_per
    acc, i = 0.0, 0
    targets = [total * k / max(count - 1, 1) for k in range(count)]
    seg_len = [(path[j + 1] - path[j]).length for j in range(len(path) - 1)]
    for tgt in targets:
        while i < len(seg_len) - 1 and acc + seg_len[i] < tgt:
            acc += seg_len[i]; i += 1
        f = (tgt - acc) / max(seg_len[i], 1e-6)
        p = path[i].lerp(path[i + 1], min(f, 1.0))
        d = (path[i + 1] - path[i]).normalized()
        m = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=r * random.uniform(0.85, 1.1))
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        sc = Matrix.Diagonal((1.0, 0.55, 0.75, 1.0))
        bmesh.ops.transform(bm, matrix=Matrix.Translation(p) @ rot @ sc, verts=m["verts"])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); smooth(o); o.data.materials.append(mat)
    return o


def loft(name, center, radius, rings=120, segs=32, profile=None, mat=None, cap=True):
    """A tube along center(t) (t 0..1) with radius(t); profile(th, t) -> (sx, sz) shapes the cross-section."""
    verts, faces = [], []
    for i in range(rings):
        t = i / (rings - 1)
        c = Vector(center(t))
        T = (Vector(center(min(1, t + 1e-3))) - Vector(center(max(0, t - 1e-3)))).normalized()
        up = Vector((0, 0, 1)) if abs(T.z) < 0.95 else Vector((0, 1, 0))
        B = T.cross(up).normalized(); U = B.cross(T).normalized()
        r = radius(t)
        for j in range(segs):
            th = 2 * math.pi * j / segs
            sx, sz = profile(th, t) if profile else (1.0, 1.0)
            verts.append(tuple(c + B * (math.cos(th) * r * sx) + U * (math.sin(th) * r * sz)))
    for i in range(rings - 1):
        for j in range(segs):
            a = i * segs + j; b = i * segs + (j + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    if cap:
        for end, ring in ((0, 0), (1, rings - 1)):
            ci = len(verts); verts.append(tuple(Vector(center(end))))
            for j in range(segs):
                a = ring * segs + j; b = ring * segs + (j + 1) % segs
                faces.append((a, b, ci) if end else (b, a, ci))
    return mesh_obj(name, verts, faces, mat)


# ------------------------------------------------------------------ materials
def nodes(mat):
    mat.use_nodes = True
    return mat.node_tree.nodes, mat.node_tree.links


def simple(name, col, rough, metal=0.0, emit=None, es=0.0, trans=0.0, ior=1.45):
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Transmission Weight"].default_value = trans
    b.inputs["IOR"].default_value = ior
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = es
    return m


def _ao_mix(N, L, color_socket, dirt, dist=0.06):
    ao = N.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = dist
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    inv = N.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    L.new(ao.outputs["AO"], inv.inputs[1])
    pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 0.6
    L.new(inv.outputs[0], pw.inputs[0])
    L.new(pw.outputs[0], mx.inputs[0]); L.new(color_socket, mx.inputs[6]); mx.inputs[7].default_value = (*dirt, 1)
    return mx.outputs[2], ao


def steel(name, base=(0.11, 0.115, 0.12), heat=0.6, rust=0.5, scale=1.0, rough=0.42):
    """Worked steel: brushed noise, polished worn edges (pointiness), heat temper colours (straw / bronze / blue /
    purple bands from a warped noise, `heat` 0..1), rust and grime in cavities (AO x noise, `rust` 0..1)."""
    m = bpy.data.materials.new(name)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Metallic"].default_value = 1.0
    tc = N.new("ShaderNodeTexCoord")
    brush = N.new("ShaderNodeTexNoise"); brush.inputs["Scale"].default_value = 60 * scale; brush.inputs["Detail"].default_value = 8
    mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (1, 1, 14)
    L.new(tc.outputs["Object"], mp.inputs["Vector"]); L.new(mp.outputs["Vector"], brush.inputs["Vector"])
    temper = N.new("ShaderNodeTexNoise"); temper.inputs["Scale"].default_value = 2.2 * scale; temper.inputs["Detail"].default_value = 4
    temper.inputs["Distortion"].default_value = 1.2
    L.new(tc.outputs["Object"], temper.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.3; els[0].color = (*base, 1)
    els[1].position = 0.72; els[1].color = (base[0] * 1.1, base[1] * 1.1, base[2] * 1.15, 1)
    for pos, col in ((0.45, (0.36, 0.28, 0.12)), (0.52, (0.3, 0.16, 0.08)), (0.58, (0.16, 0.12, 0.26)), (0.64, (0.08, 0.14, 0.3))):
        e = els.new(pos)
        e.color = (base[0] + (col[0] - base[0]) * heat, base[1] + (col[1] - base[1]) * heat, base[2] + (col[2] - base[2]) * heat, 1)
    L.new(temper.outputs["Fac"], ramp.inputs["Fac"])
    geo = N.new("ShaderNodeNewGeometry")
    edge = N.new("ShaderNodeMapRange"); edge.inputs["From Min"].default_value = 0.53; edge.inputs["From Max"].default_value = 0.62
    L.new(geo.outputs["Pointiness"], edge.inputs["Value"])
    polish = N.new("ShaderNodeMix"); polish.data_type = "RGBA"
    L.new(edge.outputs["Result"], polish.inputs[0]); L.new(ramp.outputs["Color"], polish.inputs[6])
    polish.inputs[7].default_value = (0.55, 0.55, 0.56, 1)
    rn = N.new("ShaderNodeTexNoise"); rn.inputs["Scale"].default_value = 9 * scale; rn.inputs["Detail"].default_value = 10
    rn.inputs["Roughness"].default_value = 0.7
    L.new(tc.outputs["Object"], rn.inputs["Vector"])
    ao = N.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.07
    inv = N.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    L.new(ao.outputs["AO"], inv.inputs[1])
    rm = N.new("ShaderNodeMath"); rm.operation = "MULTIPLY"
    L.new(inv.outputs[0], rm.inputs[0]); L.new(rn.outputs["Fac"], rm.inputs[1])
    rmask = N.new("ShaderNodeMapRange"); rmask.inputs["From Min"].default_value = 0.12 * (1.2 - rust); rmask.inputs["From Max"].default_value = 0.32 * (1.2 - rust) + 0.02
    L.new(rm.outputs[0], rmask.inputs["Value"])
    if rust <= 0.0:  # no rust at all (AO alone had browned occluded corners even at rust 0)
        rmask.inputs["From Min"].default_value = 5.0; rmask.inputs["From Max"].default_value = 6.0
    rusty = N.new("ShaderNodeMix"); rusty.data_type = "RGBA"
    L.new(rmask.outputs["Result"], rusty.inputs[0]); L.new(polish.outputs[2], rusty.inputs[6])
    rusty.inputs[7].default_value = (0.16, 0.06, 0.025, 1)
    L.new(rusty.outputs[2], b.inputs["Base Color"])
    rr = N.new("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = rough; rr.inputs["To Max"].default_value = 0.95
    L.new(rmask.outputs["Result"], rr.inputs["Value"])
    rr2 = N.new("ShaderNodeMath"); rr2.operation = "SUBTRACT"
    L.new(rr.outputs["Result"], rr2.inputs[0])
    ed = N.new("ShaderNodeMath"); ed.operation = "MULTIPLY"; ed.inputs[1].default_value = 0.22
    L.new(edge.outputs["Result"], ed.inputs[0]); L.new(ed.outputs[0], rr2.inputs[1])
    L.new(rr2.outputs[0], b.inputs["Roughness"])
    met = N.new("ShaderNodeMapRange"); met.inputs["To Min"].default_value = 1.0; met.inputs["To Max"].default_value = 0.0
    L.new(rmask.outputs["Result"], met.inputs["Value"])
    L.new(met.outputs["Result"], b.inputs["Metallic"])
    h = N.new("ShaderNodeMath"); h.operation = "ADD"
    bs = N.new("ShaderNodeMath"); bs.operation = "MULTIPLY"; bs.inputs[1].default_value = 0.3
    L.new(brush.outputs["Fac"], bs.inputs[0]); L.new(bs.outputs[0], h.inputs[0]); L.new(rmask.outputs["Result"], h.inputs[1])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.2; bump.inputs["Distance"].default_value = 0.004
    L.new(h.outputs[0], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def rubber(name, col=(0.025, 0.025, 0.027)):
    m = simple(name, col, 0.7)
    N, L = nodes(m)
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 40
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.1
    L.new(nz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    dirt, _ = _ao_mix(N, L, _const(N, col), (0.008, 0.007, 0.006))
    L.new(dirt, b.inputs["Base Color"])
    return m


def _const(N, col):
    rgb = N.new("ShaderNodeRGB"); rgb.outputs[0].default_value = (*col, 1)
    return rgb.outputs[0]


def glow(name, col, strength, base=(0.02, 0.01, 0.0)):
    """An emissive surface (name it fxR_ / fxG_ for the game's glow groups)."""
    return simple(name, base, 0.3, emit=col, es=strength)


# ------------------------------------------------------------------ stage: backdrop, lights, camera, views
def stage(head=True):
    """head=False for full masks: the game leaves the wearer's head off under them."""
    w = bpy.data.worlds.new("w"); SC.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.006, 0.007, 0.01, 1)
    if os.environ.get("MASK_STUDIO", "1") == "1":  # metals need something to reflect: a soft studio sky seen only in reflections
        wn, wl = w.node_tree.nodes, w.node_tree.links
        lp = wn.new("ShaderNodeLightPath"); mix = wn.new("ShaderNodeMixShader"); sky = wn.new("ShaderNodeBackground")
        grad = wn.new("ShaderNodeTexGradient"); tc = wn.new("ShaderNodeTexCoord"); sep = wn.new("ShaderNodeSeparateXYZ")
        ramp = wn.new("ShaderNodeValToRGB")
        wl.new(tc.outputs["Generated"], sep.inputs[0]); wl.new(sep.outputs["Z"], ramp.inputs["Fac"])
        ramp.color_ramp.elements[0].color = (0.02, 0.022, 0.026, 1); ramp.color_ramp.elements[1].color = (0.5, 0.52, 0.56, 1)
        ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[1].position = 0.8
        wl.new(ramp.outputs["Color"], sky.inputs["Color"]); sky.inputs["Strength"].default_value = 1.0
        bgn = wn["Background"]
        wl.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
        wl.new(sky.outputs[0], mix.inputs[1]); wl.new(bgn.outputs[0], mix.inputs[2])
        wl.new(mix.outputs[0], wn["World Output"].inputs["Surface"])
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
    stand = simple("mannequin", (0.015, 0.015, 0.017), 0.8)
    if head:
        ball("stand_head", 1.0, (0, 0, 0), stand, (0.78, 0.95, 1.0), 40)
    cyl("stand_neck", 0.42, 1.2, (0, 0.1, -1.15), mat=stand, verts=40)
    s = ball("stand_shoulders", 1.0, (0, 0.2, -1.85), stand, (1.6, 0.85, 0.45), 48)
    _light("key", (3.2, -4.0, 3.6), 300, 2.5, (1.0, 0.9, 0.78))
    _light("fill", (-4.2, -3.0, 0.2), 90, 4.0, (0.6, 0.72, 1.0))
    _light("rim_l", (-2.8, 2.5, 2.4), 420, 1.5, (0.75, 0.85, 1.0))
    _light("rim_r", (2.8, 2.2, 1.8), 300, 1.5, (1.0, 0.85, 0.7))
    _light("back_key", (-3.0, 4.5, 2.2), 260, 2.5, (0.95, 0.9, 0.85), target=(0, 0.6, 0))
    _light("bd_glow", (0, 3.0, 0.5), 900, 6.0, (0.55, 0.62, 0.8), target=(0, 6, 0))
    return s


def _look(o, target):
    o.rotation_euler = (Vector(target) - o.location).to_track_quat("-Z", "Y").to_euler()


def _light(name, loc, power, size, col, target=(0, -0.6, 0.1)):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy, ld.size, ld.color = power, size, col
    o = link(bpy.data.objects.new(name, ld))
    o.location = loc
    _look(o, target)


def shoot_views(prefix):
    cd = bpy.data.cameras.new("cam"); cam = link(bpy.data.objects.new("cam", cd)); SC.camera = cam
    cd.dof.use_dof = True; cd.dof.aperture_fstop = 6.0
    views = {"34": ((3.6, -6.4, 0.9), (0.05, -0.6, 0.1), 62), "front": ((0.0, -7.6, 0.55), (0, -0.6, 0.12), 62),
             "side": ((-7.2, -0.6, 0.6), (0, -0.4, 0.05), 55), "back": ((-4.6, 5.2, 1.3), (0, 0.1, 0.05), 62)}
    pick = list(views) if VIEWS == "all" else VIEWS.split(",")
    for v in pick:
        loc, target, lens = views[v]
        cam.location = loc; _look(cam, target); cd.lens = lens
        cd.dof.focus_distance = (Vector(loc) - Vector((0, -0.6, 0.1))).length
        SC.render.filepath = os.path.join(OUT, "%s_%s.png" % (prefix, v))
        bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ signed distance sculpting (organic forms: skulls, animal heads)
# Each sd_* takes P = numpy array (..., 3) and returns distances (negative inside). Combine with smin / smax; turn into
# a mesh with sdf_mesh (marching cubes). Seams: groove() cuts a recessed line where a plane crosses the surface.
import numpy as np  # noqa: E402


def sd_ellipsoid(P, c, r):
    q = (P - np.array(c)) / np.array(r)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / np.array(r), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def sd_capsule(P, a, b, r):
    a, b = np.array(a, dtype=float), np.array(b, dtype=float)
    pa, ba = P - a, b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - r


def sd_box(P, c, half, round_r=0.0):
    q = np.abs(P - np.array(c)) - (np.array(half) - round_r)
    return np.linalg.norm(np.maximum(q, 0.0), axis=-1) + np.minimum(np.max(q, axis=-1), 0.0) - round_r


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):  # smooth subtraction: smax(a, -b, k) cuts b out of a
    return -smin(-a, -b, k)


def groove(d, plane_dist, depth=0.012, width=0.016, step=0.0):
    """A seam where a plane crosses the form: the surface sinks `depth` in a band `width` wide; one side is raised
    `step` (an overlapping plate)."""
    # (the step eases over ~1 cm: a hard switch made a beaded stair along the seam after marching cubes)
    return d + depth * np.exp(-(plane_dist / width) ** 2) - step * 0.5 * (1.0 + np.tanh(plane_dist / 0.005))


def sdf_mesh(name, fn, lo, hi, res=0.014, mat=None, relax=2):
    """Samples fn over the box lo..hi at `res` and makes the surface mesh (outward normals)."""
    from skimage import measure
    lo, hi = np.array(lo, dtype=float), np.array(hi, dtype=float)
    n = np.ceil((hi - lo) / res).astype(int) + 1
    xs, ys, zs = [np.linspace(lo[i], hi[i], n[i]) for i in range(3)]
    G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1)
    D = fn(G)
    verts, faces, normals, _ = measure.marching_cubes(D, 0.0, spacing=tuple((hi - lo) / (n - 1)))
    verts = verts + lo
    o = mesh_obj(name, [tuple(v) for v in verts], [tuple(f) for f in faces], mat)
    me = o.data
    me.update()
    cen = Vector(tuple(verts.mean(0)))
    step = max(len(me.polygons) // 400, 1)
    out = sum((Vector(me.polygons[i].center) - cen).dot(me.polygons[i].normal) for i in range(0, len(me.polygons), step))
    if out < 0:
        for p in me.polygons:
            p.flip()
        me.update()
    if relax > 0:
        m = o.modifiers.new("relax", "SMOOTH")
        m.factor, m.iterations = 0.5, relax
    return o


def ray_onto(o, origin, direction):
    """(location, normal) where a ray hits object `o` (evaluated), or (None, None)."""
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, n, i, ob, mw = SC.ray_cast(dg, Vector(origin), Vector(direction).normalized())
    return (loc, n) if hit and ob is not None and ob.name == o.name else (None, None)

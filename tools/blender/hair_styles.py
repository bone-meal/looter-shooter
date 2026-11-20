# Purpose: developer-time maker of the 10 new rigged hairstyles (polish1 item 6; runs in Blender's Python module
# `bpy`, never in the game). Each style is built twice, on the female and on the male base head of the CC0 Quaternius
# pack: a cap that follows the skull (rays from the head's middle find the scalp, the style says how thick the hair
# stands there and where its hairline runs), an optional drape that falls straight from the widest part of the head,
# and extras (ponytail, braid, buns, spikes, locks, a crest) as tapered tubes. Every piece hangs on the Head bone of
# that body's own skeleton, so the game's rigged_body.gd puts it on like the pack's own hairstyles. Also paints the
# strand texture the game tints with the chosen hair colour.
# Output: assets/models/hair/Hair_<Style>_<F|M>.gltf (+ .bin) and assets/models/hair/T_Hair_Strands.png.
# Run: python3 tools/blender/hair_styles.py [style ...]   (no names = all; "shots" also renders tools/shots/hair_*.png)
# Dependencies: pip packages bpy, numpy, pillow; assets/cc0/packs/universal_base_characters_standard/.
import math
import os
import sys

import bpy  # must come first: it brings bmesh and mathutils with it
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from PIL import Image

PACK = "assets/cc0/packs/universal_base_characters_standard/"
OUT = "assets/models/hair/"
BODIES = {"F": ("base_characters_godot_ue/Superhero_Female_FullBody.gltf", "Superhero_Female"),
          "M": ("base_characters_godot_ue/Superhero_Male_FullBody.gltf", "SuperHero_Male")}


# ---------- the strand texture (light grey strands; the game multiplies it by the hair colour) ----------

def strand_texture(path):
    rng = np.random.default_rng(7)
    w, h = 256, 512
    cols = rng.normal(size=w)
    for _ in range(3):  # strands a few pixels wide that drift along their length
        cols = (cols + np.roll(cols, 1) + np.roll(cols, -1)) / 3.0
    shade = np.zeros((h, w))
    drift = np.cumsum(rng.normal(size=h)) * 0.15
    for y in range(h):
        shade[y] = np.roll(cols, int(drift[y]))
    fine = rng.normal(size=(h, w))
    fine = (fine + np.roll(fine, 1, 0) + np.roll(fine, -1, 0) + np.roll(fine, 2, 0) + np.roll(fine, -2, 0)) / 5.0
    v = 0.78 + 0.16 * shade / (np.abs(shade).max() + 1e-9) + 0.06 * fine
    v = np.clip(v, 0.45, 1.0)
    img = (np.dstack([v, v * 0.98, v * 0.96]) * 255).astype(np.uint8)
    Image.fromarray(img).save(path)


# ---------- the head: measured from the base body ----------

class Head:
    def __init__(self, body):
        path, mesh_name = BODIES[body]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=PACK + path)
        self.objects = [o for o in bpy.data.objects if o not in before]
        self.armature = [o for o in self.objects if o.type == "ARMATURE"][0]
        body_obj = bpy.data.objects[mesh_name]
        group = body_obj.vertex_groups["Head"].index
        wm = body_obj.matrix_world
        verts = [wm @ v.co for v in body_obj.data.vertices]
        on_head = set()
        for v in body_obj.data.vertices:
            for g in v.groups:
                if g.group == group and g.weight > 0.3:
                    on_head.add(v.index)
        tris = []
        for p in body_obj.data.polygons:
            if all(i in on_head for i in p.vertices):
                vs = list(p.vertices)
                for k in range(1, len(vs) - 1):
                    tris.append((vs[0], vs[k], vs[k + 1]))
        self.bvh = BVHTree.FromPolygons(verts, tris)
        pts = [verts[i] for i in on_head]
        self.top = max(p.z for p in pts)
        eyes = [o for o in self.objects if o.name.startswith("Eyes")][0]
        box = [eyes.matrix_world @ Vector(c) for c in eyes.bound_box]
        self.eye = (min(b.z for b in box) + max(b.z for b in box)) * 0.5
        y_mid = (min(p.y for p in pts) + max(p.y for p in pts)) * 0.5
        self.center = Vector((0.0, y_mid + 0.01, self.eye + 0.01))
        self.radius = self.top - self.center.z

    # Where a ray from the head's middle meets the scalp (theta from straight up, phi round from the face).
    def scalp(self, theta, phi):
        d = Vector((math.sin(theta) * math.sin(phi), -math.sin(theta) * math.cos(phi), math.cos(theta)))
        hit = self.bvh.ray_cast(self.center, d, 0.5)
        if hit[0] is None:
            return self.center + d * self.radius * 0.92, d
        return hit[0], d

    def drop(self):
        for o in self.objects:
            if o != self.armature:
                bpy.data.objects.remove(o, do_unlink=True)


# ---------- geometry ----------

class Builder:
    def __init__(self):
        self.verts, self.faces, self.uvs = [], [], []

    def grid(self, rows, wrap):
        # rows = list of rows, each a list of (point, (u, v)); every row the same length
        base = len(self.verts)
        n = len(rows[0])
        for row in rows:
            for p, uv in row:
                self.verts.append(p)
                self.uvs.append(uv)
        for r in range(len(rows) - 1):
            for c in range(n if wrap else n - 1):
                c2 = (c + 1) % n
                a, b = base + r * n + c, base + r * n + c2
                d, e = base + (r + 1) * n + c, base + (r + 1) * n + c2
                self.faces.append((a, b, e, d))

    def tube(self, points, radii, flat=1.0, sides=8, twist=0.0, uv_scale=3.0):
        # a tapered tube along points (radius per point), flattened sideways by `flat` (1 = round)
        rows = []
        up = Vector((0, 0, 1))
        length = 0.0
        for i, p in enumerate(points):
            if i > 0:
                length += (p - points[i - 1]).length
            ahead = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
            side = ahead.cross(up)
            if side.length < 1e-4:
                side = Vector((1, 0, 0))
            side.normalize()
            normal = side.cross(ahead).normalized()
            row = []
            for s in range(sides + 1):
                a = s / sides * math.tau + twist * i
                off = side * math.cos(a) * radii[i] * flat + normal * math.sin(a) * radii[i]
                row.append((p + off, (s / sides, length * uv_scale)))
            rows.append(row)
        self.grid(rows, False)
        tip = points[-1] + (points[-1] - points[-2]).normalized() * radii[-1]
        base = len(self.verts)
        self.verts.append(tip)
        self.uvs.append((0.5, length * uv_scale))
        last = base - (sides + 1)
        for s in range(sides):
            self.faces.append((last + s, last + s + 1, base))

    def blob(self, at, size, seed=0, rough=0.08):
        # an ellipsoid (a bun) with lumpy strands
        rng = np.random.default_rng(seed)
        rows = []
        bumps = rng.normal(size=8)
        for i in range(10):
            th = i / 9 * math.pi
            row = []
            for j in range(17):
                ph = j / 16 * math.tau
                lump = 1.0 + rough * math.sin(3 * ph + bumps[0]) * math.sin(2 * th + bumps[1])
                d = Vector((math.sin(th) * math.cos(ph) * size[0], math.sin(th) * math.sin(ph) * size[1], math.cos(th) * size[2])) * lump
                row.append((at + d, (j / 16 * 2.0, i / 9 * 2.0)))
            rows.append(row)
        self.grid(rows, False)


def smooth(edge0, edge1, x):
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def front_ness(phi):
    # 1 at the face, 0 at the back of the head
    return (math.cos(phi) + 1.0) * 0.5


def cap(b, head, hairline, thick, drape=None, cols=64, rows=22, drape_rows=10, grooves=0.18):
    # The hair over the skull: rows from the crown (theta 0) to the hairline (theta_max(phi)), standing thick(t, phi)
    # metres off the scalp; drape(phi) = (metres it falls below the cap's end, tuck inward 0..1) for hair that hangs.
    grid = []
    ends = []
    rng = np.random.default_rng(cols * 31 + rows)
    wisps = rng.normal(size=cols) * math.radians(2.2)  # an uneven hairline, not a ruled edge
    for r in range(rows + 1):
        t = r / rows
        row = []
        for c in range(cols):
            phi = c / cols * math.tau
            theta = t * (hairline(phi) + wisps[c] * smooth(0.6, 1.0, t))
            p, d = head.scalp(max(theta, 0.001), phi)
            clump = 1.0 + grooves * smooth(0.08, 0.3, t) * (0.6 * math.sin(c * math.pi * 0.5) + 0.4 * math.sin(c * 1.7 + t * 3.0))  # strand clumps from the crown out
            p = p + d * thick(t, phi) * clump
            row.append((p, (c / cols * 6.0, t * 2.2)))
            if r == rows:
                ends.append((p, phi))
        grid.append(row)
    if drape is not None:
        for k in range(1, drape_rows + 1):
            f = k / drape_rows
            row = []
            for c, (p, phi) in enumerate(ends):
                length, tuck = drape(phi)
                flat = Vector((p.x - head.center.x, p.y - head.center.y, 0.0))
                inward = flat * (-tuck * f * f)
                row.append((Vector((p.x, p.y, p.z - length * f)) + inward, (c / cols * 6.0, 2.2 + length * f * 8.0)))
            grid.append(row)
    b.grid(grid, True)


def scalp_point(head, theta_deg, phi_deg, lift=0.0):
    p, d = head.scalp(math.radians(theta_deg), math.radians(phi_deg))
    return p + d * lift, d


def hang(start, out, length, steps=10, swing=0.0):
    # a lock that leaves the head along `out`, then falls under its own weight
    pts = []
    p = Vector(start)
    v = Vector(out).normalized() * (length / steps) * 1.4
    for i in range(steps + 1):
        pts.append(p.copy())
        v = (v + Vector((swing * 0.002, 0, -length / steps * 0.45))).normalized() * (length / steps)
        p = p + v
    return pts


# ---------- the styles (each: def style(b, head)) ----------

def hairline_full(head, front=60.0, side=88.0, back=128.0):
    def f(phi):
        a = abs(((phi + math.pi) % math.tau) - math.pi)  # 0 at the face .. pi at the back
        deg = front + (side - front) * smooth(0.0, math.pi / 2, a) + (back - side) * smooth(math.pi / 2, math.pi, a)
        return math.radians(deg)
    return f


def edge_taper(t, keep=0.0):
    return keep + (1.0 - keep) * (1.0 - smooth(0.82, 1.0, t))


def ponytail(b, head):
    cap(b, head, hairline_full(head), lambda t, phi: 0.004 + 0.009 * edge_taper(t) * (0.7 + 0.3 * front_ness(phi)))
    root, d = scalp_point(head, 108, 180, 0.012)
    pts = hang(root, Vector((0, 1.0, 0.25)), 0.30, 12)
    radii = [0.030 * (1.0 - 0.75 * (i / (len(pts) - 1)) ** 1.3) + 0.004 for i in range(len(pts))]
    radii[0] = 0.024
    b.tube(pts, radii, flat=0.8, sides=10)
    b.tube([root - Vector((0, 0.006, 0)), root + Vector((0, 0.012, -0.004))], [0.026, 0.026], sides=10)  # the hair tie


def braid(b, head):
    cap(b, head, hairline_full(head), lambda t, phi: 0.004 + 0.008 * edge_taper(t))
    root, d = scalp_point(head, 112, 180, 0.01)
    path = hang(root, Vector((0, 0.6, -0.6)), 0.36, 14)
    for i in range(len(path) - 1):  # plaited lobes left and right
        p, q = path[i], path[i + 1]
        mid = (p + q) * 0.5
        side = Vector((0.010 if i % 2 else -0.010, 0, 0))
        r = 0.022 * (1.0 - 0.55 * i / len(path))
        b.blob(mid + side, (r * 1.05, r * 0.9, (q - p).length * 0.72), seed=i, rough=0.05)
    b.tube([path[-1], path[-1] + Vector((0, 0.01, -0.06))], [0.012, 0.004], sides=8)


def bob(b, head):
    def line(phi):
        a = abs(((phi + math.pi) % math.tau) - math.pi)
        return math.radians(62 + 44 * smooth(0.3, 1.0, a))  # bangs to the brow, then the widest part of the head
    def thick(t, phi):
        return 0.008 + 0.014 * smooth(0.0, 0.6, t)
    def drape(phi):
        a = abs(((phi + math.pi) % math.tau) - math.pi)
        return (0.12 * smooth(0.6, 1.1, a), 0.25)
    cap(b, head, line, thick, drape)


def pixie(b, head):
    cap(b, head, hairline_full(head, 62, 84, 118), lambda t, phi: 0.003 + (0.016 - 0.009 * (1 - front_ness(phi))) * edge_taper(t))
    for i in range(7):  # a fringe swept to the right
        root, d = scalp_point(head, 30 + i * 3, -25 + i * 8, 0.012)
        tip = root + Vector((0.035 + i * 0.004, -0.03, -0.035))
        b.tube([root, (root + tip) * 0.5 + Vector((0, -0.012, 0.004)), tip], [0.012, 0.009, 0.002], flat=1.6, sides=6)


def mohawk(b, head):
    cap(b, head, hairline_full(head), lambda t, phi: 0.0025 * edge_taper(t, 0.3))
    for i in range(16):  # the crest from the forehead to the nape
        theta = -60 + i * 10.5
        phi = 0 if theta < 0 else 180
        root, d = scalp_point(head, abs(theta), phi, 0.0)
        height = 0.065 * (1.0 - abs(i - 5) / 16.0)
        tip = root + d * height + Vector((0, 0.02, 0))
        b.tube([root - d * 0.004, root + d * height * 0.5, tip], [0.022, 0.016, 0.002], flat=0.55, sides=6)


def afro(b, head):
    def thick(t, phi):
        return (0.05 + 0.006 * math.sin(phi * 9) * math.sin(t * 11)) * (0.45 + 0.55 * smooth(0.0, 0.3, t)) * edge_taper(t, 0.25) + 0.004
    cap(b, head, hairline_full(head, 62, 92, 122), thick, cols=72, rows=26, grooves=0.05)


def top_knot(b, head):
    cap(b, head, hairline_full(head), lambda t, phi: 0.004 + 0.007 * edge_taper(t))
    root, d = scalp_point(head, 18, 180, 0.0)
    b.blob(root + d * 0.035, (0.042, 0.042, 0.036), seed=3)
    b.tube([root - d * 0.002, root + d * 0.012], [0.022, 0.022], sides=10)  # the band under the bun


def undercut(b, head):
    def thick(t, phi):  # long on top, swept back (fuller at the front), clipped short below a line
        top = 1.0 - smooth(0.44, 0.56, t)
        return 0.0025 + 0.026 * top * (0.55 + 0.45 * front_ness(phi)) * (0.8 + 0.2 * smooth(0.0, 0.3, t))
    cap(b, head, hairline_full(head, 58, 86, 120), thick, grooves=0.28)


def dreadlocks(b, head):
    cap(b, head, hairline_full(head), lambda t, phi: 0.004 + 0.008 * edge_taper(t))
    rng = np.random.default_rng(11)
    for i in range(28):
        theta = 55 + rng.uniform(0, 70)
        phi = rng.uniform(60, 300)
        root, d = scalp_point(head, theta, phi, 0.006)
        length = 0.16 + rng.uniform(0, 0.08)
        pts = hang(root, d * 0.35 + Vector((0, 0.15, -1.0)), length, 8)
        b.tube(pts, [0.009 - 0.004 * k / 8 for k in range(9)], sides=6, twist=0.6)


def curtains(b, head):
    def line(phi):
        a = abs(((phi + math.pi) % math.tau) - math.pi)
        return math.radians(70 + 36 * smooth(0.25, 0.9, a))
    def thick(t, phi):
        part = smooth(0.0, 0.25, abs(((phi + math.pi) % math.tau) - math.pi))  # the middle parting
        return 0.004 + 0.014 * smooth(0.0, 0.5, t) * (0.35 + 0.65 * part)
    def drape(phi):
        a = abs(((phi + math.pi) % math.tau) - math.pi)
        return (0.19 * smooth(0.35, 0.9, a), 0.15)
    cap(b, head, line, thick, drape)


STYLES = {"Ponytail": ponytail, "Braid": braid, "Bob": bob, "Pixie": pixie, "Mohawk": mohawk, "Afro": afro,
          "TopKnot": top_knot, "Undercut": undercut, "Dreadlocks": dreadlocks, "Curtains": curtains}


# ---------- export ----------

def make_object(b, name, head):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in b.verts], [], b.faces)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = b.uvs[vi]
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.validate()
    mat = bpy.data.materials.get("MI_Hair_Strands") or bpy.data.materials.new("MI_Hair_Strands")
    mat.use_backface_culling = False
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.06, 0.035, 0.02, 1.0)  # the test pictures only
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = obj.vertex_groups.new(name="Head")
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    obj.parent = head.armature
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = head.armature
    return obj


def export(obj, head, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    head.armature.select_set(True)
    bpy.context.view_layer.objects.active = head.armature
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_skins=True,
                              export_animations=False, export_materials="PLACEHOLDER", export_apply=False)


view_turn = [0.0]  # degrees the test camera stands round the head (0 = in front)


def shot(objs, path, head):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"  # (the workbench needs a display; Cycles renders headless on the CPU)
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.render.resolution_x, scene.render.resolution_y = 300, 300
    if "sun" not in bpy.data.objects:
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 4.0
        sun.rotation_euler = (math.radians(50), 0, math.radians(30))
        scene.collection.objects.link(sun)
        world = bpy.data.worlds.new("w")
        world.color = (0.5, 0.5, 0.55)
        scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.42
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    turn = math.radians(view_turn[0])
    cam.location = Vector((math.sin(turn) * 1.5, -math.cos(turn) * 1.5, head.center.z - 0.04))
    cam.rotation_euler = (math.radians(90), 0, turn)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    wanted = [a for a in sys.argv[1:] if a in STYLES] or list(STYLES)
    shots = "shots" in sys.argv[1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    strand_texture(OUT + "T_Hair_Strands.png")
    for body in BODIES:
        head = Head(body)
        made = []
        for name in wanted:
            b = Builder()
            STYLES[name](b, head)
            obj = make_object(b, "Hair_%s" % name, head)
            export(obj, head, OUT + "Hair_%s_%s.gltf" % (name, body))
            made.append(obj)
            print("HAIR %s %s: %d verts, %d faces" % (name, body, len(b.verts), len(b.faces)))
        if shots:  # each style on the head, side by side: front and side views
            os.makedirs("tools/shots", exist_ok=True)
            for obj in made:
                for o in made:
                    o.hide_render = o != obj
                for view, rot in (("front", 0.0), ("side", 90.0), ("back", 180.0)) if body == "F" else (("side", 90.0),):
                    view_turn[0] = rot
                    shot(made, "tools/shots/hair_%s_%s_%s.png" % (obj.name[5:], body, view), head)
        for obj in made:
            bpy.data.objects.remove(obj, do_unlink=True)
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    print("HAIR_DONE")


main()

# Purpose: developer-time modelling kit (runs in Blender's Python module `bpy`, never in the game). Builds detailed
# models from side profiles, tubes and plates with bevelled edges, box-mapped UVs and shared PBR textures made here
# with numpy, and exports glTF files the game loads. Shapes are written in GUN SPACE: x = right, y = up, f = forward
# (the game's -Z), in the same model units as the old code-built models so sights and hold positions still fit.
# Dependencies: pip packages bpy, numpy, pillow. Used by tools/blender/weapons.py, weapon_parts.py, creatures.py, wasteland.py.
import math
import os

import bpy  # must come first: it brings bmesh and mathutils with it
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

TEX = 512


# ---------- textures (tileable: filtered noise made in frequency space) ----------

def _noise(seed, falloff, stretch=1.0):
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(TEX)[:, None] * stretch
    fx = np.fft.fftfreq(TEX)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)
    radius[0, 0] = 1.0
    spectrum = (rng.normal(size=(TEX, TEX)) + 1j * rng.normal(size=(TEX, TEX))) / radius ** falloff
    spectrum[0, 0] = 0
    field = np.real(np.fft.ifft2(spectrum))
    return (field - field.mean()) / (field.std() + 1e-9)


def _normal_map(height, strength):
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def _save(path, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(path)


# kinds: "metal" (brushed, worn), "paint" (matte painted metal), "polymer", "matte", "wood", "fabric", "hide", "scrap".
# Returns the three file paths.
def make_textures(folder, name, kind, color, seed):
    os.makedirs(folder, exist_ok=True)
    base = np.array(color, dtype=float)[None, None, :]
    blotch = _noise(seed, 1.6)
    if kind == "wood":
        v = np.linspace(0, 1, TEX, endpoint=False)[:, None] * np.ones((1, TEX))
        grain = np.sin((v * 7.0 + 0.22 * _noise(seed + 1, 2.6, 5.0)) * 2 * math.pi)
        fibre = _noise(seed + 2, 1.4, 14.0)
        shade = 0.5 + 0.5 * grain
        albedo = base * (0.86 + 0.22 * shade[..., None]) * (1.0 + 0.03 * fibre[..., None])
        rough = 0.5 + 0.1 * shade + 0.02 * fibre
        metal = np.zeros_like(rough)
        height = 0.5 * grain + 0.2 * fibre
        strength = 0.35
    elif kind == "matte":  # bone, plaster: soft uneven surface, no sparkle
        lumps = _noise(seed + 1, 1.7)
        albedo = base * (1.0 - 0.1 * np.clip(blotch, 0, 2)[..., None])
        rough = 0.72 + 0.05 * blotch
        metal = np.zeros_like(rough)
        height = lumps
        strength = 0.6
    elif kind == "fabric":  # woven cloth with grime and soft folds
        u = np.linspace(0, 1, TEX, endpoint=False)
        weave = np.sin(u[None, :] * 64 * 2 * math.pi) * np.sin(u[:, None] * 64 * 2 * math.pi)
        folds = _noise(seed + 4, 2.6, 2.5)
        stains = np.clip(_noise(seed + 3, 2.4) - 0.7, 0, 1.5)
        albedo = base * (0.94 + 0.02 * weave[..., None] + 0.05 * blotch[..., None] - 0.16 * stains[..., None])
        rough = 0.86 + 0.02 * weave - 0.05 * stains
        metal = np.zeros_like(rough)
        height = 0.1 * weave + 2.0 * folds
        strength = 0.3
    elif kind == "hide":  # skin and leather: mottled, pores, fine creases
        mottle = _noise(seed + 1, 1.9)
        pores = _noise(seed + 2, 0.9)
        creases = _noise(seed + 5, 1.5, 3.0)
        albedo = base * (0.95 + 0.05 * blotch[..., None] - 0.07 * np.clip(mottle, 0, 2)[..., None])
        rough = 0.62 + 0.05 * mottle
        metal = np.zeros_like(rough)
        height = 0.6 * mottle + 0.12 * pores + 0.5 * creases
        strength = 0.3
    elif kind == "scrap":  # worn sheet metal with rust patches
        scratch = _noise(seed + 1, 1.3, 0.05)
        rust = np.clip(_noise(seed + 3, 2.0) * 0.8 + 0.1, 0, 1)
        albedo = base * (1.0 + 0.05 * scratch[..., None]) * (1.0 - 0.28 * rust[..., None]) + rust[..., None] * np.array([0.14, 0.06, 0.02])[None, None, :]
        rough = 0.45 + 0.3 * rust + 0.05 * scratch
        metal = 0.35 - 0.25 * rust  # mostly paint and rust: full metal turned black wherever the sky reflection is dark
        height = 0.4 * scratch + 0.8 * rust + 0.15 * _noise(seed + 2, 1.0)
        strength = 0.3
    elif kind == "polymer":
        speck = _noise(seed + 1, 1.1)  # soft grain; white noise here sparkled on black parts
        albedo = base * (1.0 + 0.04 * blotch[..., None])
        rough = 0.6 + 0.04 * blotch
        metal = np.zeros_like(rough)
        height = speck
        strength = 0.12
    else:
        scratch = _noise(seed + 1, 1.3, 0.05)  # long streaks along u
        wear = np.clip(_noise(seed + 3, 2.2) - 1.7, 0, 1)  # a few soft worn patches
        albedo = base * (1.0 + 0.04 * blotch[..., None] + 0.03 * scratch[..., None]) + 0.1 * wear[..., None]
        rough = (0.42 if kind == "metal" else 0.66) + 0.05 * blotch + 0.05 * scratch - 0.1 * wear
        metal = np.full_like(rough, 1.0 if kind == "metal" else 0.2) + (0.6 * wear if kind == "paint" else 0)
        height = 0.4 * scratch + 0.1 * _noise(seed + 2, 1.0)
        strength = 0.15
    paths = [os.path.join(folder, "%s_%s.png" % (name, part)) for part in ("albedo", "orm", "normal")]
    _save(paths[0], albedo)
    _save(paths[1], np.dstack([np.ones_like(rough), rough, metal]))
    _save(paths[2], _normal_map(height, strength))
    return paths


def material(name, paths, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    if paths is None:  # plain colour (lenses)
        bsdf.inputs["Base Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.08
        bsdf.inputs["Metallic"].default_value = 0.6
        return mat
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = bpy.data.images.load(paths[0])
    links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
    orm = nodes.new("ShaderNodeTexImage")
    orm.image = bpy.data.images.load(paths[1])
    orm.image.colorspace_settings.name = "Non-Color"
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(orm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(paths[2])
    normal.image.colorspace_settings.name = "Non-Color"
    bump = nodes.new("ShaderNodeNormalMap")
    links.new(normal.outputs["Color"], bump.inputs["Color"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ---------- geometry ----------

# Per-corner colours of colored models: False = a byte layer (the glTF export turns it from screen colours into linear
# light), True = a float layer (written to the file exactly as given). tools/blender/fantasy_kit.py switches it on.
FLOAT_COLORS = False


class Model:
    """One exported file. Parts are added in gun space and collected per node (default node "Body")."""

    # colored=True: a part's material may be given as (material, (r, g, b)); the colour is stored per corner and
    # multiplies the texture in the game, so many differently coloured parts share one material (one draw call).
    def __init__(self, name, uv_scale=4.0, colored=False):
        self.name = name
        self.uv_scale = uv_scale
        self.colored = colored
        self.nodes = {}  # node name -> [bmesh, [materials]]
        self.empties = []
        self.tree = {}  # node name -> (pivot in Blender space, parent name): jointed parts the game turns

    # Declares a jointed part: its parts are still written in model space; the game turns it about `pivot`.
    def node(self, name, pivot=(0.0, 0.0, 0.0), parent=None):
        self.tree[name] = (Vector((pivot[0], pivot[2], pivot[1])), parent)

    def _add(self, bm, mat, node, bevel, rim_only=False):
        color = (1.0, 1.0, 1.0)
        if isinstance(mat, tuple):
            mat, color = mat
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if bevel > 0:
            edges = bm.edges[:]
            if rim_only:  # tubes: round only the two end rims
                edges = list({e for face in bm.faces if len(face.verts) > 4 for e in face.edges})
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
        bm.normal_update()
        target, mats = self.nodes.setdefault(node, [bmesh.new(), []])
        if mat not in mats:
            mats.append(mat)
        uv = bm.loops.layers.uv.verify()
        target.loops.layers.uv.verify()
        s = self.uv_scale
        layers = bm.loops.layers.float_color if FLOAT_COLORS else bm.loops.layers.color
        paint = layers.verify() if self.colored else None
        if self.colored:
            (target.loops.layers.float_color if FLOAT_COLORS else target.loops.layers.color).verify()
        for face in bm.faces:
            face.material_index = mats.index(mat)
            face.smooth = True
            n = face.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            for loop in face.loops:
                if paint is not None:
                    loop[paint] = (color[0], color[1], color[2], 1.0)
                c = loop.vert.co
                loop[uv].uv = (c.y * s, c.z * s) if axis == 0 else ((c.y * s, c.x * s) if axis == 2 else (c.x * s, c.z * s))
        mesh = bpy.data.meshes.new("part")
        bm.to_mesh(mesh)
        bm.free()
        target.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    # Side profile [(f, y), ...] made `w` thick across x. across="f": front profile [(x, y), ...] made `w` thick along f.
    def prof(self, mat, w, pts, x=0.0, bevel=0.006, node="Body", across="x"):
        bm = bmesh.new()
        if across == "x":
            face = bm.faces.new([bm.verts.new((x - w / 2, f, y)) for f, y in pts])
        else:
            face = bm.faces.new([bm.verts.new((px, x - w / 2, y)) for px, y in pts])
        made = bmesh.ops.extrude_face_region(bm, geom=[face])
        bmesh.ops.translate(bm, verts=[v for v in made["geom"] if isinstance(v, bmesh.types.BMVert)], vec=(w, 0, 0) if across == "x" else (0, w, 0))
        self._add(bm, mat, node, bevel)

    # Ellipsoid with radii (x, y, f) at (x, y, f); yaw turns it about the up axis, pitch about the x axis (degrees).
    def ball(self, mat, radii, at, node="Body", yaw=0.0, pitch=0.0, u=12, v=8):
        if isinstance(radii, (int, float)):
            radii = (radii, radii, radii)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0, matrix=Matrix.Translation((at[0], at[2], at[1]))
            @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "X") @ Matrix.Diagonal((radii[0], radii[2], radii[1], 1.0)))
        self._add(bm, mat, node, 0)

    # Round bar from p0 to p1, both (x, y, f); r2 = radius at p1.
    def rod(self, mat, r, p0, p1, r2=None, node="Body", segs=8):
        a, b = Vector((p0[0], p0[2], p0[1])), Vector((p1[0], p1[2], p1[1]))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=(b - a).length,
            matrix=Matrix.Translation((a + b) / 2) @ Vector((0, 0, 1)).rotation_difference(b - a).to_matrix().to_4x4())
        self._add(bm, mat, node, 0)

    # A bone: bar with a knob at each end.
    def bone(self, mat, r, p0, p1, node="Body", knob=1.7):
        self.rod(mat, r, p0, p1, node=node)
        for p in (p0, p1):
            self.ball(mat, r * knob, p, node=node, u=8, v=6)

    # Turned shape: profile [(radius, height), ...] spun about the up axis at (x, y, f); squash flattens it front to back.
    # axis="f": heights run forward instead and squash flattens it top to bottom.
    def lathe(self, mat, profile, at, node="Body", segs=20, squash=1.0, axis="y"):
        bm = bmesh.new()
        rings = [[bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * squash * math.sin(2 * math.pi * i / segs), h)) for i in range(segs)] for r, h in profile]
        for low, high in zip(rings, rings[1:]):
            for i in range(segs):
                bm.faces.new((low[i], low[(i + 1) % segs], high[(i + 1) % segs], high[i]))
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
        turn = Matrix.Translation((at[0], at[2], at[1]))
        if axis == "f":
            turn = turn @ Matrix.Rotation(math.radians(-90), 4, "X")
        bmesh.ops.transform(bm, matrix=turn, verts=bm.verts[:])
        self._add(bm, mat, node, 0)

    # Organic limb or trunk: a smooth curve through rings [(x, y, f, r1, r2), ...] skinned with `segs` sides and closed
    # with rounded ends. r1 = half-width across x; r2 = the half-size the other way (front to back for upright parts,
    # up and down for parts lying along f). steps = rings fitted between two given ones. flat=True: plain flat ends
    # (bands and sleeves worn around something; a rounded end is as long as the part is thick).
    def loft(self, mat, rings, node="Body", segs=12, steps=3, flat=False):
        keys = [(Vector((r[0], r[2], r[1])), r[3], r[4]) for r in rings]
        path = []
        for i in range(len(keys) - 1):
            a, b, c, d = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]
            for k in range(steps):
                t = k / steps
                w = (-0.5 * t ** 3 + t * t - 0.5 * t, 1.5 * t ** 3 - 2.5 * t * t + 1.0, -1.5 * t ** 3 + 2.0 * t * t + 0.5 * t, 0.5 * t ** 3 - 0.5 * t * t)
                path.append(tuple(sum((q[j] * w[n] for n, q in enumerate((a, b, c, d))), Vector((0, 0, 0)) if j == 0 else 0.0) for j in range(3)))
        path.append(keys[-1])
        bm = bmesh.new()
        made = []
        side = None
        for i, (at, r1, r2) in enumerate(path):
            t = (path[min(i + 1, len(path) - 1)][0] - path[max(i - 1, 0)][0]).normalized()
            if side is None:
                side = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
            side = (side - t * side.dot(t)).normalized()  # carried along the curve, so the skin never twists
            other = t.cross(side)
            shapes = [(0.0, 1.0)]
            if not flat and (i == 0 or i == len(path) - 1):  # rounded end: two shrinking rings pushed outwards
                out = -1.0 if i == 0 else 1.0
                shapes = [(0.0, 1.0), (out * 0.5, 0.82), (out * 0.85, 0.45)] if i else [(out * 0.85, 0.45), (out * 0.5, 0.82), (0.0, 1.0)]
            for push, size in shapes:
                c = at + t * (push * min(r1, r2))
                made.append([bm.verts.new(c + side * (max(r1, 0.002) * size * math.cos(2 * math.pi * k / segs)) + other * (max(r2, 0.002) * size * math.sin(2 * math.pi * k / segs))) for k in range(segs)])
        for low, high in zip(made, made[1:]):
            for k in range(segs):
                bm.faces.new((low[k], low[(k + 1) % segs], high[(k + 1) % segs], high[k]))
        bm.faces.new(made[0][::-1])
        bm.faces.new(made[-1])
        self._add(bm, mat, node, 0)

    # Tube along the barrel direction from f0 to f1 (r2 = other end radius for cones).
    def cyl(self, mat, r, f0, f1, y=0.0, x=0.0, segs=20, bevel=0.003, r2=None, node="Body"):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=abs(f1 - f0),
            matrix=Matrix.Translation((x, (f0 + f1) / 2, y)) @ Matrix.Rotation(math.radians(-90), 4, "X"))
        self._add(bm, mat, node, bevel, True)

    # Tube across the gun (pins, drums, knobs) from x0 to x1.
    def cylx(self, mat, r, x0, x1, f, y, segs=14, bevel=0.002, node="Body"):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=abs(x1 - x0),
            matrix=Matrix.Translation(((x0 + x1) / 2, f, y)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
        self._add(bm, mat, node, bevel, True)

    # Block of size (sx, sy, sf) centred at (x, y, f), tilted about the x axis (degrees).
    def box(self, mat, size, at, tilt=0.0, bevel=0.004, node="Body"):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((at[0], at[2], at[1])) @ Matrix.Rotation(math.radians(tilt), 4, "X")
            @ Matrix.Diagonal((size[0], size[2], size[1], 1.0)))
        self._add(bm, mat, node, bevel)

    # Bent plate following a side path [(f, y), ...]: trigger guards, handles, slings.
    def strip(self, mat, w, t, pts, x=0.0, node="Body"):
        for (f0, y0), (f1, y1) in zip(pts, pts[1:]):
            length = math.hypot(f1 - f0, y1 - y0)
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((x, (f0 + f1) / 2, (y0 + y1) / 2))
                @ Matrix.Rotation(math.atan2(y1 - y0, f1 - f0), 4, "X") @ Matrix.Diagonal((w, length + t, t, 1.0)))
            self._add(bm, mat, node, min(t, w) * 0.3)

    # A marker point; `parent` = the jointed part it moves with.
    def empty(self, name, x, y, f, parent=None):
        self.empties.append((name, Vector((x, f, y)), parent))

    def export(self, folder):
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj)
        scene = bpy.context.scene
        triangles = 0
        made = {}
        for node in list(self.nodes) + [n for n in self.tree if n not in self.nodes]:
            pivot = self.tree.get(node, (Vector((0, 0, 0)), None))[0]
            mesh = None
            if node in self.nodes:
                bm, mats = self.nodes[node]
                bmesh.ops.translate(bm, verts=bm.verts[:], vec=-pivot)
                bmesh.ops.triangulate(bm, faces=bm.faces[:])
                triangles += len(bm.faces)
                mesh = bpy.data.meshes.new(node)
                bm.to_mesh(mesh)
                bm.free()
                for mat in mats:
                    mesh.materials.append(mat)
                if self.colored and len(mesh.color_attributes):  # the exporter only writes the colour set marked active
                    mesh.color_attributes.active_color = mesh.color_attributes[0]
                    mesh.color_attributes.render_color_index = 0
                mesh.set_sharp_from_angle(angle=math.radians(38))
            made[node] = bpy.data.objects.new(node, mesh)
            scene.collection.objects.link(made[node])
        for node, obj in made.items():
            pivot, parent = self.tree.get(node, (Vector((0, 0, 0)), None))
            obj.location = pivot - (self.tree[parent][0] if parent else Vector((0, 0, 0)))
            if parent:
                obj.parent = made[parent]
        for name, at, parent in self.empties:
            marker = bpy.data.objects.new(name, None)
            marker.location = at - (self.tree[parent][0] if parent else Vector((0, 0, 0)))
            if parent:
                marker.parent = made[parent]
            scene.collection.objects.link(marker)
        os.makedirs(folder, exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(folder, self.name + ".gltf"), export_format="GLTF_SEPARATE",
            export_keep_originals=True, export_apply=True, export_yup=True, export_vertex_color="ACTIVE" if self.colored else "MATERIAL")
        return triangles

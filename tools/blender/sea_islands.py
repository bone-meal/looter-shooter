# Purpose: developer-time tool. Builds the four TEST islands of sea step 4 (assets/models/sea/isle_*.glb: tiny, small,
# medium, large) so streaming, foam and the look can be judged before the hand-made islands of step 13: a shore
# that slopes under the water (the ocean's depth foam needs it), sand, grass, rock on steep ground, a peak.
# Run: python3 tools/blender/sea_islands.py   (bpy 4.x/5.x as a module)
# Dependencies: bpy, bmesh. No game code.
import math
import os
import random

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "sea")

SAND = (0.86, 0.78, 0.56)
WET = (0.62, 0.55, 0.4)
GRASS = (0.36, 0.58, 0.28)
DARK_GRASS = (0.26, 0.45, 0.22)
ROCK = (0.5, 0.48, 0.45)

# id: (radius m, peak m, roughness, seed)
ISLANDS = {"isle_tiny": (14.0, 3.0, 0.15, 1), "isle_small": (55.0, 14.0, 0.25, 2), "isle_medium": (160.0, 42.0, 0.35, 3), "isle_large": (420.0, 120.0, 0.4, 4)}


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1.0,)


def height(x, z, radius, peak, rough, rnd):
    d = math.hypot(x, z) / radius
    wobble = 1.0 + rough * 0.25 * (math.sin(math.atan2(z, x) * 3 + rnd[0]) + 0.6 * math.sin(math.atan2(z, x) * 7 + rnd[1]))
    d /= wobble
    if d > 1.0:  # the shelf going down under the sea
        return -6.0 * min((d - 1.0) / 0.35, 1.0) - 0.4
    core = (1.0 - d * d) ** 1.6
    bumps = rough * (math.sin(x / radius * 9 + rnd[2]) * math.cos(z / radius * 7 + rnd[3])) * 0.18
    return max(core + bumps, 0.0) * peak - 0.4 + 1.2 * (1.0 - d)


def build(name, radius, peak, rough, seed):
    rnd = [random.Random(seed).uniform(0, 6.28) for _ in range(4)]
    random.seed(seed)
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    n = 96 if radius > 100 else 48
    reach = radius * 1.45
    verts = {}
    for i in range(n + 1):
        for j in range(n + 1):
            x = (i / n * 2 - 1) * reach
            z = (j / n * 2 - 1) * reach
            if math.hypot(x, z) > reach * 1.02:
                continue
            verts[(i, j)] = bm.verts.new((x, -z, height(x, z, radius, peak, rough, rnd)))
    for i in range(n):
        for j in range(n):
            q = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]  # wound so the faces look up
            if all(k in verts for k in q):
                bm.faces.new([verts[k] for k in q])
    bm.normal_update()
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for loop in f.loops:
            v = loop.vert
            h = v.co.z
            steep = 1.0 - v.normal.z
            if h < 0.3:
                c = WET
            elif h < 1.8:
                c = SAND
            elif steep > 0.45:
                c = ROCK
            else:
                c = GRASS if (int(v.co.x * 0.2) + int(v.co.y * 0.2)) % 3 else DARK_GRASS
            loop[layer] = c + (1.0,)  # sRGB values: the colour layer stores them as sRGB and glTF writes them linear
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    mesh.materials.append(mat)
    return obj


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (radius, peak, rough, seed) in ISLANDS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = build(name, radius, peak, rough, seed)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), use_selection=True, export_format="GLB")
        print(name, len(obj.data.vertices))


main()

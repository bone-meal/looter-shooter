# Purpose: developer-time tool. The sea's ISLAND KIT (director: a kit + one hand-designed start island): what every
# island script shares, so a new island is only its height function and its own hand-placed bits.
#   ground(name, land, reach, cells, trodden)  the ground mesh from a height function, painted for game/isle_ground.gd:
#       vertex colour = light / dark patches, UV = (grass, rock) weights, UV2 = (wet shore, trodden) weights
#       (glTF stores v flipped; the shader flips it back)
#   scatter(land, reach, seed, clear, density) the props by readable rules: palms on the beach crest, shells, coconuts
#       and driftwood on the sand, bushes and ferns inland, grass tufts, boulders on steep ground and the tideline
#   save(name, obj, props)  writes assets/models/sea/<name>.glb and data/sea/isles/<name>.json
# Prop models: tools/blender/sea_isle_props.py. Used by sea_isle_start.py and sea_islands.py.
# Dependencies: bpy, bmesh. No game code.
import json
import math
import os
import random

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "sea")
PROPS_OUT = os.path.join(ROOT, "data", "sea", "isles")
SOLID = {"palm_a": 0.3, "palm_b": 0.3, "boulder_a": 1.0, "boulder_b": 2.0, "boulder_c": 0.5, "sea_stack": 4.5, "ruin_wall": 0.0}


def noise(x, z, seed=0.0):
    """Smooth noise from a few rotated sine layers (no numpy needed), about -1..1."""
    v = 0.0
    amp = 1.0
    f = 0.035
    for k in range(5):
        a = 1.3 * k + seed
        u = x * math.cos(a) - z * math.sin(a)
        w = x * math.sin(a) + z * math.cos(a)
        v += amp * (math.sin(u * f + 1.7 * k + seed) * math.cos(w * f * 1.3 + 0.9 * k))
        amp *= 0.5
        f *= 2.03
    return v / 1.94


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a) if b != a else 0.0))
    return t * t * (3 - 2 * t)


def slope(land, x, z, e=1.0):
    hx = land(x + e, z) - land(x - e, z)
    hz = land(x, z + e) - land(x, z - e)
    return math.hypot(hx, hz) / (2 * e)


def ground(name, land, reach, cells, trodden=None):
    """land(x, z) -> metres above sea level (island-local, x east, z south). trodden(x, z) -> 0..1 path weight."""
    bm = bmesh.new()
    verts = {}
    for i in range(cells + 1):
        for j in range(cells + 1):
            x = (i / cells * 2 - 1) * reach
            z = (j / cells * 2 - 1) * reach
            if math.hypot(x, z) > reach * 1.01:
                continue
            verts[(i, j)] = bm.verts.new((x, -z, land(x, z)))
    for i in range(cells):
        for j in range(cells):
            q = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]  # wound so the faces look up
            if all(k in verts for k in q):
                bm.faces.new([verts[k] for k in q])
    bm.normal_update()
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    uv2 = bm.loops.layers.uv.new("UVMap2")
    for f in bm.faces:
        for loop in f.loops:
            v = loop.vert
            x, z, h = v.co.x, -v.co.y, v.co.z
            steep = 1.0 - v.normal.z
            n = noise(x * 1.7, z * 1.7, 11.0)
            rock = smooth(0.3, 0.5, steep + 0.08 * n)
            grass = smooth(1.6, 3.2, h + n * 0.8) * (1.0 - rock)
            wet = 1.0 - smooth(-0.2, 0.7, h)
            path = trodden(x, z) if trodden else 0.0
            shade = 0.94 + 0.06 * n  # light and dark patches (the colours come from the island's tints in the game)
            warm = 0.03 * noise(x * 0.6, z * 0.6, 5.0)
            loop[col] = (shade + warm, shade, shade - warm, 1.0)
            loop[uv].uv = (grass, rock)
            loop[uv2].uv = (wet, path)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(bpy.data.materials.new("isle_ground"))
    return obj


def scatter(land, reach, seed, clear=None, density=1.0, green=1.0):
    """The props by rule: [model, x, y, z, yaw degrees, scale] in island-local metres. density 1 = the start island's;
    green thins the grass tufts, bushes and ferns on their own (big islands are mostly green)."""
    rnd = random.Random(seed)
    out = []
    for _ in range(int(52000 * density * (reach / 150.0) ** 2)):
        x, z = rnd.uniform(-reach, reach), rnd.uniform(-reach, reach)
        h = land(x, z)
        if h < -0.2 or (clear and clear(x, z)):
            continue
        s = slope(land, x, z)
        roll = rnd.random()
        if 1.0 < h < 6.5 and s < 0.35 and roll < 0.05:
            put(out, rnd, land, "palm_a" if rnd.random() < 0.6 else "palm_b", x, z, rnd.uniform(0.85, 1.2), 0.3)
        elif 0.3 < h < 1.8 and s < 0.25 and roll < 0.05:
            put(out, rnd, land, rnd.choice(["shells", "shells", "coconuts", "driftwood"]), x, z, rnd.uniform(0.8, 1.2), 0.0)
        elif h > 2.5 and s < 0.5 and roll < 0.09 * green:
            put(out, rnd, land, rnd.choice(["bush", "bush", "fern"]), x, z, rnd.uniform(0.7, 1.4), 0.1)
        elif h > 2.0 and s < 0.6 and roll < 0.42 * green:
            put(out, rnd, land, "grass_tuft", x, z, rnd.uniform(0.8, 1.5), 0.0)
        elif s > 0.45 and roll < 0.035:
            put(out, rnd, land, rnd.choice(["boulder_a", "boulder_b", "boulder_c"]), x, z, rnd.uniform(0.8, 1.6), 0.4)
        elif -0.2 < h < 1.0 and roll < 0.006:
            put(out, rnd, land, rnd.choice(["boulder_a", "boulder_c"]), x, z, rnd.uniform(0.6, 1.3), 0.3)
    return out


def put(out, rnd, land, model, x, z, scale=1.0, sink=0.05):
    out.append([model, round(x, 2), round(land(x, z) - sink * scale, 2), round(z, 2), round(rnd.uniform(0, 360), 1), round(scale, 2)])


def save(name, obj, props, source):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PROPS_OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), use_selection=True, export_format="GLB")
    about = "Island props (%s writes this): [model, x, y, z, yaw degrees, scale] in island-local metres. solid = collision radius per model (0 = a wall: a box)." % source
    with open(os.path.join(PROPS_OUT, name + ".json"), "w") as f:
        json.dump({"_about": about, "props": props, "solid": SOLID}, f)
    counts = {}
    for p in props:
        counts[p[0]] = counts.get(p[0], 0) + 1
    print(name, len(obj.data.vertices), "verts", len(props), "props", counts)

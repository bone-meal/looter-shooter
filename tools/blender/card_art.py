# Purpose: developer-time card art studio for "You got me Lobster?" (runs in Blender's Python module `bpy`, never in the
# game). For each card in data/tcg/art.json it builds a lit scene from OUR models (assets/models/...), poses their parts
# mid-action, adds a stage (sky, ground, backdrop props), effects (spray, sparks, fire, magic, bolts, smoke, chips ...),
# a low dramatic camera with depth of field, renders with Cycles and paints the result over in the compositor (Kuwahara
# brush strokes, glow, colour grade, vignette). Writes assets/tcg/art/<id>.png (ART_W x ART_H).
# Director's choice 2026-11-13: art = renders from our models, "dynamic and interesting" scenes.
# Usage: python3 tools/blender/card_art.py [card ids ...] [--samples N] [--fast]
# Dependencies: pip packages bpy, numpy; data/tcg/art.json; the glTF models under assets/models/.
import json
import math
import os
import random
import sys

import bpy  # must come first: it brings mathutils with it
from mathutils import Euler, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "tcg", "art")
ART_W, ART_H = 640, 480


# ---------------------------------------------------------------- scene basics

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.resolution_x = ART_W
    scene.render.resolution_y = ART_H
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 8
    world = bpy.data.worlds.new("World")
    scene.world = world
    return scene


def mat(name, color, rough=0.5, metal=0.0, emit=None, strength=1.0, alpha=1.0, transmission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if transmission:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    return m


def noise_mat(name, a, b, scale=6.0, rough=0.8, bump=0.3, detail=8.0):
    """Two-colour procedural surface (sand, rock, dirt, stone) with bump."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = detail
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*a, 1)
    ramp.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bmp = nt.nodes.new("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump
    nt.links.new(tex.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    return m


CC0 = os.path.join(ROOT, "assets", "cc0", "textures")


def pbr(name, folder, scale=4.0, tint=(1, 1, 1), rough=0.85, bump=1.0):
    """A Poly Haven CC0 surface from assets/cc0/textures/<folder> (diffuse + normal), tiled `scale` times per metre."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    files = os.listdir(os.path.join(CC0, folder))
    diff = [f for f in files if "_diff_" in f and not f.endswith(".import")]
    nor = [f for f in files if "_nor" in f and not f.endswith(".import")]
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(CC0, folder, diff[0]))
    nt.links.new(mapping.outputs["Vector"], img.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs["B"].default_value = (*tint, 1)
    nt.links.new(img.outputs["Color"], mix.inputs["A"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if nor:
        nimg = nt.nodes.new("ShaderNodeTexImage")
        nimg.image = bpy.data.images.load(os.path.join(CC0, folder, nor[0]))
        nimg.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mapping.outputs["Vector"], nimg.inputs["Vector"])
        nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.inputs["Strength"].default_value = bump
        nt.links.new(nimg.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def add(obj, material=None):
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    return obj


def plane(size, at, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=at, rotation=rot)
    return add(bpy.context.object, material)


def sphere(r, at, material, seg=24, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=at, segments=seg, ring_count=max(8, seg // 2))
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.shade_smooth()
    return add(o, material)


def cone(r, depth, at, material, rot=(0, 0, 0), r2=0.0):
    bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=at, rotation=rot, vertices=16)
    return add(bpy.context.object, material)


def cube(size, at, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=rot)
    o = bpy.context.object
    o.scale = size
    return add(o, material)


def light(kind, at, energy, color=(1, 1, 1), size=1.0, aim=None, angle=None):
    data = bpy.data.lights.new(kind + "L", kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    if kind == "SUN" and angle is not None:
        data.angle = math.radians(angle)
    if kind in ("POINT", "SPOT"):
        data.shadow_soft_size = size
    o = bpy.data.objects.new(kind, data)
    bpy.context.collection.objects.link(o)
    o.location = at
    if aim is not None:
        look(o, aim)
    return o


def look(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


# ---------------------------------------------------------------- skies

SKIES = {  # zenith, upper, horizon glow, ground haze, sun colour, cloud colour, sun height (deg), cloud amount
    "sunset": [(0.03, 0.05, 0.18), (0.45, 0.2, 0.35), (1.0, 0.5, 0.18), (0.35, 0.18, 0.12), (1.0, 0.65, 0.3), (0.55, 0.25, 0.3), 6, 0.55],
    "day": [(0.1, 0.28, 0.7), (0.3, 0.55, 0.9), (0.75, 0.87, 1.0), (0.55, 0.6, 0.6), (1.0, 0.95, 0.85), (1.0, 1.0, 1.0), 45, 0.4],
    "night": [(0.0, 0.0, 0.015), (0.01, 0.02, 0.08), (0.05, 0.08, 0.2), (0.02, 0.03, 0.06), (0.6, 0.7, 1.0), (0.08, 0.1, 0.18), 30, 0.3],
    "storm": [(0.02, 0.025, 0.04), (0.07, 0.09, 0.13), (0.25, 0.28, 0.33), (0.1, 0.11, 0.13), (0.7, 0.8, 1.0), (0.12, 0.14, 0.18), 25, 0.9],
    "dusk": [(0.02, 0.02, 0.1), (0.2, 0.08, 0.3), (0.85, 0.35, 0.4), (0.25, 0.12, 0.2), (1.0, 0.55, 0.5), (0.4, 0.2, 0.35), 3, 0.5],
    "cave": [(0.0, 0.0, 0.0), (0.01, 0.02, 0.02), (0.04, 0.07, 0.06), (0.02, 0.03, 0.03), (0.4, 0.9, 0.7), (0.03, 0.05, 0.05), 40, 0.0],
    "club": [(0.02, 0.0, 0.04), (0.12, 0.0, 0.2), (0.55, 0.05, 0.4), (0.08, 0.02, 0.1), (1.0, 0.3, 0.8), (0.3, 0.05, 0.3), 20, 0.0],
    "fire": [(0.04, 0.0, 0.0), (0.25, 0.04, 0.02), (0.95, 0.35, 0.06), (0.3, 0.08, 0.02), (1.0, 0.5, 0.15), (0.3, 0.08, 0.05), 8, 0.7],
    "dust": [(0.25, 0.18, 0.15), (0.55, 0.38, 0.25), (0.95, 0.68, 0.4), (0.55, 0.4, 0.28), (1.0, 0.8, 0.5), (0.8, 0.6, 0.45), 20, 0.3],
}


def sky(scene, kind, sun_yaw=0.0):
    """Painted sky: vertical gradient, a glowing sun, noise clouds. Returns the horizon / haze colour for the mist."""
    zen, up, hor, haze, sun_c, cloud_c, sun_h, clouds = SKIES[kind]
    w = scene.world
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    lift = nt.nodes.new("ShaderNodeMath"); lift.operation = "MULTIPLY_ADD"; lift.inputs[1].default_value = 0.5; lift.inputs[2].default_value = 0.5
    nt.links.new(sep.outputs["Z"], lift.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.42, (*haze, 1)
    els[1].position, els[1].color = 1.0, (*zen, 1)
    e = els.new(0.5); e.color = (*hor, 1)
    e = els.new(0.62); e.color = (*up, 1)
    nt.links.new(lift.outputs[0], ramp.inputs["Fac"])
    # sun glow: dot(direction, sun) ^ n
    sd = Vector((math.sin(math.radians(sun_yaw)), math.cos(math.radians(sun_yaw)), math.tan(math.radians(sun_h)))).normalized()
    dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"; dot.inputs[1].default_value = sd
    nt.links.new(coord.outputs["Generated"], dot.inputs[0])
    clampn = nt.nodes.new("ShaderNodeMath"); clampn.operation = "MAXIMUM"; clampn.inputs[1].default_value = 0.0
    nt.links.new(dot.outputs["Value"], clampn.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 400.0
    nt.links.new(clampn.outputs[0], pw.inputs[0])
    pw2 = nt.nodes.new("ShaderNodeMath"); pw2.operation = "POWER"; pw2.inputs[1].default_value = 4.0
    nt.links.new(clampn.outputs[0], pw2.inputs[0])
    halo = nt.nodes.new("ShaderNodeMath"); halo.operation = "MULTIPLY_ADD"; halo.inputs[1].default_value = 0.6
    nt.links.new(pw2.outputs[0], halo.inputs[0]); nt.links.new(pw.outputs[0], halo.inputs[2])
    sunmix = nt.nodes.new("ShaderNodeMix"); sunmix.data_type = "RGBA"; sunmix.blend_type = "ADD"
    sunmix.inputs["B"].default_value = (*sun_c, 1)
    nt.links.new(halo.outputs[0], sunmix.inputs["Factor"]); nt.links.new(ramp.outputs["Color"], sunmix.inputs["A"])
    # clouds: stretched noise above the horizon
    mapn = nt.nodes.new("ShaderNodeMapping"); mapn.inputs["Scale"].default_value = (2.0, 2.0, 7.0)
    nt.links.new(coord.outputs["Generated"], mapn.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 2.2; noise.inputs["Detail"].default_value = 10; noise.inputs["Roughness"].default_value = 0.6
    nt.links.new(mapn.outputs["Vector"], noise.inputs["Vector"])
    cramp = nt.nodes.new("ShaderNodeValToRGB")
    cramp.color_ramp.elements[0].position = 0.62 - clouds * 0.2
    cramp.color_ramp.elements[1].position = 0.75 - clouds * 0.15
    nt.links.new(noise.outputs["Fac"], cramp.inputs["Fac"])
    band = nt.nodes.new("ShaderNodeMapRange"); band.inputs["From Min"].default_value = 0.0; band.inputs["From Max"].default_value = 0.25
    nt.links.new(sep.outputs["Z"], band.inputs["Value"])
    cm = nt.nodes.new("ShaderNodeMath"); cm.operation = "MULTIPLY"
    nt.links.new(cramp.outputs["Color"], cm.inputs[0]); nt.links.new(band.outputs["Result"], cm.inputs[1])
    cmix = nt.nodes.new("ShaderNodeMix"); cmix.data_type = "RGBA"
    cmix.inputs["B"].default_value = (*cloud_c, 1)
    nt.links.new(cm.outputs[0], cmix.inputs["Factor"]); nt.links.new(sunmix.outputs["Result"], cmix.inputs["A"])
    nt.links.new(cmix.outputs["Result"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    if kind != "cave" and kind != "club":  # stars at night
        pass
    return haze, hor, sd, sun_c


# ---------------------------------------------------------------- stages (ground + backdrop per place)

def props(rng, names, n, xr, yr, scale=(0.8, 1.4)):
    """Scatters our game's prop models (assets/models/fantasy/<name>.gltf) in the backdrop."""
    for i in range(n):
        name = names[i % len(names)]
        x = rng.uniform(*xr) * rng.choice([-1, 1])
        load_model("fantasy/" + name, (x, rng.uniform(*yr), 0), rng.uniform(0, 360), rng.uniform(*scale), {})


def volume(at, size, color, density, rng):
    """A soft cloud of smoke / dust / mist (Cycles volume shaped by noise inside a ball)."""
    bpy.ops.mesh.primitive_ico_sphere_add(radius=1, location=at, subdivisions=3)
    o = bpy.context.object
    o.scale = size
    m = bpy.data.materials.new("vol")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (*color, 1)
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 2.5; noise.inputs["Detail"].default_value = 6
    noise.noise_dimensions = "4D"; noise.inputs["W"].default_value = rng.uniform(0, 10)
    grad = nt.nodes.new("ShaderNodeTexGradient"); grad.gradient_type = "SPHERICAL"
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], grad.inputs["Vector"])
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    nt.links.new(noise.outputs["Fac"], mul.inputs[0]); nt.links.new(grad.outputs["Fac"], mul.inputs[1])
    sharp = nt.nodes.new("ShaderNodeMapRange"); sharp.inputs["From Min"].default_value = 0.15; sharp.inputs["From Max"].default_value = 0.5
    sharp.inputs["To Max"].default_value = density
    nt.links.new(mul.outputs[0], sharp.inputs["Value"])
    nt.links.new(sharp.outputs["Result"], vol.inputs["Density"])
    nt.links.new(vol.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
    add(o, m)
    return o

def stage(scene, kind, rng):
    if kind == "beach":
        sand = plane(1, (0, -6, 0), pbr("sand", "coast_sand_01", 0.6, (1.0, 0.92, 0.8)))
        sand.scale = (80, 24, 1)
        bpy.ops.mesh.primitive_grid_add(x_subdivisions=200, y_subdivisions=200, size=160, location=(0, 84, -0.12))
        sea = add(bpy.context.object, mat("sea", (0.01, 0.08, 0.13), 0.04))
        foam = plane(1, (0, 6.2, -0.02), mat("foamline", (0.9, 0.95, 1.0), 0.6, alpha=0.7))
        foam.scale = (80, 0.5, 1)
        wave = sea.modifiers.new("w", "DISPLACE"); tex = bpy.data.textures.new("wt", "CLOUDS"); tex.noise_scale = 1.5; wave.texture = tex; wave.strength = 0.5
        bpy.ops.object.shade_smooth()
        for i in range(10):  # rocks on the shore
            sphere(rng.uniform(0.3, 1.2), (rng.choice([-1, 1]) * rng.uniform(3, 12), rng.uniform(2, 9), -0.2), pbr("rock%d" % i, "cliff_side", 0.8), 12, (1, rng.uniform(0.7, 1.3), rng.uniform(0.5, 0.9)))
        props(rng, ["tree_palm"], 4, (5, 14), (0, 5), (1.0, 1.5))
    elif kind == "waste":
        plane(120, (0, 0, 0), pbr("dirt", "dry_ground_01", 0.5, (1.0, 0.85, 0.7)))
        for i in range(12):
            sphere(rng.uniform(1.5, 5), (rng.uniform(-30, 30), rng.uniform(15, 50), -1), pbr("dune%d" % i, "sand_01", 0.2, (1.0, 0.8, 0.6)), 16, (2.5, 1.5, 0.6))
        for i in range(6):  # wreck silhouettes
            cube((rng.uniform(0.5, 2), rng.uniform(0.5, 2), rng.uniform(1, 4)), (rng.uniform(-14, 14), rng.uniform(10, 22), 0.8), pbr("wreck%d" % i, "rusty_metal_02", 0.5), (0, rng.uniform(-0.4, 0.4), rng.uniform(0, 3)))
        props(rng, ["cart_broken", "barrel", "loot_crate", "tree_dead", "boulder_sand", "spire_sand"], 10, (3, 16), (4, 20))
    elif kind == "crypt":
        plane(80, (0, 0, 0), pbr("flag", "cobblestone_floor_04", 0.5, (0.55, 0.55, 0.6)))
        for x in (-6, -3, 3, 6):  # pillars
            bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=8, location=(x, 9 + abs(x), 4), vertices=12)
            add(bpy.context.object, pbr("pillar%d" % x, "medieval_blocks_02", 0.6, (0.5, 0.5, 0.55)))
        for i in range(8):  # gravestones
            cube((0.7, 0.2, rng.uniform(0.9, 1.4)), (rng.uniform(-8, 8), rng.uniform(5, 14), 0.5), pbr("grave%d" % i, "large_sandstone_blocks_01", 1.0, (0.45, 0.45, 0.5)), (0, rng.uniform(-0.2, 0.2), rng.uniform(-0.3, 0.3)))
        props(rng, ["ruin_arch", "ruin_wall", "bone_pile", "statue", "tree_dead"], 8, (3, 12), (5, 18))
    elif kind == "field":
        plane(120, (0, 0, 0), pbr("grass", "leafy_grass", 0.6))
        for i in range(9):  # hills and trees
            sphere(rng.uniform(4, 9), (rng.uniform(-40, 40), rng.uniform(30, 60), -2), pbr("hill%d" % i, "aerial_grass_rock", 0.1), 16, (2, 1, 0.5))
        props(rng, ["tree_oak", "tree_pine", "tree_oak", "bush_green", "boulder_moss"], 14, (4, 22), (8, 30))
    elif kind == "club":
        plane(60, (0, 0, 0), mat("floor", (0.03, 0.02, 0.05), 0.15, 0.3))
        for i in range(14):  # glowing floor tiles and neon bars
            cube((1.8, 1.8, 0.04), ((i % 7) * 2 - 6, 3 + (i // 7) * 2, 0.02), mat("tile%d" % i, (0.02, 0.02, 0.02), 0.3, emit=[(1, 0.1, 0.6), (0.1, 0.9, 1), (1, 0.8, 0.2)][i % 3], strength=1.5))
        for x in (-7, 7):
            cube((0.2, 0.2, 6), (x, 10, 3), mat("neon%d" % x, (0, 0, 0), emit=(1, 0.1, 0.6) if x < 0 else (0.1, 0.9, 1), strength=12))
        cube((20, 0.5, 9), (0, 14, 4.5), mat("wall", (0.08, 0.03, 0.12), 0.6))
    elif kind == "arena":
        plane(80, (0, 0, 0), pbr("sandpit", "gravelly_sand", 0.6))
        for i in range(16):
            a = math.pi * (0.15 + 0.7 * i / 15)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.6, depth=7, location=(math.cos(a) * -18, math.sin(a) * 18 + 4, 3.5), vertices=12)
            add(bpy.context.object, pbr("col%d" % i, "sandstone_blocks_08", 0.7))
    elif kind == "ice":
        plane(80, (0, 0, 0), pbr("snow", "snow_02", 0.5))
        for i in range(10):
            cone(rng.uniform(1, 3), rng.uniform(4, 10), (rng.uniform(-20, 20), rng.uniform(15, 35), 2), mat("ice%d" % i, (0.6, 0.8, 0.95), 0.1, transmission=0.6))
        props(rng, ["boulder_ice", "ice_shards", "tree_pine"], 8, (3, 14), (4, 18))
    elif kind == "volcano":
        plane(80, (0, 0, 0), pbr("basalt", "burned_ground_01", 0.5, (0.35, 0.3, 0.3)))
        for i in range(8):
            cube((rng.uniform(1, 4), 0.3, 0.05), (rng.uniform(-10, 10), rng.uniform(3, 18), 0.03), mat("lava%d" % i, (1, 0.2, 0), emit=(1, 0.3, 0.02), strength=8), (0, 0, rng.uniform(0, 3)))
        cone(14, 12, (8, 40, 4), noise_mat("mount", (0.05, 0.04, 0.04), (0.2, 0.12, 0.1), 2, 0.8, 0.5), r2=3)
        props(rng, ["boulder_basalt", "spire_basalt", "tree_ember"], 8, (3, 14), (4, 18))


# ---------------------------------------------------------------- subjects (our models), posed

def detail(m):
    """Gives a flat model material painted variation and a fine bump so close-ups read as surfaces, not plastic."""
    m["detailed"] = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    if b is None or b.inputs["Base Color"].is_linked:
        return
    base = tuple(b.inputs["Base Color"].default_value)
    tex = nt.nodes.new("ShaderNodeTexNoise"); tex.inputs["Scale"].default_value = 18.0; tex.inputs["Detail"].default_value = 12.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (base[0] * 0.55, base[1] * 0.55, base[2] * 0.55, 1)
    ramp.color_ramp.elements[1].color = (min(base[0] * 1.25, 1), min(base[1] * 1.25, 1), min(base[2] * 1.25, 1), 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = max(b.inputs["Roughness"].default_value, 0.45)


def load_model(rel, at, yaw, scale, pose, tint=None):
    path = os.path.join(ROOT, "assets", "models", rel + ".gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("subject", None)
    bpy.context.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
        # glTF is Y-up; the importer already turned it Z-up. Pose by part name: degrees about x, y, z.
        if o.name.split(".")[0] in pose:
            r = pose[o.name.split(".")[0]]
            o.rotation_mode = "XYZ"
            o.rotation_euler = Euler((o.rotation_euler.x + math.radians(r[0]), o.rotation_euler.y + math.radians(r[1]), o.rotation_euler.z + math.radians(r[2])))
        if o.type == "MESH":
            for slot in o.material_slots:
                if slot.material and slot.material.use_nodes and not slot.material.get("detailed"):
                    detail(slot.material)
        if tint and o.type == "MESH":
            for slot in o.material_slots:
                if slot.material and slot.material.use_nodes:
                    b = slot.material.node_tree.nodes.get("Principled BSDF")
                    if b:
                        c = b.inputs["Base Color"].default_value
                        b.inputs["Base Color"].default_value = (c[0] * tint[0], c[1] * tint[1], c[2] * tint[2], 1)
    root.location = at
    root.rotation_euler = (0, 0, math.radians(yaw))
    root.scale = (scale, scale, scale)
    return root


PACKS = os.path.join(ROOT, "assets", "cc0", "packs")
CHARACTERS = os.path.join(PACKS, "modular_character_outfits_fantasy_standard", "exports_gltf_godot_unreal_outfits")
CLIPS = os.path.join(PACKS, "universal_animation_library", "unreal_engine", "AL_Standard.fbx")  # bone names match the outfits


def _fcurves(action):
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    out += list(bag.fcurves)
    return out


def load_human(body, clip, phase, at, yaw, scale=1.0, tint=None, ears=None, hold=None):
    """A rigged CC0 character (Female_Peasant, Female_Ranger, Male_Peasant, Male_Ranger) frozen at `phase` (0..1) of an
    animation clip from the universal animation library (Sword_Attack, Spell_Simple_Shoot, Punch_Cross, Pistol_Shoot,
    Dance_Loop, Jump_Loop, Sprint_Loop, Death01 ...). ears = colour of a pair of bunny ears (the club staff's
    uniform), hold = "sword" / "staff" / "pistol" / "bat" put in the right hand."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(CHARACTERS, body + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in [o for o in new if o.name.startswith("Icosphere")]:  # the outfit files carry a 1 m helper ball at the feet
        new.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
    rig = next(o for o in new if o.type == "ARMATURE")
    if "clips" not in bpy.data.texts:  # the library is imported once per scene; its own rig is hidden
        lib_before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=CLIPS)
        for o in [o for o in bpy.data.objects if o not in lib_before]:
            o.hide_render = True
            o.hide_viewport = True
        bpy.data.texts.new("clips")
    action = next((a for a in bpy.data.actions if a.name.split("|")[-1] == clip), None)
    if action is not None:
        rig.animation_data_create()
        rig.animation_data.action = action
        for fc in [f for f in _fcurves(action) if f.data_path.endswith("location") and "pelvis" not in f.data_path]:
            pass
        if hasattr(rig.animation_data, "action_slot") and action.slots:
            rig.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        bpy.context.scene.frame_set(int(start + (end - start) * phase))
    root = bpy.data.objects.new("human", None)
    bpy.context.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
        if o.type == "MESH" and tint:
            for slot in o.material_slots:
                b = slot.material.node_tree.nodes.get("Principled BSDF") if slot.material and slot.material.use_nodes else None
                if b is not None:
                    mixn = slot.material.node_tree.nodes.new("ShaderNodeMix"); mixn.data_type = "RGBA"; mixn.blend_type = "MULTIPLY"
                    mixn.inputs["Factor"].default_value = 0.8; mixn.inputs["B"].default_value = (*tint, 1)
                    src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].is_linked else None
                    if src is not None:
                        slot.material.node_tree.links.new(src, mixn.inputs["A"])
                        slot.material.node_tree.links.new(mixn.outputs["Result"], b.inputs["Base Color"])
    root.location = at
    root.rotation_euler = (0, 0, math.radians(yaw))
    root.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    def bone_world(name):
        pb = rig.pose.bones.get(name)
        return rig.matrix_world @ pb.head if pb else None, (rig.matrix_world @ pb.matrix) if pb else None
    if ears:
        head, hm = bone_world("DEF-head")
        if head is not None:
            em = mat("ears", ears, 0.5)
            for side in (-1, 1):
                o = sphere(0.035, (0, 0, 0), em, 12, (1, 0.5, 4.2))
                o.matrix_world = hm
                o.location = hm @ Vector((side * 0.06, 0.24, 0.0))
    if hold:
        hand, hmx = bone_world("DEF-hand.R")
        if hand is not None:
            col = {"sword": (0.8, 0.82, 0.88), "staff": (0.4, 0.25, 0.12), "pistol": (0.15, 0.15, 0.16), "bat": (0.45, 0.28, 0.12)}[hold]
            length = {"sword": 0.9, "staff": 1.6, "pistol": 0.25, "bat": 0.8}[hold]
            bpy.ops.mesh.primitive_cylinder_add(radius=0.02 if hold != "bat" else 0.035, depth=length, vertices=10)
            o = add(bpy.context.object, mat("held", col, 0.3, 0.9 if hold != "staff" else 0.0))
            o.matrix_world = hmx
            o.location = hmx @ Vector((0, length * 0.45, 0))
            if hold == "staff":
                sphere(0.07, hmx @ Vector((0, length * 0.95, 0)), mat("orb", (0.4, 0.8, 1.0), emit=(0.4, 0.8, 1.0), strength=30), 16)
    return root


# ---------------------------------------------------------------- effects

def fx(kind, at, rng, size=1.0, color=None, count=None):
    at = Vector(at)
    if kind == "spray":  # water droplets and foam
        m = mat("spray", (0.8, 0.9, 1.0), 0.05, transmission=0.9)
        foam = mat("foam", (0.95, 0.97, 1.0), 0.5)
        for i in range(count or 70):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 0.6), abs(rng.gauss(0, 1)))) * size
            sphere(rng.uniform(0.006, 0.025) * size, at + d, foam if i % 3 == 0 else m, 8, (1, 1, rng.uniform(1, 2.5)))
    elif kind in ("sparks", "embers"):
        c = color or ((1.0, 0.6, 0.15) if kind == "sparks" else (1.0, 0.35, 0.05))
        m = mat(kind, c, emit=c, strength=25)
        for i in range(count or 50):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0.6, 0.8))) * size
            o = sphere(rng.uniform(0.004, 0.012) * size, at + d, m, 6, (1, 1, rng.uniform(2, 6)))
            look(o, at + d * 2); o.rotation_euler.x += math.pi / 2
    elif kind == "fire":  # flame tongues
        for i in range(count or 18):
            c = (1.0, rng.uniform(0.25, 0.6), 0.05)
            m = mat("flame%d" % i, c, emit=c, strength=rng.uniform(15, 35), alpha=0.85)
            d = Vector((rng.gauss(0, 0.5), rng.gauss(0, 0.5), 0)) * size
            cone(rng.uniform(0.15, 0.35) * size, rng.uniform(0.6, 1.6) * size, at + d + Vector((0, 0, 0.5 * size)), m, (rng.gauss(0, 0.2), rng.gauss(0, 0.2), 0))
        light("POINT", at + Vector((0, 0, size)), 400 * size, (1, 0.5, 0.15), 0.5)
    elif kind == "magic":  # glowing orbs and a swirl
        c = color or (0.4, 0.7, 1.0)
        m = mat("magic", c, emit=c, strength=20)
        for i in range(count or 60):
            t = i / (count or 60) * math.pi * 4
            r = size * (0.3 + 0.7 * i / (count or 60))
            sphere(rng.uniform(0.008, 0.025) * size, at + Vector((math.cos(t) * r, math.sin(t) * r * 0.6, 0.3 * size + i * 0.02 * size)), m, 8)
        light("POINT", at + Vector((0, 0, 0.6 * size)), 300 * size, c, 0.4)
    elif kind == "bolt":  # lightning from the sky to `at`
        c = color or (0.6, 0.8, 1.0)
        m = mat("bolt", c, emit=c, strength=60)
        p = at + Vector((rng.uniform(-1, 1), 0, 8))
        while p.z > at.z:
            q = p + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.3), -rng.uniform(0.4, 0.9)))
            mid = (p + q) / 2
            bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=(q - p).length, location=mid, vertices=6)
            o = add(bpy.context.object, m); look(o, q); o.rotation_euler.x += math.pi / 2
            p = q
        light("POINT", at + Vector((0, 0, 1)), 2000, c, 0.3)
    elif kind == "smoke":
        volume(at + Vector((0, 0, 0.8 * size)), (1.6 * size, 1.0 * size, 1.2 * size), color or (0.12, 0.12, 0.13), 6.0, rng)
    elif kind == "chips":  # flying poker chips
        cols = [(0.8, 0.05, 0.05), (0.05, 0.05, 0.05), (0.1, 0.3, 0.9), (0.1, 0.6, 0.2)]
        for i in range(count or 30):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.12 * size, depth=0.03 * size, location=at + Vector((rng.gauss(0, 1), rng.gauss(0, 0.7), abs(rng.gauss(0.6, 0.7)))) * size, vertices=20, rotation=(rng.uniform(0, 3), rng.uniform(0, 3), 0))
            add(bpy.context.object, mat("chip%d" % i, cols[i % 4], 0.3))
    elif kind == "confetti":
        for i in range(count or 80):
            c = [(1, 0.1, 0.6), (0.1, 0.9, 1), (1, 0.85, 0.1), (0.5, 1, 0.3)][i % 4]
            cube((0.08 * size, 0.04 * size, 0.005), at + Vector((rng.gauss(0, 1.5), rng.gauss(0, 1), abs(rng.gauss(1, 1)))) * size, mat("conf%d" % i, c, 0.4, emit=c, strength=2), (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)))
    elif kind == "bones":  # flying bone shards
        m = mat("bone", (0.85, 0.82, 0.7), 0.6)
        for i in range(count or 25):
            o = cube((0.04 * size, 0.04 * size, rng.uniform(0.15, 0.35) * size), at + Vector((rng.gauss(0, 1), rng.gauss(0, 0.7), abs(rng.gauss(0.6, 0.6)))) * size, m, (rng.uniform(0, 3), rng.uniform(0, 3), 0))
    elif kind == "dust":
        volume(at + Vector((0, 0, 0.3 * size)), (2.5 * size, 1.2 * size, 0.6 * size), color or (0.75, 0.58, 0.38), 4.0, rng)
    elif kind == "beam":  # god-ray column of light
        c = color or (1.0, 0.9, 0.6)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.45 * size, depth=12, location=at + Vector((0, 1.8, 6)), vertices=24)
        add(bpy.context.object, mat("beam", c, emit=c, strength=2, alpha=0.06))
    elif kind == "streaks":  # speed lines behind something moving toward the camera
        c = color or (1, 1, 1)
        m = mat("streak", c, emit=c, strength=4, alpha=0.6)
        for i in range(count or 20):
            cube((0.02 * size, rng.uniform(1.5, 4) * size, 0.02 * size), at + Vector((rng.gauss(0, 0.8), rng.uniform(1, 3), rng.gauss(0.8, 0.5))) * size, m)
    elif kind == "glow":  # a soft coloured light
        light("POINT", at, 300 * size, color or (1, 0.8, 0.5), 1.0)


# ---------------------------------------------------------------- lights, camera, paint-over

def lighting(sun_dir, sun_c, haze, subject, power=1.0):
    """Sun from the sky's sun (usually behind the subject: rim light), a warm key from the camera side, a cool fill."""
    sun = light("SUN", Vector(subject) + sun_dir * 10, 3.0 * power, sun_c, angle=2)
    look(sun, subject)
    key = light("AREA", Vector(subject) + Vector((2.5, -3.5, 3.0)), 500 * power, (1.0, 0.9, 0.8), 3, aim=subject)
    rim = light("AREA", Vector(subject) + Vector((-1.5, 3.0, 2.5)), 900 * power, sun_c, 2, aim=subject)
    fill = light("AREA", Vector(subject) + Vector((-4, -2, 1.5)), 150 * power, (0.55, 0.65, 1.0), 5, aim=subject)
    return sun, key, rim, fill


def auto_camera(card_id, roots):
    """A low hero shot of whatever stands in the scene: framed to its size, a little to the side, slightly tilted."""
    pts = []
    bpy.context.view_layer.update()
    for root in roots:
        for o in [root] + list(root.children_recursive):
            if o.type == "MESH" and not o.hide_render:
                pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    h = sum(ord(ch) for ch in card_id)
    side = [-1, 1][h % 2]
    if not pts:
        return {"from": [side * 0.9, -3.4, 0.7], "at": [0, 1.0, 0.9], "lens": 26, "roll": side * 6}
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    size = max(hi.z - lo.z, (hi.x - lo.x) * 0.75, 0.4)
    dist = size * 1.25 + 0.5
    at = Vector((centre.x, centre.y, lo.z + (hi.z - lo.z) * 0.55))
    lo.z = max(lo.z, 0.0)  # models reaching below the ground (slimes) must not pull the camera under it
    at.z = max(at.z, 0.35)
    return {"from": [at.x + side * dist * 0.38, at.y - dist, max(lo.z + size * 0.22 + 0.15, 0.3)], "at": [at.x, at.y + size * 0.3, at.z + size * 0.08],
            "focus": [at.x, at.y, at.z], "lens": 28, "roll": side * (4 + h % 7)}


def camera(scene, cam):
    data = bpy.data.cameras.new("cam")
    data.lens = cam.get("lens", 30)
    data.dof.use_dof = True
    data.dof.aperture_fstop = cam.get("fstop", 2.2)
    o = bpy.data.objects.new("cam", data)
    bpy.context.collection.objects.link(o)
    o.location = cam["from"]
    look(o, cam["at"])
    o.rotation_euler.rotate_axis("Z", math.radians(cam.get("roll", 0)))
    data.dof.focus_distance = (Vector(cam["from"]) - Vector(cam.get("focus", cam["at"]))).length
    scene.camera = o


def paint_over(scene, strength, haze, mist):
    """Compositor: aerial haze from the mist pass, Kuwahara brush strokes, a soft glow, a vignette (Blender 5 node group)."""
    scene.view_layers[0].use_pass_mist = True
    scene.world.mist_settings.start = mist[0]
    scene.world.mist_settings.depth = mist[1]
    ng = bpy.data.node_groups.new("paint", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    scene.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    fog = ng.nodes.new("ShaderNodeMix"); fog.data_type = "RGBA"
    fog.inputs["B"].default_value = (*haze, 1)
    fmul = ng.nodes.new("ShaderNodeMath"); fmul.operation = "MULTIPLY"; fmul.inputs[1].default_value = 0.75
    near = ng.nodes.new("ShaderNodeMath"); near.operation = "LESS_THAN"; near.inputs[1].default_value = 0.999  # the sky keeps its own colours
    ng.links.new(rl.outputs["Mist"], near.inputs[0])
    only = ng.nodes.new("ShaderNodeMath"); only.operation = "MULTIPLY"
    ng.links.new(rl.outputs["Mist"], only.inputs[0]); ng.links.new(near.outputs[0], only.inputs[1])
    ng.links.new(only.outputs[0], fmul.inputs[0])
    ng.links.new(fmul.outputs[0], fog.inputs["Factor"]); ng.links.new(rl.outputs["Image"], fog.inputs["A"])
    kuw = ng.nodes.new("CompositorNodeKuwahara")
    kuw.inputs["Type"].default_value = "Anisotropic"
    kuw.inputs["Size"].default_value = strength
    glare = ng.nodes.new("CompositorNodeGlare")
    glare.inputs["Type"].default_value = "Fog Glow"
    glare.inputs["Threshold"].default_value = 0.85
    glare.inputs["Strength"].default_value = 0.7
    mask = ng.nodes.new("CompositorNodeEllipseMask")
    for k, v in (("Size", (0.95, 1.05)),):
        if k in mask.inputs:
            mask.inputs[k].default_value = v
    blur = ng.nodes.new("CompositorNodeBlur")
    if "Size" in blur.inputs:
        blur.inputs["Size"].default_value = (180, 180)
    vig = ng.nodes.new("ShaderNodeMix"); vig.data_type = "RGBA"; vig.blend_type = "MULTIPLY"
    vig.inputs["Factor"].default_value = 1.0
    lift = ng.nodes.new("ShaderNodeMapRange"); lift.inputs["To Min"].default_value = 0.35
    out = ng.nodes.new("NodeGroupOutput")
    hsv = ng.nodes.new("CompositorNodeHueSat")
    for k, v in (("Saturation", 1.3), ("Value", 1.05)):
        if k in hsv.inputs:
            hsv.inputs[k].default_value = v
    ng.links.new(fog.outputs["Result"], hsv.inputs["Image"])
    ng.links.new(hsv.outputs["Image"], kuw.inputs["Image"])
    ng.links.new(kuw.outputs["Image"], glare.inputs["Image"])
    ng.links.new(mask.outputs[0], blur.inputs["Image"])
    ng.links.new(blur.outputs[0], lift.inputs["Value"])
    ng.links.new(glare.outputs["Image"], vig.inputs["A"])
    ng.links.new(lift.outputs["Result"], vig.inputs["B"])
    ng.links.new(vig.outputs["Result"], out.inputs[0])


# ---------------------------------------------------------------- one card

def render(card_id, recipe, samples):
    scene = reset()
    rng = random.Random(sum(ord(ch) * (i + 1) for i, ch in enumerate(card_id)))
    haze, hor, sun_dir, sun_c = sky(scene, recipe.get("time", "day"), recipe.get("sun_yaw", 0))
    stage(scene, recipe.get("stage", "beach"), rng)
    roots = []
    for s in recipe.get("subjects", []):
        if "human" in s:
            roots.append(load_human(s["human"], s.get("clip", "Idle_Loop"), s.get("phase", 0.4), s.get("at", (0, 0, 0)), s.get("yaw", 0), s.get("scale", 1), s.get("tint"), s.get("ears"), s.get("hold")))
        else:
            roots.append(load_model(s["model"], s.get("at", (0, 0, 0)), s.get("yaw", 0), s.get("scale", 1), s.get("pose", {}), s.get("tint")))
    if recipe["camera"] == "auto":
        recipe["camera"] = auto_camera(card_id, roots)
    focus = recipe["camera"].get("focus", recipe["camera"]["at"])
    for f in recipe.get("fx", []):
        fx(f["kind"], f["at"], rng, f.get("size", 1), f.get("color"), f.get("count"))
    lighting(sun_dir, sun_c, haze, focus, recipe.get("light", 1.8 if recipe.get("time") in ("club", "night", "cave") else 1.0))
    camera(scene, recipe["camera"])
    paint_over(scene, recipe.get("paint", 5), hor, recipe.get("mist", (4, 40)))
    scene.cycles.samples = samples
    os.makedirs(OUT, exist_ok=True)
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 92
    scene.render.filepath = os.path.join(OUT, card_id + ".jpg")
    bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[1:]
    samples = 64
    if "--samples" in args:
        i = args.index("--samples"); samples = int(args[i + 1]); del args[i:i + 2]
    recipes = json.load(open(os.path.join(ROOT, "data", "tcg", "art.json")))["art"]
    sys.path.insert(0, os.path.dirname(__file__))
    import card_art_auto
    cards = json.load(open(os.path.join(ROOT, "data", "tcg", "cards.json")))["cards"]
    for lid, l in json.load(open(os.path.join(ROOT, "data", "tcg", "leaders.json")))["leaders"].items():
        cards[lid] = {"faction": l["faction"], "type": "creature", "rarity": "legendary", "leader": True}
    cur = None
    for line in open(os.path.join(ROOT, "data", "tcg", "writing", "cards.txt")):
        line = line.strip()
        if line.startswith("[card ") or line.startswith("[leader "):
            cur = line[1:-1].split(" ")[1]
        elif line.startswith("name: ") and cur in cards:
            cards[cur]["name"] = line[6:]
    skip = "--missing" in args
    args = [a for a in args if a != "--missing"]
    ids = args or [k for k, v in cards.items() if v.get("rarity") != "token" or k == "lucky_chip"]
    for card_id in ids:
        if skip and (os.path.exists(os.path.join(OUT, card_id + ".jpg")) or os.path.exists(os.path.join(OUT, card_id + ".png"))):
            continue
        r = recipes.get(card_id) or card_art_auto.recipe(card_id, cards[card_id])
        render(card_id, r, samples)
        print("ART", card_id, flush=True)


if __name__ == "__main__":
    main()

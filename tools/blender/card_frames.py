# Purpose: developer-time builder of the card FRAMES of "You got me Lobster?" (runs in Blender's Python module `bpy`, never
# in the game). Models each part as bevelled, embossed 3D (metal plate with the art window and text window cut out,
# raised rims, a cloth name banner, a parchment text plaque, faction ornaments, gems and badges), lights it like a
# product shot and renders it from straight above with a transparent background, then crops every layer to its box.
# Writes assets/tcg/frames/*.png and data/tcg/card_layout.json (where each layer and each text box sits on the card,
# in card pixels). Our own designs (no frame, gem or badge shapes copied from other card games).
# Usage: python3 tools/blender/card_frames.py [layer names ...]
# Dependencies: pip packages bpy, numpy, pillow.
import json
import math
import os
import sys

import bpy  # must come first
import bmesh
from mathutils import Vector
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "tcg", "frames")
W, H = 5.0, 7.0          # card size in Blender units
PX = 120                 # pixels per unit -> 600 x 840
ART = (0.42, 3.55, 4.58, 6.62)    # x0, y0, x1, y1 of the art window (creature)
TEXT = (0.62, 0.78, 4.38, 2.78)   # rules text plaque
BANNER_Y = 3.22                    # centre of the name banner

FACTIONS = {  # plate metal, accent metal, banner cloth, ornament kind
    "tide": ((0.12, 0.38, 0.36), (0.75, 0.62, 0.32), (0.05, 0.25, 0.42), "shell"),
    "waste": ((0.32, 0.18, 0.1), (0.62, 0.5, 0.38), (0.45, 0.18, 0.06), "rivet"),
    "crypt": ((0.2, 0.2, 0.24), (0.78, 0.76, 0.7), (0.18, 0.12, 0.25), "skull"),
    "aurelind": ((0.16, 0.3, 0.12), (0.95, 0.72, 0.3), (0.12, 0.35, 0.12), "leaf"),
    "club": ((0.06, 0.03, 0.08), (1.0, 0.78, 0.35), (0.55, 0.05, 0.32), "chip"),
    "neutral": ((0.36, 0.3, 0.24), (0.72, 0.6, 0.4), (0.35, 0.28, 0.2), "rope"),
}
RARITY = {"common": (0.2, 0.85, 0.3), "rare": (0.2, 0.5, 1.0), "epic": (0.7, 0.25, 1.0), "legendary": (1.0, 0.55, 0.1)}


# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 48
    s.cycles.use_denoising = True
    s.render.resolution_x = int(W * PX)
    s.render.resolution_y = int(H * PX)
    s.render.film_transparent = True
    s.view_settings.view_transform = "AgX"
    s.view_settings.look = "AgX - Punchy"
    world = bpy.data.worlds.new("w"); s.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.33, 0.32, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = H
    o = bpy.data.objects.new("c", cam); s.collection.objects.link(o)
    o.location = (W / 2, H / 2, 20); s.camera = o
    for at, e, c in (((-3, 9, 9), 900, (1, 0.95, 0.85)), ((9, -2, 6), 350, (0.7, 0.8, 1.0)), ((2.5, 3.5, 12), 300, (1, 1, 1))):
        L = bpy.data.lights.new("l", "AREA"); L.energy = e; L.color = c; L.size = 4
        lo = bpy.data.objects.new("l", L); s.collection.objects.link(lo); lo.location = at
        d = Vector((W / 2, H / 2, 0)) - Vector(at); lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return s


def metal(name, color, rough=0.3, scratches=0.4):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 30; noise.inputs["Detail"].default_value = 12
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (color[0] * 0.55, color[1] * 0.55, color[2] * 0.55, 1)
    ramp.color_ramp.elements[1].color = (*color, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = scratches * 0.3
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def cloth(name, color):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.75
    b.inputs["Sheen Weight"].default_value = 0.6
    wave = nt.nodes.new("ShaderNodeTexWave"); wave.inputs["Scale"].default_value = 60; wave.inputs["Distortion"].default_value = 2
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (color[0] * 0.7, color[1] * 0.7, color[2] * 0.7, 1)
    ramp.color_ramp.elements[1].color = (*color, 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def parchment():
    m = bpy.data.materials.new("parch"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 6; noise.inputs["Detail"].default_value = 14
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.62, 0.52, 0.36, 1); ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[1].color = (0.93, 0.87, 0.72, 1); ramp.color_ramp.elements[1].position = 0.6
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def glass(name, color, glow=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Transmission Weight"].default_value = 0.6
    b.inputs["IOR"].default_value = 1.8
    b.inputs["Coat Weight"].default_value = 1.0
    if glow:
        b.inputs["Emission Color"].default_value = (*color, 1); b.inputs["Emission Strength"].default_value = glow
    return m


CC0 = os.path.join(ROOT, "assets", "cc0", "textures")


def plate_mat(faction, color):
    """The frame body: a different surface per faction (engraved waves, rusted iron, carved stone, enamel, lacquer, wood)."""
    m = bpy.data.materials.new("plate_" + faction); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.5
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (color[0] * 0.45, color[1] * 0.45, color[2] * 0.45, 1)
    ramp.color_ramp.elements[1].color = (*[min(1, c * 1.3) for c in color], 1)
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    if faction in ("waste", "crypt", "neutral"):
        folder = {"waste": "rusty_metal_02", "crypt": "medieval_blocks_02", "neutral": "medieval_wood"}[faction]
        files = [f for f in os.listdir(os.path.join(CC0, folder)) if "_diff_" in f and not f.endswith(".import")]
        img = nt.nodes.new("ShaderNodeTexImage"); img.image = bpy.data.images.load(os.path.join(CC0, folder, files[0]))
        mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (0.35, 0.35, 0.35)
        nt.links.new(coord.outputs["Object"], mp.inputs["Vector"]); nt.links.new(mp.outputs["Vector"], img.inputs["Vector"])
        bw = nt.nodes.new("ShaderNodeRGBToBW"); nt.links.new(img.outputs["Color"], bw.inputs["Color"])
        nt.links.new(bw.outputs["Val"], ramp.inputs["Fac"]); nt.links.new(bw.outputs["Val"], bump.inputs["Height"])
        b.inputs["Metallic"].default_value = 0.6 if faction == "waste" else 0.0
        b.inputs["Roughness"].default_value = 0.6
    else:
        if faction == "tide":
            t = nt.nodes.new("ShaderNodeTexWave"); t.wave_type = "RINGS"; t.inputs["Scale"].default_value = 1.6; t.inputs["Distortion"].default_value = 6; t.inputs["Detail"].default_value = 4
        elif faction == "club":
            t = nt.nodes.new("ShaderNodeTexBrick"); t.inputs["Scale"].default_value = 9; t.inputs["Mortar Size"].default_value = 0.01
            t.inputs["Color1"].default_value = (0.6, 0.6, 0.6, 1); t.inputs["Color2"].default_value = (0.4, 0.4, 0.4, 1)
        else:  # aurelind: green enamel marbled
            t = nt.nodes.new("ShaderNodeTexWave"); t.inputs["Scale"].default_value = 2.5; t.inputs["Distortion"].default_value = 14; t.inputs["Detail"].default_value = 8
        nt.links.new(coord.outputs["Object"], t.inputs["Vector"])
        out = t.outputs["Fac"]
        nt.links.new(out, ramp.inputs["Fac"]); nt.links.new(out, bump.inputs["Height"])
        b.inputs["Metallic"].default_value = 0.7 if faction == "tide" else 0.2
        b.inputs["Roughness"].default_value = 0.35 if faction != "club" else 0.15
        b.inputs["Coat Weight"].default_value = 0.6 if faction in ("club", "aurelind") else 0.0
    return m


# ---------------------------------------------------------------- geometry helpers

def rrect(x0, y0, x1, y1, r, seg=8):
    pts = []
    for cx, cy, a0 in ((x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def arch(x0, y0, x1, y1, seg=24):
    """A window with a round-arched top (for creatures)."""
    r = (x1 - x0) / 2
    top = y1 - r * 0.45
    pts = [(x0, y0), (x1, y0), (x1, top)]
    for i in range(1, seg):
        a = math.pi * i / seg
        pts.append(((x0 + x1) / 2 + math.cos(a) * r, top + math.sin(a) * r * 0.45))
    pts.append((x0, top))
    return pts


def ellipse(cx, cy, rx, ry, seg=48):
    return [(cx + math.cos(2 * math.pi * i / seg) * rx, cy + math.sin(2 * math.pi * i / seg) * ry) for i in range(seg)]


def slab(name, outline, depth, z, material, holes=(), bevel=0.04, segs=3):
    """Extrudes a 2D outline (with optional holes) into a bevelled slab whose top is at z."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    rings = [outline] + list(holes)
    edges = []
    for ring in rings:
        vs = [bm.verts.new((x, y, z - depth)) for x, y in ring]
        for i in range(len(vs)):
            edges.append(bm.edges.new((vs[i], vs[(i + 1) % len(vs)])))
    bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=True, edges=edges)
    faces = list(bm.faces)
    ext = bmesh.ops.extrude_face_region(bm, geom=faces)
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    if bevel:
        mod = o.modifiers.new("b", "BEVEL"); mod.width = bevel; mod.segments = segs; mod.limit_method = "ANGLE"
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def ring(name, outline, width, depth, z, material, bevel=0.03):
    """A raised rim along a closed outline (an inset copy cut out of it)."""
    cx = sum(p[0] for p in outline) / len(outline); cy = sum(p[1] for p in outline) / len(outline)
    inner = []
    for x, y in outline:
        d = Vector((x - cx, y - cy)); L = d.length
        inner.append((x - d.x / L * width, y - d.y / L * width) if L > 0 else (x, y))
    grow = []
    for x, y in outline:
        d = Vector((x - cx, y - cy)); L = d.length
        grow.append((x + d.x / L * width * 0.2, y + d.y / L * width * 0.2) if L > 0 else (x, y))
    return slab(name, grow, depth, z, material, [inner], bevel)


def disc(name, at, r, depth, z, material, seg=48, bevel=0.03):
    return slab(name, ellipse(at[0], at[1], r, r, seg), depth, z, material, (), bevel)


# ---------------------------------------------------------------- faction ornaments

def ornaments(kind, accent, z):
    m = metal("orn", accent, 0.25)
    spots = [(0.35, 6.75), (4.65, 6.75), (0.3, 0.3), (4.7, 0.3)]
    if kind == "shell":
        for x, y in spots:
            up = 1 if y > 3 else -1
            for i in range(7):  # fan of ridges = a scallop shell
                a = math.radians(-60 + i * 20)
                pts = [(x, y), (x + math.sin(a - 0.12) * 0.42, y - up * math.cos(a - 0.12) * 0.42), (x + math.sin(a + 0.12) * 0.42, y - up * math.cos(a + 0.12) * 0.42)]
                slab("shell", pts, 0.08, z + 0.02 * i, m, (), 0.02)
    elif kind == "rivet":
        for t in range(18):
            x = 0.18 + t * (4.64 / 17)
            for y in (0.16, 6.84):
                disc("rivet", (x, y), 0.07, 0.06, z + 0.04, m, 16, 0.03)
        for x, y in spots:
            disc("bolt", (x, y), 0.2, 0.08, z + 0.06, m, 6, 0.02)
    elif kind == "skull":
        bone = metal("bone", (0.85, 0.82, 0.7), 0.55, 0.2); bone.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.0
        for x, y in spots:
            disc("skull", (x, y + 0.03), 0.22, 0.12, z + 0.08, bone, 32, 0.08)
            slab("jaw", rrect(x - 0.12, y - 0.22, x + 0.12, y - 0.08, 0.04), 0.08, z + 0.05, bone, (), 0.03)
            for ex in (-0.08, 0.08):
                disc("eye", (x + ex, y + 0.04), 0.055, 0.04, z + 0.1, metal("dark", (0.02, 0.02, 0.02), 0.6), 16, 0.01)
    elif kind == "leaf":
        for x, y in spots:
            for i in range(3):
                a = math.radians(-50 + i * 50) + (0 if y > 3 else math.pi)
                tip = (x + math.sin(a) * 0.5, y + math.cos(a) * 0.5)
                side = Vector((math.cos(a), -math.sin(a))) * 0.12
                mid = ((x + tip[0]) / 2, (y + tip[1]) / 2)
                pts = [(x, y), (mid[0] + side.x, mid[1] + side.y), tip, (mid[0] - side.x, mid[1] - side.y)]
                slab("leaf", pts, 0.06, z + 0.03 + i * 0.01, m, (), 0.04)
            disc("acorn", (x, y), 0.1, 0.1, z + 0.08, metal("acorn", (0.55, 0.32, 0.12), 0.4), 24, 0.05)
    elif kind == "chip":
        cols = [(0.8, 0.05, 0.08), (0.05, 0.05, 0.05), (0.1, 0.3, 0.9), (0.1, 0.6, 0.2)]
        for i, (x, y) in enumerate(spots):
            chip = metal("chip%d" % i, cols[i], 0.35, 0.1); chip.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.0
            disc("chip", (x, y), 0.28, 0.08, z + 0.06, chip, 40, 0.03)
            ring("chipedge", ellipse(x, y, 0.22, 0.22, 40), 0.05, 0.03, z + 0.09, m, 0.01)
        neon = glass("neon", (1.0, 0.15, 0.6), 6)
        slab("neon", rrect(0.9, 6.86, 4.1, 6.93, 0.03), 0.04, z + 0.05, neon, (), 0.01)
    elif kind == "rope":
        rope = cloth("rope", (0.62, 0.5, 0.3))
        for t in range(60):
            x = 0.15 + t * (4.7 / 59)
            for y in (0.13, 6.87):
                disc("knot", (x, y), 0.065, 0.06, z + 0.04, rope, 12, 0.03)


# ---------------------------------------------------------------- one frame

def build_frame(faction, kind):
    plate_c, accent_c, cloth_c, orn = FACTIONS[faction]
    plate = plate_mat(faction, plate_c)
    accent = metal("accent", accent_c, 0.22, 0.3)
    window = arch(*ART) if kind == "creature" else ellipse((ART[0] + ART[2]) / 2, (ART[1] + ART[3]) / 2 - 0.05, (ART[2] - ART[0]) / 2, (ART[3] - ART[1]) / 2 + 0.05)
    text = rrect(*TEXT, 0.25)
    outline = rrect(0.0, 0.0, W, H, 0.32, 10)
    slab("plate", outline, 0.25, 0.25, plate, [window, text], 0.06)
    ring("outer", outline, 0.12, 0.08, 0.33, accent, 0.03)
    ring("artrim", window, 0.1, 0.12, 0.37, accent, 0.03)
    ring("textrim", text, 0.08, 0.08, 0.33, accent, 0.03)
    slab("plaque", text, 0.05, 0.12, parchment(), (), 0.0)
    # name banner: a ribbon with folded tails, slightly arched
    m = cloth("banner", cloth_c)
    pts = []
    for i in range(41):
        t = i / 40; x = 0.15 + t * 4.7; y = BANNER_Y - 0.28 + math.sin(t * math.pi) * 0.12
        pts.append((x, y))
    for i in range(40, -1, -1):
        t = i / 40; x = 0.15 + t * 4.7; y = BANNER_Y + 0.28 + math.sin(t * math.pi) * 0.12
        pts.append((x, y))
    slab("banner", pts, 0.08, 0.45, m, (), 0.03)
    for side in (-1, 1):
        cx = W / 2 + side * 2.35
        slab("tail", [(cx, BANNER_Y - 0.3), (cx + side * 0.25, BANNER_Y - 0.42), (cx + side * 0.12, BANNER_Y), (cx + side * 0.25, BANNER_Y + 0.42), (cx, BANNER_Y + 0.3)], 0.05, 0.4, cloth("tail", tuple(c * 0.6 for c in cloth_c)), (), 0.02)
    for edge in (-1, 1):  # gold piping along both edges of the ribbon
        strip = []
        for i in range(41):
            t = i / 40; x = 0.15 + t * 4.7; y = BANNER_Y + edge * 0.28 + math.sin(t * math.pi) * 0.12
            strip.append((x, y + 0.035))
        for i in range(40, -1, -1):
            t = i / 40; x = 0.15 + t * 4.7; y = BANNER_Y + edge * 0.28 + math.sin(t * math.pi) * 0.12
            strip.append((x, y - 0.035))
        slab("piping", strip, 0.03, 0.5, accent, (), 0.01)
    # tribe plate and gem setting
    slab("tribeplate", rrect(1.6, 0.18, 3.4, 0.62, 0.15), 0.08, 0.4, accent, (), 0.03)
    disc("gemsetting", (W / 2, BANNER_Y - 0.42), 0.2, 0.08, 0.5, accent, 32, 0.03)
    if kind == "creature":  # sockets for the attack and health badges
        disc("sockA", (0.62, 0.62), 0.55, 0.06, 0.35, accent, 48, 0.03)
        disc("sockH", (4.38, 0.62), 0.55, 0.06, 0.35, accent, 48, 0.03)
    disc("sockC", (0.62, 6.38), 0.55, 0.06, 0.35, accent, 6, 0.03)
    ornaments(orn, accent_c, 0.38)


def build_layer(name):
    """Separate parts drawn over every frame: cost gem, attack, health, rarity gems, legendary crest, card back."""
    if name == "cost":
        o = slab("cost", ellipse(0.62, 6.38, 0.48, 0.48, 6), 0.25, 0.7, glass("mana", (0.15, 0.35, 1.0), 0.4), (), 0.12)
        o.rotation_euler.z = 0
    elif name == "attack":
        gold = metal("gold", (0.95, 0.7, 0.25), 0.25)
        disc("atk", (0.62, 0.62), 0.48, 0.2, 0.65, gold, 48, 0.08)
        steel = metal("steel", (0.85, 0.88, 0.92), 0.2)
        slab("blade", [(0.35, 0.35), (0.42, 0.28), (0.92, 0.78), (0.95, 0.95), (0.78, 0.92)], 0.05, 0.72, steel, (), 0.02)
    elif name == "health":
        red = glass("blood", (0.85, 0.05, 0.05), 0.3)
        pts = []
        for i in range(48):  # a drop: circle at the bottom, point at the top
            a = 2 * math.pi * i / 48
            r = 0.42 * (1 - 0.55 * max(0.0, math.sin(a)) ** 6)
            pts.append((4.38 + math.cos(a) * r * 0.95, 0.55 + math.sin(a) * r + max(0.0, math.sin(a)) ** 6 * 0.45))
        slab("hp", pts, 0.25, 0.7, red, (), 0.12)
    elif name.startswith("gem_"):
        disc("gem", (W / 2, BANNER_Y - 0.42), 0.15, 0.15, 0.62, glass("g", RARITY[name[4:]], 1.5), 8, 0.06)
    elif name == "crest":  # legendary: two golden lobster claws over the arch
        gold = metal("gold", (1.0, 0.72, 0.2), 0.2)
        for side in (-1, 1):
            cx = W / 2 + side * 1.2
            pts = []
            for i in range(25):
                a = math.radians(200 - i * 7.5) if side < 0 else math.radians(-20 + i * 7.5)
                pts.append((cx + math.cos(a) * 0.9, 6.55 + math.sin(a) * 0.7))
            pts += [(cx + side * 0.15, 6.7), (cx, 6.6)]
            slab("claw", pts, 0.18, 0.8, gold, (), 0.08)
        disc("crestgem", (W / 2, 6.9), 0.2, 0.15, 0.85, glass("cg", (1.0, 0.4, 0.05), 2), 8, 0.06)
    elif name == "back":
        build_back()


def build_back():
    """Card back: deep crimson with a gold border and the medallion the painted logo sits in (tools/paint_logo.py)."""
    red = metal("backred", (0.35, 0.03, 0.08), 0.45, 0.2); red.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.3
    gold = metal("gold", (1.0, 0.72, 0.25), 0.22)
    outline = rrect(0, 0, W, H, 0.32, 10)
    slab("back", outline, 0.2, 0.2, red, (), 0.05)
    ring("b1", outline, 0.14, 0.08, 0.28, gold, 0.03)
    ring("b2", rrect(0.35, 0.35, W - 0.35, H - 0.35, 0.25), 0.06, 0.05, 0.26, gold, 0.02)
    disc("medal", (W / 2, H / 2), 1.55, 0.1, 0.3, metal("medal", (0.12, 0.02, 0.04), 0.35), 64, 0.04)
    ring("medalrim", ellipse(W / 2, H / 2, 1.55, 1.55, 64), 0.1, 0.06, 0.36, gold, 0.02)
    # the logo itself is painted into the medallion afterwards by tools/paint_logo.py


# ---------------------------------------------------------------- render + crop

LAYOUT = {}


def render(name, builder):
    reset()
    builder()
    path = os.path.join(OUT, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = Image.open(path)
    box = img.getbbox() or (0, 0, img.width, img.height)
    img.crop(box).save(path)
    LAYOUT[name] = [box[0], box[1], box[2] - box[0], box[3] - box[1]]
    print("FRAME", name, LAYOUT[name], flush=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]
    jobs = []
    for f in FACTIONS:
        for kind in ("creature", "spell"):
            jobs.append(("frame_%s_%s" % (f, kind), (lambda f=f, kind=kind: build_frame(f, kind))))
    for layer in ["cost", "attack", "health", "crest", "back"] + ["gem_" + r for r in RARITY]:
        jobs.append((layer, (lambda layer=layer: build_layer(layer))))
    path = os.path.join(ROOT, "data", "tcg", "card_layout.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    for name, fn in jobs:
        if not want or name in want:
            render(name, fn)
    layers = old.get("layers", {}); layers.update(LAYOUT)
    s = PX
    layout = {"version": 1, "_about": "Card layout in card pixels (card %d x %d). layers: [x, y, w, h] of each picture in assets/tcg/frames/ (made by tools/blender/card_frames.py). boxes: where the game draws the art and the words." % (W * s, H * s),
              "size": [int(W * s), int(H * s)], "layers": layers,
              "boxes": {"art": [int(ART[0] * s) - 6, int((H - ART[3]) * s) - 6, int((ART[2] - ART[0]) * s) + 12, int((ART[3] - ART[1]) * s) + 12],
                        "name": [int(0.5 * s), int((H - BANNER_Y - 0.28) * s), int(4.0 * s), int(0.56 * s)],
                        "text": [int((TEXT[0] + 0.1) * s), int((H - TEXT[3] + 0.08) * s), int((TEXT[2] - TEXT[0] - 0.2) * s), int((TEXT[3] - TEXT[1] - 0.16) * s)],
                        "cost": [int(0.14 * s), int((H - 6.86) * s), int(0.96 * s), int(0.96 * s)],
                        "attack": [int(0.14 * s), int((H - 1.1) * s), int(0.96 * s), int(0.96 * s)],
                        "health": [int(3.9 * s), int((H - 1.1) * s), int(0.96 * s), int(0.96 * s)],
                        "tribe": [int(1.6 * s), int((H - 0.62) * s), int(1.8 * s), int(0.44 * s)]}}
    json.dump(layout, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()

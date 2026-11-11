# Purpose: developer-time helpers shared by the fantasy world's model scripts (fantasy_props.py, fantasy_life.py):
# materials named after what a part is MADE OF (the game puts a real texture on each name and keeps the part's own
# colour, see game/fantasy_models.gd and data/surfaces.json "fx_<kind>"), the regional colour schemes, the half-timbered
# house builder, and the footprint list data/fantasy/props.json (size of every model, used for colliders and so that
# creatures walk around things).
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")
FOOTPRINTS = os.path.join(os.path.dirname(__file__), "..", "..", "data", "fantasy", "props.json")
KINDS = ["paint", "plaster", "adobe", "timber", "wood", "roof", "thatch", "slate", "stone", "sandstone", "cloth", "leather", "metal", "bark", "pinebark", "leaf", "rock", "fur", "scale", "ice", "bone", "feather"]
MATS = {}
GLOW = None
SCHEME_KIND = {"wall": "plaster", "timber": "timber", "roof": "roof", "stone": "stone", "trim": "wood"}
WOOD, DARK, IRON, GREY, CLOTH, STRAW, ROPE = (0.55, 0.42, 0.27), (0.3, 0.22, 0.14), (0.3, 0.3, 0.33), (0.6, 0.58, 0.55), (0.85, 0.8, 0.68), (0.85, 0.72, 0.35), (0.7, 0.6, 0.4)

# One colour scheme per region: wall, timber, roof, stone, trim, and whether roofs are flat (desert).
SCHEMES = {
    "amber": {"kinds": {"wall": "plaster", "roof": "roof", "stone": "stone"}, "wall": (0.93, 0.88, 0.74), "timber": (0.36, 0.24, 0.14), "roof": (0.78, 0.6, 0.28), "stone": (0.62, 0.6, 0.56), "trim": (0.5, 0.24, 0.18)},
    "green": {"kinds": {"wall": "plaster", "roof": "thatch", "stone": "stone"}, "wall": (0.72, 0.66, 0.5), "timber": (0.25, 0.18, 0.1), "roof": (0.3, 0.42, 0.22), "stone": (0.45, 0.46, 0.4), "trim": (0.75, 0.6, 0.2)},
    "brine": {"kinds": {"wall": "plaster", "roof": "slate", "stone": "stone"}, "wall": (0.96, 0.96, 0.94), "timber": (0.5, 0.42, 0.34), "roof": (0.42, 0.5, 0.6), "stone": (0.75, 0.76, 0.78), "trim": (0.25, 0.38, 0.52)},
    "sun": {"kinds": {"wall": "adobe", "roof": "adobe", "stone": "sandstone"}, "wall": (0.9, 0.76, 0.52), "timber": (0.5, 0.34, 0.2), "roof": (0.84, 0.66, 0.42), "stone": (0.78, 0.62, 0.42), "trim": (0.25, 0.5, 0.52), "flat": True},
    "frost": {"kinds": {"wall": "plaster", "roof": "slate", "stone": "stone"}, "wall": (0.82, 0.86, 0.92), "timber": (0.3, 0.3, 0.38), "roof": (0.52, 0.62, 0.72), "stone": (0.6, 0.64, 0.72), "trim": (0.62, 0.3, 0.28)},
    "cinder": {"kinds": {"wall": "stone", "roof": "slate", "stone": "stone"}, "wall": (0.3, 0.27, 0.28), "timber": (0.12, 0.1, 0.1), "roof": (0.5, 0.26, 0.2), "stone": (0.2, 0.19, 0.2), "trim": (1.0, 0.55, 0.1)},
    "storm": {"kinds": {"wall": "stone", "roof": "slate", "stone": "stone"}, "wall": (0.6, 0.6, 0.64), "timber": (0.28, 0.26, 0.3), "roof": (0.36, 0.34, 0.5), "stone": (0.48, 0.48, 0.54), "trim": (0.5, 0.46, 0.66)},
    "pale": {"kinds": {"wall": "plaster", "roof": "slate", "stone": "stone"}, "wall": (0.88, 0.88, 0.88), "timber": (0.6, 0.6, 0.6), "roof": (0.78, 0.78, 0.8), "stone": (0.7, 0.7, 0.72), "trim": (0.5, 0.5, 0.52)},
}




def init():
    global GLOW
    kit.FLOAT_COLORS = True  # colours reach the file exactly as real() gives them
    for kind in KINDS:
        MATS[kind] = kit.material(kind, None, (1.0, 1.0, 1.0))
    GLOW = kit.material("glow", None, (1.0, 0.9, 0.6))  # windows, fire, crystals: the game makes it unshaded


def real(rgb):
    """A colour chosen by eye (as on screen) calmed down for the realistic look: in linear light a third of the
    saturation is taken out and it is well over a third darker, so sunlit walls do not burn out. It is stored screen-encoded
    (the game's materials are flagged vertex_color_is_srgb), which keeps dark colours smooth in eight bits. The
    game's land and grass go through the same sum (game/fantasy_ground.gd toned), so models and ground stay matched."""
    lin = [max(v, 0.0) ** 2.2 for v in rgb]
    lum = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    return tuple(((lum + (v - lum) * 0.7) * 0.62) ** (1 / 2.2) for v in lin)


def K(kind, rgb):
    """A part made of `kind`, in its own colour (given as seen on screen)."""
    return (MATS[kind], real(rgb))


def c(rgb):
    return K("paint", rgb)


def S(scheme, key):
    """A part in one of a region scheme's colours (wall, timber, roof, stone, trim), made of what that region builds with."""
    return K(scheme.get("kinds", {}).get(key, SCHEME_KIND[key]), scheme[key])


def blob(m, mat, radii, at, seed=0, rough=0.2, node="Body", cuts=2):
    """An uneven lump (foliage, boulders, heaps): a sphere whose surface is pushed in and out."""
    import random
    import bmesh
    from mathutils import Matrix
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=cuts, radius=1.0)
    rnd = random.Random(seed)
    for v in bm.verts:
        v.co *= 1.0 + rnd.uniform(-rough, rough)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((at[0], at[2], at[1])) @ Matrix.Diagonal((radii[0], radii[2], radii[1], 1.0)), verts=bm.verts[:])
    m._add(bm, mat, node, 0)


class Maker:
    """Builds and exports models and remembers their footprints."""

    def __init__(self):
        self.sizes = {}

    def model(self, name, build, solid=True, uv=0.5):
        m = kit.Model(name, uv_scale=uv, colored=True)
        build(m)
        lo, hi = [1e9] * 3, [-1e9] * 3
        for bm, _mats in m.nodes.values():
            for v in bm.verts:
                for i in range(3):
                    lo[i], hi[i] = min(lo[i], v.co[i]), max(hi[i], v.co[i])
        # Blender x = right, y = forward (the game's -z), z = up
        self.sizes[name] = {"w": round(hi[0] - lo[0], 2), "d": round(hi[1] - lo[1], 2), "h": round(hi[2], 2), "x": round((hi[0] + lo[0]) / 2, 2), "z": round(-(hi[1] + lo[1]) / 2, 2), "solid": solid}
        print(name, m.export(OUT), self.sizes[name])

    def save(self):
        known = {}
        if os.path.exists(FOOTPRINTS):
            known = json.load(open(FOOTPRINTS)).get("props", {})
        known.update(self.sizes)
        about = "Footprint of every fantasy model, written by tools/blender/fantasy_kit.py: w, d = size across and along (metres), h = height, x, z = middle of the footprint from the model's origin, solid = things walk around it."
        json.dump({"_about": about, "props": dict(sorted(known.items()))}, open(FOOTPRINTS, "w"), indent=1)


def house(m, s, w, d, floors, roof_h, chimney=True, frame=True, door_x=0.0):
    """A half-timbered house: stone footing, plastered floors with dark beams, gable roof (or flat with a parapet)."""
    wall_h = 0.5 + 2.5 * floors
    m.box(S(s, "stone"), (w + 0.2, 0.6, d + 0.2), (0, 0.3, 0), bevel=0.04)
    m.box(S(s, "wall"), (w, wall_h - 0.5, d), (0, 0.5 + (wall_h - 0.5) / 2, 0), bevel=0.03)
    if floors > 1:  # the upper floor juts out a little
        m.box(S(s, "wall"), (w + 0.5, 2.4, d + 0.5), (0, wall_h - 1.2, 0), bevel=0.03)
    if frame:
        big = 0.25 if floors > 1 else 0.0
        for sx in (-1, 1):
            for sf in (-1, 1):
                m.box(S(s, "timber"), (0.2, wall_h - 0.5, 0.2), (sx * (w / 2 + big), 0.5 + (wall_h - 0.5) / 2, sf * (d / 2 + big)), bevel=0.02)
        for y in ([3.0] if floors > 1 else []) + [wall_h - 0.1]:
            m.box(S(s, "timber"), (w + 2 * big + 0.24, 0.2, 0.2), (0, y, d / 2 + big), bevel=0.02)
            m.box(S(s, "timber"), (w + 2 * big + 0.24, 0.2, 0.2), (0, y, -d / 2 - big), bevel=0.02)
            m.box(S(s, "timber"), (0.2, 0.2, d + 2 * big + 0.24), (w / 2 + big, y, 0), bevel=0.02)
            m.box(S(s, "timber"), (0.2, 0.2, d + 2 * big + 0.24), (-w / 2 - big, y, 0), bevel=0.02)
        posts = max(1, int(w / 2.4))
        for i in range(1, posts):
            x = -w / 2 + w * i / posts
            for sf in (-1, 1):
                m.box(S(s, "timber"), (0.14, wall_h - 0.5, 0.1), (x, 0.5 + (wall_h - 0.5) / 2, sf * (d / 2 + big + 0.02)), bevel=0.015)
        for sx in (-1, 1):  # diagonal braces on the front
            m.rod(S(s, "timber"), 0.07, (sx * (w / 2 + big), wall_h - 2.3, d / 2 + big + 0.03), (sx * (w / 2 + big - 1.1), wall_h - 0.2, d / 2 + big + 0.03), segs=4)
    # door and windows (front = +f)
    front = d / 2 + (0.27 if floors > 1 else 0.02)
    m.box(S(s, "timber"), (1.1, 2.0, 0.12), (door_x, 1.55, d / 2 + 0.03), bevel=0.03)
    m.box(S(s, "trim"), (0.9, 1.8, 0.14), (door_x, 1.5, d / 2 + 0.04), bevel=0.03)
    m.ball(c((0.9, 0.8, 0.3)), 0.05, (door_x + 0.3, 1.5, d / 2 + 0.13), u=6, v=4)
    for floor in range(floors):
        y = 1.9 + 2.5 * floor
        for x in [v for v in (-w / 2 + 1.3, w / 2 - 1.3) if abs(v - door_x) > 1.2 or floor > 0]:
            f = front if floor > 0 else d / 2 + 0.02
            m.box(S(s, "timber"), (1.0, 1.1, 0.1), (x, y, f), bevel=0.02)
            m.box(c((0.35, 0.5, 0.65)), (0.8, 0.9, 0.12), (x, y, f + 0.01), bevel=0.01)
            m.box(S(s, "timber"), (0.06, 0.9, 0.14), (x, y, f + 0.01), bevel=0)
            m.box(S(s, "timber"), (0.8, 0.06, 0.14), (x, y, f + 0.01), bevel=0)
            m.box(S(s, "trim"), (1.1, 0.14, 0.26), (x, y - 0.62, f + 0.08), bevel=0.02)  # flower box
    grow = 0.5 if floors > 1 else 0.0
    if s.get("flat"):
        m.box(S(s, "roof"), (w + 0.4, 0.3, d + 0.4), (0, wall_h + 0.15, 0), bevel=0.04)
        for sx in (-1, 1):
            m.box(S(s, "wall"), (0.3, 0.5, d + 0.4), (sx * (w / 2 + 0.05), wall_h + 0.5, 0), bevel=0.04)
        for sf in (-1, 1):
            m.box(S(s, "wall"), (w + 0.4, 0.5, 0.3), (0, wall_h + 0.5, sf * (d / 2 + 0.05)), bevel=0.04)
        m.strip(S(s, "trim"), w * 0.8, 0.05, [(d / 2 + 0.3, wall_h - 0.2), (d / 2 + 1.8, wall_h - 0.7)], x=0)  # awning
    else:
        half = d / 2 + grow / 2 + 0.55
        m.prof(S(s, "roof"), w + grow + 0.9, [(-half, wall_h - 0.15), (0, wall_h + roof_h), (half, wall_h - 0.15)], x=0, bevel=0.05)
        m.prof(S(s, "wall"), w + grow, [(-half + 0.5, wall_h), (0, wall_h + roof_h - 0.45), (half - 0.5, wall_h)], x=0, bevel=0.0)
        m.box(S(s, "timber"), (w + grow + 1.0, 0.16, 0.2), (0, wall_h + roof_h + 0.02, 0), bevel=0.03)
        for k in range(1, 4):  # roof courses, so the big faces are not blank
            t = k / 4.0
            for sf in (-1, 1):
                m.box(K(s["kinds"]["roof"], tuple(v * 0.86 for v in s["roof"])), (w + grow + 0.94, 0.05, 0.12), (0, wall_h - 0.15 + (roof_h + 0.15) * (1 - t) + 0.04, sf * half * t), tilt=sf * math.degrees(math.atan2(roof_h + 0.15, half)), bevel=0)
    if chimney:
        top = wall_h + (0.9 if s.get("flat") else roof_h + 0.7)
        m.box(S(s, "stone"), (0.7, top - 0.5, 0.7), (w / 2 - 1.0, 0.5 + (top - 0.5) / 2, -d / 4), bevel=0.04)
        m.box(S(s, "stone"), (0.86, 0.2, 0.86), (w / 2 - 1.0, top, -d / 4), bevel=0.03)
    return wall_h



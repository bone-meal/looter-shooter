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
        if getattr(m, "walls", None):  # the builder named its solid parts itself ([x, z, width, depth] each, game axes): roofs and overhangs stop nobody
            self.sizes[name].update({"walls": m.walls, "wall_h": round(hi[2], 2)})
        print(name, m.export(OUT), self.sizes[name])

    def save(self):
        known = {}
        if os.path.exists(FOOTPRINTS):
            known = json.load(open(FOOTPRINTS)).get("props", {})
        known.update(self.sizes)
        about = "Footprint of every fantasy model, written by tools/blender/fantasy_kit.py: w, d = size across and along (metres), h = height, x, z = middle of the footprint from the model's origin, solid = things walk around it."
        json.dump({"_about": about, "props": dict(sorted(known.items()))}, open(FOOTPRINTS, "w"), indent=1)


def weathered(strength=1.0, moss=0.0):
    """Use as `with weathered():` round the parts of a building: every colour gets darker towards the ground (damp
    and splash-back) and drifts a little along the walls, so nothing is one flat tone. `moss` turns the damp foot
    green (old stone walls)."""
    import contextlib

    @contextlib.contextmanager
    def scope():
        def shade(co):
            low = math.exp(-max(co.z, 0.0) / 0.9)
            k = (1.0 - 0.28 * strength * low) * (1.0 + 0.05 * strength * math.sin(co.x * 1.7 + co.y * 2.3 + co.z * 0.9))
            return (k * (1.0 - 0.3 * moss * low), k, k * (1.0 - 0.38 * moss * low))
        before = kit.SHADE
        kit.SHADE = shade
        try:
            yield
        finally:
            kit.SHADE = before
    return scope()


def house(m, s, w, d, floors, roof_h, chimney=True, frame=True, door_x=0.0, gable_front=False):
    """A house in the region's way of building (see fantasy_house.py). Returns the height of its walls."""
    import fantasy_house
    return fantasy_house.build(m, s, w, d, floors, roof_h, chimney=chimney, frame=frame, door_x=door_x, gable_front=gable_front)



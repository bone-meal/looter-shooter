# Purpose: developer-time script. Models what round 3 of the fantasy world needs with tools/blender/fantasy_kit.py:
# the staff every caster carries for now (staff_orb: black shaft, silver rings, twin-pronged head, glowing orb, a ring
# round the orb), the gate of a palisade (palisade_gate), containers whose lids and doors are parts of their own so the
# game can open them (chest, cupboard, loot_barrel, loot_crate), the WALK-IN houses of the main story (open_house_<scheme>, open_farmhouse: hollow, a real doorway,
# their wall pieces written into data/fantasy/props.json as "walls" so the game can build colliders you can walk
# between), and the furniture that fills every interior (bed, chest, cupboard, shelf, hearth, oven, counter, stool,
# pew, altar, bedroll, bookcase, keg). Model space: x right, y up, f forward (the front, where the door is).
# Run: python3 tools/blender/fantasy_inside.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_house as fh
import fantasy_kit as fk
from fantasy_kit import K, S, c, WOOD, DARK, IRON, GREY, CLOTH, STRAW

BLACK = (0.07, 0.07, 0.08)
SILVER = (0.78, 0.79, 0.82)
WALL_T = 0.3  # thickness of a walk-in house's walls
DOOR_W = 1.5


def staff(m):
    # round 4: the director wants a much larger head and a thicker shaft than the first version
    top = 1.08  # where the shaft ends and the head begins
    m.rod(c(BLACK), 0.026, (0, -0.2, 0), (0, top, 0), segs=10)
    m.lathe(c(BLACK), [(0.028, 0.0), (0.034, -0.04), (0.055, -0.1), (0.06, -0.125), (0.0, -0.125)], (0, -0.2, 0), segs=12)  # flared foot
    m.rod(K("metal", SILVER), 0.062, (0, -0.34, 0), (0, -0.318, 0), segs=12)
    for y in (-0.215, -0.235, top - 0.03, top + 0.005):
        m.rod(K("metal", SILVER), 0.033, (0, y, 0), (0, y + 0.012, 0), segs=10)
    orb = top + 0.36
    for side in (-1, 1):  # two prongs that part round the orb and close again into twin points
        m.loft(c(BLACK), [(side * 0.02, top + 0.01, 0, 0.02, 0.02), (side * 0.1, top + 0.15, 0, 0.018, 0.024), (side * 0.14, orb, 0, 0.018, 0.032),
            (side * 0.118, orb + 0.17, 0, 0.024, 0.042), (side * 0.072, orb + 0.34, 0, 0.02, 0.03), (side * 0.028, orb + 0.56, 0, 0.002, 0.004)], segs=8, steps=3)
        m.rod(K("metal", SILVER), 0.025, (side * 0.074, top + 0.1, 0), (side * 0.088, top + 0.135, 0), segs=8)
        for face in (-1, 1):  # glowing inlays near the points
            m.box(fk.GLOW, (0.01, 0.13, 0.005), (side * 0.083, orb + 0.28, face * 0.031), tilt=0, bevel=0)
    m.node("Orb", (0, orb, 0))
    m.ball(fk.GLOW, 0.088, (0, orb, 0), node="Orb", u=16, v=10)
    m.node("Ring", (0, orb, 0))
    ring = [(0.16 + 0.008 * math.cos(a), 0.008 * math.sin(a)) for a in [k * math.pi / 3 for k in range(7)]]
    m.lathe(K("metal", SILVER), ring, (0, orb, 0), node="Ring", segs=28)


def palisade_gate(m):
    """The way through a palisade: two heavy posts, a beam across, stakes filling out to the wall on each side."""
    for sx in (-1, 1):
        m.rod(K("bark", (0.4, 0.3, 0.2)), 0.3, (sx * 2.3, 0, 0), (sx * 2.3, 4.3, 0), r2=0.24, segs=8)
        m.rod(K("wood", (0.75, 0.62, 0.42)), 0.24, (sx * 2.3, 4.3, 0), (sx * 2.3, 4.9, 0), r2=0.02, segs=8)
        for k in range(2):
            h = 2.6 + 0.3 * k
            m.rod(K("bark", (0.42, 0.32, 0.22)), 0.16, (sx * (2.75 + k * 0.4), 0, 0), (sx * (2.75 + k * 0.4), h, 0), r2=0.13, segs=6)
            m.rod(K("wood", (0.75, 0.62, 0.42)), 0.13, (sx * (2.75 + k * 0.4), h, 0), (sx * (2.75 + k * 0.4), h + 0.4, 0), r2=0.01, segs=6)
    m.rod(K("bark", (0.4, 0.3, 0.2)), 0.2, (-2.7, 3.9, 0), (2.7, 3.9, 0), segs=8)
    for sx in (-1, 1):
        m.rod(K("cloth", (0.7, 0.62, 0.45)), 0.03, (sx * 2.0, 3.9, 0.1), (sx * 2.3, 3.2, 0.1), segs=4)  # lashings


def loot_barrel(m):
    m.lathe(K("wood", WOOD), [(0.32, 0.0), (0.41, 0.26), (0.43, 0.52), (0.41, 0.78), (0.33, 1.02)], (0, 0, 0), segs=12)
    for h in (0.2, 0.82):
        m.lathe(K("metal", IRON), [(0.405, h - 0.03), (0.415, h + 0.03)], (0, 0, 0), segs=12)
    m.lathe(K("wood", (0.2, 0.15, 0.1)), [(0.0, 0.94), (0.32, 0.94), (0.32, 0.96), (0.0, 0.96)], (0, 0, 0), segs=12)  # the dark inside
    m.node("Lid", (0, 1.03, -0.33))  # hinged at the back
    m.lathe(K("wood", DARK), [(0.0, 1.02), (0.35, 1.02), (0.35, 1.07), (0.0, 1.07)], (0, 0, 0), node="Lid", segs=12)
    m.rod(K("metal", IRON), 0.03, (0, 1.07, 0), (0, 1.13, 0), node="Lid", segs=6)


def loot_crate(m):
    s = 0.8
    m.box(K("wood", WOOD), (s, s * 0.85, s), (0, s * 0.425, 0), bevel=0.02)
    for sx in (-1, 1):
        m.box(K("wood", DARK), (0.06, s * 0.85 + 0.02, s + 0.02), (sx * (s / 2 - 0.05), s * 0.425, 0), bevel=0.01)
    m.node("Lid", (0, s * 0.85, -s / 2))  # hinged at the back
    m.box(K("wood", DARK), (s + 0.04, 0.06, s + 0.04), (0, s * 0.85 + 0.03, 0), bevel=0.01, node="Lid")
    for sf in (-0.25, 0.25):
        m.box(K("wood", WOOD), (s + 0.06, 0.03, 0.12), (0, s * 0.85 + 0.07, sf), bevel=0.005, node="Lid")


def open_house(m, s, w, d, wall_h=3.2, roof_h=2.6, chimney=True):
    """A hollow house: plank floor, four walls with a doorway in the front, a ceiling under the roof. Outside it is
    built like every other house of its region (fantasy_house.py): frame or cut stone, leaded windows, a real roof."""
    t = WALL_T
    kind = s.get("kinds", {}).get("wall", "plaster")
    flat = bool(s.get("flat"))
    with fk.weathered():
        m.box(K("wood", (0.5, 0.38, 0.25)), (w - 0.1, 0.16, d - 0.1), (0, 0.08, 0), bevel=0.0)
        m.box(S(s, "wall"), (w, wall_h, t), (0, wall_h / 2, -d / 2 + t / 2), bevel=0.0)
        fw = (w - DOOR_W) / 2
        for sx in (-1, 1):
            m.box(S(s, "wall"), (t, wall_h, d - 2 * t), (sx * (w / 2 - t / 2), wall_h / 2, 0), bevel=0.0)
            m.box(S(s, "wall"), (fw, wall_h, t), (sx * (DOOR_W / 2 + fw / 2), wall_h / 2, d / 2 - t / 2), bevel=0.0)
            m.box(S(s, "timber"), (0.16, 2.3, t + 0.1), (sx * (DOOR_W / 2 + 0.02), 1.15, d / 2 - t / 2), bevel=0.0)  # door posts
        m.box(S(s, "wall"), (DOOR_W, wall_h - 2.3, t), (0, 2.3 + (wall_h - 2.3) / 2, d / 2 - t / 2), bevel=0.0)  # above the door
        m.box(S(s, "timber"), (DOOR_W + 0.3, 0.18, t + 0.1), (0, 2.36, d / 2 - t / 2), bevel=0.0)
        m.box(K("wood", (0.42, 0.32, 0.2)), (w - 0.2, 0.1, d - 0.2), (0, wall_h - 0.05, 0), bevel=0.0)  # ceiling boards
        for k in range(1, 4):  # ceiling beams
            m.box(S(s, "timber"), (0.18, 0.2, d - 2 * t), (-w / 2 + w * k / 4, wall_h - 0.2, 0), bevel=0.0)
        for name, plane, half in (("front", d / 2, w / 2), ("back", d / 2, w / 2), ("right", w / 2, d / 2), ("left", w / 2, d / 2)):
            face = fh.Face(m, name, plane, half)
            door = name == "front"
            for a, b in ([(-half, -DOOR_W / 2 - 0.1), (DOOR_W / 2 + 0.1, half)] if door else [(-half - 0.14, half + 0.14)]):
                face.box(S(s, "stone"), b - a, 0.5, 0.14, (a + b) / 2, 0.25, 0.07, bevel=fh.soft(0.03))  # footing
            if kind == "plaster" and not flat:
                fh.timber_face(face, s, 0.5, wall_h - 0.5, gap=(0.0, DOOR_W + 0.3) if door else None)
            elif kind == "stone":
                fh.stone_face(face, s, 0.0, wall_h)
            spots = [-half * 0.62, half * 0.62] if name in ("front", "back") else [0.0]
            for u in spots:  # no shutters beside the doorway: the open door lies against that wall
                fh.window(face, s, u, 1.95, shutters=not flat and not door, stone=kind == "stone" or flat)
        front = fh.Face(m, "front", d / 2, w / 2)
        front.box(S(s, "trim"), 1.0, 2.15, 0.08, -DOOR_W / 2 - 0.62, 1.15, 0.13)  # the door, swung back against the wall
        for dy in () if fh.PLAIN else (0.55, 1.75):
            front.box(K("metal", fh.IRON), 0.9, 0.07, 0.03, -DOOR_W / 2 - 0.62, dy, 0.185)
        front.box(S(s, "stone"), DOOR_W + 0.3, 0.1, 0.5, 0.0, 0.05, 0.2, bevel=fh.soft(0.03))
        if flat:
            fh.flat_roof(m, s, w / 2, d / 2, wall_h)
        else:
            fh.gable_roof(m, s, w / 2, d / 2, wall_h, roof_h, timbered=kind == "plaster")
        if chimney:
            fh.chimney_stack(m, s, -w / 2 + 1.2, -d / 2 - 0.3, wall_h + (1.2 if flat else roof_h * 0.55 + 1.0))
    # the wall pieces as boxes in the game's own axes (x right, z = -f): [x, z, width, depth]
    fw = (w - DOOR_W) / 2
    walls = [[0, d / 2 - t / 2, w, t], [w / 2 - t / 2, 0, t, d], [-w / 2 + t / 2, 0, t, d],
        [DOOR_W / 2 + fw / 2, -d / 2 + t / 2, fw, t], [-DOOR_W / 2 - fw / 2, -d / 2 + t / 2, fw, t]]
    return {"walls": [[round(v, 3) for v in piece] for piece in walls], "wall_h": wall_h, "inner": [round(w / 2 - t - 0.35, 2), round(d / 2 - t - 0.35, 2)]}


def furniture(mk):
    def bed(m):
        m.box(K("wood", WOOD), (1.0, 0.3, 2.0), (0, 0.3, 0), bevel=0.02)
        m.box(K("wood", DARK), (1.0, 0.9, 0.08), (0, 0.6, -1.0), bevel=0.02)
        m.box(K("cloth", (0.75, 0.7, 0.6)), (0.92, 0.16, 1.9), (0, 0.52, 0.02), bevel=0.05)
        m.box(K("cloth", (0.5, 0.25, 0.2)), (0.94, 0.1, 1.2), (0, 0.6, 0.36), bevel=0.04)
        m.box(K("cloth", (0.9, 0.88, 0.8)), (0.6, 0.12, 0.34), (0, 0.66, -0.72), bevel=0.05)
    def chest(m):
        m.box(K("wood", WOOD), (1.0, 0.5, 0.6), (0, 0.25, 0), bevel=0.02)
        m.box(K("wood", (0.2, 0.15, 0.1)), (0.9, 0.02, 0.5), (0, 0.5, 0), bevel=0.0)  # the dark inside, seen when the lid is up
        for x in (-0.36, 0.36):
            m.box(K("metal", IRON), (0.07, 0.52, 0.64), (x, 0.25, 0), bevel=0.01)
        m.node("Lid", (0, 0.5, -0.3))  # hinged along the back edge
        m.prof(K("wood", DARK), 1.0, [(-0.3, 0.5), (-0.2, 0.68), (0.2, 0.68), (0.3, 0.5)], x=0, bevel=0.02, node="Lid")
        for x in (-0.36, 0.36):
            m.prof(K("metal", IRON), 0.07, [(-0.32, 0.5), (-0.21, 0.7), (0.21, 0.7), (0.32, 0.5)], x=x, bevel=0.005, node="Lid")
        m.box(K("metal", (0.8, 0.7, 0.3)), (0.12, 0.14, 0.04), (0, 0.5, 0.31), bevel=0.01, node="Lid")
    def cupboard(m):
        m.box(K("wood", WOOD), (1.3, 2.0, 0.55), (0, 1.0, 0), bevel=0.03)
        m.box(K("wood", (0.2, 0.15, 0.1)), (1.16, 1.7, 0.02), (0, 1.05, 0.27), bevel=0.0)  # the dark inside, seen when the doors swing out
        for sx, name in ((-1, "DoorL"), (1, "DoorR")):
            m.node(name, (sx * 0.61, 1.05, 0.28))  # each door hinged at its outer edge
            m.box(K("wood", DARK), (0.58, 1.7, 0.04), (sx * 0.32, 1.05, 0.3), bevel=0.02, node=name)
            m.ball(K("metal", (0.8, 0.7, 0.3)), 0.03, (sx * 0.064, 1.05, 0.34), u=6, v=4, node=name)
    def shelf(m):
        for x in (-0.6, 0.6):
            m.box(K("wood", DARK), (0.06, 1.8, 0.34), (x, 0.9, 0), bevel=0.01)
        for i, y in enumerate((0.3, 0.8, 1.3, 1.75)):
            m.box(K("wood", WOOD), (1.24, 0.05, 0.34), (0, y, 0), bevel=0.01)
            if i < 3:
                for k in range(4):  # jars, pots and bundles
                    x = -0.45 + k * 0.3
                    tone = [(0.6, 0.35, 0.25), (0.75, 0.68, 0.5), (0.35, 0.45, 0.35), (0.5, 0.42, 0.3)][(i + k) % 4]
                    m.lathe(K("adobe", tone), [(0.0, 0.0), (0.07, 0.0), (0.09, 0.1), (0.05, 0.2), (0.06, 0.23), (0.0, 0.23)], (x, y + 0.03, 0.0), segs=8)
    def hearth(m):
        m.box(K("stone", GREY), (2.0, 0.3, 0.9), (0, 0.15, 0), bevel=0.03)
        for x in (-0.8, 0.8):
            m.box(K("stone", GREY), (0.4, 1.3, 0.8), (x, 0.95, -0.05), bevel=0.03)
        m.box(K("stone", GREY), (2.0, 0.4, 0.8), (0, 1.8, -0.05), bevel=0.03)
        m.box(K("stone", (0.25, 0.23, 0.22)), (1.2, 1.3, 0.1), (0, 0.95, -0.4), bevel=0.01)
        m.box(K("stone", GREY), (1.2, 1.4, 0.7), (0, 2.7, -0.1), bevel=0.03)
        for k in range(3):
            m.rod(K("wood", DARK), 0.06, (-0.4 + k * 0.4, 0.36, -0.2), (-0.3 + k * 0.3, 0.42, 0.2), segs=6)
        m.node("Pulse", (0, 0.4, 0))
        m.lathe(fk.GLOW, [(0.0, 0.0), (0.28, 0.05), (0.2, 0.3), (0.08, 0.55), (0.0, 0.75)], (0, 0.42, -0.05), node="Pulse", segs=7)
    def oven(m):
        m.box(K("stone", GREY), (1.6, 0.8, 1.5), (0, 0.4, 0), bevel=0.03)
        m.ball(K("adobe", (0.7, 0.55, 0.42)), (0.8, 0.7, 0.75), (0, 0.85, 0), u=12, v=8)
        m.box(K("stone", (0.12, 0.1, 0.1)), (0.6, 0.4, 0.1), (0, 1.0, 0.72), bevel=0.02)
        m.box(fk.GLOW, (0.4, 0.14, 0.04), (0, 0.9, 0.76), bevel=0.01)
    def counter(m):
        m.box(K("wood", WOOD), (2.4, 0.95, 0.7), (0, 0.475, 0), bevel=0.02)
        m.box(K("wood", DARK), (2.5, 0.08, 0.8), (0, 0.99, 0), bevel=0.02)
        m.box(K("cloth", (0.5, 0.3, 0.25)), (0.6, 0.02, 0.5), (-0.6, 1.04, 0), bevel=0.005)
    def stool(m):
        m.lathe(K("wood", WOOD), [(0.0, 0.42), (0.19, 0.42), (0.19, 0.47), (0.0, 0.47)], (0, 0, 0), segs=10)
        for k in range(3):
            a = k * 2.1
            m.rod(K("wood", DARK), 0.025, (math.cos(a) * 0.17, 0.0, math.sin(a) * 0.17), (math.cos(a) * 0.1, 0.43, math.sin(a) * 0.1), segs=5)
    def pew(m):
        m.box(K("wood", WOOD), (2.2, 0.08, 0.45), (0, 0.45, 0), bevel=0.02)
        m.box(K("wood", DARK), (2.2, 0.6, 0.06), (0, 0.75, -0.22), bevel=0.02)
        for x in (-1.05, 1.05):
            m.box(K("wood", DARK), (0.08, 0.9, 0.5), (x, 0.45, 0), bevel=0.02)
    def altar(m):
        m.box(K("stone", GREY), (1.8, 1.0, 0.8), (0, 0.5, 0), bevel=0.04)
        m.box(K("cloth", (0.85, 0.82, 0.75)), (1.9, 0.04, 0.9), (0, 1.02, 0), bevel=0.01)
        for x in (-0.6, 0.6):
            m.rod(K("metal", (0.8, 0.7, 0.3)), 0.03, (x, 1.04, 0), (x, 1.3, 0), segs=6)
            m.ball(fk.GLOW, (0.03, 0.06, 0.03), (x, 1.36, 0), u=6, v=4)
    def bedroll(m):
        m.box(K("cloth", (0.55, 0.42, 0.3)), (0.8, 0.08, 1.9), (0, 0.04, 0), bevel=0.03)
        m.cyl(K("cloth", (0.7, 0.62, 0.5)), 0.13, -0.95, -0.7, y=0.13, segs=10)
        m.box(K("fur", (0.45, 0.38, 0.3)), (0.82, 0.06, 1.1), (0, 0.1, 0.3), bevel=0.03)
    def bookcase(m):
        m.box(K("wood", DARK), (1.4, 2.1, 0.4), (0, 1.05, 0), bevel=0.02)
        for i, y in enumerate((0.25, 0.75, 1.25, 1.72)):
            for k in range(7):
                tone = [(0.45, 0.2, 0.18), (0.2, 0.3, 0.4), (0.4, 0.36, 0.22), (0.25, 0.35, 0.25)][(i * 3 + k) % 4]
                m.box(K("leather", tone), (0.13, 0.34 + 0.04 * ((k + i) % 3), 0.26), (-0.54 + k * 0.18, y + 0.19, 0.09), bevel=0.01)
    def keg(m):
        for x in (-0.45, 0.45):
            m.box(K("wood", DARK), (0.12, 0.5, 0.9), (x, 0.25, 0), bevel=0.02)
        m.cyl(K("wood", WOOD), 0.42, -0.6, 0.6, y=0.85, segs=14)
        for f in (-0.4, 0.4):
            m.cyl(K("metal", IRON), 0.435, f - 0.03, f + 0.03, y=0.85, segs=14)
        m.rod(K("metal", (0.8, 0.7, 0.3)), 0.025, (0, 0.6, 0.6), (0, 0.6, 0.75), segs=6)
    mk.model("loot_barrel", loot_barrel, solid=False)
    mk.model("loot_crate", loot_crate, solid=False)
    for name, build in [("bed", bed), ("chest", chest), ("cupboard", cupboard), ("shelf", shelf), ("hearth", hearth), ("oven", oven), ("counter", counter),
            ("stool", stool), ("pew", pew), ("altar", altar), ("bedroll", bedroll), ("bookcase", bookcase), ("keg", keg)]:
        mk.model(name, build, solid=False)


def build_all():
    fk.init()
    mk = fk.Maker()
    mk.model("staff_orb", staff, solid=False)
    mk.model("palisade_gate", palisade_gate)
    mk.sizes["palisade_gate"].update({"walls": [[2.75, 0, 1.5, 0.7], [-2.75, 0, 1.5, 0.7]], "wall_h": 4.3})  # the way through stays open
    extra = {}
    for scheme_name, scheme in fk.SCHEMES.items():
        extra["open_house_" + scheme_name] = None
        def house(m, s=scheme, key="open_house_" + scheme_name):
            extra[key] = open_house(m, s, 9.0, 8.0)
        mk.model("open_house_" + scheme_name, house, plain=True)
    def farm(m):
        extra["open_farmhouse"] = open_house(m, fk.SCHEMES["amber"], 15.0, 10.0, wall_h=3.6, roof_h=3.8)
    mk.model("open_farmhouse", farm, plain=True)
    for name, more in extra.items():
        mk.sizes[name].update(more)
    furniture(mk)
    mk.plain_pass()
    mk.save()


if __name__ == "__main__":
    build_all()

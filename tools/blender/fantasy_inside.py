# Purpose: developer-time script. Models what round 3 of the fantasy world needs with tools/blender/fantasy_kit.py:
# the staff every caster carries for now (staff_orb: black shaft, silver rings, twin-pronged head, glowing orb, a ring
# round the orb), the WALK-IN houses of the main story (open_house_<scheme>, open_farmhouse: hollow, a real doorway,
# their wall pieces written into data/fantasy/props.json as "walls" so the game can build colliders you can walk
# between), and the furniture that fills every interior (bed, chest, cupboard, shelf, hearth, oven, counter, stool,
# pew, altar, bedroll, bookcase, keg). Model space: x right, y up, f forward (the front, where the door is).
# Run: python3 tools/blender/fantasy_inside.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K, S, c, WOOD, DARK, IRON, GREY, CLOTH, STRAW

BLACK = (0.07, 0.07, 0.08)
SILVER = (0.78, 0.79, 0.82)
WALL_T = 0.3  # thickness of a walk-in house's walls
DOOR_W = 1.5


def staff(m):
    m.rod(c(BLACK), 0.015, (0, -0.2, 0), (0, 1.23, 0), segs=8)
    m.lathe(c(BLACK), [(0.016, 0.0), (0.02, -0.03), (0.033, -0.075), (0.036, -0.09), (0.0, -0.09)], (0, -0.2, 0), segs=12)  # flared foot
    m.rod(K("metal", SILVER), 0.037, (0, -0.305, 0), (0, -0.288, 0), segs=12)
    for y in (-0.212, -0.226, 1.215, 1.238):
        m.rod(K("metal", SILVER), 0.0195, (0, y, 0), (0, y + 0.008, 0), segs=10)
    for side in (-1, 1):  # two prongs that part round the orb and close again into twin points
        m.loft(c(BLACK), [(side * 0.012, 1.24, 0, 0.011, 0.011), (side * 0.048, 1.32, 0, 0.009, 0.012), (side * 0.064, 1.42, 0, 0.009, 0.015),
            (side * 0.052, 1.52, 0, 0.012, 0.02), (side * 0.032, 1.64, 0, 0.011, 0.016), (side * 0.013, 1.82, 0, 0.001, 0.002)], segs=8, steps=3)
        m.rod(K("metal", SILVER), 0.0125, (side * 0.036, 1.292, 0), (side * 0.043, 1.31, 0), segs=8)
        for face in (-1, 1):  # glowing inlays near the points
            m.box(fk.GLOW, (0.005, 0.07, 0.003), (side * 0.036, 1.6, face * 0.016), tilt=0, bevel=0)
    m.node("Orb", (0, 1.42, 0))
    m.ball(fk.GLOW, 0.043, (0, 1.42, 0), node="Orb", u=14, v=9)
    m.node("Ring", (0, 1.42, 0))
    ring = [(0.078 + 0.0042 * math.cos(a), 0.0042 * math.sin(a)) for a in [k * math.pi / 3 for k in range(7)]]
    m.lathe(K("metal", SILVER), ring, (0, 1.42, 0), node="Ring", segs=28)


def open_house(m, s, w, d, wall_h=3.2, roof_h=2.6, chimney=True):
    """A hollow house: plank floor, four walls with a doorway in the front, a ceiling under the roof."""
    t = WALL_T
    m.box(K("wood", (0.5, 0.38, 0.25)), (w - 0.1, 0.16, d - 0.1), (0, 0.08, 0), bevel=0.01)
    m.box(S(s, "wall"), (w, wall_h, t), (0, wall_h / 2, -d / 2 + t / 2), bevel=0.02)
    for sx in (-1, 1):
        m.box(S(s, "wall"), (t, wall_h, d - 2 * t), (sx * (w / 2 - t / 2), wall_h / 2, 0), bevel=0.02)
        fw = (w - DOOR_W) / 2
        m.box(S(s, "wall"), (fw, wall_h, t), (sx * (DOOR_W / 2 + fw / 2), wall_h / 2, d / 2 - t / 2), bevel=0.02)
        m.box(S(s, "timber"), (0.16, 2.3, t + 0.1), (sx * (DOOR_W / 2 + 0.02), 1.15, d / 2 - t / 2), bevel=0.02)  # door posts
        for sf in (-1, 1):  # corner posts outside
            m.box(S(s, "timber"), (0.22, wall_h, 0.22), (sx * (w / 2), wall_h / 2, sf * (d / 2)), bevel=0.02)
        m.box(S(s, "stone"), (0.14, 0.5, d + 0.3), (sx * (w / 2 + 0.07), 0.25, 0), bevel=0.03)  # footing
        # a window on each side wall: frame and dark pane outside
        m.box(S(s, "timber"), (0.1, 1.1, 1.1), (sx * (w / 2 + 0.03), 1.75, 0), bevel=0.02)
        m.box(c((0.3, 0.42, 0.55)), (0.12, 0.9, 0.9), (sx * (w / 2 + 0.04), 1.75, 0), bevel=0.01)
    m.box(S(s, "wall"), (DOOR_W, wall_h - 2.3, t), (0, 2.3 + (wall_h - 2.3) / 2, d / 2 - t / 2), bevel=0.02)  # above the door
    m.box(S(s, "timber"), (DOOR_W + 0.3, 0.18, t + 0.1), (0, 2.36, d / 2 - t / 2), bevel=0.02)
    for sf in (-1, 1):
        m.box(S(s, "timber"), (w + 0.24, 0.2, 0.2), (0, wall_h - 0.1, sf * (d / 2)), bevel=0.02)
    m.box(K("wood", (0.42, 0.32, 0.2)), (w - 0.2, 0.1, d - 0.2), (0, wall_h - 0.05, 0), bevel=0.01)  # ceiling boards
    for k in range(1, 4):  # ceiling beams
        m.box(S(s, "timber"), (0.18, 0.2, d - 2 * t), (-w / 2 + w * k / 4, wall_h - 0.2, 0), bevel=0.02)
    if s.get("flat"):
        m.box(S(s, "roof"), (w + 0.4, 0.3, d + 0.4), (0, wall_h + 0.15, 0), bevel=0.04)
    else:
        half = d / 2 + 0.55
        m.prof(S(s, "roof"), w + 0.9, [(-half, wall_h - 0.02), (0, wall_h + roof_h), (half, wall_h - 0.02)], x=0, bevel=0.05)
        m.box(S(s, "timber"), (w + 1.0, 0.16, 0.2), (0, wall_h + roof_h + 0.02, 0), bevel=0.03)
    if chimney:
        m.box(S(s, "stone"), (0.8, wall_h + roof_h + 0.6, 0.7), (-w / 2 + 1.2, (wall_h + roof_h + 0.6) / 2, -d / 2 - 0.3), bevel=0.04)
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
        m.prof(K("wood", DARK), 1.0, [(-0.3, 0.5), (-0.2, 0.68), (0.2, 0.68), (0.3, 0.5)], x=0, bevel=0.02)
        for x in (-0.36, 0.36):
            m.box(K("metal", IRON), (0.07, 0.72, 0.64), (x, 0.35, 0), bevel=0.01)
        m.box(K("metal", (0.8, 0.7, 0.3)), (0.12, 0.14, 0.04), (0, 0.46, 0.31), bevel=0.01)
    def cupboard(m):
        m.box(K("wood", WOOD), (1.3, 2.0, 0.55), (0, 1.0, 0), bevel=0.03)
        for x in (-0.32, 0.32):
            m.box(K("wood", DARK), (0.58, 1.7, 0.04), (x, 1.05, 0.28), bevel=0.02)
            m.ball(K("metal", (0.8, 0.7, 0.3)), 0.03, (x * 0.2, 1.05, 0.32), u=6, v=4)
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
    for name, build in [("bed", bed), ("chest", chest), ("cupboard", cupboard), ("shelf", shelf), ("hearth", hearth), ("oven", oven), ("counter", counter),
            ("stool", stool), ("pew", pew), ("altar", altar), ("bedroll", bedroll), ("bookcase", bookcase), ("keg", keg)]:
        mk.model(name, build, solid=False)


def build_all():
    fk.init()
    mk = fk.Maker()
    mk.model("staff_orb", staff, solid=False)
    extra = {}
    for scheme_name, scheme in fk.SCHEMES.items():
        extra["open_house_" + scheme_name] = None
        def house(m, s=scheme, key="open_house_" + scheme_name):
            extra[key] = open_house(m, s, 9.0, 8.0)
        mk.model("open_house_" + scheme_name, house)
    def farm(m):
        extra["open_farmhouse"] = open_house(m, fk.SCHEMES["amber"], 15.0, 10.0, wall_h=3.6, roof_h=3.8)
    mk.model("open_farmhouse", farm)
    for name, more in extra.items():
        mk.sizes[name].update(more)
    furniture(mk)
    mk.save()


if __name__ == "__main__":
    build_all()

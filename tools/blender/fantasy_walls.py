# Purpose: developer-time helpers that build the stone town wall, its gatehouse and the chapel in real detail (round 4, item 12).
# The wall is one 6 m stretch, outside to the front: a sloping foot, a buttress, a string course, a parapet with
# capped teeth and an arrow slit, odd stones standing proud, scaffold holes, and a timber wall walk on brackets
# inside. The gate is two towers with courses, arrow slits, battlements and slate caps, a pointed arch with a
# raised portcullis and open doors, and a timber-framed guard room over the way through. The chapel is a buttressed
# nave with pointed windows and a west tower with louvres, battlements and a spire. Used by fantasy_life.py.
# Model space: x right, y up, f forward (out of the town).
import math

import fantasy_kit as fk
import fantasy_house as fh
from fantasy_kit import K, c, GREY, DARK, IRON, WOOD

PALE = (0.56, 0.54, 0.52)
HOLE = (0.07, 0.07, 0.08)
BARN = {"kinds": {"wall": "wood", "roof": "thatch", "stone": "stone"}, "wall": (0.5, 0.33, 0.2), "timber": DARK, "roof": (0.72, 0.6, 0.32), "stone": GREY, "trim": (0.36, 0.24, 0.15)}
CHAPEL = {"kinds": {"wall": "stone", "roof": "slate", "stone": "stone"}, "wall": GREY, "timber": DARK, "roof": (0.35, 0.36, 0.42), "stone": PALE, "trim": DARK}
GUARD = {"kinds": {"wall": "plaster", "roof": "slate", "stone": "stone"}, "wall": (0.84, 0.8, 0.7), "timber": DARK, "roof": (0.35, 0.36, 0.42), "stone": GREY, "trim": (0.45, 0.2, 0.16)}


def stone(k=1.0, base=GREY):
    return K("stone", tuple(v * k * 0.85 for v in base))  # a little darker than new-cut stone: these walls are old


def tall(m, mat, size, at, foot=1.3):
    """A high block of masonry in two lifts, so that damp and moss stay in the lowest one (colours run corner to corner)."""
    m.box(mat, (size[0], foot, size[2]), (at[0], foot / 2, at[2]), bevel=0.0)
    m.box(mat, (size[0], size[1] - foot, size[2]), (at[0], foot + (size[1] - foot) / 2, at[2]), bevel=0.0)


def town_wall(m):
    with fk.weathered(1.4, moss=1.0):
        tall(m, stone(), (6.0, 3.4, 1.0), (0, 0, 0))
        m.prof(stone(0.86), 6.0, [(0.5, 0.0), (1.0, 0.0), (0.5, 1.2)], x=0, bevel=0.0)  # the sloping foot outside
        m.prof(stone(0.9), 0.8, [(0.5, 0.0), (1.35, 0.0), (1.35, 1.1), (1.0, 1.5), (1.0, 2.3), (0.6, 2.8), (0.5, 2.8)], x=0, bevel=0.0)  # buttress
        m.box(stone(0.78), (6.0, 0.18, 1.14), (0, 3.31, 0), bevel=0.0)
        m.box(stone(0.95), (6.0, 0.55, 0.38), (0, 3.675, 0.31), bevel=0.0)
        for side in (-1, 1):  # a pier at each end, so stretches set on a curve leave no slit between them
            tall(m, stone(0.9), (0.26, 3.2, 1.06), (side * 3.0, 0, 0))
            m.prof(stone(0.84), 0.26, [(0.5, 0.0), (1.04, 0.0), (0.5, 1.26)], x=side * 3.0, bevel=0.0)
        for k, x in enumerate((-2.0, 0.0, 2.0)):  # the teeth, each under a cap stone
            m.box(stone(1.0 if k != 1 else 0.93, PALE), (1.1, 0.75, 0.38), (x, 4.325, 0.31), bevel=0.03)
            m.box(stone(1.12, PALE), (1.22, 0.1, 0.5), (x, 4.75, 0.31), bevel=0.0)
        m.box(c(HOLE), (0.1, 0.5, 0.4), (0.0, 4.3, 0.31), bevel=0.0)  # arrow slit
        spots = [(-2.4, 0.9, 0.7, 1.12), (-1.2, 2.5, 0.55, 0.9), (1.5, 1.9, 0.8, 1.1), (2.3, 2.9, 0.6, 0.88), (-0.9, 1.6, 0.5, 0.85), (1.0, 0.7, 0.65, 1.15),
            (-2.5, 2.1, 0.5, 0.92), (2.5, 1.2, 0.5, 1.08)]
        for x, y, wide, shade in spots:  # odd stones standing a little proud of the face
            m.box(stone(shade), (wide, 0.3, 0.06), (x, y, 0.51), bevel=0.0)
        for k, (x, y, wide, shade) in enumerate(spots[:5]):  # and on the town side
            m.box(stone(shade), (wide, 0.3, 0.06), (-x, y + 0.2 - 0.9 * (k % 2), -0.51), bevel=0.0)
        for x in (-1.6, 1.6):  # holes the builders' scaffold left
            m.box(c(HOLE), (0.14, 0.14, 0.05), (x, 2.25, 0.5), bevel=0.0)
        m.box(K("wood", WOOD), (6.0, 0.08, 0.95), (0, 3.36, -0.95), bevel=0.0)  # the wall walk, widened in timber
        for k in (-1, 1):
            m.box(K("wood", tuple(v * 0.8 for v in WOOD)), (6.0, 0.09, 0.02), (0, 3.36, -0.95 + k * 0.3), bevel=0.0)
        for x in (-2.0, 0.0, 2.0):
            m.box(K("timber", DARK), (0.14, 0.14, 0.95), (x, 3.25, -0.95), bevel=0.0)
            m.rod(K("timber", DARK), 0.06, (x, 2.45, -0.5), (x, 3.2, -1.3), segs=4)
            m.rod(K("timber", DARK), 0.05, (x, 3.4, -1.36), (x, 4.3, -1.36), segs=4)
        m.rod(K("timber", DARK), 0.04, (-3.0, 4.25, -1.36), (3.0, 4.25, -1.36), segs=4)
    m.walls = [[0.0, 0.0, 6.0, 1.0]]


def _arch_y(x, half=2.0, spring=2.6, rise=1.9):
    return spring + rise * math.sin(math.acos(max(-1.0, min(1.0, x / half))))


def town_gate(m):
    glow = fk.GLOW
    with fk.weathered(1.4, moss=1.0):
        for sx in (-1, 1):
            x = sx * 3.6
            m.box(stone(0.86), (2.9, 1.0, 2.9), (x, 0.5, 0), bevel=0.08)
            tall(m, stone(), (2.6, 6.0, 2.6), (x, 0, 0))
            for y in (2.3, 4.5):
                m.box(stone(0.78), (2.72, 0.16, 2.72), (x, y, 0), bevel=0.0)
            m.box(stone(0.8), (3.0, 0.3, 3.0), (x, 6.0, 0), bevel=0.0)  # the battlement stands out on a corbel course
            for a in range(4):
                dx, df = (1, 0, -1, 0)[a], (0, 1, 0, -1)[a]
                size = (0.3, 0.5, 3.0) if dx else (3.0, 0.5, 0.3)
                m.box(stone(0.95), size, (x + dx * 1.35, 6.4, df * 1.35), bevel=0.0)
                for side in (-1, 1):
                    at = (x + dx * 1.35 + (0 if dx else side * 1.1), 6.95, df * 1.35 + (side * 1.1 if dx else 0))
                    m.box(stone(1.05, PALE), (0.3, 0.6, 0.8) if dx else (0.8, 0.6, 0.3), at, bevel=0.0)
            m.lathe(K("slate", (0.35, 0.36, 0.42)), [(1.3, 6.3), (1.15, 6.6), (0.6, 7.9), (0.06, 9.3)], (x, 0, 0), segs=8)
            m.rod(K("metal", IRON), 0.03, (x, 9.2, 0), (x, 10.2, 0), segs=4)
            m.box(K("cloth", (0.6, 0.16, 0.14)), (0.7, 0.36, 0.02), (x + 0.38, 9.95, 0), bevel=0.0)  # pennant
            for y in (1.7, 3.4):
                m.box(c(HOLE), (0.12, 0.9, 0.06), (x, y, 1.3), bevel=0.0)  # arrow slits to the front
                m.box(c(HOLE), (0.06, 0.9, 0.12), (x + sx * 1.3, y, 0), bevel=0.0)  # and to the side
            m.box(stone(1.1, PALE), (0.62, 1.04, 0.08), (x, 5.2, 1.3), bevel=0.0)
            m.box(glow, (0.4, 0.8, 0.1), (x, 5.2, 1.32), bevel=0.0)
            m.strip(K("cloth", (0.6, 0.16, 0.14)), 0.8, 0.03, [(1.34, 4.4), (1.36, 2.6)], x=x)  # a banner down the tower
            m.box(K("cloth", (0.9, 0.78, 0.4)), (0.5, 0.5, 0.02), (x, 3.6, 1.385), bevel=0.0)
            tall(m, stone(0.92), (0.3, 2.6, 1.6), (sx * 2.15, 0, 0))  # the arch's jambs
        curve = [(2.0 * math.cos(math.pi * k / 10.0), 0.0) for k in range(11)]
        curve = [(x, _arch_y(x)) for x, _unused in curve]
        m.prof(stone(), 1.6, [(-2.3, 2.6), (-2.3, 5.4), (2.3, 5.4), (2.3, 2.6)] + curve, x=0, bevel=0.0, across="f")
        ring = curve + [(x * 1.16, 2.6 + (y - 2.6) * 1.16) for x, y in reversed(curve)]
        m.prof(stone(1.15, PALE), 1.72, ring, x=0, bevel=0.0, across="f")  # the arch's own ring of cut stone
        m.box(stone(0.78), (4.6, 0.18, 1.72), (0, 5.35, 0), bevel=0.0)
        # the guard room over the way through: timber-framed, jutting out a little, under its own roof
        m.box(fk.S(GUARD, "wall"), (4.6, 2.0, 2.0), (0, 6.4, 0), bevel=0.0)
        for name in ("front", "back"):
            face = fh.Face(m, name, 1.0, 2.3)
            fh.timber_face(face, GUARD, 5.4, 2.0)
            for u in (-1.15, 1.15):
                fh.window(face, GUARD, u, 6.55, ww=0.7, wh=0.85)
            for k in range(6):
                face.box(K("timber", DARK), 0.14, 0.18, 0.3, -2.0 + k * 0.8, 5.36, -0.08)
        fh.gable_roof(m, GUARD, 1.85, 1.0, 7.4, 1.5, timbered=False)
        m.box(c((0.62, 0.16, 0.14)), (0.7, 0.8, 0.08), (0, 4.95, 0.84), bevel=0.0)  # a painted shield over the arch
        m.box(c((0.92, 0.8, 0.42)), (0.35, 0.4, 0.09), (-0.175, 5.15, 0.84), bevel=0.0)
        m.box(c((0.92, 0.8, 0.42)), (0.35, 0.4, 0.09), (0.175, 4.75, 0.84), bevel=0.0)
        for k in range(9):  # the portcullis, drawn up
            x = -1.6 + k * 0.4
            m.rod(K("metal", IRON), 0.045, (x, _arch_y(x) + 0.05, 0.45), (x, 3.3, 0.45), r2=0.012, segs=4)
        for y in (3.65, 4.1):
            reach = min(1.6, 2.0 * math.cos(math.asin((y - 2.6) / 1.9)) - 0.05)
            m.rod(K("metal", IRON), 0.04, (-reach, y, 0.45), (reach, y, 0.45), segs=4)
        for sx in (-1, 1):  # the doors standing open, and a lantern each side
            m.box(K("wood", DARK), (0.12, 2.9, 1.9), (sx * 1.94, 1.5, 1.75), bevel=0.0)
            for k in range(3):
                m.box(K("wood", tuple(v * 0.7 for v in DARK)), (0.13, 2.86, 0.03), (sx * 1.94, 1.5, 1.3 + k * 0.47), bevel=0.0)
            for y in (0.6, 1.5, 2.4):
                m.box(K("metal", IRON), (0.14, 0.09, 1.7), (sx * 1.94, y, 1.7), bevel=0.0)
            m.rod(K("metal", IRON), 0.025, (sx * 2.75, 3.3, 1.3), (sx * 2.75, 3.3, 1.75), segs=4)
            m.box(K("metal", IRON), (0.24, 0.06, 0.24), (sx * 2.75, 3.25, 1.75), bevel=0.0)
            m.box(glow, (0.18, 0.28, 0.18), (sx * 2.75, 3.08, 1.75), bevel=0.0)


def _lancet(m, glow, at, low, high, wide, side=None, f=None, x=None):
    """A pointed window: a lit pane in a surround of pale cut stone. On a side wall (`side` = -1 / 1 at f) or on a
    front or back wall (at x; `at` is then the wall's f)."""
    def shape(mid, grow):
        return [(mid - wide / 2 - grow, low - grow), (mid + wide / 2 + grow, low - grow), (mid + wide / 2 + grow, high - wide * 0.8), (mid, high + grow * 1.6), (mid - wide / 2 - grow, high - wide * 0.8)]
    if side is not None:
        m.prof(stone(1.12, PALE), 0.1, shape(f, 0.14), x=at, bevel=0.0)
        m.prof(glow, 0.1, shape(f, 0.0), x=at + side * 0.03, bevel=0.0)
        m.box(c(HOLE), (0.12, high - low - 0.2, 0.05), (at + side * 0.03, (low + high) / 2 - 0.1, f), bevel=0.0)
    else:
        way = 1 if at > 0 else -1
        m.prof(stone(1.12, PALE), 0.1, shape(x, 0.14), x=at, bevel=0.0, across="f")
        m.prof(glow, 0.1, shape(x, 0.0), x=at + way * 0.03, bevel=0.0, across="f")
        m.box(c(HOLE), (0.05, high - low - 0.2, 0.12), (x, (low + high) / 2 - 0.1, at + way * 0.03), bevel=0.0)


def chapel(m):
    glow = fk.GLOW
    with fk.weathered(1.2, moss=0.6):
        m.box(stone(0.86), (6.3, 0.5, 10.3), (0, 0.25, 0), bevel=0.04)
        tall(m, stone(), (6.0, 5.0, 10.0), (0, 0, 0))
        m.box(stone(0.78), (6.12, 0.16, 10.12), (0, 4.9, 0), bevel=0.0)
        fh.gable_roof(m, CHAPEL, 3.0, 5.0, 5.0, 3.2, front=True, timbered=False, gable_window=False)
        for f in (-3.0, 0.0, 3.0):
            for sx in (-1, 1):
                _lancet(m, glow, sx * 3.0, 1.7, 3.9, 0.8, side=sx, f=f)
                outline = [(3.0, 0.0), (3.9, 0.0), (3.9, 1.9), (3.55, 2.5), (3.55, 3.8), (3.1, 4.4), (3.0, 4.4)]
                m.prof(stone(0.9), 0.7, [(sx * px, y) for px, y in outline], x=f + 1.5, bevel=0.0, across="f")  # stepped buttress
        for x in (-1.3, 0.0, 1.3):  # three lights in the east wall
            _lancet(m, glow, -5.0, 1.9, 4.3 if x == 0.0 else 3.8, 0.7, x=x)
        # the tower at the west end, over the door
        m.box(stone(0.86), (4.4, 0.8, 4.4), (0, 0.4, 6.6), bevel=0.06)
        tall(m, stone(1.0, PALE), (4.0, 11.0, 4.0), (0, 0, 6.6))
        for y in (4.2, 7.9, 10.7):
            m.box(stone(0.78), (4.12, 0.16, 4.12), (0, y, 6.6), bevel=0.0)
        for a in range(4):
            dx, df = (1, 0, -1, 0)[a], (0, 1, 0, -1)[a]
            m.box(stone(0.95), (0.3, 0.5, 4.3) if dx else (4.3, 0.5, 0.3), (dx * 2.0, 11.25, 6.6 + df * 2.0), bevel=0.0)
            m.box(c(HOLE), (0.08, 1.5, 1.0) if dx else (1.0, 1.5, 0.08), (dx * 2.0, 9.3, 6.6 + df * 2.0), bevel=0.0)  # belfry openings
            for k in range(4):  # louvre boards across them
                m.box(K("wood", DARK), (0.12, 0.07, 1.0) if dx else (1.0, 0.07, 0.12), (dx * 2.02, 8.75 + k * 0.36, 6.6 + df * 2.02), bevel=0.0)
            cx, cf = (1, -1, -1, 1)[a] * 2.0, (1, 1, -1, -1)[a] * 2.0
            m.lathe(stone(1.05, PALE), [(0.3, 11.0), (0.3, 11.9), (0.03, 12.9)], (cx, 0, 6.6 + cf), segs=4)  # a pinnacle on each corner
        m.lathe(K("slate", (0.3, 0.31, 0.38)), [(1.8, 11.1), (1.65, 11.5), (0.85, 14.4), (0.06, 17.6)], (0, 0, 6.6), segs=8)
        m.rod(K("metal", IRON), 0.03, (0, 17.5, 6.6), (0, 18.6, 6.6), segs=4)
        m.ball(K("metal", (0.8, 0.7, 0.3)), 0.12, (0, 18.1, 6.6), u=6, v=4)
        _lancet(m, glow, 8.6, 5.0, 7.2, 0.8, x=0.0)
        door = [(-0.8, 0.3), (0.8, 0.3), (0.8, 2.2), (0.0, 3.1), (-0.8, 2.2)]
        m.prof(stone(1.12, PALE), 0.1, [(x * 1.2, 0.3 + (y - 0.3) * 1.08) for x, y in door], x=8.6, bevel=0.0, across="f")
        m.prof(K("wood", DARK), 0.1, door, x=8.64, bevel=0.0, across="f")
        for x in (-0.4, 0.0, 0.4):
            m.box(K("wood", tuple(v * 0.7 for v in DARK)), (0.03, 1.9, 0.03), (x, 1.25, 8.7), bevel=0.0)
        for y in (0.8, 1.8):
            m.box(K("metal", IRON), (1.4, 0.08, 0.03), (0, y, 8.705), bevel=0.0)
        m.box(stone(0.9), (2.4, 0.15, 1.0), (0, 0.075, 9.2), bevel=0.03)
        m.box(stone(0.95), (2.0, 0.3, 0.6), (0, 0.15, 8.95), bevel=0.03)
    m.walls = [[0.0, -6.6, 4.4, 4.4], [0.0, 0.0, 6.3, 10.3]]  # the tower first: the door is in it

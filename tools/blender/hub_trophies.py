# Purpose: developer-time models of the hub's trophy room (locked: diary/DECISIONS_HUB.md; data/trophies.json):
#   hub_trophy_room  the room behind the hall's left doorway: plank floor, panelled walls, beamed ceiling (14 x 15 m)
#   hub_cabinet      one player's cabinet, 5 m wide: two wings of six shelves and the raised, lit centre podium
#   trophy_cup, trophy_statuette, trophy_plaque, trophy_medal, trophy_skull, trophy_crown   the common shapes
#   trophy_stand     the dusty empty stand of an unearned trophy, ??? carved on its front
#   trophy_u0 .. trophy_u26   the hardest ones' own shapes (9 tops x 3 stems)
# Trophies are WHITE where the game tints them (game/trophy_room.gd multiplies each by its tier or own tint), with a
# dark base. All small: a trophy stands about 0.15 m tall on a 0.19 m shelf spacing.
# Kit axes: (x, up, forward). Run: python3 tools/blender/hub_trophies.py [names...]
# Dependencies: tools/blender/kit.py, tools/blender/fantasy_kit.py.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401 (must load before bmesh)
import kit
import fantasy_kit
from fantasy_kit import K, init

WHITE = (0.95, 0.95, 0.95)
BASE = (0.22, 0.2, 0.19)
DARK = (0.05, 0.05, 0.05)


def body(m):
    return K("metal", WHITE)


def base(m, w=0.07, h=0.03):
    m.box(K("stone", BASE), (w, h, w), (0, h / 2, 0), bevel=0.0)


# ---------------------------------------------------------------- common shapes

def cup(m):
    base(m)
    m.lathe(body(m), [(0.02, 0.03), (0.008, 0.045), (0.006, 0.07), (0.012, 0.075), (0.03, 0.09), (0.036, 0.13), (0.034, 0.14)], (0, 0, 0), segs=8)
    for s in (-1, 1):
        m.rod(body(m), 0.004, (s * 0.033, 0.13, 0), (s * 0.05, 0.11, 0), segs=4)
        m.rod(body(m), 0.004, (s * 0.05, 0.11, 0), (s * 0.03, 0.095, 0), segs=4)


def statuette(m):
    base(m)
    m.lathe(body(m), [(0.012, 0.03), (0.016, 0.06), (0.012, 0.1), (0.01, 0.11)], (0, 0, 0), segs=8)  # robe and body
    m.ball(body(m), 0.012, (0, 0.122, 0), u=8, v=5)
    m.rod(body(m), 0.004, (0.008, 0.1, 0), (0.02, 0.15, 0))  # an arm raised high
    m.ball(body(m), 0.007, (0.021, 0.155, 0), u=8, v=5)


def plaque(m):
    m.box(K("wood", (0.35, 0.2, 0.1)), (0.09, 0.12, 0.012), (0, 0.075, 0), bevel=0.0)
    m.box(body(m), (0.065, 0.075, 0.006), (0, 0.08, -0.008), bevel=0.0)
    m.box(K("wood", (0.35, 0.2, 0.1)), (0.05, 0.01, 0.04), (0, 0.005, 0.01), bevel=0.0)
    m.rod(K("wood", (0.35, 0.2, 0.1)), 0.003, (0, 0.03, 0.006), (0, 0.006, 0.025))  # the little prop behind


def medal(m):
    base(m, 0.08, 0.02)
    for s in (-1, 1):
        m.rod(K("stone", BASE), 0.003, (s * 0.03, 0.02, 0), (s * 0.03, 0.15, 0), segs=4)
    m.rod(K("stone", BASE), 0.003, (-0.03, 0.15, 0), (0.03, 0.15, 0), segs=4)
    m.box(K("cloth", (0.7, 0.12, 0.1)), (0.02, 0.05, 0.003), (0, 0.122, 0))  # the ribbon
    m.cyl(body(m), 0.022, -0.003, 0.003, y=0.08, x=0.0, segs=8)


def skull(m):
    base(m)
    m.ball(body(m), (0.03, 0.03, 0.032), (0, 0.075, 0), u=8, v=5)
    m.box(body(m), (0.034, 0.02, 0.03), (0, 0.048, -0.008), bevel=0.0)  # jaw
    for s in (-1, 1):
        m.ball(K("paint", DARK), (0.009, 0.008, 0.004), (s * 0.012, 0.075, -0.029), u=8, v=5)
    m.box(K("paint", DARK), (0.006, 0.008, 0.004), (0, 0.062, -0.03), bevel=0.0)


def crown(m):
    m.box(K("cloth", (0.45, 0.1, 0.15)), (0.08, 0.025, 0.08), (0, 0.0125, 0), bevel=0.0)  # the cushion
    m.lathe(body(m), [(0.03, 0.03), (0.032, 0.06), (0.03, 0.062)], (0, 0, 0), segs=8)
    for k in range(8):
        a = k / 8 * math.tau
        x, f = math.cos(a) * 0.031, math.sin(a) * 0.031
        m.rod(body(m), 0.006, (x, 0.06, f), (x * 1.05, 0.09, f * 1.05), r2=0.001, segs=4)
        m.ball(body(m), 0.004, (x * 1.05, 0.092, f * 1.05), u=8, v=5)


def stand(m):
    """The empty, dusty stand of an unearned trophy, with ??? carved on its front."""
    m.box(K("stone", (0.6, 0.6, 0.58)), (0.07, 0.03, 0.07), (0, 0.015, 0), bevel=0.0)
    m.box(K("stone", (0.6, 0.6, 0.58)), (0.03, 0.03, 0.03), (0, 0.045, 0), bevel=0.0)
    for i, x in enumerate((-0.016, 0.0, 0.016)):  # three question marks: hook, stem, dot
        m.box(K("paint", (0.2, 0.2, 0.2)), (0.008, 0.002, 0.001), (x, 0.026, -0.0355), bevel=0.0)
        m.box(K("paint", (0.2, 0.2, 0.2)), (0.002, 0.006, 0.001), (x + 0.004, 0.022, -0.0355), bevel=0.0)
        m.box(K("paint", (0.2, 0.2, 0.2)), (0.002, 0.004, 0.001), (x, 0.016, -0.0355), bevel=0.0)
        m.box(K("paint", (0.2, 0.2, 0.2)), (0.002, 0.002, 0.001), (x, 0.009, -0.0355), bevel=0.0)


# ---------------------------------------------------------------- the hardest ones' own shapes

def _stem(m, kind, top):
    """Base and stem up to height `top`."""
    if kind == 0:  # slim column on a square base
        base(m, 0.075, 0.025)
        m.lathe(body(m), [(0.014, 0.025), (0.009, 0.035), (0.007, top - 0.012), (0.012, top)], (0, 0, 0), segs=8)
    elif kind == 1:  # a string of beads on a round base
        m.lathe(K("stone", BASE), [(0.04, 0.0), (0.04, 0.02), (0.03, 0.028)], (0, 0, 0), segs=8)
        n = 5
        for i in range(n):
            y = 0.028 + (top - 0.028) * (i + 0.5) / n
            m.ball(body(m), 0.011 if i % 2 == 0 else 0.007, (0, y, 0), u=10, v=6)
    else:  # tiered rings on a stepped base
        m.box(K("stone", BASE), (0.085, 0.015, 0.085), (0, 0.0075, 0), bevel=0.0)
        m.box(K("stone", BASE), (0.065, 0.015, 0.065), (0, 0.0225, 0), bevel=0.0)
        prof = [(0.016, 0.03)]
        steps = 4
        for i in range(steps):
            y0 = 0.03 + (top - 0.03) * i / steps
            y1 = 0.03 + (top - 0.03) * (i + 1) / steps
            prof += [(0.008, y0 + 0.004), (0.008, y1 - 0.006), (0.014, y1 - 0.002), (0.008, y1)]
        m.lathe(body(m), prof, (0, 0, 0), segs=8)


def _top(m, kind, y):
    b = body(m)
    if kind == 0:  # eight-point star
        for k in range(8):
            a = k / 8 * math.tau
            r = 0.04 if k % 2 == 0 else 0.026
            m.rod(b, 0.009, (0, y + 0.04, 0), (math.cos(a) * r, y + 0.04 + math.sin(a) * r, 0), r2=0.002, segs=4)
        m.ball(b, 0.012, (0, y + 0.04, 0), u=8, v=5)
    elif kind == 1:  # an orb held in claws
        m.ball(b, 0.026, (0, y + 0.032, 0), u=8, v=5)
        for k in range(4):
            a = k / 4 * math.tau + 0.4
            m.rod(b, 0.004, (0, y, 0), (math.cos(a) * 0.024, y + 0.03, math.sin(a) * 0.024), segs=4)
    elif kind == 2:  # crescent moon
        for k in range(9):
            a = math.pi * (0.15 + 0.7 * k / 8)
            r = 0.035
            m.ball(b, 0.007 + 0.005 * math.sin(math.pi * k / 8), (math.cos(a + math.pi / 2) * r, y + 0.04 + math.sin(a + math.pi / 2) * r, 0), u=8, v=5)
    elif kind == 3:  # sun disc with rays
        m.cyl(b, 0.022, -0.004, 0.004, y=y + 0.04, x=0.0, segs=8)
        for k in range(12):
            a = k / 12 * math.tau
            m.rod(b, 0.003, (math.cos(a) * 0.022, y + 0.04 + math.sin(a) * 0.022, 0), (math.cos(a) * 0.04, y + 0.04 + math.sin(a) * 0.04, 0), r2=0.001, segs=4)
    elif kind == 4:  # flame
        m.lathe(b, [(0.0, y), (0.022, y + 0.012), (0.018, y + 0.035), (0.008, y + 0.06), (0.0, y + 0.075)], (0, 0, 0), segs=8)
        for s in (-1, 1):
            m.rod(b, 0.007, (s * 0.012, y + 0.012, 0), (s * 0.02, y + 0.05, 0), r2=0.001, segs=4)
    elif kind == 5:  # spread wings
        m.ball(b, (0.01, 0.018, 0.01), (0, y + 0.015, 0), u=8, v=5)
        for s in (-1, 1):
            for i in range(4):
                m.box(b, (0.012, 0.04 - i * 0.007, 0.004), (s * (0.014 + i * 0.01), y + 0.03 + i * 0.006, 0), bevel=0.0)
    elif kind == 6:  # crossed swords
        for s in (-1, 1):
            a = math.radians(30 * s)
            p0 = (-math.sin(a) * 0.04, y, 0)
            p1 = (math.sin(a) * 0.04, y + 0.09, 0)
            m.rod(b, 0.003, p0, p1, segs=4)
            m.rod(b, 0.002, (p0[0] * 0.6 - 0.012, y + 0.02, 0), (p0[0] * 0.6 + 0.012, y + 0.02, 0), segs=4)
    elif kind == 7:  # hourglass
        m.box(b, (0.05, 0.006, 0.05), (0, y + 0.003, 0), bevel=0.0)
        m.box(b, (0.05, 0.006, 0.05), (0, y + 0.077, 0), bevel=0.0)
        m.lathe((fantasy_kit.GLOW, (1.0, 0.85, 0.5)), [(0.018, y + 0.006), (0.004, y + 0.04), (0.018, y + 0.074)], (0, 0, 0), segs=8)
        for s in (-1, 1):
            for t in (-1, 1):
                m.rod(b, 0.002, (s * 0.02, y + 0.006, t * 0.02), (s * 0.02, y + 0.074, t * 0.02), segs=4)
    else:  # clockwork gear
        m.cyl(b, 0.026, -0.005, 0.005, y=y + 0.035, x=0.0, segs=8)
        for k in range(10):
            a = k / 10 * math.tau
            m.box(b, (0.01, 0.012, 0.01), (math.cos(a) * 0.03, y + 0.035 + math.sin(a) * 0.03, 0), bevel=0.0)
        m.cyl(K("paint", DARK), 0.008, -0.006, 0.006, y=y + 0.035, x=0.0, segs=8)


def unique(i):
    def build(m):
        top = 0.06 + 0.012 * (i % 3)
        _stem(m, i // 9, top)
        _top(m, i % 9, top)
    return build


# ---------------------------------------------------------------- the room and the cabinet

def room(m):
    """Floor x -39..-26, z -3..12 (world metres from the hub's middle; this model is built at the room's middle)."""
    w, d, h = 13.0, 15.0, 5.0
    planks = []
    for i in range(int(d / 0.25)):
        shade = 0.36 + 0.05 * ((i * 7) % 3)
        m.box(K("wood", (shade, shade * 0.7, shade * 0.45)), (w, 0.1, 0.245), (0, -0.05, -(-d / 2 + 0.125 + i * 0.25)), bevel=0.0)
    panel = K("wood", (0.28, 0.17, 0.1))
    for x, f, sx, sf in [(-w / 2 - 0.25, 0, 0.5, d), (0, d / 2 + 0.25, w + 1, 0.5), (0, -d / 2 - 0.25, w + 1, 0.5)]:
        m.box(panel, (sx, h, sf), (x, h / 2, -f), bevel=0.0)
    # the hall side (x = +w/2) is the hall's own wall; only a frame round the doorway on this side
    for z in (4.5, 7.5):
        m.box(K("wood", (0.2, 0.12, 0.07)), (0.2, 4.0, 0.25), (w / 2 - 0.1, 2.0, -(z - 4.5)), bevel=0.0)
    m.box(K("plaster", (0.55, 0.5, 0.45)), (w + 1, 0.3, d + 1), (0, h + 0.15, 0), bevel=0.0)
    for i in range(6):
        m.box(K("wood", (0.2, 0.12, 0.07)), (w, 0.3, 0.3), (0, h - 0.15, -(-d / 2 + 1.25 + i * 2.5)), bevel=0.0)
    # a dado rail and a skirting round the three panelled walls
    for x, f, sx, sf in [(-w / 2 + 0.03, 0, 0.06, d), (0, d / 2 - 0.03, w, 0.06), (0, -d / 2 + 0.03, w, 0.06)]:
        m.box(K("wood", (0.4, 0.26, 0.14)), (sx, 0.06, sf), (x, 1.0, -f), bevel=0.0)
        m.box(K("wood", (0.15, 0.09, 0.05)), (sx, 0.18, sf), (x, 0.09, -f), bevel=0.0)


def cabinet(m):
    """5 m wide, 2.7 m tall, 0.5 m deep, its back at forward = 0 and its front facing -forward (toward the room).
    Wings: x -2.5..-0.45 and 0.45..2.5, six shelves at 0.35 + 0.38 k (k = 0..5; the eye-level row is k = 3, 1.49 m).
    Podium in the middle: top at 1.1 m, lit from a glowing strip above. A brass button at the outer end of each shelf but
    the eye-level row (polish1 item 16)."""
    wood = K("wood", (0.26, 0.15, 0.08))
    dark = K("wood", (0.12, 0.07, 0.04))
    m.box(dark, (5.0, 2.7, 0.04), (0, 1.35, -0.02), bevel=0.0)  # back board
    for x in (-2.48, -0.45, 0.45, 2.48):
        m.box(wood, (0.06, 2.7, 0.5), (x, 1.35, -0.25), bevel=0.004)
    m.box(wood, (5.1, 0.12, 0.55), (0, 2.76, -0.27), bevel=0.006)  # crown moulding
    m.box(wood, (5.0, 0.2, 0.5), (0, 0.1, -0.25), bevel=0.0)  # plinth
    for k in range(6):
        y = 0.35 + 0.38 * k
        for sx in (-1, 1):
            m.box(wood, (2.0, 0.03, 0.48), (sx * 1.465, y - 0.015, -0.25), bevel=0.0)
        if k == 3:  # the eye-level row is the hardest: a brass edge on its shelves
            for sx in (-1, 1):
                m.box(K("metal", (0.85, 0.65, 0.3)), (2.0, 0.02, 0.01), (sx * 1.465, y - 0.02, -0.5), bevel=0.0)
    m.box(K("stone", (0.82, 0.8, 0.76)), (0.84, 1.1, 0.48), (0, 0.55, -0.25), bevel=0.004)  # podium
    m.box(K("cloth", (0.35, 0.05, 0.08)), (0.8, 0.02, 0.44), (0, 1.11, -0.25), bevel=0.0)
    m.box((fantasy_kit.GLOW, (1.0, 0.9, 0.7)), (0.8, 0.03, 0.08), (0, 2.55, -0.45), bevel=0.0)  # the light over the podium
    m.box(dark, (0.84, 0.06, 0.12), (0, 2.6, -0.44), bevel=0.0)
    m.box(K("metal", (0.85, 0.65, 0.3)), (0.7, 0.12, 0.01), (0, 2.4, -0.505), bevel=0.0)  # name plate (the name is Label3D)
    for k in (0, 1, 2, 4, 5):  # (polish1 item 16) a brass button on the outer post of every shelf but the eye-level row:
        for sx in (-1, 1):  # it turns that shelf to other achievements (game/trophy_room.gd BUTTON_*)
            m.cyl(K("metal", (0.9, 0.68, 0.28)), 0.028, -0.49, -0.535, y=0.35 + 0.38 * k + 0.06, x=sx * 2.475, segs=12)


MODELS = [("hub_trophy_room", room, 0.5), ("hub_cabinet", cabinet, 1.0),
    ("trophy_cup", cup, 4.0), ("trophy_statuette", statuette, 4.0), ("trophy_plaque", plaque, 4.0), ("trophy_medal", medal, 4.0),
    ("trophy_skull", skull, 4.0), ("trophy_crown", crown, 4.0), ("trophy_stand", stand, 4.0)] + [("trophy_u%d" % i, unique(i), 4.0) for i in range(27)]

if __name__ == "__main__":
    init()
    fantasy_kit.OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")
    for name, build, uv in MODELS:
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        m = kit.Model(name, uv_scale=uv, colored=True)
        build(m)
        print(name, m.export(fantasy_kit.OUT))

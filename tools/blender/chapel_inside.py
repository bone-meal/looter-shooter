# Purpose: developer-time script (polish1 E5, item 122). Models the inside of the GRAND CHAPEL (game/fantasy_rooms.gd
# builds the hall from data/fantasy/interiors.json rooms.chapel: size, height, roof, windows, items): a clustered stone
# column, a tall pointed (lancet) window of stained glass, a round rose window, an iron candelabra, a long carpet
# runner, a hanging banner, a lectern and the stone altar step. Stained glass is material "stained" (unshaded and in its
# own colours: game/fantasy_models.gd), candle flames "glow". Footprints go to data/fantasy/props.json.
# Run: python3 tools/blender/chapel_inside.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
import kit
from fantasy_kit import K

STONE = (0.74, 0.7, 0.64)
IRON = (0.22, 0.22, 0.24)
GLASS = [(0.6, 0.09, 0.1), (0.13, 0.22, 0.62), (0.88, 0.6, 0.16), (0.14, 0.46, 0.27), (0.4, 0.16, 0.52)]  # ruby, cobalt, amber, emerald, violet
STAINED = None


def glass(rgb):
    return (STAINED, rgb)


def chapel_column(m):
    h = 6.6
    m.lathe(K("stone", STONE), [(0.62, 0.0), (0.62, 0.35), (0.5, 0.45), (0.44, 0.6)], (0, 0, 0), segs=12)  # base
    for k in range(4):  # four shafts round a core: a clustered pier
        a = math.pi / 4 + k * math.pi / 2
        m.rod(K("stone", STONE), 0.17, (math.cos(a) * 0.26, 0.55, math.sin(a) * 0.26), (math.cos(a) * 0.26, h - 0.6, math.sin(a) * 0.26), segs=10)
    m.rod(K("stone", tuple(v * 0.95 for v in STONE)), 0.3, (0, 0.55, 0), (0, h - 0.6, 0), segs=12)
    m.lathe(K("stone", STONE), [(0.44, h - 0.6), (0.5, h - 0.45), (0.7, h - 0.2), (0.7, h)], (0, 0, 0), segs=12)  # capital
    for k in range(8):  # carved leaves round the capital
        a = k * math.pi / 4
        m.ball(K("stone", (0.68, 0.64, 0.58)), (0.12, 0.16, 0.06), (math.cos(a) * 0.55, h - 0.38, math.sin(a) * 0.55), yaw=math.degrees(-a) + 90, u=6, v=4)


def chapel_window(m):
    w, h, sill = 1.5, 4.2, 1.6  # a lancet in the wall's face (the room puts it against the wall, glass facing in)
    pts = []
    for i in range(13):  # the pointed top: two arcs meeting
        t = i / 12.0
        a = math.pi * t
        pts.append((-w / 2 * math.cos(a), sill + h - w / 2 + w / 2 * math.sin(a) * 1.3))
    frame = K("stone", STONE)
    m.box(frame, (w + 0.4, 0.25, 0.3), (0, sill - 0.12, 0), bevel=0.02)  # sill
    for side in (-1, 1):
        m.box(frame, (0.2, h - w / 2, 0.3), (side * (w / 2 + 0.1), sill + (h - w / 2) / 2, 0), bevel=0.02)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):  # the arch's stones
        m.rod(frame, 0.11, (x0 * 1.13, y0 + 0.05, 0), (x1 * 1.13, y1 + 0.05, 0), segs=6)
    rows, cols = 7, 3
    for r in range(rows):  # the glass in coloured panes with lead between
        for c in range(cols):
            y = sill + (h - w / 2) * (r + 0.5) / rows
            x = -w / 2 + w * (c + 0.5) / cols
            m.box(glass(GLASS[(r * 2 + c) % len(GLASS)]), (w / cols - 0.05, (h - w / 2) / rows - 0.05, 0.03), (x, y, -0.02), bevel=0.0)
    m.ball(glass(GLASS[2]), (w / 2 - 0.05, w / 2 * 1.2, 0.015), (0, sill + h - w / 2, -0.02), u=12, v=8)  # the head of the light
    m.box(K("metal", IRON), (0.04, h - 0.2, 0.05), (0, sill + (h - 0.2) / 2, -0.01), bevel=0.0)  # a mullion


def chapel_rose(m):
    r = 1.6
    m.lathe(K("stone", STONE), [(r + 0.25, -0.12), (r + 0.25, 0.12), (r, 0.12), (r, -0.12)], (0, 0, 0), segs=24, axis="f")
    m.ball(glass(GLASS[2]), (0.42, 0.42, 0.03), (0, 0, -0.03), u=12, v=8)
    for k in range(12):  # petals of glass between stone spokes
        a = k * math.pi / 6
        m.ball(glass(GLASS[k % len(GLASS)]), (0.32, 0.6, 0.02), (math.cos(a) * 1.0, math.sin(a) * 1.0, -0.03), pitch=0, u=8, v=6)
        m.rod(K("stone", STONE), 0.05, (math.cos(a) * 0.45, math.sin(a) * 0.45, 0), (math.cos(a) * r, math.sin(a) * r, 0), segs=5)


def candelabra(m):
    iron = K("metal", IRON)
    m.lathe(iron, [(0.28, 0.0), (0.28, 0.05), (0.06, 0.12), (0.04, 1.5)], (0, 0, 0), segs=10)
    for k in range(5):
        x = (k - 2) * 0.16
        top = 1.5 + 0.12 - abs(k - 2) * 0.04
        if k != 2:
            m.rod(iron, 0.015, (0, 1.42, 0), (x, top - 0.05, 0), segs=5)
        m.lathe(iron, [(0.05, top - 0.05), (0.05, top)], (x, 0, 0), segs=8)
        m.rod(K("paint", (0.95, 0.92, 0.82)), 0.025, (x, top, 0), (x, top + 0.16, 0), segs=8)  # the candle
        m.ball(fk.GLOW, (0.022, 0.05, 0.022), (x, top + 0.21, 0), u=6, v=4)  # its flame


def chapel_runner(m):
    m.box(K("cloth", (0.55, 0.1, 0.1)), (1.5, 0.02, 14.0), (0, 0.01, 0), bevel=0.0)
    for side in (-1, 1):
        m.box(K("cloth", (0.85, 0.65, 0.2)), (0.1, 0.022, 14.0), (side * 0.65, 0.011, 0), bevel=0.0)


def chapel_banner(m):
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.03, (-0.65, 3.6, 0.12), (0.65, 3.6, 0.12), segs=6)
    m.box(K("cloth", (0.5, 0.1, 0.12)), (1.1, 2.4, 0.03), (0, 2.38, 0.12), bevel=0.0)
    for side in (-1, 1):
        m.box(K("cloth", (0.5, 0.1, 0.12)), (0.55, 0.3, 0.03), (side * 0.275, 1.04, 0.12), tilt=0, bevel=0.0)  # a swallow-tail
    m.lathe(K("cloth", (0.9, 0.72, 0.25)), [(0.3, -0.01), (0.3, 0.01)], (0, 2.6, 0.1), segs=16, axis="f")  # a gold sun on it


def lectern(m):
    wood = K("wood", (0.45, 0.3, 0.17))
    m.lathe(wood, [(0.3, 0.0), (0.3, 0.06), (0.08, 0.12), (0.07, 1.0)], (0, 0, 0), segs=8)
    m.box(wood, (0.6, 0.05, 0.45), (0, 1.12, 0), tilt=-25)
    m.box(K("paint", (0.92, 0.88, 0.76)), (0.5, 0.04, 0.34), (0, 1.16, 0.0), tilt=-25)  # an open book


def build_all():
    global STAINED
    fk.init()
    STAINED = kit.material("stained", None, (1.0, 1.0, 1.0))
    mk = fk.Maker()
    for name, build, solid in (("chapel_column", chapel_column, True), ("chapel_window", chapel_window, False), ("chapel_rose", chapel_rose, False),
            ("candelabra", candelabra, True), ("chapel_runner", chapel_runner, False), ("chapel_banner", chapel_banner, False), ("lectern", lectern, True)):
        mk.model(name, build, solid=solid, uv=0.5)
    mk.save()


if __name__ == "__main__":
    build_all()

# Purpose: developer-time script (polish1 E4, item 131). Models the HARVEST KING's threshing ground: the old threshing
# floor (a ring of kerb stones round beaten earth strewn with straw), stooks (sheaves leaning together to dry), a rack
# of flails, loose straw on the ground and a heap of threshed grain with a wooden shovel. Every part is named after what
# it is made of (tools/blender/fantasy_kit.py). Footprints are added to data/fantasy/props.json; the floor and the loose
# straw are walked over (data/fantasy/layouts.json walk_over). Laid out by layouts.json kind "arena_threshing".
# Run: python3 tools/blender/threshing_props.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K, blob

STRAW = (0.88, 0.72, 0.34)
EARTH = (0.46, 0.34, 0.22)
WOOD = (0.5, 0.36, 0.22)


def threshing_floor(m):
    r = 9.0  # (raised a hand above the arena yard: the drawn ground there may sit a little above its middle)
    m.lathe(K("adobe", EARTH), [(r, -0.1), (r, 0.14), (0.0, 0.14)], (0, 0, 0), segs=28)  # beaten earth (outside in: its top faces up)
    rnd = random.Random(3)
    for k in range(34):  # the kerb: a ring of rough stones
        a = 2 * math.pi * k / 34
        blob(m, K("stone", (0.62, 0.6, 0.55)), (0.42, 0.16, 0.3), (math.cos(a) * (r + 0.2), 0.14, math.sin(a) * (r + 0.2)), seed=k, rough=0.25, cuts=1)
    for k in range(70):  # straw strewn over it, thicker toward the middle where the sheaves were beaten
        d = r * math.sqrt(rnd.random()) * 0.9
        a = rnd.random() * 2 * math.pi
        x, f = math.cos(a) * d, math.sin(a) * d
        turn = rnd.random() * math.pi
        m.rod(K("thatch", STRAW), 0.012, (x - math.cos(turn) * 0.35, 0.15, f - math.sin(turn) * 0.35), (x + math.cos(turn) * 0.35, 0.15, f + math.sin(turn) * 0.35), segs=3)
    m.lathe(K("stone", (0.45, 0.42, 0.38)), [(0.9, 0.0), (0.9, 0.16), (0.0, 0.16)], (0, 0, 0), segs=12)  # the old centre stone


def stook(m):
    for k in range(6):  # sheaves leaning together in a cone
        a = 2 * math.pi * k / 6
        foot = (math.cos(a) * 0.45, 0.0, math.sin(a) * 0.45)
        top = (math.cos(a) * 0.08, 1.25, math.sin(a) * 0.08)
        m.rod(K("thatch", STRAW), 0.13, foot, top, r2=0.07, segs=6)
        m.ball(K("thatch", (0.95, 0.8, 0.38)), (0.12, 0.2, 0.12), (math.cos(a) * 0.04, 1.4, math.sin(a) * 0.04), u=6, v=4)
    m.lathe(K("leather", (0.55, 0.4, 0.22)), [(0.2, 0.95), (0.2, 1.0)], (0, 0, 0), segs=8)  # twine round the waist


def flail(m, x, f, lean):
    top = (x + lean, 1.45, f - 0.25)
    m.rod(K("wood", WOOD), 0.022, (x, 0.0, f), top, segs=6)  # the handle
    m.rod(K("leather", (0.3, 0.2, 0.12)), 0.012, top, (top[0] + 0.05, top[1] + 0.06, top[2]), segs=4)  # the leather hinge
    m.rod(K("wood", (0.62, 0.48, 0.3)), 0.03, (top[0] + 0.05, top[1] + 0.06, top[2]), (top[0] + 0.12, top[1] - 0.55, top[2] + 0.08), segs=6)  # the swingle hanging down


def flail_rack(m):
    for x in (-0.9, 0.9):
        m.rod(K("wood", WOOD), 0.05, (x, 0.0, 0.0), (x, 1.5, 0.0), segs=6)
    m.rod(K("wood", WOOD), 0.04, (-1.0, 1.42, 0.0), (1.0, 1.42, 0.0), segs=6)
    for k, x in enumerate((-0.6, -0.2, 0.25, 0.65)):
        flail(m, x, 0.45, -0.05 + 0.03 * k)


def straw_strew(m):
    rnd = random.Random(11)
    for k in range(40):
        d = 1.6 * math.sqrt(rnd.random())
        a = rnd.random() * 2 * math.pi
        x, f = math.cos(a) * d, math.sin(a) * d
        turn = rnd.random() * math.pi
        m.rod(K("thatch", STRAW if k % 3 else (0.78, 0.62, 0.28)), 0.014, (x - math.cos(turn) * 0.3, 0.02, f - math.sin(turn) * 0.3), (x + math.cos(turn) * 0.3, 0.02, f + math.sin(turn) * 0.3), segs=3)


def grain_heap(m):
    blob(m, K("thatch", (0.82, 0.66, 0.36)), (0.9, 0.45, 0.8), (0, 0.15, 0), seed=5, rough=0.12, cuts=2)  # threshed grain
    blob(m, K("thatch", (0.72, 0.58, 0.32)), (0.5, 0.2, 0.45), (0.9, 0.05, 0.3), seed=6, rough=0.15, cuts=1)  # chaff blown aside
    m.rod(K("wood", WOOD), 0.025, (-0.2, 0.25, -0.1), (-1.1, 0.9, -0.5), segs=6)  # the wooden shovel stuck in it
    m.box(K("wood", (0.6, 0.46, 0.28)), (0.26, 0.03, 0.32), (-0.05, 0.22, 0.0), tilt=20, bevel=0.0)


def build_all():
    fk.init()
    mk = fk.Maker()
    for name, build, solid in (("threshing_floor", threshing_floor, False), ("stook", stook, True), ("flail_rack", flail_rack, True), ("straw_strew", straw_strew, False), ("grain_heap", grain_heap, True)):
        mk.model(name, build, solid=solid, uv=0.5)
    mk.save()


if __name__ == "__main__":
    build_all()

# Purpose: developer-time tool. Builds the salvage models of sea step 5b into assets/models/sea/: salvage_chest (an
# iron-banded sea chest half sunk in sand, barnacles), wreck_small (a broken length of hull with ribs, planks and a
# snapped mast stump), seabed_patch (a sandy patch with rocks and weed the finds lie on) and rope_float (the cork
# float on the end of a thrown rope). Materials are named after what a part is made of (tools/blender/fantasy_kit.py).
# Run: python3 tools/blender/sea_salvage.py   (bpy as a module)
# Dependencies: bpy, bmesh, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
WOOD = (0.32, 0.26, 0.2)
ROTTEN = (0.26, 0.24, 0.19)
IRON = (0.3, 0.24, 0.2)
SAND = (0.78, 0.72, 0.56)
ROCK = (0.42, 0.42, 0.4)
WEED = (0.24, 0.42, 0.22)
BARNACLE = (0.82, 0.8, 0.72)
CORK = (0.74, 0.56, 0.34)
RED = (0.78, 0.18, 0.14)


def barnacles(m, rnd, n, lo, hi, node="Body"):
    for _ in range(n):
        x, y, f = (rnd.uniform(lo[i], hi[i]) for i in range(3))
        m.ball(K("rock", BARNACLE), (0.035, 0.03, 0.035), (x, y, f), node=node, u=6, v=4)


def chest(m):
    rnd = random.Random(5)
    m.box(K("wood", WOOD), (0.9, 0.5, 0.55), (0.0, 0.2, 0.0), tilt=6)
    m.box(K("wood", ROTTEN), (0.92, 0.18, 0.57), (0.0, 0.52, -0.02), tilt=-14)  # lid ajar
    for x in (-0.32, 0.0, 0.32):
        m.box(K("metal", IRON), (0.06, 0.54, 0.6), (x, 0.22, 0.0), tilt=6)
    m.box(K("metal", (0.7, 0.6, 0.3)), (0.12, 0.12, 0.04), (0.0, 0.36, 0.3))  # lock plate
    barnacles(m, rnd, 26, (-0.45, 0.05, -0.28), (0.45, 0.6, 0.28))
    for k in range(5):
        a = k * 1.3
        m.ball(K("leaf", WEED), (0.05, 0.35, 0.05), (0.6 * math.cos(a), 0.3, 0.45 * math.sin(a)), u=6, v=5)


def wreck(m):
    rnd = random.Random(9)
    for i in range(6):  # ribs
        f = -2.4 + i * 0.95
        pts = [(1.6 * math.sin(t / 8 * math.pi * 0.9), 0.2 + 1.8 * (1 - math.cos(t / 8 * math.pi * 0.9))) for t in range(9)]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            m.rod(K("wood", ROTTEN), 0.08, (x0, y0, f), (x1, y1, f), segs=6)
    for k in range(7):  # planks still on one side, broken off at uneven lengths
        t = k / 6.0
        y = 0.25 + 1.6 * t
        x = 1.55 * math.sin(t * math.pi * 0.45) + 0.05
        length = 4.8 - rnd.uniform(0.0, 2.6) * t
        m.box(K("wood", WOOD), (0.08, 0.28, length), (x, y, -2.4 + length / 2), tilt=0)
    m.box(K("wood", ROTTEN), (0.3, 0.3, 5.6), (0.0, 0.15, 0.0))  # keel
    m.rod(K("wood", WOOD), 0.16, (0.0, 0.2, 0.4), (0.25, 2.2, 0.7), r2=0.11, segs=10)  # mast stump
    barnacles(m, rnd, 40, (-0.2, 0.1, -2.5), (1.6, 1.8, 2.4))
    for k in range(6):
        m.ball(K("leaf", WEED), (0.05, 0.5, 0.05), (rnd.uniform(-1.5, 1.8), 0.45, rnd.uniform(-2.6, 2.6)), u=6, v=5)


def patch(m):
    import bmesh
    rnd = random.Random(3)
    bm = bmesh.new()
    rings, segs = 5, 20
    centre = bm.verts.new((0, 0, 0.05))
    prev = None
    first = None
    for r in range(1, rings + 1):
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            rad = 7.0 * r / rings * (1 + rnd.uniform(-0.12, 0.12))
            ring.append(bm.verts.new((rad * math.cos(a), rad * math.sin(a), -0.5 * (r / rings) ** 2 + rnd.uniform(-0.05, 0.05))))
        if prev is None:
            for k in range(segs):
                bm.faces.new((centre, ring[k], ring[(k + 1) % segs]))
        else:
            for k in range(segs):
                bm.faces.new((prev[k], ring[k], ring[(k + 1) % segs], prev[(k + 1) % segs]))
        prev = ring
    m._add(bm, K("rock", SAND), "Body", 0)
    for _ in range(9):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(2.0, 6.0)
        fk.blob(m, K("rock", ROCK), (rnd.uniform(0.3, 0.8), rnd.uniform(0.2, 0.5), rnd.uniform(0.3, 0.7)), (d * math.cos(a), 0.0, d * math.sin(a)), seed=rnd.randint(0, 99), rough=0.25)
    for _ in range(14):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(1.5, 6.5)
        h = rnd.uniform(0.4, 1.2)
        m.ball(K("leaf", WEED), (0.06, h, 0.06), (d * math.cos(a), h * 0.8, d * math.sin(a)), u=6, v=5)


def rope_float(m):
    m.lathe(K("wood", CORK), [(0.0, -0.12), (0.22, -0.1), (0.28, 0.0), (0.22, 0.1), (0.0, 0.12)], (0.0, 0.0, 0.0), segs=16)
    for k in range(4):
        a = k * math.pi / 2
        m.box(K("paint", RED), (0.1, 0.25, 0.1), (0.27 * math.cos(a), 0.0, 0.27 * math.sin(a)), bevel=0.01)


if __name__ == "__main__":
    fk.init()
    for name, build in (("salvage_chest", chest), ("wreck_small", wreck), ("seabed_patch", patch), ("rope_float", rope_float)):
        if fk.ONLY and name not in fk.ONLY:
            continue
        m = kit.Model(name, uv_scale=0.6, colored=True)
        build(m)
        print(name, m.export(OUT))

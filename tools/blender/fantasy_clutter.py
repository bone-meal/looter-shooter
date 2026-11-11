# Purpose: developer-time script. Models the solid clutter of the fantasy world's open country with
# tools/blender/fantasy_kit.py: boulders and rock spires in each region's stone, fallen logs, stumps, bushes and ice
# shards. They stand scattered between the places (data/fantasy/world.json regions.clutter; rules
# core/fantasy_layout.gd `clutter`), so nobody can walk backwards across the land for ever. Sizes go into
# data/fantasy/props.json like every other model. Model space: x right, y up, f forward.
# Run: python3 tools/blender/fantasy_clutter.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K, c


def boulder(m, kind, rgb, size, seed, cap=None):
    """Two or three lumps grown into each other; `cap` = a colour of moss or snow lying on top."""
    fk.blob(m, K(kind, rgb), (size, size * 0.72, size * 0.85), (0, size * 0.45, 0), seed=seed, rough=0.22)
    fk.blob(m, K(kind, tuple(v * 0.9 for v in rgb)), (size * 0.6, size * 0.5, size * 0.62), (size * 0.62, size * 0.28, size * 0.25), seed=seed + 1, rough=0.25)
    fk.blob(m, K(kind, tuple(v * 1.06 for v in rgb)), (size * 0.45, size * 0.36, size * 0.5), (-size * 0.6, size * 0.2, -size * 0.3), seed=seed + 2, rough=0.25, cuts=1)
    if cap:
        fk.blob(m, c(cap), (size * 0.7, size * 0.16, size * 0.6), (0.05, size * 1.02, 0), seed=seed + 3, rough=0.15, cuts=1)


def spire(m, kind, rgb, height, seed):
    """A leaning tooth of rock with two smaller ones at its foot."""
    lean = 0.18 * height
    m.loft(K(kind, rgb), [(0, 0, 0, 0.95, 0.8), (lean * 0.3, height * 0.35, 0.05, 0.78, 0.62), (lean * 0.7, height * 0.72, 0.1, 0.5, 0.42), (lean, height, 0.12, 0.08, 0.07)], segs=6, steps=2)
    for k, (dx, df, h) in enumerate(((0.9, 0.5, 0.42), (-0.8, -0.4, 0.3))):
        m.loft(K(kind, tuple(v * (0.9 + 0.1 * k) for v in rgb)), [(dx, 0, df, 0.5, 0.45), (dx * 1.1, height * h * 0.6, df, 0.34, 0.3), (dx * 1.25, height * h, df * 1.1, 0.05, 0.05)], segs=5, steps=2)
    fk.blob(m, K(kind, tuple(v * 0.85 for v in rgb)), (0.5, 0.3, 0.45), (0.2, 0.15, -0.9), seed=seed, rough=0.25, cuts=1)


def fallen_log(m):
    bark = K("bark", (0.36, 0.27, 0.18))
    m.loft(bark, [(-2.3, 0.42, 0.1, 0.42, 0.42), (-0.8, 0.4, 0.0, 0.4, 0.4), (0.9, 0.36, -0.08, 0.36, 0.36), (2.3, 0.3, 0.05, 0.28, 0.28)], segs=8, steps=2)
    m.ball(K("wood", (0.72, 0.6, 0.4)), (0.06, 0.38, 0.38), (-2.32, 0.42, 0.1), u=8, v=5)  # the sawn end
    for x, f, up in ((-1.0, 0.3, 0.9), (0.4, -0.35, 0.8), (1.5, 0.25, 0.6)):
        m.rod(bark, 0.09, (x, 0.5, f * 0.5), (x + 0.25, 0.5 + up, f * 2.0), r2=0.035, segs=5)
    fk.blob(m, K("leaf", (0.3, 0.45, 0.2)), (0.5, 0.12, 0.3), (0.3, 0.74, 0), seed=5, rough=0.2, cuts=1)  # moss


def stump(m):
    bark = K("bark", (0.38, 0.28, 0.18))
    m.lathe(bark, [(0.62, 0.0), (0.5, 0.15), (0.44, 0.75), (0.4, 0.8)], (0, 0, 0), segs=9)
    m.lathe(K("wood", (0.74, 0.62, 0.42)), [(0.4, 0.8), (0.0, 0.84)], (0, 0, 0), segs=9)
    for k in range(4):
        a = k * 1.6 + 0.3
        m.loft(bark, [(math.cos(a) * 0.4, 0.2, math.sin(a) * 0.4, 0.16, 0.14), (math.cos(a) * 0.85, 0.06, math.sin(a) * 0.85, 0.08, 0.06), (math.cos(a) * 1.15, 0.0, math.sin(a) * 1.15, 0.03, 0.03)], segs=5, steps=2)


def bush(m, leaves, twig, seed):
    for k, (dx, df, r) in enumerate(((0, 0, 0.8), (0.6, 0.2, 0.6), (-0.55, 0.3, 0.55), (0.1, -0.6, 0.6))):
        fk.blob(m, K("leaf", leaves[k % len(leaves)]), (r, r * 0.8, r), (dx, r * 0.75, df), seed=seed + k, rough=0.28, cuts=1 if k else 2)
    for k in range(3):
        a = k * 2.1
        m.rod(K("bark", twig), 0.05, (0, 0, 0), (math.cos(a) * 0.5, 0.6, math.sin(a) * 0.5), r2=0.02, segs=4)


def dry_bush(m, twig, seed):
    import random
    rnd = random.Random(seed)
    for k in range(11):
        a = k * 0.57 + rnd.uniform(-0.2, 0.2)
        reach = rnd.uniform(0.6, 1.1)
        mid = (math.cos(a) * reach * 0.5, rnd.uniform(0.5, 0.9), math.sin(a) * reach * 0.5)
        tip = (math.cos(a + 0.4) * reach, rnd.uniform(0.9, 1.5), math.sin(a + 0.4) * reach)
        m.rod(K("bark", twig), 0.04, (0, 0, 0), mid, r2=0.025, segs=4)
        m.rod(K("bark", twig), 0.025, mid, tip, r2=0.008, segs=4)
        m.rod(K("bark", twig), 0.015, mid, (mid[0] * 1.5, mid[1] + 0.35, mid[2] * 1.2), r2=0.006, segs=3)


def ice_shards(m):
    ice = K("ice", (0.72, 0.88, 1.0))
    for k, (dx, df, h, lean) in enumerate(((0, 0, 2.6, 0.2), (0.7, 0.3, 1.7, 0.5), (-0.6, 0.4, 1.4, -0.4), (0.2, -0.7, 1.9, 0.1), (-0.5, -0.5, 1.0, -0.3))):
        m.loft(ice if k % 2 == 0 else K("ice", (0.6, 0.78, 0.96)), [(dx, 0, df, 0.42, 0.36), (dx + lean * 0.4, h * 0.6, df, 0.3, 0.26), (dx + lean, h, df + lean * 0.3, 0.03, 0.03)], segs=5, steps=2)


def build_all():
    fk.init()
    mk = fk.Maker()
    mk.model("boulder_grey", lambda m: boulder(m, "rock", (0.55, 0.54, 0.5), 1.25, 11))
    mk.model("boulder_moss", lambda m: boulder(m, "rock", (0.42, 0.44, 0.38), 1.4, 23, cap=(0.28, 0.46, 0.2)))
    mk.model("boulder_sand", lambda m: boulder(m, "sandstone", (0.82, 0.66, 0.44), 1.3, 37))
    mk.model("boulder_ice", lambda m: boulder(m, "rock", (0.6, 0.66, 0.74), 1.3, 41, cap=(0.95, 0.97, 1.0)))
    mk.model("boulder_basalt", lambda m: boulder(m, "rock", (0.2, 0.18, 0.19), 1.35, 53))
    mk.model("boulder_pale", lambda m: boulder(m, "rock", (0.78, 0.78, 0.8), 1.2, 67))
    mk.model("spire_sand", lambda m: spire(m, "sandstone", (0.8, 0.6, 0.38), 4.6, 3))
    mk.model("spire_basalt", lambda m: spire(m, "rock", (0.22, 0.19, 0.2), 5.0, 5))
    mk.model("spire_grey", lambda m: spire(m, "rock", (0.5, 0.52, 0.58), 5.2, 7))
    mk.model("fallen_log", fallen_log)
    mk.model("stump", stump)
    mk.model("bush_green", lambda m: bush(m, [(0.24, 0.48, 0.18), (0.3, 0.55, 0.22), (0.2, 0.42, 0.16)], (0.3, 0.22, 0.14), 71))
    mk.model("bush_gold", lambda m: bush(m, [(0.62, 0.6, 0.24), (0.7, 0.66, 0.26), (0.5, 0.56, 0.22)], (0.36, 0.26, 0.16), 73))
    mk.model("bush_dry", lambda m: dry_bush(m, (0.5, 0.42, 0.3), 79))
    mk.model("bush_ash", lambda m: dry_bush(m, (0.16, 0.14, 0.14), 83))
    mk.model("ice_shards", ice_shards)
    mk.save()


if __name__ == "__main__":
    build_all()

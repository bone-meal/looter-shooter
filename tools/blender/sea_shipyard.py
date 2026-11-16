# Purpose: developer-time tool. Builds the slipway of sea step 5c (assets/models/sea/slipway.gltf): a timber ramp on
# log runners running down into the water (its foot faces the model's forward, the game's -z), a launching cradle,
# a scaffold of posts and beams, the shipwright's workbench with a stack of planks and a saw, and a sign post. The
# game puts the workbench's station at data/sea/ships.json shipyard.bench. Until the home port (step 7) it stands
# on region 1's test island.
# Run: python3 tools/blender/sea_shipyard.py   (bpy as a module)
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
WOOD = (0.5, 0.38, 0.24)
DARK = (0.28, 0.2, 0.13)
LIGHT = (0.7, 0.58, 0.4)
ROPE = (0.62, 0.52, 0.36)
IRON = (0.28, 0.28, 0.3)


def slipway(m):
    # the ramp: two log runners and planks across, from the land (f -8, y 0.6) down into the sea (f 14, y -2.0)
    def y_at(f):
        return 0.6 + (f + 8.0) / 22.0 * (-2.6)
    for x in (-2.2, 2.2):
        m.rod(K("bark", DARK), 0.22, (x, y_at(-8.0) - 0.2, -8.0), (x, y_at(14.0) - 0.2, 14.0), segs=10)
    f = -7.8
    while f < 13.8:
        m.box(K("wood", WOOD if int(f * 2) % 3 else LIGHT), (5.2, 0.1, 0.36), (0.0, y_at(f), f), tilt=-6.7)
        f += 0.42
    for x in (-1.4, 1.4):  # the cradle the hull sits in while being built
        for f in (-4.0, 0.0, 4.0):
            m.box(K("wood", DARK), (0.3, 0.9, 0.3), (x, y_at(f) + 0.5, f))
            m.rod(K("wood", DARK), 0.08, (x, y_at(f) + 0.95, f), (x * 0.4, y_at(f) + 0.3, f), segs=6)
    for x in (-3.4, 3.4):  # scaffold: posts, a long beam on top, braces
        for f in (-7.0, -1.0, 5.0):
            m.box(K("wood", WOOD), (0.22, 6.0, 0.22), (x, 2.9 + y_at(f) * 0.5, f))
        m.box(K("wood", WOOD), (0.24, 0.24, 13.0), (x, 5.8, -1.0))
        for f in (-7.0, -1.0):
            m.rod(K("wood", DARK), 0.06, (x, 1.2, f), (x, 5.6, f + 6.0), segs=6)
    for f in (-7.0, -1.0, 5.0):
        m.box(K("wood", WOOD), (7.0, 0.22, 0.22), (0.0, 5.9, f))
    m.rod(K("leather", ROPE), 0.035, (0.0, 5.8, -1.0), (0.0, 2.0, -1.0), segs=6)  # a hoist rope
    m.lathe(K("metal", IRON), [(0.12, -0.05), (0.12, 0.05)], (0.0, 5.7, -1.0), segs=12)


def bench(m, at):
    x, f = at
    m.box(K("wood", LIGHT), (2.4, 0.12, 1.0), (x, 0.95, f))  # top
    for dx in (-1.05, 1.05):
        for df in (-0.4, 0.4):
            m.box(K("wood", DARK), (0.12, 0.9, 0.12), (x + dx, 0.45, f + df))
    for k in range(5):  # plank stack beside it
        m.box(K("wood", WOOD if k % 2 else LIGHT), (0.3, 0.06, 3.0), (x + 2.0, 0.08 + k * 0.08, f + 0.3), bevel=0.01)
    m.box(K("metal", IRON), (0.02, 0.18, 0.7), (x - 0.4, 1.12, f))  # saw blade
    m.box(K("wood", DARK), (0.06, 0.12, 0.2), (x - 0.4, 1.12, f + 0.42))  # its handle
    m.cyl(K("wood", DARK), 0.05, f - 0.3, f - 0.05, y=1.06, x=x + 0.6, segs=8)  # mallet
    m.box(K("wood", DARK), (0.12, 0.12, 0.3), (x + 0.6, 1.06, f - 0.42))
    # sign post with a sail painted on it
    m.box(K("wood", DARK), (0.14, 2.4, 0.14), (x - 1.7, 1.2, f - 0.8))
    m.box(K("wood", LIGHT), (1.0, 0.6, 0.06), (x - 1.7, 2.2, f - 0.75))
    m.box(K("paint", (0.92, 0.9, 0.8)), (0.4, 0.38, 0.02), (x - 1.7, 2.22, f - 0.71))


if __name__ == "__main__":
    import json
    fk.init()
    cfg = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "data", "sea", "ships.json")))["shipyard"]
    m = kit.Model("slipway", uv_scale=0.6, colored=True)
    slipway(m)
    bench(m, (cfg["bench"][0], -cfg["bench"][1]))
    print("slipway", m.export(OUT))

# Purpose: developer-time script. Models region 2's PITCH POT (sea step 13 R2g) with tools/blender/kit.py into
# assets/models/sea/pitch_pot.gltf: a squat clay pot on three flat stones under a hollow wooden spout driven into a
# mangrove root stump, black pitch glossy at the brim and a drip down the side ("Pitch": the game hides it while the pot
# is empty). Our own design. Model space: x right, y up, f forward; base on y = 0, about 1.2 m tall with the stump.
# Run: python3 tools/blender/sea_pitch_pot.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")

CLAY = (0.55, 0.33, 0.2)
CLAY_DARK = (0.4, 0.23, 0.14)
STONE = (0.45, 0.43, 0.4)
ROOT = (0.27, 0.2, 0.13)
WOOD = (0.42, 0.32, 0.2)
PITCH = (0.05, 0.04, 0.03)


def pot(m):
    clay, clay_dark, stone = K("rock", CLAY), K("rock", CLAY_DARK), K("rock", STONE)
    root, wood, pitch = K("wood", ROOT), K("wood", WOOD), K("metal", PITCH)
    for k in range(3):  # three flat stones under it
        a = 2 * math.pi * k / 3 + 0.3
        fk.blob(m, stone, (0.16, 0.06, 0.13), (math.cos(a) * 0.2, 0.05, math.sin(a) * 0.2), seed=5 + k, rough=0.25, cuts=1)
    m.lathe(clay, [(0.0, 0.08), (0.2, 0.09), (0.3, 0.2), (0.33, 0.34), (0.28, 0.46), (0.22, 0.5), (0.24, 0.54), (0.2, 0.55), (0.0, 0.5)], (0.0, 0.0, 0.0), segs=16)
    m.lathe(clay_dark, [(0.32, 0.3), (0.335, 0.32), (0.33, 0.34)], (0.0, 0.0, 0.0), segs=16)  # a band round its belly
    m.node("Pitch", (0.0, 0.52, 0.0))
    m.lathe(pitch, [(0.0, 0.53), (0.2, 0.53), (0.19, 0.51), (0.0, 0.51)], (0.0, 0.0, 0.0), segs=14, node="Pitch")
    m.loft(pitch, [(0.22, 0.52, 0.05, 0.03, 0.02), (0.29, 0.38, 0.06, 0.025, 0.018), (0.32, 0.27, 0.07, 0.012, 0.01)], segs=6, node="Pitch")  # a drip
    # the root stump behind it and the spout
    m.loft(root, [(0.0, 0.0, -0.55, 0.22, 0.2), (0.02, 0.6, -0.52, 0.18, 0.17), (0.05, 1.15, -0.5, 0.12, 0.11)], segs=10)
    for k in range(4):  # roots splaying from the stump
        a = 2 * math.pi * k / 4 + 0.8
        m.rod(root, 0.06, (0.0, 0.25, -0.55), (math.cos(a) * 0.45, 0.0, -0.55 + math.sin(a) * 0.4), r2=0.03, segs=6)
    m.rod(wood, 0.035, (0.0, 0.85, -0.45), (0.0, 0.72, -0.08), r2=0.03, segs=8)
    m.ball(pitch, (0.03, 0.05, 0.03), (0.0, 0.68, -0.07), u=6, v=5, node="Pitch")


def main():
    fk.init()
    m = kit.Model("pitch_pot", uv_scale=2.0, colored=True)
    pot(m)
    print("pitch_pot", m.export(OUT))


if __name__ == "__main__":
    main()

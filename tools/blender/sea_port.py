# Purpose: developer-time tool. Builds the HARBOUR MASTER'S STALL of sea step 6 (the port's shop, money changer and
# ferry desk until the home port town of step 7 gives them buildings) into assets/models/sea/harbour_stall.gltf: a
# timber counter with a ledger and scales, two posts carrying a striped awning, a hanging sign painted with a gold
# anchor and a coin, crates and a barrel of supplies, a coiled rope and a hanging lantern. ~3.6 m wide, front = -f.
# Materials are named after what a part is made of (tools/blender/fantasy_kit.py).
# Run: python3 tools/blender/sea_port.py   (bpy as a module)
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
WOOD = (0.48, 0.33, 0.2)
DARK = (0.3, 0.2, 0.12)
TEAL = (0.12, 0.45, 0.5)
CREAM = (0.94, 0.9, 0.78)
GOLD = (0.9, 0.7, 0.24)
IRON = (0.22, 0.22, 0.23)
ROPE = (0.62, 0.52, 0.36)
PAPER = (0.9, 0.86, 0.72)


def stall(m):
    m.box(K("wood", WOOD), (3.4, 1.0, 0.7), (0.0, 0.5, -0.4))  # counter
    m.box(K("wood", DARK), (3.6, 0.08, 0.85), (0.0, 1.04, -0.42))  # counter top
    for x in (-1.2, -0.4, 0.4, 1.2):  # panel battens on its front
        m.box(K("wood", DARK), (0.06, 0.9, 0.04), (x, 0.5, -0.77))
    for x in (-1.7, 1.7):  # posts and the awning
        m.rod(K("wood", DARK), 0.07, (x, 0.0, 0.1), (x, 2.7, 0.1), segs=8)
        m.rod(K("wood", DARK), 0.06, (x, 0.0, -0.75), (x, 2.4, -0.75), segs=8)
    for k in range(8):
        x = -1.75 + 3.5 * (k + 0.5) / 8
        m.box(K("cloth", TEAL if k % 2 == 0 else CREAM), (3.5 / 8 + 0.01, 0.03, 1.5), (x, 2.62, -0.45), tilt=-14)
    for k in range(8):  # the scalloped valance
        x = -1.75 + 3.5 * (k + 0.5) / 8
        m.ball(K("cloth", TEAL if k % 2 == 0 else CREAM), (3.5 / 16, 0.12, 0.02), (x, 2.36, -1.18), u=10, v=4)
    # the sign hanging from a bracket on the left post: a board with a gold anchor and a coin
    m.rod(K("metal", IRON), 0.02, (-1.7, 2.3, -0.75), (-1.7, 2.3, -1.45), segs=6)
    for f in (-1.05, -1.35):
        m.rod(K("metal", IRON), 0.008, (-1.7, 2.3, f), (-1.7, 2.12, f), segs=4)
    m.box(K("wood", TEAL), (0.05, 0.5, 0.5), (-1.7, 1.86, -1.2))
    m.rod(K("paint", GOLD), 0.018, (-1.73, 2.02, -1.2), (-1.73, 1.7, -1.2), segs=6)  # anchor shank
    m.rod(K("paint", GOLD), 0.015, (-1.73, 1.98, -1.29), (-1.73, 1.98, -1.11), segs=6)  # stock
    for side in (-1, 1):
        m.rod(K("paint", GOLD), 0.016, (-1.73, 1.72, -1.2), (-1.73, 1.78, -1.2 + side * 0.11), segs=6)  # flukes
    m.ball(K("paint", GOLD), (0.012, 0.06, 0.06), (-1.73, 2.06, -1.2), u=10, v=6)  # ring
    # on the counter: a ledger, a set of scales, a stack of coins
    m.box(K("cloth", PAPER), (0.42, 0.04, 0.3), (-0.6, 1.1, -0.45), tilt=0)
    m.box(K("leather", (0.4, 0.15, 0.12)), (0.44, 0.02, 0.32), (-0.6, 1.085, -0.45))
    m.rod(K("metal", GOLD), 0.012, (0.5, 1.08, -0.45), (0.5, 1.45, -0.45), segs=6)
    m.rod(K("metal", GOLD), 0.01, (0.32, 1.45, -0.45), (0.68, 1.45, -0.45), segs=6)
    for x in (0.32, 0.68):
        m.lathe(K("metal", GOLD), [(0.0, -0.01), (0.08, 0.0), (0.0, 0.01)], (x, 1.3, -0.45), segs=10)
    for k in range(5):
        m.lathe(K("metal", GOLD), [(0.0, -0.006), (0.035, -0.006), (0.035, 0.006), (0.0, 0.006)], (1.1, 1.095 + 0.013 * k, -0.4), segs=10)
    # supplies: crates, a barrel, a coil of rope
    for x, f, s in ((2.2, -0.5, 0.6), (2.25, -0.1, 0.5), (2.2, -0.3, 0.42)):
        m.box(K("wood", WOOD), (s, s, s), (x, s * 0.5 if f != -0.3 else 0.6 + s * 0.5, f))
    m.lathe(K("wood", DARK), [(0.0, 0.0), (0.26, 0.0), (0.31, 0.4), (0.26, 0.8), (0.0, 0.8)], (-2.25, 0.0, -0.4), segs=14)
    for y in (0.12, 0.68):
        m.lathe(K("metal", IRON), [(0.0, -0.02), (0.3, -0.02), (0.3, 0.02), (0.0, 0.02)], (-2.25, y, -0.4), segs=14)
    for k in range(5):
        m.lathe(K("cloth", ROPE), [(0.0, -0.02), (0.22 - k * 0.025, -0.02), (0.22 - k * 0.025, 0.02), (0.0, 0.02)], (-2.3, 0.82 + 0.035 * k, -0.4), segs=14)
    # a lantern under the awning
    m.rod(K("metal", IRON), 0.01, (1.2, 2.5, -1.0), (1.2, 2.25, -1.0), segs=4)
    m.lathe(K("metal", IRON), [(0.0, 0.0), (0.08, 0.0), (0.09, 0.2), (0.05, 0.24), (0.0, 0.26)], (1.2, 2.0, -1.0), segs=8)


if __name__ == "__main__":
    fk.init()
    m = kit.Model("harbour_stall", uv_scale=0.6, colored=True)
    stall(m)
    print("harbour_stall", m.export(OUT))

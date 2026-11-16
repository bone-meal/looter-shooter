# Purpose: developer-time tool. Builds the ship's salvage crane of sea step 5e (LOCKED: "a crane on the ship (must be
# BOUGHT as an upgrade); until then diving") into assets/models/sea/crane.gltf: an iron-bound timber davit on a deck
# plate: a round post, a jib reaching out and up over the side (+x), a diagonal brace, a pulley block at the jib's
# tip (node "Tip" marks where the rope leaves it) and a hand winch with its crank on the post.
# Materials are named after what a part is made of (tools/blender/fantasy_kit.py).
# Run: python3 tools/blender/sea_crane.py   (bpy as a module)
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
WOOD = (0.45, 0.31, 0.19)
DARK = (0.3, 0.21, 0.13)
IRON = (0.22, 0.22, 0.23)
ROPE = (0.62, 0.52, 0.36)
POST = 2.2
JIB = 2.6
LIFT = math.radians(35)
TIP = (JIB * math.cos(LIFT), POST + JIB * math.sin(LIFT), 0.0)  # game/sea_crane.gd uses the same numbers


def crane(m):
    m.box(K("wood", DARK), (0.7, 0.08, 0.7), (0.0, 0.04, 0.0))  # deck plate
    for x, f in ((-0.28, -0.28), (-0.28, 0.28), (0.28, -0.28), (0.28, 0.28)):
        m.ball(K("metal", IRON), (0.03, 0.02, 0.03), (x, 0.09, f), u=6, v=4)
    m.rod(K("wood", WOOD), 0.13, (0.0, 0.05, 0.0), (0.0, POST + 0.15, 0.0), r2=0.11, segs=12)  # post
    for y in (0.4, 1.3, POST - 0.1):  # iron bands
        m.rod(K("metal", IRON), 0.14, (0.0, y - 0.03, 0.0), (0.0, y + 0.03, 0.0), segs=12)
    m.rod(K("wood", WOOD), 0.085, (0.0, POST, 0.0), TIP, r2=0.07, segs=10)  # jib
    m.rod(K("wood", DARK), 0.06, (0.0, POST - 1.0, 0.0), (JIB * 0.55 * math.cos(LIFT), POST + JIB * 0.55 * math.sin(LIFT), 0.0), segs=8)  # brace
    m.lathe(K("wood", DARK), [(0.0, -0.05), (0.13, -0.05), (0.15, 0.0), (0.13, 0.05), (0.0, 0.05)], (TIP[0], TIP[1] - 0.08, TIP[2]), segs=14, axis="f")  # pulley sheave
    m.box(K("metal", IRON), (0.06, 0.32, 0.14), (TIP[0], TIP[1] - 0.04, 0.0))  # block cheeks
    m.lathe(K("wood", DARK), [(0.0, -0.14), (0.09, -0.14), (0.09, 0.14), (0.0, 0.14)], (-0.22, 1.0, 0.0), segs=12, axis="f")  # winch drum
    for k in range(6):  # rope wound on the drum
        m.lathe(K("cloth", ROPE), [(0.0, -0.012), (0.1, -0.012), (0.1, 0.012), (0.0, 0.012)], (-0.22, 1.0, -0.1 + 0.04 * k), segs=12, axis="f")
    m.rod(K("metal", IRON), 0.02, (-0.22, 1.0, 0.16), (-0.22, 1.0, 0.3), segs=6)  # crank
    m.rod(K("metal", IRON), 0.02, (-0.22, 1.0, 0.3), (-0.22, 0.8, 0.3), segs=6)
    m.rod(K("wood", DARK), 0.03, (-0.22, 0.8, 0.3), (-0.22, 0.8, 0.42), segs=6)
    m.rod(K("cloth", ROPE), 0.015, (-0.22, 1.1, 0.0), (0.0, POST + 0.05, 0.0), segs=6)  # rope up the post
    m.rod(K("cloth", ROPE), 0.015, (0.0, POST + 0.05, 0.0), (TIP[0], TIP[1] + 0.06, TIP[2]), segs=6)  # along the jib
    m.box(K("metal", IRON), (0.01, 0.01, 0.01), (TIP[0], TIP[1] - 0.2, TIP[2]), node="Tip")


if __name__ == "__main__":
    fk.init()
    m = kit.Model("crane", uv_scale=0.6, colored=True)
    crane(m)
    print("crane", m.export(OUT), "tip", TIP)

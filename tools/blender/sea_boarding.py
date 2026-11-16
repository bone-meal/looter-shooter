# Purpose: developer-time tool. Builds the boarding gear of sea step 5d (director "1 and 3": grappling hooks AND a
# boarding plank) into assets/models/sea/: grapnel (a four-pronged iron grappling hook: shank, ring, curved barbed
# prongs; ~0.5 m) and boarding_plank (a 1 m long, 0.62 m wide gangway section of three boards on two cleats with
# side battens and nail heads, centred on its middle, length along -f so the game stretches it to any span).
# Materials are named after what a part is made of (tools/blender/fantasy_kit.py).
# Run: python3 tools/blender/sea_boarding.py   (bpy as a module)
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
IRON = (0.2, 0.2, 0.21)
RUST = (0.36, 0.22, 0.14)
WOOD = (0.5, 0.36, 0.22)
OLD_WOOD = (0.4, 0.3, 0.2)
NAIL = (0.3, 0.29, 0.27)


def grapnel(m):
    m.rod(K("metal", IRON), 0.025, (0.0, 0.0, 0.0), (0.0, 0.42, 0.0), segs=10)  # shank
    ring_y = 0.47
    for k in range(10):  # the ring the rope is tied to
        a0, a1 = 2 * math.pi * k / 10, 2 * math.pi * (k + 1) / 10
        m.rod(K("metal", RUST), 0.012, (0.05 * math.cos(a0), ring_y + 0.05 * math.sin(a0), 0.0), (0.05 * math.cos(a1), ring_y + 0.05 * math.sin(a1), 0.0), segs=6)
    for p in range(4):  # four prongs curving up and out, each with a barb
        a = p * math.pi / 2 + math.pi / 4
        pts = []
        for t in range(6):
            u = t / 5
            r = 0.02 + 0.17 * math.sin(u * math.pi * 0.62)
            y = 0.02 + 0.2 * u * u - 0.03 * math.sin(u * math.pi)
            pts.append((r * math.cos(a), y, r * math.sin(a)))
        for s0, s1 in zip(pts, pts[1:]):
            m.rod(K("metal", IRON), 0.019, s0, s1, r2=0.016, segs=8)
        tip = pts[-1]
        m.rod(K("metal", IRON), 0.014, tip, (tip[0] * 0.82, tip[1] - 0.06, tip[2] * 0.82), r2=0.004, segs=6)  # barb
    m.ball(K("metal", IRON), (0.04, 0.035, 0.04), (0.0, 0.01, 0.0), u=10, v=6)  # crown


def plank(m):
    for x in (-0.21, 0.0, 0.21):  # three boards, slightly uneven
        m.box(K("wood", WOOD if x != 0.0 else OLD_WOOD), (0.19, 0.05, 1.0), (x, 0.0, 0.0), bevel=0.008)
    for f in (-0.32, 0.32):  # cleats underneath
        m.box(K("wood", OLD_WOOD), (0.62, 0.05, 0.08), (0.0, -0.045, f), bevel=0.006)
    for f in (-0.4, -0.13, 0.13, 0.4):  # cross battens on top: footholds on the slope
        m.box(K("wood", OLD_WOOD), (0.6, 0.025, 0.035), (0.0, 0.035, f), bevel=0.004)
    for x in (-0.31, 0.31):  # side battens
        m.box(K("wood", OLD_WOOD), (0.03, 0.06, 1.0), (x, 0.01, 0.0), bevel=0.004)
    for x in (-0.21, 0.0, 0.21):
        for f in (-0.32, 0.32):
            m.ball(K("metal", NAIL), (0.01, 0.006, 0.01), (x, 0.027, f), u=6, v=3)


if __name__ == "__main__":
    fk.init()
    for name, build in (("grapnel", grapnel), ("boarding_plank", plank)):
        m = kit.Model(name, uv_scale=0.6, colored=True)
        build(m)
        print(name, m.export(OUT))

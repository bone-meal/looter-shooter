# Purpose: developer-time tool. Builds the ship's cannon of sea step 5d (cannons manned by players: sit, aim, fire)
# into assets/models/sea/cannon.glb: a wooden truck carriage (two stepped cheeks, axles, four wheels, a bed with a
# quoin wedge, iron bolts and two breeching ring bolts) and a cast iron barrel (node "Barrel": tapered chase, reinforce
# rings, muzzle swell, cascabel knob, trunnions resting in the cheeks) with an empty node-marker "Muzzle" at its mouth.
# The game (game/sea_cannons.gd) pivots "Barrel" round the trunnions (TRUNNION below) and aims along Barrel -> Muzzle.
# Materials are named after what a part is made of (tools/blender/fantasy_kit.py).
# Run: python3 tools/blender/sea_cannon.py   (bpy as a module)
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
WOOD = (0.42, 0.28, 0.17)
DARK_WOOD = (0.3, 0.2, 0.12)
IRON = (0.16, 0.16, 0.17)
BOLT = (0.32, 0.3, 0.28)
TRUNNION = (0.0, 0.62, 0.05)  # the barrel's pivot (game/sea_cannons.gd uses the same numbers)


def cannon(m):
    # carriage: stepped cheeks (higher at the back, as on a truck carriage)
    for x in (-0.26, 0.26):
        m.box(K("wood", WOOD), (0.1, 0.36, 1.05), (x, 0.36, 0.0))
        m.box(K("wood", WOOD), (0.1, 0.16, 0.5), (x, 0.62, 0.22))
        for f in (-0.35, 0.0, 0.35):
            m.ball(K("metal", BOLT), (0.025, 0.025, 0.025), (x * 1.22, 0.42, f), u=6, v=4)
        m.lathe(K("metal", BOLT), [(0.0, -0.02), (0.05, -0.02), (0.05, 0.02), (0.0, 0.02)], (x * 1.25, 0.5, -0.45), segs=10, axis="x")
    m.box(K("wood", DARK_WOOD), (0.62, 0.08, 0.95), (0.0, 0.2, 0.02))  # bed
    m.box(K("wood", DARK_WOOD), (0.18, 0.12, 0.4), (0.0, 0.3, 0.38), tilt=-8)  # quoin under the breech
    for f in (-0.38, 0.4):  # axles and trucks (wheels)
        m.box(K("wood", DARK_WOOD), (0.82, 0.1, 0.12), (0.0, 0.16, f))
        for x in (-0.38, 0.38):
            m.lathe(K("wood", WOOD), [(0.0, -0.045), (0.15, -0.045), (0.16, 0.0), (0.15, 0.045), (0.0, 0.045)], (x, 0.16, f), segs=14, axis="x")
            m.lathe(K("metal", IRON), [(0.0, -0.05), (0.04, -0.05), (0.04, 0.05), (0.0, 0.05)], (x, 0.16, f), segs=8, axis="x")
    # barrel (node Barrel): breech at +f, muzzle at -f
    tx, ty, tz = TRUNNION
    m.rod(K("metal", IRON), 0.165, (tx, ty, tz + 0.55), (tx, ty, tz - 0.25), r2=0.15, node="Barrel", segs=16)
    m.rod(K("metal", IRON), 0.145, (tx, ty, tz - 0.25), (tx, ty, tz - 1.15), r2=0.11, node="Barrel", segs=16)
    m.rod(K("metal", IRON), 0.135, (tx, ty, tz - 1.15), (tx, ty, tz - 1.3), r2=0.15, node="Barrel", segs=16)  # muzzle swell
    for f, r in ((0.45, 0.185), (-0.25, 0.165), (-0.6, 0.15)):  # reinforce rings
        m.rod(K("metal", IRON), r, (tx, ty, tz + f + 0.03), (tx, ty, tz + f - 0.03), node="Barrel", segs=16)
    m.ball(K("metal", IRON), (0.13, 0.13, 0.1), (tx, ty, tz + 0.6), node="Barrel", u=12, v=8)
    m.ball(K("metal", IRON), (0.06, 0.06, 0.06), (tx, ty, tz + 0.74), node="Barrel", u=8, v=6)  # cascabel knob
    m.rod(K("metal", IRON), 0.055, (tx - 0.3, ty, tz), (tx + 0.3, ty, tz), node="Barrel", segs=10)  # trunnions
    m.rod(K("metal", (0.05, 0.05, 0.05)), 0.075, (tx, ty, tz - 1.25), (tx, ty, tz - 1.31), node="Barrel", segs=12)  # the bore's dark mouth
    m.box(K("metal", IRON), (0.01, 0.01, 0.01), (tx, ty, tz - 1.32), node="Muzzle")


if __name__ == "__main__":
    fk.init()
    m = kit.Model("cannon", uv_scale=0.6, colored=True)
    cannon(m)
    print("cannon", m.export(OUT))

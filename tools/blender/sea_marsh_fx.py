# Purpose: developer-time script (polish1 A7). Models two region 2 glows that were plain spheres into
# assets/models/sea/: false_lure.gltf (the Lantern Queen's FALSE LURE: a rooted stalk whose head curls over and hangs a
# ribbed teardrop bulb, like her own lure; node "Bulb" is lit by the game, node "Stalk" is stretched by the game to
# reach the water, node "Hood" keeps its size) and marsh_wisp.gltf (a MARSH LIGHT: a flame-like teardrop "Core" with a
# curling tail and a soft "Halo" shell the game makes see-through). Our own designs. Model space: x right, y up,
# f forward; origin = the bulb's / the core's middle.
# Run: python3 tools/blender/sea_marsh_fx.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. Used by game/queen_false_lures.gd and
# game/sea_marsh_lights.gd (both fall back to spheres without the files).
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")

FLESH = (0.24, 0.21, 0.14)
FLESH_DARK = (0.15, 0.13, 0.09)
FIN = (0.32, 0.3, 0.18)
GLOW = (0.78, 1.0, 0.58)


def false_lure(m):
    flesh, dark, fin, glow = K("scale", FLESH), K("scale", FLESH_DARK), K("leaf", FIN), K("paint", GLOW)
    # the bulb: a ribbed teardrop hanging point down
    m.node("Bulb", (0.0, 0.0, 0.0))
    m.lathe(glow, [(0.0, -0.52), (0.1, -0.44), (0.3, -0.25), (0.42, 0.0), (0.38, 0.22), (0.22, 0.4), (0.07, 0.47), (0.0, 0.48)], (0.0, 0.0, 0.0), segs=14, node="Bulb")
    for k in range(6):  # ribs down its sides
        a = 2 * math.pi * k / 6
        m.loft(glow, [(math.cos(a) * 0.2, 0.4, math.sin(a) * 0.2, 0.03, 0.03), (math.cos(a) * 0.43, 0.0, math.sin(a) * 0.43, 0.035, 0.035),
                      (math.cos(a) * 0.12, -0.46, math.sin(a) * 0.12, 0.02, 0.02)], segs=5, node="Bulb")
    # the hood: the stalk's head curls over and lets the bulb down on a short cord (keeps its size)
    m.node("Hood", (0.0, 0.3, -0.6))
    m.loft(flesh, [(0.0, 0.3, -0.6, 0.09, 0.09), (0.0, 0.85, -0.55, 0.08, 0.08), (0.0, 1.05, -0.25, 0.07, 0.07),
                   (0.0, 0.95, 0.02, 0.055, 0.055), (0.0, 0.72, 0.05, 0.04, 0.04)], segs=8, node="Hood")
    m.rod(dark, 0.025, (0.0, 0.74, 0.04), (0.0, 0.46, 0.0), r2=0.03, segs=6, node="Hood")
    for k, (y, f, s) in enumerate(((0.95, -0.42, 1.0), (1.03, -0.12, 0.8), (0.7, -0.6, 0.9))):  # ragged fins on the curl
        side = 1.0 if k % 2 == 0 else -1.0
        m.loft(fin, [(0.0, y, f, 0.02, 0.05), (0.18 * side * s, y + 0.1, f + 0.05, 0.015, 0.09), (0.3 * side * s, y + 0.02, f + 0.12, 0.01, 0.03)],
               segs=5, node="Hood", flat=True)
    # the stalk: from the hood straight down to y -1 (the game stretches it to the water)
    m.node("Stalk", (0.0, 0.0, -0.6))
    m.loft(flesh, [(0.0, 0.0, -0.6, 0.09, 0.09), (0.04, -0.35, -0.62, 0.1, 0.1), (-0.03, -0.7, -0.58, 0.11, 0.11),
                   (0.0, -1.0, -0.6, 0.13, 0.13)], segs=8, node="Stalk")
    for k in range(5):  # rings of darker skin down it
        y = -0.12 - k * 0.18
        m.lathe(dark, [(0.1, y - 0.015), (0.118, y), (0.1, y + 0.015)], (0.0, 0.0, -0.6), segs=8, node="Stalk")


def wisp(m):
    glow = K("paint", GLOW)
    # the core: a flame-like teardrop, round below, its tail curling up and back
    m.node("Core", (0.0, 0.0, 0.0))
    m.lathe(glow, [(0.0, -0.38), (0.2, -0.32), (0.34, -0.12), (0.33, 0.06), (0.24, 0.22), (0.1, 0.34), (0.0, 0.38)], (0.0, 0.0, 0.0), segs=12, node="Core")
    m.loft(glow, [(0.0, 0.3, 0.0, 0.14, 0.14), (0.0, 0.55, -0.12, 0.09, 0.09), (0.05, 0.72, -0.32, 0.05, 0.05), (0.12, 0.74, -0.52, 0.02, 0.02)],
           segs=8, node="Core")
    # the halo: a soft round shell the game draws faint
    m.node("Halo", (0.0, 0.0, 0.0))
    m.ball(glow, (0.62, 0.66, 0.62), (0.0, 0.05, 0.0), node="Halo", u=12, v=8)


def main():
    fk.init()
    m = kit.Model("false_lure", uv_scale=2.0, colored=True)
    false_lure(m)
    print("false_lure", m.export(OUT))
    m = kit.Model("marsh_wisp", uv_scale=2.0, colored=True)
    wisp(m)
    print("marsh_wisp", m.export(OUT))


if __name__ == "__main__":
    main()

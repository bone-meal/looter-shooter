# Purpose: developer-time tool (sea step 8e-4). The G U-BOAT (director: an unknown force at sea, only ever seen far off,
# never caught): our own long dark submarine ~40 m: a cigar hull with a sharp bow and saddle tanks, a riveted deck
# casing with a slim deck gun, a tall conning tower with a rail, a PERISCOPE on node "Periscope" (the game raises it
# alone above the water), and a flag staff aft of the tower with a flag panel on node "Flag" (the game paints the
# checkerboard G on it). Waterline at y = 0 when surfaced; the game sinks it for periscope sightings.
# -> assets/models/sea/uboat.gltf.  Run: python3 tools/blender/sea_uboat.py
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
HULL = (0.2, 0.23, 0.22)
HULL_DARK = (0.12, 0.13, 0.13)
RED = (0.42, 0.12, 0.1)
RUST = (0.4, 0.24, 0.14)
DECK = (0.26, 0.24, 0.2)


def uboat(m):
    hull, dark, red, rust, deck = K("paint", HULL), K("paint", HULL_DARK), K("paint", RED), K("paint", RUST), K("wood", DECK)
    L = 20.0
    rings = [(-L, 0.2, 0.3), (-L + 3, 1.2, 1.3), (-L + 9, 2.0, 2.0), (0.0, 2.3, 2.3), (L - 9, 2.0, 2.0), (L - 3, 1.1, 1.3), (L, 0.15, 0.6)]
    m.loft(hull, [(0.0, 0.2, f, rx, ry) for f, rx, ry in rings], segs=18)
    m.loft(red, [(0.0, -0.7, f, rx * 0.98, ry * 0.75) for f, rx, ry in rings[1:-1]], segs=16)  # the red below the waterline
    for side in (-1, 1):  # saddle tanks
        m.loft(dark, [(side * 1.9, 0.0, -10.0, 0.6, 0.7), (side * 2.1, 0.0, 0.0, 0.8, 0.9), (side * 1.9, 0.0, 9.0, 0.6, 0.7)], segs=12)
        for k in range(12):  # flood holes
            m.box(K("paint", (0.03, 0.03, 0.03)), (0.05, 0.25, 0.6), (side * 2.55, 0.15, -9.0 + k * 1.6), bevel=0.0)
    m.box(deck, (1.8, 0.25, 30.0), (0.0, 2.55, -1.0), bevel=0.02)  # the deck casing
    for k in range(6):  # rust streaks down the sides
        f = -14.0 + k * 5.5
        for side in (-1, 1):
            m.box(rust, (0.04, 1.4, 0.18), (side * 2.28, 1.2, f), bevel=0.0)
    # the conning tower: tall, rounded front, open bridge rail
    m.loft(hull, [(0.0, 2.7, -3.5, 0.9, 0.5), (0.0, 3.6, -2.0, 1.1, 1.0), (0.0, 4.2, 0.5, 1.1, 1.3), (0.0, 4.3, 2.2, 0.8, 0.6), (0.0, 4.0, 3.2, 0.3, 0.3)], segs=14)
    m.box(hull, (2.0, 2.2, 4.0), (0.0, 3.6, 0.0), bevel=0.15)
    for k in range(9):  # bridge rail posts
        a = math.radians(-80 + k * 20)
        m.rod(dark, 0.03, (math.sin(a) * 1.0, 4.7, math.cos(a) * 1.4 + 0.2), (math.sin(a) * 1.0, 5.3, math.cos(a) * 1.4 + 0.2), segs=5)
    m.loft(dark, [(-1.0, 5.3, 0.2, 0.03, 0.03), (0.0, 5.3, 1.6, 0.03, 0.03), (1.0, 5.3, 0.2, 0.03, 0.03)], segs=5)
    # the deck gun forward of the tower
    m.lathe(dark, [(0.0, 0.0), (0.35, 0.0), (0.3, 0.6), (0.0, 0.6)], (0.0, 2.65, 6.0), segs=10)
    m.cyl(dark, 0.09, 6.0, 8.6, y=3.2, segs=10, r2=0.07)
    m.box(dark, (0.8, 0.6, 1.0), (0.0, 3.2, 5.9), bevel=0.05)
    # the periscope (raised alone above the water when it hunts)
    m.node("Periscope", (0.3, 4.5, -0.6))
    m.rod(dark, 0.09, (0.3, 4.4, -0.6), (0.3, 8.6, -0.6), r2=0.07, segs=8, node="Periscope")
    m.box(dark, (0.18, 0.3, 0.38), (0.3, 8.7, -0.5), bevel=0.02, node="Periscope")
    m.box(K("paint", (0.6, 0.75, 0.8)), (0.12, 0.12, 0.02), (0.3, 8.72, -0.3), bevel=0.0, node="Periscope")
    # the flag staff aft of the tower and its flag panel (painted in the game)
    m.rod(dark, 0.04, (0.0, 4.2, -3.6), (0.0, 7.6, -3.6), segs=6)
    m.node("Flag", (0.0, 7.0, -3.6))
    m.box(K("cloth", (0.9, 0.9, 0.9)), (0.03, 1.1, 1.7), (0.0, 7.0, -4.5), bevel=0.0, node="Flag")


if __name__ == "__main__":
    fk.init()
    m = kit.Model("uboat", uv_scale=0.5, colored=True)
    uboat(m)
    print("uboat", m.export(OUT))

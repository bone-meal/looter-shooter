# Purpose: developer-time tool (sea step 8). The floating cargo a sunk pirate ship leaves (game/sea_flotsam.gd):
# flotsam_barrel (a barrel lying on its side with a rope round it and a cork bung), flotsam_crate (a lashed crate with
# a broken plank across it), flotsam_chest (an iron-bound sea chest, lid a little open on gold). Each floats with its
# waterline at y = 0. -> assets/models/sea/flotsam_<name>.gltf
# Run: python3 tools/blender/sea_flotsam.py
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py, sea_town_parts.py. No game code.
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K
import sea_town_parts as P
from sea_town_parts import blk, tone

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
WOOD = (0.42, 0.29, 0.17)
DARK = (0.3, 0.2, 0.12)
GOLD = (0.9, 0.7, 0.25)


def barrel(m):
    """On its side across x, half under: staves, iron hoops, a bung, a rope tied round the middle."""
    h = 1.0
    m.lathe(K("wood", WOOD), [(0.0, 0.0), (0.3, 0.0), (0.37, h / 2), (0.3, h), (0.0, h)], (0.0, 0.0, 0.0), segs=14, axis="x")
    for dx in (0.12, 0.38, h - 0.38, h - 0.12):
        m.lathe(K("metal", P.IRON), [(0.0, -0.025), (0.33 if dx in (0.12, h - 0.12) else 0.37, -0.025), (0.33 if dx in (0.12, h - 0.12) else 0.37, 0.025), (0.0, 0.025)], (dx, 0.0, 0.0), segs=14, axis="x")
    blk(m, K("wood", DARK), (0.08, 0.06, 0.08), (h / 2, 0.37, 0.0))
    for k in range(3):
        m.lathe(K("cloth", P.ROPE), [(0.39 + k * 0.012, -0.02), (0.41 + k * 0.012, -0.02), (0.41 + k * 0.012, 0.02), (0.39 + k * 0.012, 0.02)], (h / 2 - 0.06 + k * 0.05, 0.0, 0.0), segs=12, axis="x")


def crate(m):
    s = 0.8
    blk(m, K("wood", WOOD), (s, s, s), (0.0, s * 0.15, 0.0), yaw=12.0)
    for dy in (-s * 0.25 + 0.06, s * 0.55 - 0.06):
        blk(m, K("wood", tone(K("wood", WOOD), 0.7)[1]), (s + 0.04, 0.08, s + 0.04), (0.0, dy, 0.0), yaw=12.0)
    for x in (-s / 2 + 0.06, s / 2 - 0.06):
        blk(m, K("wood", tone(K("wood", WOOD), 0.7)[1]), (0.08, s + 0.02, s + 0.04), (x, s * 0.15, 0.0), yaw=12.0)
    blk(m, K("cloth", P.ROPE), (s + 0.06, 0.04, 0.05), (0.0, s * 0.56, 0.0), yaw=12.0)
    blk(m, K("cloth", P.ROPE), (0.05, 0.04, s + 0.06), (0.0, s * 0.56, 0.0), yaw=12.0)
    blk(m, K("wood", (0.5, 0.38, 0.25)), (1.9, 0.07, 0.22), (0.2, s * 0.58, 0.15), yaw=-28.0, roll=4.0)  # a broken plank
    blk(m, K("wood", (0.5, 0.38, 0.25)), (0.5, 0.07, 0.2), (1.25, 0.02, 0.7), yaw=-40.0)


def chest(m):
    w, d, hgt = 0.95, 0.6, 0.45
    blk(m, K("wood", (0.36, 0.22, 0.13)), (w, hgt, d), (0.0, hgt / 2 - 0.12, 0.0))
    for x in (-w / 2 + 0.1, 0.0, w / 2 - 0.1):
        blk(m, K("metal", P.IRON), (0.06, hgt + 0.02, d + 0.02), (x, hgt / 2 - 0.12, 0.0))
    # the lid, opened a hand's width, with gold showing under it
    lid = 0.22
    blk(m, K("wood", (0.36, 0.22, 0.13)), (w, 0.08, d), (0.0, hgt - 0.12 + lid / 2 + 0.03, -0.06), pitch=-22.0)
    for x in (-w / 2 + 0.1, 0.0, w / 2 - 0.1):
        blk(m, K("metal", P.IRON), (0.06, 0.1, d + 0.02), (x, hgt - 0.12 + lid / 2 + 0.03, -0.06), pitch=-22.0)
    for k in range(9):
        x = -w / 2 + 0.15 + (k % 5) * 0.16
        z = -0.12 + (k // 5) * 0.16
        m.lathe(K("metal", GOLD), [(0.0, 0.0), (0.05, 0.0), (0.05, 0.015), (0.0, 0.015)], (x, hgt - 0.11 + (k % 3) * 0.01, z), segs=8)
    blk(m, K("metal", GOLD), (0.12, 0.12, 0.04), (0.0, hgt - 0.2, d / 2 + 0.01))  # the lock plate


if __name__ == "__main__":
    fk.init()
    for name, job in (("flotsam_barrel", barrel), ("flotsam_crate", crate), ("flotsam_chest", chest)):
        m = kit.Model(name, uv_scale=0.5, colored=True)
        job(m)
        print(name, m.export(OUT))

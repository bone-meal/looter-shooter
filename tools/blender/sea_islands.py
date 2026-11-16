# Purpose: developer-time tool. Builds the TEST islands of sea step 4 (assets/models/sea/isle_*.glb: tiny, medium,
# large; the small one gave way to the showcase start island, tools/blender/sea_isle_start.py) so streaming, foam and
# the look can be judged before the hand-made islands of step 13: a shore that slopes under the water (the ocean's
# depth foam needs it), a peak; ground painting and props from the island kit (tools/blender/sea_isle_kit.py).
# Run: python3 tools/blender/sea_islands.py   (bpy 4.x/5.x as a module)
# Dependencies: bpy, tools/blender/sea_isle_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
import sea_isle_kit as kit

# id: (radius m, peak m, roughness, seed, prop density against the start island's)
ISLANDS = {"isle_tiny": (14.0, 3.0, 0.15, 1, 1.0), "isle_medium": (160.0, 42.0, 0.35, 3, 0.45), "isle_large": (420.0, 120.0, 0.4, 4, 0.2)}


def height(x, z, radius, peak, rough, rnd):
    d = math.hypot(x, z) / radius
    wobble = 1.0 + rough * 0.25 * (math.sin(math.atan2(z, x) * 3 + rnd[0]) + 0.6 * math.sin(math.atan2(z, x) * 7 + rnd[1]))
    d /= wobble
    if d > 1.0:  # the shelf going down under the sea
        return -6.0 * min((d - 1.0) / 0.35, 1.0) - 0.4
    core = (1.0 - d * d) ** 1.6
    bumps = rough * (math.sin(x / radius * 9 + rnd[2]) * math.cos(z / radius * 7 + rnd[3])) * 0.18
    return max(core + bumps, 0.0) * peak - 0.4 + 1.2 * (1.0 - d)


def main():
    for name, (radius, peak, rough, seed, density) in ISLANDS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        rnd = [random.Random(seed).uniform(0, 6.28) for _ in range(4)]
        reach = radius * 1.45
        land = lambda x, z: height(x, z, radius, peak, rough, rnd)  # noqa: E731
        obj = kit.ground(name, land, reach, 160 if radius > 100 else 48)
        kit.save(name, obj, kit.scatter(land, reach, seed, density=density, green=0.35 if radius > 100 else 1.0), "tools/blender/sea_islands.py")


main()
